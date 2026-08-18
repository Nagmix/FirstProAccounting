import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/services/production_service.dart';
import 'package:firstpro/data/models/production_order_model.dart';

void main() {
  late Database db;
  late ProductionService service;
  late int rawProductId;
  late int finishedProductId;
  const now = '2026-08-19T00:00:00.000Z';

  Future<int> ensureAccount(String code, String name) async {
    final rows = await db.query(
      'accounts',
      columns: ['id'],
      where: 'account_code = ? AND currency = ?',
      whereArgs: [code, 'YER'],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.single['id'] as int;
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

  Future<int> insertProduct({
    required String name,
    required double stock,
    required double averageCost,
    required int inventoryAccountId,
  }) async {
    return db.insert('products', {
      'name_ar': name,
      'name_en': name,
      'item_code': 'P-${DateTime.now().microsecondsSinceEpoch}-$name',
      'costing_method': 'weighted_average',
      'current_stock': stock,
      'cost_price': MoneyHelper.toCents(averageCost),
      'average_cost': MoneyHelper.toCents(averageCost),
      'sell_price': MoneyHelper.toCents(averageCost * 2),
      'inventory_account_id': inventoryAccountId,
      'is_active': 1,
      'track_stock': 1,
      'product_kind': 'stock',
      'allow_negative': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> seedRecipe() async {
    final recipeId = await db.insert('recipes', {
      'output_product_id': finishedProductId,
      'name': 'وصفة الخبز الأساسية',
      'output_quantity': 1,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('recipe_lines', {
      'recipe_id': recipeId,
      'component_product_id': rawProductId,
      'quantity': 2,
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
    service = ProductionService(DatabaseHelper());

    rawProductId = await insertProduct(
      name: 'دقيق خام',
      stock: 10,
      averageCost: 5,
      inventoryAccountId: await ensureAccount('1301', 'مخزون المواد الخام'),
    );
    finishedProductId = await insertProduct(
      name: 'خبز تام',
      stock: 0,
      averageCost: 0,
      inventoryAccountId: await ensureAccount('1302', 'مخزون الإنتاج التام'),
    );
    await seedRecipe();
  });

  tearDown(() async {
    DatabaseHelper.clearTestDatabase();
    await db.close();
  });

  ProductionOrder _draft({double plannedQuantity = 2}) {
    return ProductionOrder(
      id: 'PO-2026-0001',
      orderNumber: 'PROD-2026-0001',
      recipeId: 1,
      outputProductId: finishedProductId,
      plannedQuantity: plannedQuantity,
      currencyCode: 'YER',
      exchangeRate: 1,
      notes: 'دفعة اختبار إنتاج خبز',
    );
  }

  Future<void> _createDraft({double plannedQuantity = 2}) async {
    await service.createDraft(order: _draft(plannedQuantity: plannedQuantity));
  }

  test('ينشئ أمر إنتاج مسودة بحالة draft وغير مرحّل', () async {
    await _createDraft();

    final row = (await db.query(
      'production_orders',
      where: 'id = ?',
      whereArgs: ['PO-2026-0001'],
    )).single;

    expect(row['status'], 'draft');
    expect(row['is_posted'], 0);
    expect(row['posted_journal_id'], isNull);
    expect(row['planned_quantity'], 2.0);
  });

  test('يرحّل الإنتاج باستهلاك الخام وإضافة المنتج التام وقيد متوازن', () async {
    await _createDraft();

    await service.postProduction(orderId: 'PO-2026-0001');

    final raw = (await db.query('products', where: 'id = ?', whereArgs: [rawProductId])).single;
    final finished = (await db.query('products', where: 'id = ?', whereArgs: [finishedProductId])).single;
    final order = (await db.query('production_orders', where: 'id = ?', whereArgs: ['PO-2026-0001'])).single;
    final consumption = (await db.query('production_consumptions')).single;
    final output = (await db.query('production_outputs')).single;
    final transactions = await db.query(
      'transactions',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['production', 'PO-2026-0001'],
    );

    expect((raw['current_stock'] as num).toDouble(), closeTo(6, 0.001));
    expect((finished['current_stock'] as num).toDouble(), closeTo(2, 0.001));
    expect((finished['average_cost'] as num).toInt(), MoneyHelper.toCents(10));
    expect(order['status'], 'completed');
    expect(order['is_posted'], 1);
    expect(order['posted_journal_id'], isNotNull);
    expect(consumption['quantity'], 4.0);
    expect(consumption['unit_cost'], MoneyHelper.toCents(5));
    expect(consumption['total_cost'], MoneyHelper.toCents(20));
    expect(output['quantity'], 2.0);
    expect(output['total_cost'], MoneyHelper.toCents(20));
    expect(transactions, hasLength(2));
    expect(
      transactions.fold<int>(0, (sum, row) => sum + (row['debit'] as num).toInt()),
      MoneyHelper.toCents(20),
    );
    expect(
      transactions.fold<int>(0, (sum, row) => sum + (row['credit'] as num).toInt()),
      MoneyHelper.toCents(20),
    );
  });

  test('يرفض نقص المخزون ويعيد كل آثار الترحيل إلى الحالة السابقة', () async {
    await db.update('products', {'current_stock': 1}, where: 'id = ?', whereArgs: [rawProductId]);
    await _createDraft();

    await expectLater(
      service.postProduction(orderId: 'PO-2026-0001'),
      throwsStateError,
    );

    final raw = (await db.query('products', where: 'id = ?', whereArgs: [rawProductId])).single;
    final order = (await db.query('production_orders', where: 'id = ?', whereArgs: ['PO-2026-0001'])).single;
    expect((raw['current_stock'] as num).toDouble(), closeTo(1, 0.001));
    expect(order['status'], 'draft');
    expect(order['is_posted'], 0);
    expect(await db.query('production_consumptions'), isEmpty);
    expect(await db.query('production_outputs'), isEmpty);
    expect(await db.query('stock_movements'), isEmpty);
    expect(await db.query('transactions'), isEmpty);
  });

  test('يمنع الترحيل المكرر دون مضاعفة المخزون أو القيود', () async {
    await _createDraft();
    await service.postProduction(orderId: 'PO-2026-0001');
    final beforeTransactions = await db.query('transactions');
    final beforeMovements = await db.query('stock_movements');

    await expectLater(
      service.postProduction(orderId: 'PO-2026-0001'),
      throwsStateError,
    );

    expect(await db.query('transactions'), hasLength(beforeTransactions.length));
    expect(await db.query('stock_movements'), hasLength(beforeMovements.length));
  });

  test('يلغي الإنتاج بقيد عكسي ولا يحذف القيد الأصلي', () async {
    await _createDraft();
    await service.postProduction(orderId: 'PO-2026-0001');
    final originalTransactions = await db.query(
      'transactions',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['production', 'PO-2026-0001'],
    );

    await service.cancelProduction(
      orderId: 'PO-2026-0001',
      reason: 'إلغاء دفعة الإنتاج للاختبار',
    );

    final raw = (await db.query('products', where: 'id = ?', whereArgs: [rawProductId])).single;
    final finished = (await db.query('products', where: 'id = ?', whereArgs: [finishedProductId])).single;
    final order = (await db.query('production_orders', where: 'id = ?', whereArgs: ['PO-2026-0001'])).single;
    final reversalTransactions = await db.query(
      'transactions',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['production_reversal', 'PO-2026-0001'],
    );

    expect(order['status'], 'cancelled');
    expect(order['is_posted'], 1);
    expect((raw['current_stock'] as num).toDouble(), closeTo(10, 0.001));
    expect((finished['current_stock'] as num).toDouble(), closeTo(0, 0.001));
    expect(originalTransactions, hasLength(2));
    expect(
      await db.query(
        'transactions',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['production', 'PO-2026-0001'],
      ),
      hasLength(2),
    );
    expect(reversalTransactions, hasLength(2));
    expect(
      reversalTransactions.fold<int>(0, (sum, row) => sum + (row['debit'] as num).toInt()),
      MoneyHelper.toCents(20),
    );
    expect(
      reversalTransactions.fold<int>(0, (sum, row) => sum + (row['credit'] as num).toInt()),
      MoneyHelper.toCents(20),
    );
  });
}
