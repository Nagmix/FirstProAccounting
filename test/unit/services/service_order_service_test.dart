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

  ServiceOrder draft() => ServiceOrder(
        id: 'SO-100',
        orderNumber: 'SRV-100',
        receivedAt: DateTime.utc(2026, 8, 18),
      );

  test('creates a draft and stores monetary columns as minor units', () async {
    await service.createDraft(order: draft());

    final row = (await db.query(
      'service_orders',
      where: 'id = ?',
      whereArgs: ['SO-100'],
    )).single;

    expect(row['status'], 'draft');
    expect(row['subtotal'], 0);
    expect(row['currency_code'], 'YER');
  });

  test('adds a line, recalculates totals, and records status history', () async {
    await service.createDraft(order: draft());
    await service.addLine(
      orderId: 'SO-100',
      line: ServiceOrderLine(
        serviceOrderId: 'SO-100',
        lineType: 'service',
        description: 'Screen repair',
        quantity: 1,
        unitPrice: 100.25,
        taxAmount: 15.04,
        lineTotal: 100.25,
      ),
    );
    await service.transitionStatus(
      orderId: 'SO-100',
      toStatus: 'received',
      note: 'Device received',
    );

    final order = await service.getById('SO-100');
    expect(order, isNotNull);
    expect(order!.subtotal, 100.25);
    expect(order.taxAmount, 15.04);
    expect(order.total, 115.29);

    final lines = await db.query('service_order_lines');
    expect(lines.single['unit_price'], MoneyHelper.toCents(100.25));
    expect(lines.single['tax_amount'], MoneyHelper.toCents(15.04));

    final history = await service.getStatusHistory('SO-100');
    expect(history, hasLength(1));
    expect(history.single['from_status'], 'draft');
    expect(history.single['to_status'], 'received');
  });

  test('rejects editing a posted order', () async {
    await service.createDraft(order: draft());
    await db.update(
      'service_orders',
      {'is_posted': 1, 'status': 'ready'},
      where: 'id = ?',
      whereArgs: ['SO-100'],
    );

    expect(
      () => service.addLine(
        orderId: 'SO-100',
        line: ServiceOrderLine(
          serviceOrderId: 'SO-100',
          lineType: 'service',
          description: 'Blocked edit',
          quantity: 1,
          unitPrice: 10,
          lineTotal: 10,
        ),
      ),
      throwsStateError,
    );
  });
}
