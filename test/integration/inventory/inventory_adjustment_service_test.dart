import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/services/inventory_adjustment_service.dart';

void main() {
  late Database db;
  late InventoryAdjustmentService service;
  late int productId;
  late int inventoryAccountId;
  const now = '2026-08-19T00:00:00.000Z';

  Future<int> ensureAccount(String code, String name) async {
    final rows = await db.query(
      'accounts',
      columns: ['id'],
      where: 'account_code = ? AND currency = ?',
      whereArgs: [code, 'YER'],
      limit: 1,
    );
    if (rows.isNotEmpty) return (rows.single['id'] as num).toInt();
    return db.insert('accounts', {
      'name_ar': name,
      'name_en': name,
      'account_code': code,
      'account_type': 'ASSET',
      'balance': 0,
      'currency': 'YER',
      'balance_type': 'debit',
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 58,
      onCreate: (database, version) async {
        await DatabaseSchema.onCreate(database, version);
      },
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
    DatabaseHelper.useTestDatabase(db);
    inventoryAccountId = await ensureAccount('1301', 'مخزون الدقيق');
    productId = await db.insert('products', {
      'item_code': 'FLOUR-001',
      'name_ar': 'دقيق',
      'name_en': 'Flour',
      'cost_price': MoneyHelper.toCents(5),
      'average_cost': MoneyHelper.toCents(5),
      'sell_price': MoneyHelper.toCents(8),
      'inventory_account_id': inventoryAccountId,
      'current_stock': 24,
      'track_stock': 1,
      'product_kind': 'stock',
      'allow_negative': 0,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    service = InventoryAdjustmentService(DatabaseHelper());
  });

  tearDown(() async {
    DatabaseHelper.clearTestDatabase();
    await db.close();
  });

  InventoryAdjustmentDraft draft({double actualInPacks = 3}) {
    return InventoryAdjustmentDraft(
      voucherNumber: 'INV-2026-0001',
      date: now,
      description: 'جرد مخزون الدقيق',
      lines: [
        InventoryAdjustmentLine(
          productId: productId,
          actualQuantity: actualInPacks,
          conversionFactor: 12,
          unitCost: 5,
        ),
      ],
    );
  }

  test('ينشئ جرداً ويحوّل العبوات إلى الوحدة الأساسية ويثبت قيد التفاوت', () async {
    final voucherId = await service.createDraft(draft());
    await service.confirm(voucherId);

    final product = (await db.query('products', where: 'id = ?', whereArgs: [productId])).single;
    expect(product['current_stock'], 36.0);

    final movement = (await db.query(
      'stock_movements',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['inventory_adjustment', voucherId.toString()],
    )).single;
    expect(movement['quantity'], 12.0);

    final transactions = await db.query(
      'transactions',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['inventory_adjustment', voucherId.toString()],
    );
    expect(transactions, hasLength(2));
    expect(
      transactions.fold<int>(0, (sum, row) => sum + (row['debit'] as num).toInt()),
      MoneyHelper.toCents(60),
    );
    expect(
      transactions.fold<int>(0, (sum, row) => sum + (row['credit'] as num).toInt()),
      MoneyHelper.toCents(60),
    );
  });

  test('يرفض التسوية التي تؤدي إلى مخزون سالب مع rollback كامل', () async {
    final voucherId = await service.createDraft(draft(actualInPacks: 1));
    await db.update(
      'inventory_voucher_items',
      {'actual_quantity': -1, 'difference': -25},
      where: 'voucher_id = ?',
      whereArgs: [voucherId],
    );

    await expectLater(service.confirm(voucherId), throwsStateError);
    final product = (await db.query('products', where: 'id = ?', whereArgs: [productId])).single;
    expect(product['current_stock'], 24.0);
    expect(await db.query('stock_movements'), isEmpty);
    expect(await db.query('transactions'), isEmpty);
    expect((await db.query('inventory_vouchers', where: 'id = ?', whereArgs: [voucherId])).single['status'], 'draft');
  });

  test('يمنع التأكيد المكرر ويحافظ على الحركة والقيد الأصليين', () async {
    final voucherId = await service.createDraft(draft());
    await service.confirm(voucherId);
    await expectLater(service.confirm(voucherId), throwsStateError);

    expect(await db.query('stock_movements'), hasLength(1));
    expect(await db.query('transactions'), hasLength(2));
  });
}
