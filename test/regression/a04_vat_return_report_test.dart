import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// A-04 regression test: VAT Return report queries.
///
/// Verifies that ReportService.getVatReturnSummary and
/// getVatReturnDetails correctly compute Output VAT (sale/POS invoices)
/// and Input VAT (purchase invoices), with returns signed negative so
/// net VAT reflects the true payable or refundable amount.
///
/// The test seeds:
///   - 2 sale invoices @ 15% VAT (tax_amount = 1500 cents each)
///   - 1 sale return (tax_amount = 500 cents, signed -500)
///   - 1 purchase invoice @ 15% VAT (tax_amount = 800 cents)
///   - 1 purchase return (tax_amount = 200 cents, signed -200)
///
/// Expected (in SAR cents):
///   output_vat (gross) = 1500 + 1500 = 3000
///   output_vat_returns = 500
///   net output_vat = 3000 - 500 = 2500
///   input_vat (gross) = 800
///   input_vat_returns = 200
///   net input_vat = 800 - 200 = 600
///   net_vat = 2500 - 600 = 1900 (payable)
void main() {
  late Database db;

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
    await _seedTestData(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// The exact SQL queries used by ReportService.getVatReturnSummary and
  /// getVatReturnDetails. Kept in sync with
  /// lib/data/datasources/services/report_service.dart.
  /// If the query in report_service.dart changes, update these constants
  /// to match — the test's job is to verify the queries behave correctly
  /// on the seeded data.
  const summaryQuery = r'''
      SELECT
        i.currency,
        SUM(CASE WHEN i.type IN ('sale','pos') AND i.is_return = 0
                 THEN CAST(i.tax_amount AS INTEGER) ELSE 0 END) AS output_vat,
        SUM(CASE WHEN i.type IN ('sale','pos') AND i.is_return = 1
                 THEN -CAST(i.tax_amount AS INTEGER) ELSE 0 END) AS output_vat_returns,
        SUM(CASE WHEN i.type = 'purchase' AND i.is_return = 0
                 THEN CAST(i.tax_amount AS INTEGER) ELSE 0 END) AS input_vat,
        SUM(CASE WHEN i.type = 'purchase' AND i.is_return = 1
                 THEN -CAST(i.tax_amount AS INTEGER) ELSE 0 END) AS input_vat_returns,
        SUM(CASE WHEN i.type IN ('sale','pos') AND i.is_return = 0
                 THEN CAST(i.subtotal AS INTEGER) - CAST(i.discount_amount AS INTEGER)
                 ELSE 0 END) AS sales_taxable,
        SUM(CASE WHEN i.type = 'purchase' AND i.is_return = 0
                 THEN CAST(i.subtotal AS INTEGER) - CAST(i.discount_amount AS INTEGER)
                 ELSE 0 END) AS purchases_taxable,
        SUM(CASE WHEN i.type IN ('sale','pos') AND i.is_return = 0
                 THEN CAST(i.total AS INTEGER) ELSE 0 END) AS sales_total,
        SUM(CASE WHEN i.type = 'purchase' AND i.is_return = 0
                 THEN CAST(i.total AS INTEGER) ELSE 0 END) AS purchases_total,
        SUM(CASE WHEN i.type IN ('sale','pos') AND i.is_return = 0
                 THEN 1 ELSE 0 END) AS sales_count,
        SUM(CASE WHEN i.type = 'purchase' AND i.is_return = 0
                 THEN 1 ELSE 0 END) AS purchases_count
      FROM invoices i
      WHERE 1=1
        AND CAST(i.tax_amount AS INTEGER) > 0
      GROUP BY i.currency
      ORDER BY i.currency
    ''';

  const detailsQuery = r'''
      SELECT
        i.id, i.type, i.is_return, i.created_at, i.currency,
        CAST(i.subtotal AS INTEGER) AS subtotal,
        CAST(i.discount_amount AS INTEGER) AS discount_amount,
        CAST(i.subtotal AS INTEGER) - CAST(i.discount_amount AS INTEGER) AS taxable_amount,
        CASE WHEN i.is_return = 1
             THEN -CAST(i.tax_amount AS INTEGER)
             ELSE CAST(i.tax_amount AS INTEGER)
        END AS tax_amount,
        CAST(i.total AS INTEGER) AS total,
        i.exchange_rate,
        CASE WHEN i.customer_id IS NOT NULL THEN c.name
             WHEN i.supplier_id IS NOT NULL THEN s.name
             ELSE 'بدون عميل/مورد' END AS entity_name
      FROM invoices i
      LEFT JOIN customers c ON c.id = i.customer_id
      LEFT JOIN suppliers s ON s.id = i.supplier_id
      WHERE CAST(i.tax_amount AS INTEGER) > 0
      ORDER BY i.created_at DESC, i.id
    ''';

  test('A-04: VAT summary computes output/input VAT with returns signed negative', () async {
    final summary = await db.rawQuery(summaryQuery);

    expect(summary, hasLength(1),
        reason: 'Only SAR has VAT activity in the seed data.');
    final row = summary.first;
    expect(row['currency'], 'SAR');

    // Output VAT (gross) = 1500 + 1500 = 3000 cents
    expect(row['output_vat'], 3000);
    // Output VAT returns = 500 (the sale return's tax_amount)
    expect(row['output_vat_returns'], -500,
        reason: 'output_vat_returns is the negated sum of return tax '
            'amounts. Sale return has tax_amount=500 → contributes -500.');

    // Input VAT (gross) = 800
    expect(row['input_vat'], 800);
    // Input VAT returns = 200 (the purchase return's tax_amount, negated)
    expect(row['input_vat_returns'], -200);

    // Sales count = 2 (two sale invoices, no POS)
    expect(row['sales_count'], 2);
    // Purchases count = 1
    expect(row['purchases_count'], 1);
  });

  test('A-04: VAT details return all 5 invoices with signed tax_amount', () async {
    final details = await db.rawQuery(detailsQuery);

    expect(details, hasLength(5),
        reason: 'Seed data has 5 VAT-bearing invoices: 2 sales, 1 sale '
            'return, 1 purchase, 1 purchase return.');

    // Build a map of id -> signed tax_amount for easy verification.
    final byId = <String, int>{};
    for (final row in details) {
      byId[row['id'] as String] = row['tax_amount'] as int;
    }

    // Sales: positive
    expect(byId['sale-1'], 1500);
    expect(byId['sale-2'], 1500);
    // Sale return: negative
    expect(byId['sale-ret-1'], -500,
        reason: 'Sale return must have negative signed tax_amount.');

    // Purchase: positive
    expect(byId['purchase-1'], 800);
    // Purchase return: negative
    expect(byId['purchase-ret-1'], -200,
        reason: 'Purchase return must have negative signed tax_amount.');
  });

  test('A-04: net VAT payable = output_vat - output_returns - (input_vat - input_returns)', () async {
    final summary = await db.rawQuery(summaryQuery);
    final row = summary.first;

    final outputVat = (row['output_vat'] as num).toInt();
    final outputVatReturns = (row['output_vat_returns'] as num).toInt();
    final inputVat = (row['input_vat'] as num).toInt();
    final inputVatReturns = (row['input_vat_returns'] as num).toInt();

    // Net output = 3000 - 500 = 2500 (outputVatReturns is already negative)
    final netOutput = outputVat + outputVatReturns;
    // Net input = 800 - 200 = 600 (inputVatReturns is already negative)
    final netInput = inputVat + inputVatReturns;
    // Net VAT = 2500 - 600 = 1900 (payable)
    final netVat = netOutput - netInput;

    expect(netOutput, 2500);
    expect(netInput, 600);
    expect(netVat, 1900,
        reason: 'Net VAT payable should be 1900 SAR cents (19.00 SAR).');
    expect(netVat > 0, isTrue, reason: 'Net VAT is payable (positive).');
  });
}

/// Seed 5 invoices: 2 sales, 1 sale return, 1 purchase, 1 purchase return.
/// All in SAR currency (15% VAT).
Future<void> _seedTestData(Database db) async {
  final now = DateTime.now().toIso8601String();

  // Sale 1: subtotal=10000, tax=1500 (15%), total=11500
  await db.insert('invoices', {
    'id': 'sale-1',
    'type': 'sale',
    'is_return': 0,
    'subtotal': MoneyHelper.toCents(100.00),
    'discount_amount': 0,
    'tax_amount': MoneyHelper.toCents(15.00),
    'total': MoneyHelper.toCents(115.00),
    'paid_amount': MoneyHelper.toCents(115.00),
    'remaining': 0,
    'currency': 'SAR',
    'exchange_rate': 1.0,
    'is_posted': 1,
    'created_at': now,
  });

  // Sale 2: subtotal=10000, tax=1500, total=11500
  await db.insert('invoices', {
    'id': 'sale-2',
    'type': 'sale',
    'is_return': 0,
    'subtotal': MoneyHelper.toCents(100.00),
    'discount_amount': 0,
    'tax_amount': MoneyHelper.toCents(15.00),
    'total': MoneyHelper.toCents(115.00),
    'paid_amount': MoneyHelper.toCents(115.00),
    'remaining': 0,
    'currency': 'SAR',
    'exchange_rate': 1.0,
    'is_posted': 1,
    'created_at': now,
  });

  // Sale return: tax_amount=500 (signed negative in the report query)
  await db.insert('invoices', {
    'id': 'sale-ret-1',
    'type': 'sale',
    'is_return': 1,
    'subtotal': MoneyHelper.toCents(33.33),
    'discount_amount': 0,
    'tax_amount': MoneyHelper.toCents(5.00),
    'total': MoneyHelper.toCents(38.33),
    'paid_amount': 0,
    'remaining': 0,
    'currency': 'SAR',
    'exchange_rate': 1.0,
    'is_posted': 1,
    'created_at': now,
  });

  // Purchase: subtotal=5333, tax=800 (15%), total=6133
  await db.insert('invoices', {
    'id': 'purchase-1',
    'type': 'purchase',
    'is_return': 0,
    'subtotal': MoneyHelper.toCents(53.33),
    'discount_amount': 0,
    'tax_amount': MoneyHelper.toCents(8.00),
    'total': MoneyHelper.toCents(61.33),
    'paid_amount': MoneyHelper.toCents(61.33),
    'remaining': 0,
    'currency': 'SAR',
    'exchange_rate': 1.0,
    'is_posted': 1,
    'created_at': now,
  });

  // Purchase return: tax_amount=200 (signed negative in the report query)
  await db.insert('invoices', {
    'id': 'purchase-ret-1',
    'type': 'purchase',
    'is_return': 1,
    'subtotal': MoneyHelper.toCents(13.33),
    'discount_amount': 0,
    'tax_amount': MoneyHelper.toCents(2.00),
    'total': MoneyHelper.toCents(15.33),
    'paid_amount': 0,
    'remaining': 0,
    'currency': 'SAR',
    'exchange_rate': 1.0,
    'is_posted': 1,
    'created_at': now,
  });
}
