import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/services/service_order_service.dart';
import 'package:firstpro/data/models/service_order_line_model.dart';
import 'package:firstpro/data/models/service_order_model.dart';

void main() {
  late Database db;
  late ServiceOrderService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 57,
      onCreate: (database, version) async {
        await DatabaseSchema.onCreate(database, version);
      },
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
    DatabaseHelper.useTestDatabase(db);
    service = ServiceOrderService(DatabaseHelper());
  });

  tearDown(() async {
    DatabaseHelper.clearTestDatabase();
    await db.close();
  });

  Future<int> ensureAccount(String code, String name) async {
    final existing = await db.query(
      'accounts',
      columns: ['id'],
      where: 'account_code = ? AND currency = ?',
      whereArgs: [code, 'YER'],
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.single['id'] as int;
    return db.insert('accounts', {
      'name_ar': name,
      'name_en': name,
      'account_code': code,
      'account_type': code == '4100' ? 'REVENUE' : 'ASSET',
      'balance': 0,
      'currency': 'YER',
      'balance_type': code == '4100' ? 'credit' : 'debit',
      'is_active': 1,
      'created_at': '2026-08-18T00:00:00.000Z',
      'updated_at': '2026-08-18T00:00:00.000Z',
    });
  }

  Future<int> createCustomer() async {
    return db.insert('customers', {
      'name': 'Service Posting Customer',
      'balance': 0,
      'balance_type': 'credit',
      'currency': 'YER',
      'created_at': '2026-08-18T00:00:00.000Z',
      'updated_at': '2026-08-18T00:00:00.000Z',
    });
  }

  ServiceOrder order(int customerId) => ServiceOrder(
        id: 'SO-POST-1',
        orderNumber: 'SRV-POST-1',
        customerId: customerId,
        receivedAt: DateTime.utc(2026, 8, 18),
        total: 100,
        remaining: 100,
      );

  Future<void> makeReady() async {
    await service.transitionStatus(
      orderId: 'SO-POST-1',
      toStatus: 'received',
    );
    await service.transitionStatus(
      orderId: 'SO-POST-1',
      toStatus: 'diagnosing',
    );
    await service.transitionStatus(
      orderId: 'SO-POST-1',
      toStatus: 'in_progress',
    );
    await service.transitionStatus(
      orderId: 'SO-POST-1',
      toStatus: 'ready',
    );
  }

  test('posts a service-only order without stock movement or COGS', () async {
    final customerId = await createCustomer();
    await ensureAccount('1200', 'Customer receivable');
    await ensureAccount('4100', 'Service revenue');
    await service.createDraft(order: order(customerId));
    await service.addLine(
      orderId: 'SO-POST-1',
      line: ServiceOrderLine(
        serviceOrderId: 'SO-POST-1',
        lineType: 'service',
        description: 'Phone software repair',
        quantity: 1,
        unitPrice: 100,
        lineTotal: 100,
      ),
    );
    await makeReady();

    await service.postServiceOrder(orderId: 'SO-POST-1');

    final orderRow = (await db.query(
      'service_orders',
      where: 'id = ?',
      whereArgs: ['SO-POST-1'],
    )).single;
    expect(orderRow['is_posted'], 1);
    expect(orderRow['posted_journal_id'], isNotNull);

    final movements = await db.query(
      'stock_movements',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['service_order', 'SO-POST-1'],
    );
    expect(movements, isEmpty);

    final transactions = await db.query(
      'transactions',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['service_order', 'SO-POST-1'],
    );
    expect(transactions, hasLength(2));
    expect(
      transactions.fold<int>(
        0,
        (sum, row) => sum + (row['debit'] as num).toInt(),
      ),
      MoneyHelper.toCents(100),
    );
    expect(
      transactions.fold<int>(
        0,
        (sum, row) => sum + (row['credit'] as num).toInt(),
      ),
      MoneyHelper.toCents(100),
    );
  });

  test('rejects posting before ready and posting the same order twice', () async {
    final customerId = await createCustomer();
    await ensureAccount('1200', 'Customer receivable');
    await ensureAccount('4100', 'Service revenue');
    await service.createDraft(order: order(customerId));
    await service.addLine(
      orderId: 'SO-POST-1',
      line: ServiceOrderLine(
        serviceOrderId: 'SO-POST-1',
        lineType: 'service',
        description: 'Diagnostics',
        quantity: 1,
        unitPrice: 100,
        lineTotal: 100,
      ),
    );

    await expectLater(
      service.postServiceOrder(orderId: 'SO-POST-1'),
      throwsStateError,
    );

    await makeReady();
    await service.postServiceOrder(orderId: 'SO-POST-1');
    await expectLater(
      service.postServiceOrder(orderId: 'SO-POST-1'),
      throwsStateError,
    );
  });

  test('cancels a posted order by adding a reversal without deleting the original journal', () async {
    final customerId = await createCustomer();
    await ensureAccount('1200', 'Customer receivable');
    await ensureAccount('4100', 'Service revenue');
    await service.createDraft(order: order(customerId));
    await service.addLine(
      orderId: 'SO-POST-1',
      line: ServiceOrderLine(
        serviceOrderId: 'SO-POST-1',
        lineType: 'service',
        description: 'Warranty repair',
        quantity: 1,
        unitPrice: 100,
        lineTotal: 100,
      ),
    );
    await makeReady();
    await service.postServiceOrder(orderId: 'SO-POST-1');

    final original = await db.query(
      'transactions',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['service_order', 'SO-POST-1'],
    );
    await service.cancelServiceOrder(
      orderId: 'SO-POST-1',
      reason: 'Customer cancelled the repair',
    );

    final cancelled = (await db.query(
      'service_orders',
      where: 'id = ?',
      whereArgs: ['SO-POST-1'],
    )).single;
    expect(cancelled['status'], 'cancelled');
    expect(original, hasLength(2));
    expect(
      await db.query(
        'transactions',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['service_order', 'SO-POST-1'],
      ),
      hasLength(2),
    );
    expect(
      await db.query(
        'transactions',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['service_order_reversal', 'SO-POST-1'],
      ),
      hasLength(2),
    );
    final history = await service.getStatusHistory('SO-POST-1');
    expect(history.last['to_status'], 'cancelled');
    expect(history.last['note'], 'Customer cancelled the repair');
  });
}
