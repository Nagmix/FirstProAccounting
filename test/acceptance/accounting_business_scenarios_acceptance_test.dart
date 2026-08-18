import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/repositories/invoice_repository.dart';
import 'package:firstpro/data/datasources/services/base_currency_service.dart';
import 'package:firstpro/data/datasources/services/service_order_service.dart';
import 'package:firstpro/data/models/service_order_line_model.dart';
import 'package:firstpro/data/models/service_order_model.dart';

/// End-to-end accounting acceptance scenarios for the supported small-business
/// profiles: retail, credit/partial-payment sales, returns, and phone repair.
///
/// These tests intentionally exercise the real repositories/services against an
/// in-memory SQLite database instead of mirroring their arithmetic in helpers.
void main() {
  late Database db;
  late DatabaseHelper dbHelper;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await locator.reset();
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
    dbHelper = DatabaseHelper();
    locator.registerSingleton<BaseCurrencyService>(
      BaseCurrencyService(dbHelper),
    );
  });

  tearDown(() async {
    await locator.reset();
    DatabaseHelper.clearTestDatabase();
    await db.close();
  });

  test(
      'retail cycle: purchase, partial cash sale with VAT/discount/transport, and sale return stay balanced',
      () async {
    await _seedAccounts(db, const [
      '1100',
      '1200',
      '1300',
      '2100',
      '3100',
      '3200',
      '4100',
    ]);
    final productId = await _createProduct(
      db,
      code: 'RETAIL-001',
      name: 'هاتف اختبار',
      averageCost: 0,
      costPrice: 0,
      currentStock: 0,
    );
    final invoices = InvoiceRepository(dbHelper);

    await invoices.saveInvoiceWithJournalEntries(
      _invoice(
        id: 'PUR-ACCEPT-001',
        type: 'purchase',
        subtotal: 1000,
        total: 1000,
        paidAmount: 1000,
      ),
      [_item('PUR-ACCEPT-001', productId, quantity: 10, unitPrice: 100, total: 1000)],
      invoiceType: 'purchase',
      paymentMechanism: 'cash',
      isReturn: false,
      paidAmount: 1000,
    );

    var product = await _product(db, productId);
    expect(product['current_stock'], 10.0);
    expect(MoneyHelper.readMoney(product['average_cost']), 100.0);
    expect(
      await db.query('stock_movements',
          where: 'reference_id = ?', whereArgs: ['PUR-ACCEPT-001']),
      hasLength(1),
    );

    await invoices.saveInvoiceWithJournalEntries(
      _invoice(
        id: 'SALE-ACCEPT-001',
        type: 'sale',
        subtotal: 1250,
        discount: 50,
        tax: 120,
        transport: 30,
        total: 1350,
        paidAmount: 500,
      ),
      [_item('SALE-ACCEPT-001', productId, quantity: 5, unitPrice: 250, total: 1250)],
      invoiceType: 'sale',
      paymentMechanism: 'cash',
      isReturn: false,
      paidAmount: 500,
    );

    product = await _product(db, productId);
    expect(product['current_stock'], 5.0);
    final saleRows = await _journalRows(db, 'SALE-ACCEPT-001');
    expect(saleRows, hasLength(7));
    expect(_debitTotal(saleRows), MoneyHelper.toCents(1900));
    expect(_creditTotal(saleRows), MoneyHelper.toCents(1900));
    expect(_sumForCode(saleRows, '1100', 'debit'), MoneyHelper.toCents(500));
    expect(_sumForCode(saleRows, '1200', 'debit'), MoneyHelper.toCents(850));
    expect(_sumForCode(saleRows, '5400', 'debit'), MoneyHelper.toCents(50));
    expect(_sumForCode(saleRows, '4100', 'credit'), MoneyHelper.toCents(1280));
    expect(_sumForCode(saleRows, '2300', 'credit'), MoneyHelper.toCents(120));
    expect(_sumForCode(saleRows, '3200', 'debit'), MoneyHelper.toCents(500));
    expect(_sumForCode(saleRows, '1300', 'credit'), MoneyHelper.toCents(500));
    for (final row in saleRows.where((row) =>
        row['account_code'] == '3200' || row['account_code'] == '1300')) {
      expect(row['currency_code'], 'YER');
      expect(row['exchange_rate'], 1.0);
      expect(row['amount_base'], row['debit'] as int == 0 ? row['credit'] : row['debit']);
    }

    await invoices.saveInvoiceWithJournalEntries(
      _invoice(
        id: 'RET-ACCEPT-001',
        type: 'sale_return',
        isReturn: true,
        originalInvoiceId: 'SALE-ACCEPT-001',
        subtotal: 500,
        total: 500,
        paidAmount: 500,
      ),
      [
        _item(
          'RET-ACCEPT-001',
          productId,
          quantity: 2,
          unitPrice: 250,
          total: 500,
          unitCost: 100,
        ),
      ],
      invoiceType: 'sale_return',
      paymentMechanism: 'cash',
      isReturn: true,
      paidAmount: 500,
    );

    product = await _product(db, productId);
    expect(product['current_stock'], 7.0);
    final returnRows = await _journalRows(db, 'RET-ACCEPT-001');
    expect(returnRows, hasLength(4));
    expect(_debitTotal(returnRows), MoneyHelper.toCents(700));
    expect(_creditTotal(returnRows), MoneyHelper.toCents(700));
    expect(_sumForCode(returnRows, '4100', 'debit'), MoneyHelper.toCents(500));
    expect(_sumForCode(returnRows, '1100', 'credit'), MoneyHelper.toCents(500));
    expect(_sumForCode(returnRows, '1300', 'debit'), MoneyHelper.toCents(200));
    expect(_sumForCode(returnRows, '3200', 'credit'), MoneyHelper.toCents(200));
    expect(await db.query('invoices', where: 'id = ?', whereArgs: ['SALE-ACCEPT-001']), hasLength(1));
    expect(await db.query('transactions', where: 'reference_id = ?', whereArgs: ['SALE-ACCEPT-001']), isNotEmpty);
  });

  test('phone repair: service fee and spare part post together with only the part moving stock',
      () async {
    await _seedAccounts(db, const ['1200', '1300', '3200', '4100']);
    final customerId = await db.insert('customers', {
      'name': 'عميل صيانة قبول',
      'balance': 0,
      'balance_type': 'credit',
      'currency': 'YER',
      'created_at': _timestamp,
      'updated_at': _timestamp,
    });
    final partId = await _createProduct(
      db,
      code: 'PART-ACCEPT-001',
      name: 'شاشة هاتف',
      averageCost: 50,
      costPrice: 50,
      currentStock: 3,
    );
    final service = ServiceOrderService(dbHelper);
    final order = ServiceOrder(
      id: 'SO-ACCEPT-001',
      orderNumber: 'SRV-ACCEPT-001',
      customerId: customerId,
      receivedAt: DateTime.utc(2026, 8, 18),
      total: 150,
      remaining: 150,
    );

    await service.createDraft(order: order);
    await service.addLine(
      orderId: order.id,
      line: ServiceOrderLine(
        serviceOrderId: order.id,
        lineType: 'service',
        description: 'برمجة وإصلاح هاتف',
        quantity: 1,
        unitPrice: 100,
        lineTotal: 100,
      ),
    );
    await service.addLine(
      orderId: order.id,
      line: ServiceOrderLine(
        serviceOrderId: order.id,
        lineType: 'part',
        productId: partId,
        description: 'شاشة بديلة',
        quantity: 1,
        unitPrice: 50,
        unitCost: 50,
        lineTotal: 50,
      ),
    );
    for (final status in const ['received', 'diagnosing', 'in_progress', 'ready']) {
      await service.transitionStatus(orderId: order.id, toStatus: status);
    }
    await service.postServiceOrder(orderId: order.id);

    final product = await _product(db, partId);
    expect(product['current_stock'], 2.0);
    final movements = await db.query('stock_movements',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['service_order', order.id]);
    expect(movements, hasLength(1));
    expect(movements.single['quantity'], -1.0);
    expect(movements.single['unit_cost'], MoneyHelper.toCents(50));

    final rows = await _journalRows(db, order.id, referenceType: 'service_order');
    expect(rows, hasLength(4));
    expect(_debitTotal(rows), MoneyHelper.toCents(200));
    expect(_creditTotal(rows), MoneyHelper.toCents(200));
    expect(_sumForCode(rows, '1200', 'debit'), MoneyHelper.toCents(150));
    expect(_sumForCode(rows, '4100', 'credit'), MoneyHelper.toCents(150));
    expect(_sumForCode(rows, '3200', 'debit'), MoneyHelper.toCents(50));
    expect(_sumForCode(rows, '1300', 'credit'), MoneyHelper.toCents(50));
    for (final row in rows.where((row) =>
        row['account_code'] == '3200' || row['account_code'] == '1300')) {
      expect(row['currency_code'], 'YER');
      expect(row['exchange_rate'], 1.0);
      expect(row['amount_base'], row['debit'] as int == 0 ? row['credit'] : row['debit']);
    }
  });
}

const _timestamp = '2026-08-18T00:00:00.000Z';

Map<String, dynamic> _invoice({
  required String id,
  required String type,
  required double subtotal,
  required double total,
  double discount = 0,
  double tax = 0,
  double transport = 0,
  double paidAmount = 0,
  bool isReturn = false,
  String? originalInvoiceId,
}) {
  return {
    'id': id,
    'type': type,
    'payment_mechanism': 'cash',
    'payment_method': 'cash',
    'is_return': isReturn ? 1 : 0,
    'subtotal': subtotal,
    'discount_amount': discount,
    'tax_amount': tax,
    'total': total,
    'paid_amount': paidAmount,
    'remaining': total - paidAmount,
    'status': 'posted',
    'currency': 'YER',
    'exchange_rate': 1.0,
    'transport_charges': transport,
    'original_invoice_id': originalInvoiceId,
    'created_at': _timestamp,
  };
}

Map<String, dynamic> _item(
  String invoiceId,
  int productId, {
  required double quantity,
  required double unitPrice,
  required double total,
  double? unitCost,
}) {
  return {
    'invoice_id': invoiceId,
    'product_id': productId,
    'product_name': 'اختبار',
    'quantity': quantity,
    'unit_price': unitPrice,
    'total_price': total,
    'unit_cost': unitCost,
    'conversion_factor': 1.0,
    'base_quantity': quantity,
  };
}

Future<void> _seedAccounts(Database db, List<String> codes) async {
  for (final code in codes) {
    final accountType = code.startsWith('4') ? 'REVENUE' :
        (code.startsWith('2') ? 'LIABILITY' :
            (code.startsWith('3') || code.startsWith('5') ? 'EXPENSE' : 'ASSET'));
    await db.insert('accounts', {
      'name_ar': 'حساب $code',
      'name_en': 'Account $code',
      'account_code': code,
      'account_type': accountType,
      'balance': 0,
      'currency': 'YER',
      'balance_type': accountType == 'REVENUE' || accountType == 'LIABILITY' ? 'credit' : 'debit',
      'is_active': 1,
      'is_system': 1,
      'created_at': _timestamp,
      'updated_at': _timestamp,
    });
  }
}

Future<int> _createProduct(
  Database db, {
  required String code,
  required String name,
  required double averageCost,
  required double costPrice,
  required double currentStock,
}) {
  return db.insert('products', {
    'item_code': code,
    'name_ar': name,
    'name_en': name,
    'cost_price': MoneyHelper.toCents(costPrice),
    'average_cost': MoneyHelper.toCents(averageCost),
    'sell_price': MoneyHelper.toCents(250),
    'current_stock': currentStock,
    'track_stock': 1,
    'product_kind': 'stock',
    'is_active': 1,
    'is_sellable': 1,
    'is_purchasable': 1,
    'allow_negative': 0,
    'currency': 'YER',
    'costing_method': 'weighted_average',
    'created_at': _timestamp,
    'updated_at': _timestamp,
  });
}

Future<Map<String, dynamic>> _product(Database db, int id) async {
  return (await db.query('products', where: 'id = ?', whereArgs: [id], limit: 1)).single;
}

Future<List<Map<String, dynamic>>> _journalRows(
  Database db,
  String referenceId, {
  String? referenceType,
}) {
  final typeFilter = referenceType == null ? '' : ' AND t.reference_type = ?';
  final args = <dynamic>[referenceId];
  if (referenceType != null) args.add(referenceType);
  return db.rawQuery(
    'SELECT t.*, a.account_code FROM transactions t '
    'JOIN accounts a ON a.id = t.account_id '
    'WHERE t.reference_id = ?$typeFilter ORDER BY t.id',
    args,
  );
}

int _debitTotal(List<Map<String, dynamic>> rows) => rows.fold<int>(
      0,
      (sum, row) => sum + (row['debit'] as num).toInt(),
    );

int _creditTotal(List<Map<String, dynamic>> rows) => rows.fold<int>(
      0,
      (sum, row) => sum + (row['credit'] as num).toInt(),
    );

int _sumForCode(List<Map<String, dynamic>> rows, String code, String side) =>
    rows.where((row) => row['account_code'] == code).fold<int>(
          0,
          (sum, row) => sum + (row[side] as num).toInt(),
        );
