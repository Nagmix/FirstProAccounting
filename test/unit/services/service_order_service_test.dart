import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/services/service_order_service.dart';
import 'package:firstpro/data/models/service_order_line_model.dart';
import 'package:firstpro/data/models/service_order_device_model.dart';
import 'package:firstpro/data/models/service_order_model.dart';
import 'package:firstpro/data/models/service_payment_model.dart';
import 'package:firstpro/data/models/service_warranty_model.dart';

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

  test('stores devices and warranties under the service order', () async {
    await service.createDraft(order: draft());
    await service.addDevice(
      device: ServiceOrderDevice(
        serviceOrderId: 'SO-100',
        deviceType: 'phone',
        brand: 'Example',
        model: 'X1',
        imei: '123456789012345',
      ),
    );
    await service.addWarranty(
      warranty: ServiceWarranty(
        serviceOrderId: 'SO-100',
        serviceOrderLineId: null,
        startsAt: DateTime.utc(2026, 8, 18),
        endsAt: DateTime.utc(2026, 11, 18),
        terms: 'Repair warranty',
      ),
    );

    final devices = await service.getDevices('SO-100');
    final warranties = await service.getWarranties('SO-100');
    expect(devices, hasLength(1));
    expect(devices.single.imei, '123456789012345');
    expect(warranties, hasLength(1));
    expect(warranties.single.endsAt, DateTime.utc(2026, 11, 18));
  });

  test('records a payment with converted base amount and updates balance', () async {
    await service.createDraft(
      order: draft().copyWith(
        currencyCode: 'USD',
        total: 200,
        remaining: 200,
      ),
    );
    await service.createPayment(
      payment: ServicePayment(
        serviceOrderId: 'SO-100',
        amount: 100,
        currencyCode: 'USD',
        exchangeRate: 140,
        paymentDate: DateTime.utc(2026, 8, 18),
      ),
    );

    final payments = await service.getPayments('SO-100');
    final order = await service.getById('SO-100');
    expect(payments, hasLength(1));
    expect(payments.single.amount, 100);
    expect(payments.single.amountBase, 14000);
    expect(order!.paidAmount, 100);
    expect(order.remaining, 100);
  });

  test('rejects a payment that exceeds the service order total', () async {
    await service.createDraft(
      order: draft().copyWith(total: 50, remaining: 50),
    );

    expect(
      () => service.createPayment(
        payment: ServicePayment(
          serviceOrderId: 'SO-100',
          amount: 50.01,
          paymentDate: DateTime.utc(2026, 8, 18),
        ),
      ),
      throwsArgumentError,
    );
  });

  test('rejects a warranty linked to a missing line', () async {
    await service.createDraft(order: draft());

    expect(
      () => service.addWarranty(
        warranty: ServiceWarranty(
          serviceOrderId: 'SO-100',
          serviceOrderLineId: 404,
          startsAt: DateTime.utc(2026, 8, 18),
          endsAt: DateTime.utc(2026, 11, 18),
        ),
      ),
      throwsStateError,
    );
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

  test('posts a service payment as a balanced receipt journal exactly once', () async {
    final now = DateTime.utc(2026, 8, 18).toIso8601String();
    await db.insert('customers', {
      'name': 'Test Customer',
      'balance': 0,
      'balance_type': 'credit',
      'currency': 'YER',
      'created_at': now,
      'updated_at': now,
    });
    Future<int> accountIdForCode(String code) async {
      final rows = await db.query(
        'accounts',
        columns: ['id'],
        where: 'account_code = ? AND currency = ?',
        whereArgs: [code, 'YER'],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.single['id'] as int;
      return db.insert('accounts', {
        'name_ar': code == '1100' ? 'صندوق الاختبار' : 'عملاء الاختبار',
        'name_en': code == '1100'
            ? 'Test Cash'
            : 'Test Customer Receivable',
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
    final cashAccountId = await accountIdForCode('1100');
    final customerAccountId = await accountIdForCode('1200');
    final cashBoxId = await db.insert('cash_boxes', {
      'name': 'Test Cash Box',
      'type': 'cash_box',
      'currency': 'YER',
      'balance': 0,
      'balance_type': 'debit',
      'linked_account_id': cashAccountId,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    final customerId = (await db.query('customers')).single['id'] as int;
    await service.createDraft(
      order: draft().copyWith(
        customerId: customerId,
        total: 100,
        remaining: 100,
      ),
    );
    await service.createPayment(
      payment: ServicePayment(
        serviceOrderId: 'SO-100',
        amount: 50,
        cashBoxId: cashBoxId,
        paymentDate: DateTime.utc(2026, 8, 18),
      ),
    );
    final paymentId = ((await db.query('service_payments')).single['id'] as int);

    await service.postPayment(paymentId: paymentId);

    final payment = (await db.query(
      'service_payments',
      where: 'id = ?',
      whereArgs: [paymentId],
    )).single;
    expect(payment['is_posted'], 1);
    expect(payment['journal_id'], isA<int>());

    final transactions = await db.query(
      'transactions',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['service_payment', paymentId.toString()],
      orderBy: 'id ASC',
    );
    expect(transactions, hasLength(2));
    expect(transactions[0]['account_id'], cashAccountId);
    expect(transactions[0]['debit'], MoneyHelper.toCents(50));
    expect(transactions[1]['account_id'], customerAccountId);
    expect(transactions[1]['credit'], MoneyHelper.toCents(50));
    expect(transactions[0]['journal_id'], transactions[1]['journal_id']);

    expect(
      () => service.postPayment(paymentId: paymentId),
      throwsStateError,
    );
  });
}
