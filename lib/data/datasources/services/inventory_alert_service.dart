import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';

/// F-05 + F-06: Inventory alert service.
///
/// Scans the products table for:
///   - F-05: products whose `current_stock <= min_stock` (reorder alerts).
///   - F-06: products with `expiry_tracking=1` whose `expiry_date` is
///     within the configured threshold (expiry alerts).
///
/// Alerts are written to the existing `notifications` table with a
/// `type` of 'stock_alert' or 'expiry_alert' so they appear in the
/// existing NotificationsScreen.
///
/// The service is idempotent: it deduplicates alerts by checking
/// whether an unread alert of the same type+reference_id already
/// exists before inserting a new one. This makes it safe to run on
/// every app launch or on a timer.
///
/// Configuration (DB settings table):
///   - 'stock_alert_enabled' ('1'/'0', default '1') — master switch.
///   - 'expiry_alert_enabled' ('1'/'0', default '1') — master switch.
///   - 'expiry_alert_days' (int as string, default '30') — days before
///     expiry to start alerting.
class InventoryAlertService {
  final DatabaseHelper _dbHelper;
  InventoryAlertService(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  /// Notification type constants (kept in sync with the existing
  /// 'stock_alert' type used in the NotificationsScreen).
  static const String typeStockAlert = 'stock_alert';
  static const String typeExpiryAlert = 'expiry_alert';

  /// Scan products and insert alerts for any that meet the criteria.
  ///
  /// Returns an [AlertScanResult] with counts of alerts inserted and
  /// skipped (already-existing). Safe to call repeatedly — only new
  /// alerts are inserted.
  Future<AlertScanResult> scanAndGenerateAlerts() async {
    final db = await _db;
    final refRepo = locator<ReferenceDataRepository>();

    // Load configuration from settings.
    final config = await _loadConfig(refRepo);

    int stockInserted = 0;
    int stockSkipped = 0;
    int expiryInserted = 0;
    int expirySkipped = 0;

    if (config.stockAlertEnabled) {
      final result = await _scanStockAlerts(db, refRepo);
      stockInserted = result.$1;
      stockSkipped = result.$2;
    }

    if (config.expiryAlertEnabled) {
      final result = await _scanExpiryAlerts(db, refRepo, config.expiryAlertDays);
      expiryInserted = result.$1;
      expirySkipped = result.$2;
    }

    return AlertScanResult(
      stockInserted: stockInserted,
      stockSkipped: stockSkipped,
      expiryInserted: expiryInserted,
      expirySkipped: expirySkipped,
    );
  }

  /// Get a quick summary of current alert counts (without generating
  /// new alerts). Used by the dashboard or settings screen.
  Future<AlertSummary> getAlertSummary() async {
    final db = await _db;
    final now = DateTime.now();
    final today = now.toIso8601String().substring(0, 10);

    // Low-stock products: current_stock <= min_stock AND min_stock > 0.
    // (min_stock = 0 means "no reorder point set" — skip those.)
    final lowStockRows = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM products "
      "WHERE is_active = 1 AND track_stock = 1 "
      "AND min_stock > 0 AND current_stock <= min_stock",
    );
    final lowStockCount =
        (lowStockRows.first['cnt'] as num?)?.toInt() ?? 0;

    // Out-of-stock products: current_stock <= 0.
    final outOfStockRows = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM products "
      "WHERE is_active = 1 AND track_stock = 1 AND current_stock <= 0",
    );
    final outOfStockCount =
        (outOfStockRows.first['cnt'] as num?)?.toInt() ?? 0;

    // Expiring soon: expiry_tracking=1 AND expiry_date is within 30 days.
    final expiringRows = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM products "
      "WHERE is_active = 1 AND expiry_tracking = 1 "
      "AND expiry_date IS NOT NULL AND expiry_date != '' "
      "AND date(expiry_date) >= date(?) "
      "AND date(expiry_date) <= date(?, '+30 days')",
      [today, today],
    );
    final expiringCount =
        (expiringRows.first['cnt'] as num?)?.toInt() ?? 0;

    // Already expired: expiry_date < today.
    final expiredRows = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM products "
      "WHERE is_active = 1 AND expiry_tracking = 1 "
      "AND expiry_date IS NOT NULL AND expiry_date != '' "
      "AND date(expiry_date) < date(?)",
      [today],
    );
    final expiredCount =
        (expiredRows.first['cnt'] as num?)?.toInt() ?? 0;

    return AlertSummary(
      lowStockCount: lowStockCount,
      outOfStockCount: outOfStockCount,
      expiringSoonCount: expiringCount,
      expiredCount: expiredCount,
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  Private: configuration
  // ════════════════════════════════════════════════════════════════

  Future<_AlertConfig> _loadConfig(ReferenceDataRepository refRepo) async {
    bool stockEnabled = true;
    bool expiryEnabled = true;
    int expiryDays = 30;

    try {
      final s = await refRepo.getSetting('stock_alert_enabled');
      if (s != null) stockEnabled = s == '1';
    } catch (e) {
      if (kDebugMode) debugPrint('InventoryAlertService: stock_alert_enabled read failed: $e');
    }
    try {
      final s = await refRepo.getSetting('expiry_alert_enabled');
      if (s != null) expiryEnabled = s == '1';
    } catch (e) {
      if (kDebugMode) debugPrint('InventoryAlertService: expiry_alert_enabled read failed: $e');
    }
    try {
      final s = await refRepo.getSetting('expiry_alert_days');
      if (s != null) expiryDays = int.tryParse(s) ?? 30;
    } catch (e) {
      if (kDebugMode) debugPrint('InventoryAlertService: expiry_alert_days read failed: $e');
    }

    return _AlertConfig(
      stockAlertEnabled: stockEnabled,
      expiryAlertEnabled: expiryEnabled,
      expiryAlertDays: expiryDays,
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  Private: stock alerts (F-05)
  // ════════════════════════════════════════════════════════════════

  /// Scan for products at or below their min_stock threshold.
  /// Returns (inserted, skipped).
  Future<(int, int)> _scanStockAlerts(
    Database db,
    ReferenceDataRepository refRepo,
  ) async {
    // Only alert for products that have a min_stock > 0 (i.e. the user
    // actually set a reorder point). Products with min_stock = 0 are
    // treated as "no reorder needed".
    final rows = await db.query(
      'products',
      columns: ['id', 'name_ar', 'name_en', 'current_stock', 'min_stock', 'supplier_id'],
      where: 'is_active = 1 AND track_stock = 1 AND min_stock > 0 AND current_stock <= min_stock',
    );

    int inserted = 0;
    int skipped = 0;
    final now = DateTime.now().toIso8601String();

    for (final row in rows) {
      final productId = row['id'] as int;
      final nameAr = (row['name_ar'] as String?) ?? '';
      final currentStock = (row['current_stock'] as num?)?.toDouble() ?? 0.0;
      final minStock = (row['min_stock'] as num?)?.toDouble() ?? 0.0;
      final referenceId = 'product_$productId';

      // Idempotency: skip if an unread stock_alert for this product
      // already exists.
      final existing = await db.query(
        'notifications',
        where: 'type = ? AND reference_id = ? AND is_read = 0',
        whereArgs: [typeStockAlert, referenceId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        skipped++;
        continue;
      }

      final isOutOfStock = currentStock <= 0;
      final title = isOutOfStock ? 'نفاد المخزون' : 'مخزون منخفض';
      final body = isOutOfStock
          ? 'المنتج "$nameAr" نفد من المخزون. يرجى إعادة الطلب.'
          : 'المنتج "$nameAr" وصل إلى الحد الأدنى للمخزون ($currentStock / $minStock). يرجى إعادة الطلب قريباً.';

      try {
        await refRepo.insertNotification({
          'title': title,
          'body': body,
          'type': typeStockAlert,
          'reference_id': referenceId,
          'is_read': 0,
          'created_at': now,
        });
        inserted++;
      } catch (e) {
        if (kDebugMode) debugPrint('InventoryAlertService: insert stock alert failed for product $productId: $e');
      }
    }

    return (inserted, skipped);
  }

  // ════════════════════════════════════════════════════════════════
  //  Private: expiry alerts (F-06)
  // ════════════════════════════════════════════════════════════════

  /// Scan for products with expiry_tracking=1 whose expiry_date is
  /// within [daysThreshold] days from today (or already expired).
  /// Returns (inserted, skipped).
  Future<(int, int)> _scanExpiryAlerts(
    Database db,
    ReferenceDataRepository refRepo,
    int daysThreshold,
  ) async {
    final today = DateTime.now();
    final todayStr = today.toIso8601String().substring(0, 10);
    final thresholdDate = today.add(Duration(days: daysThreshold));
    final thresholdStr = thresholdDate.toIso8601String().substring(0, 10);

    // Get products with expiry_tracking enabled and an expiry_date set
    // that is within the threshold (or already expired).
    final rows = await db.rawQuery(
      "SELECT id, name_ar, expiry_date FROM products "
      "WHERE is_active = 1 AND expiry_tracking = 1 "
      "AND expiry_date IS NOT NULL AND expiry_date != '' "
      "AND date(expiry_date) <= date(?)",
      [thresholdStr],
    );

    int inserted = 0;
    int skipped = 0;
    final now = DateTime.now().toIso8601String();

    for (final row in rows) {
      final productId = row['id'] as int;
      final nameAr = (row['name_ar'] as String?) ?? '';
      final expiryDateStr = (row['expiry_date'] as String?) ?? '';
      final referenceId = 'expiry_$productId';

      // Idempotency: skip if an unread expiry_alert for this product
      // already exists.
      final existing = await db.query(
        'notifications',
        where: 'type = ? AND reference_id = ? AND is_read = 0',
        whereArgs: [typeExpiryAlert, referenceId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        skipped++;
        continue;
      }

      // Compute days remaining for the message.
      int daysRemaining = 0;
      bool isExpired = false;
      try {
        final expiryDate = DateTime.parse(expiryDateStr.substring(0, 10));
        final diff = expiryDate.difference(today).inDays;
        daysRemaining = diff;
        isExpired = diff < 0;
      } catch (e) {
        // Unparseable date — skip this product.
        if (kDebugMode) debugPrint('InventoryAlertService: unparseable expiry_date "$expiryDateStr" for product $productId');
        continue;
      }

      final title = isExpired ? 'منتج منتهي الصلاحية' : 'صلاحية تقترب من الانتهاء';
      final body = isExpired
          ? 'المنتج "$nameAr" انتهت صلاحيته بتاريخ $expiryDateStr. يرجى سحبه من البيع.'
          : 'المنتج "$nameAr" تنتهي صلاحيته خلال $daysRemaining يوم (بتاريخ $expiryDateStr).';

      try {
        await refRepo.insertNotification({
          'title': title,
          'body': body,
          'type': typeExpiryAlert,
          'reference_id': referenceId,
          'is_read': 0,
          'created_at': now,
        });
        inserted++;
      } catch (e) {
        if (kDebugMode) debugPrint('InventoryAlertService: insert expiry alert failed for product $productId: $e');
      }
    }

    return (inserted, skipped);
  }
}

/// Immutable result of an alert scan.
class AlertScanResult {
  final int stockInserted;
  final int stockSkipped;
  final int expiryInserted;
  final int expirySkipped;

  const AlertScanResult({
    required this.stockInserted,
    required this.stockSkipped,
    required this.expiryInserted,
    required this.expirySkipped,
  });

  int get totalInserted => stockInserted + expiryInserted;
  int get totalSkipped => stockSkipped + expirySkipped;

  @override
  String toString() =>
      'AlertScanResult(stockInserted: $stockInserted, stockSkipped: $stockSkipped, '
      'expiryInserted: $expiryInserted, expirySkipped: $expirySkipped)';
}

/// Immutable summary of current alert counts (no DB writes).
class AlertSummary {
  final int lowStockCount;
  final int outOfStockCount;
  final int expiringSoonCount;
  final int expiredCount;

  const AlertSummary({
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.expiringSoonCount,
    required this.expiredCount,
  });

  int get totalAlertCount =>
      lowStockCount + outOfStockCount + expiringSoonCount + expiredCount;

  @override
  String toString() =>
      'AlertSummary(lowStock: $lowStockCount, outOfStock: $outOfStockCount, '
      'expiringSoon: $expiringSoonCount, expired: $expiredCount)';
}

/// Internal configuration loaded from the settings table.
class _AlertConfig {
  final bool stockAlertEnabled;
  final bool expiryAlertEnabled;
  final int expiryAlertDays;

  const _AlertConfig({
    required this.stockAlertEnabled,
    required this.expiryAlertEnabled,
    required this.expiryAlertDays,
  });
}
