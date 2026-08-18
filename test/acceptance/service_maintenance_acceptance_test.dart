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

  Future<int> createCustomer(String name) async {
    return db.insert('customers', {
      'name': name,
      'balance': 0,
      'balance_type': 'credit',
      'currency': 'YER',
      'created_at': '2026-08-18T00:00:00.000Z',
      'updated_at': '2026-08-18T00:00:00.000Z',
    });
  }

  ServiceOrder order(String id, int customerId) => ServiceOrder(
        id: id,
        orderNumber: 'ACC-$id',
        customerId: customerId,
        receivedAt: DateTime.utc(2026, 8, 18),
        total: 100,
        remaining: 100,
      );

  Future<void> makeReady(String orderId) async {
    await service.transitionStatus(orderId: orderId, toStatus: 'received');
    await service.transitionStatus(orderId: orderId, toStatus: 'diagnosing');
    await service.transitionStatus(orderId: orderId, toStatus: 'in_progress');
    await service.transitionStatus(orderId: orderId, toStatus: 'ready');
  }

  Future<void> addServiceLine(String orderId) async {
    await service.addLine(
      orderId: orderId,
      line: ServiceOrderLine(
        serviceOrderId: orderId,
        lineType: 'service',
        description: 'Phone software repair',
        quantity: 1,
        unitPrice: 100,
        lineTotal: 100,
      ),
    );
  }

  test('service-only lifecycle posts balanced revenue without inventory movement',
      () async {
    final customerId = await createCustomer('Acceptance Customer 1');
    await ensureAccount('1200', 'Customer receivable');
    await ensureAccount('4100', 'Service revenue');
    await service.createDraft(order: order('SO-ACC-1', customerId));
    await addServiceLine('SO-ACC-1');
    await makeReady('SO-ACC-1');

    await service.postServiceOrder(orderId: 'SO-ACC-1');

    final orderRow = (await db.query(
      'service_orders',
      where: 'id = ?',
      whereArgs: ['SO-ACC-1'],
    )).single;
    expect(orderRow['is_posted'], 1);
    expect(orderRow['posted_journal_id'], isNotNull);

    final movements = await db.query(
      'stock_movements',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['service_order', 'SO-ACC-1'],
    );
    expect(movements, isEmpty);

    final transactions = await db.query(
      'transactions',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['service_order', 'SO-ACC-1'],
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

  test('posted service cancellation preserves original journal and records reason',
      () async {
    final customerId = await createCustomer('Acceptance Customer 2');
    await ensureAccount('1200', 'Customer receivable');
    await ensureAccount('4100', 'Service revenue');
    await service.createDraft(order: order('SO-ACC-2', customerId));
    await addServiceLine('SO-ACC-2');
    await makeReady('SO-ACC-2');
    await service.postServiceOrder(orderId: 'SO-ACC-2');

    final posted = (await db.query(
      'service_orders',
      where: 'id = ?',
      whereArgs: ['SO-ACC-2'],
    )).single;
    final originalJournalId = posted['posted_journal_id'];
    final originalRows = await db.query(
      'transactions',
      where: 'journal_id = ?',
      whereArgs: [originalJournalId],
    );

    await service.cancelServiceOrder(
      orderId: 'SO-ACC-2',
      reason: 'Customer cancelled the repair',
    );

    final cancelled = (await db.query(
      'service_orders',
      where: 'id = ?',
      whereArgs: ['SO-ACC-2'],
    )).single;
    expect(cancelled['status'], 'cancelled');
    expect(cancelled['posted_journal_id'], originalJournalId);

    final preservedRows = await db.query(
      'transactions',
      where: 'journal_id = ?',
      whereArgs: [originalJournalId],
    );
    expect(preservedRows, hasLength(originalRows.length));

    final reversalRows = await db.query(
      'transactions',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['service_order_reversal', 'SO-ACC-2'],
    );
    expect(reversalRows, hasLength(originalRows.length));
    expect(
      reversalRows.fold<int>(
        0,
        (sum, row) => sum + (row['debit'] as num).toInt(),
      ),
      MoneyHelper.toCents(100),
    );
    expect(
      reversalRows.fold<int>(
        0,
        (sum, row) => sum + (row['credit'] as num).toInt(),
      ),
      MoneyHelper.toCents(100),
    );

    final history = await db.query(
      'service_status_history',
      where: 'service_order_id = ? AND to_status = ? AND note = ?',
      whereArgs: [
        'SO-ACC-2',
        'cancelled',
        'Customer cancelled the repair',
      ],
    );
    expect(history, hasLength(1));
  });
}
