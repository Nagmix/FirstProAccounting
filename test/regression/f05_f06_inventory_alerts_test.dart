import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/services/inventory_alert_service.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';

/// F-05 + F-06 regression tests for InventoryAlertService.
///
/// Verifies that the service correctly:
///   - Detects products at/below min_stock (F-05).
///   - Detects products with expiry_tracking=1 whose expiry_date is
///     within the threshold (F-06).
///   - Inserts notifications into the notifications table.
///   - Is idempotent: re-running the scan does not duplicate alerts.
///   - Respects the stock_alert_enabled / expiry_alert_enabled settings.
///   - getAlertSummary returns correct counts.
void main() {
  late Database db;
  late InventoryAlertService alertService;
  late ReferenceDataRepository refRepo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 53,
      onCreate: (database, version) async {
        await DatabaseSchema.onCreate(database, version);
      },
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
    // Wire the in-memory db into a DatabaseHelper shim so that
    // InventoryAlertService (which uses DatabaseHelper) and
    // ReferenceDataRepository (which also uses DatabaseHelper) both
    // see the same in-memory db.
    // We accomplish this by registering the singleton before the
    // services are constructed.
    DatabaseHelper.useTestDatabase(db);
    refRepo = ReferenceDataRepository(DatabaseHelper());
    alertService = InventoryAlertService(DatabaseHelper());
  });

  tearDown(() async {
    DatabaseHelper.clearTestDatabase();
    await db.close();
  });

  // ── F-05: Stock alerts ──────────────────────────────────────────

  group('F-05: stock alerts', () {
    test('detects product at min_stock and inserts a notification', () async {
      // Seed a product with current_stock == min_stock (at threshold).
      await db.insert('products', {
        'item_code': 'P-LOW-1',
        'name_ar': 'منتج منخفض',
        'name_en': 'Low Product',
        'barcode': 'LOW1',
        'unit_id': 1,
        'cost_price': MoneyHelper.toCents(10.0),
        'sell_price': MoneyHelper.toCents(15.0),
        'current_stock': 5.0,
        'min_stock': 5.0, // at threshold → should alert
        'track_stock': 1,
        'is_active': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'allow_negative': 0,
        'currency': 'YER',
        'costing_method': 'weighted_average',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final result = await alertService.scanAndGenerateAlerts();
      expect(result.stockInserted, 1, reason: 'Should insert 1 stock alert.');
      expect(result.expiryInserted, 0);

      // Verify the notification was inserted.
      final notifs = await refRepo.getNotificationsByType(
          InventoryAlertService.typeStockAlert);
      expect(notifs, hasLength(1));
      expect(notifs.first['title'], 'مخزون منخفض');
      expect(notifs.first['reference_id'], 'product_1');
    });

    test('detects out-of-stock product (current_stock = 0)', () async {
      await db.insert('products', {
        'item_code': 'P-OUT-1',
        'name_ar': 'منتج نفد',
        'name_en': 'Out Product',
        'barcode': 'OUT1',
        'unit_id': 1,
        'current_stock': 0.0,
        'min_stock': 5.0,
        'track_stock': 1,
        'is_active': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'allow_negative': 0,
        'currency': 'YER',
        'costing_method': 'weighted_average',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final result = await alertService.scanAndGenerateAlerts();
      expect(result.stockInserted, 1);
      final notifs = await refRepo.getNotificationsByType(
          InventoryAlertService.typeStockAlert);
      expect(notifs.first['title'], 'نفاد المخزون',
          reason: 'Out-of-stock should use the "نفاد المخزون" title.');
    });

    test('does NOT alert for products with min_stock = 0', () async {
      await db.insert('products', {
        'item_code': 'P-NO-MIN',
        'name_ar': 'منتج بدون حد أدنى',
        'name_en': 'No Min Product',
        'barcode': 'NOMIN',
        'unit_id': 1,
        'current_stock': 0.0,
        'min_stock': 0.0, // no reorder point set
        'track_stock': 1,
        'is_active': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'allow_negative': 0,
        'currency': 'YER',
        'costing_method': 'weighted_average',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final result = await alertService.scanAndGenerateAlerts();
      expect(result.stockInserted, 0,
          reason: 'Products with min_stock=0 should NOT be alerted.');
    });

    test('does NOT alert for products above min_stock', () async {
      await db.insert('products', {
        'item_code': 'P-OK',
        'name_ar': 'منتج جيد',
        'name_en': 'OK Product',
        'barcode': 'OK1',
        'unit_id': 1,
        'current_stock': 100.0,
        'min_stock': 5.0, // well above threshold
        'track_stock': 1,
        'is_active': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'allow_negative': 0,
        'currency': 'YER',
        'costing_method': 'weighted_average',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final result = await alertService.scanAndGenerateAlerts();
      expect(result.stockInserted, 0);
    });

    test('is idempotent: re-running scan does not duplicate alerts', () async {
      await db.insert('products', {
        'item_code': 'P-IDEMP',
        'name_ar': 'منتج اختبار التكرار',
        'name_en': 'Idempotent Product',
        'barcode': 'IDEM',
        'unit_id': 1,
        'current_stock': 3.0,
        'min_stock': 5.0,
        'track_stock': 1,
        'is_active': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'allow_negative': 0,
        'currency': 'YER',
        'costing_method': 'weighted_average',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // First scan: 1 alert inserted.
      var result = await alertService.scanAndGenerateAlerts();
      expect(result.stockInserted, 1);
      expect(result.stockSkipped, 0);

      // Second scan: 0 inserted, 1 skipped (already exists, unread).
      result = await alertService.scanAndGenerateAlerts();
      expect(result.stockInserted, 0,
          reason: 'Idempotent: should not duplicate an unread alert.');
      expect(result.stockSkipped, 1);

      // Verify only 1 notification in DB.
      final notifs = await refRepo.getNotificationsByType(
          InventoryAlertService.typeStockAlert);
      expect(notifs, hasLength(1));
    });

    test('respects stock_alert_enabled = 0 (disabled)', () async {
      await db.insert('products', {
        'item_code': 'P-DISABLED',
        'name_ar': 'منتج معطّل التنبيه',
        'name_en': 'Disabled Product',
        'barcode': 'DIS',
        'unit_id': 1,
        'current_stock': 0.0,
        'min_stock': 5.0,
        'track_stock': 1,
        'is_active': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'allow_negative': 0,
        'currency': 'YER',
        'costing_method': 'weighted_average',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Disable stock alerts.
      await refRepo.setSetting('stock_alert_enabled', '0');

      final result = await alertService.scanAndGenerateAlerts();
      expect(result.stockInserted, 0,
          reason: 'stock_alert_enabled=0 should disable stock alerts.');
    });
  });

  // ── F-06: Expiry alerts ─────────────────────────────────────────

  group('F-06: expiry alerts', () {
    test('detects product expiring within the threshold', () async {
      final inSevenDays = DateTime.now().add(const Duration(days: 7));
      await db.insert('products', {
        'item_code': 'P-EXP-SOON',
        'name_ar': 'منتج يقترب انتهاؤه',
        'name_en': 'Expiring Soon Product',
        'barcode': 'EXPS',
        'unit_id': 1,
        'current_stock': 50.0,
        'min_stock': 5.0, // not low on stock
        'expiry_tracking': 1,
        'expiry_date': inSevenDays.toIso8601String().substring(0, 10),
        'track_stock': 1,
        'is_active': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'allow_negative': 0,
        'currency': 'YER',
        'costing_method': 'weighted_average',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final result = await alertService.scanAndGenerateAlerts();
      expect(result.expiryInserted, 1,
          reason: 'Product expiring in 7 days (within 30-day threshold) '
              'should trigger an expiry alert.');
      expect(result.stockInserted, 0);

      final notifs = await refRepo.getNotificationsByType(
          InventoryAlertService.typeExpiryAlert);
      expect(notifs, hasLength(1));
      expect(notifs.first['title'], 'صلاحية تقترب من الانتهاء');
      expect(notifs.first['reference_id'], 'expiry_1');
    });

    test('detects already-expired product', () async {
      final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));
      await db.insert('products', {
        'item_code': 'P-EXPIRED',
        'name_ar': 'منتج منتهي',
        'name_en': 'Expired Product',
        'barcode': 'EXP',
        'unit_id': 1,
        'current_stock': 50.0,
        'min_stock': 5.0,
        'expiry_tracking': 1,
        'expiry_date': tenDaysAgo.toIso8601String().substring(0, 10),
        'track_stock': 1,
        'is_active': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'allow_negative': 0,
        'currency': 'YER',
        'costing_method': 'weighted_average',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final result = await alertService.scanAndGenerateAlerts();
      expect(result.expiryInserted, 1);
      final notifs = await refRepo.getNotificationsByType(
          InventoryAlertService.typeExpiryAlert);
      expect(notifs.first['title'], 'منتج منتهي الصلاحية');
    });

    test('does NOT alert for product expiring after the threshold', () async {
      final inSixtyDays = DateTime.now().add(const Duration(days: 60));
      await db.insert('products', {
        'item_code': 'P-EXP-LATE',
        'name_ar': 'منتج بعيد الانتهاء',
        'name_en': 'Far Expiry Product',
        'barcode': 'EXPL',
        'unit_id': 1,
        'current_stock': 50.0,
        'min_stock': 5.0,
        'expiry_tracking': 1,
        'expiry_date': inSixtyDays.toIso8601String().substring(0, 10),
        'track_stock': 1,
        'is_active': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'allow_negative': 0,
        'currency': 'YER',
        'costing_method': 'weighted_average',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final result = await alertService.scanAndGenerateAlerts();
      expect(result.expiryInserted, 0,
          reason: 'Product expiring in 60 days (beyond 30-day threshold) '
              'should NOT trigger an alert.');
    });

    test('does NOT alert for product with expiry_tracking = 0', () async {
      final inSevenDays = DateTime.now().add(const Duration(days: 7));
      await db.insert('products', {
        'item_code': 'P-NO-TRACK',
        'name_ar': 'منتج بدون تتبع صلاحية',
        'name_en': 'No Tracking Product',
        'barcode': 'NOTR',
        'unit_id': 1,
        'current_stock': 50.0,
        'min_stock': 5.0,
        'expiry_tracking': 0, // tracking disabled
        'expiry_date': inSevenDays.toIso8601String().substring(0, 10),
        'track_stock': 1,
        'is_active': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'allow_negative': 0,
        'currency': 'YER',
        'costing_method': 'weighted_average',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final result = await alertService.scanAndGenerateAlerts();
      expect(result.expiryInserted, 0);
    });

    test('respects expiry_alert_days setting', () async {
      // Set threshold to 5 days.
      await refRepo.setSetting('expiry_alert_days', '5');

      final inTenDays = DateTime.now().add(const Duration(days: 10));
      await db.insert('products', {
        'item_code': 'P-THRESH',
        'name_ar': 'منتج عتبة',
        'name_en': 'Threshold Product',
        'barcode': 'THR',
        'unit_id': 1,
        'current_stock': 50.0,
        'min_stock': 5.0,
        'expiry_tracking': 1,
        'expiry_date': inTenDays.toIso8601String().substring(0, 10),
        'track_stock': 1,
        'is_active': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'allow_negative': 0,
        'currency': 'YER',
        'costing_method': 'weighted_average',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final result = await alertService.scanAndGenerateAlerts();
      expect(result.expiryInserted, 0,
          reason: 'With threshold=5 days, a product expiring in 10 days '
              'should NOT trigger an alert.');
    });
  });

  // ── Alert summary ───────────────────────────────────────────────

  group('getAlertSummary', () {
    test('returns correct counts for mixed scenario', () async {
      final now = DateTime.now();
      final in7Days = now.add(const Duration(days: 7));
      final tenDaysAgo = now.subtract(const Duration(days: 10));

      // 2 low-stock products (current <= min, min > 0).
      for (var i = 0; i < 2; i++) {
        await db.insert('products', {
          'item_code': 'P-LOW-$i',
          'name_ar': 'منخفض $i',
          'name_en': 'Low $i',
          'barcode': 'L$i',
          'unit_id': 1,
          'current_stock': 3.0,
          'min_stock': 5.0,
          'track_stock': 1,
          'is_active': 1,
          'is_sellable': 1,
          'is_purchasable': 1,
          'allow_negative': 0,
          'currency': 'YER',
          'costing_method': 'weighted_average',
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      }

      // 1 out-of-stock product (current = 0, min = 0 so NOT counted as low-stock).
      await db.insert('products', {
        'item_code': 'P-OUT',
        'name_ar': 'نفد',
        'name_en': 'Out',
        'barcode': 'O',
        'unit_id': 1,
        'current_stock': 0.0,
        'min_stock': 0.0,
        'track_stock': 1,
        'is_active': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'allow_negative': 0,
        'currency': 'YER',
        'costing_method': 'weighted_average',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      // 1 expiring-soon product (within 30 days, not expired).
      await db.insert('products', {
        'item_code': 'P-EXP',
        'name_ar': 'ينتهي قريباً',
        'name_en': 'Expiring',
        'barcode': 'E',
        'unit_id': 1,
        'current_stock': 50.0,
        'min_stock': 5.0,
        'expiry_tracking': 1,
        'expiry_date': in7Days.toIso8601String().substring(0, 10),
        'track_stock': 1,
        'is_active': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'allow_negative': 0,
        'currency': 'YER',
        'costing_method': 'weighted_average',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      // 1 already-expired product.
      await db.insert('products', {
        'item_code': 'P-EXPIRED',
        'name_ar': 'منتهي',
        'name_en': 'Expired',
        'barcode': 'X',
        'unit_id': 1,
        'current_stock': 50.0,
        'min_stock': 5.0,
        'expiry_tracking': 1,
        'expiry_date': tenDaysAgo.toIso8601String().substring(0, 10),
        'track_stock': 1,
        'is_active': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'allow_negative': 0,
        'currency': 'YER',
        'costing_method': 'weighted_average',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      final summary = await alertService.getAlertSummary();
      expect(summary.lowStockCount, 2,
          reason: '2 products with current<=min AND min>0.');
      expect(summary.outOfStockCount, 3,
          reason: '3 products with current<=0 (2 low-stock + 1 out).');
      expect(summary.expiringSoonCount, 1,
          reason: '1 product expiring within 30 days (not yet expired).');
      expect(summary.expiredCount, 1,
          reason: '1 product already expired.');
    });
  });
}
