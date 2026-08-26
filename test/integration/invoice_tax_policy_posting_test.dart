import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/core/finance/tax_policy_resolver.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/repositories/invoice_repository.dart';
import 'package:firstpro/data/datasources/repositories/tax_policy_repository.dart';
import 'package:firstpro/data/datasources/services/base_currency_service.dart';
import 'package:firstpro/data/models/tax_profile_model.dart';

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
      version: 59,
      onCreate: (database, version) => DatabaseSchema.onCreate(database, version),
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
    DatabaseHelper.useTestDatabase(db);
    dbHelper = DatabaseHelper();
    locator.registerSingleton<BaseCurrencyService>(BaseCurrencyService(dbHelper));
  });

  tearDown(() async {
    await locator.reset();
    DatabaseHelper.clearTestDatabase();
    await db.close();
  });

  test('posted invoice stores an immutable tax snapshot from active policy', () async {
    await db.insert('business_profile', {
      'id': 1,
      'country_code': 'XX',
      'base_currency_code': 'YER',
      'locale': 'ar',
      'timezone': 'Asia/Aden',
      'tax_mode': 'standard',
      'setup_status': 'complete',
      'setup_version': 1,
      'source': 'test',
      'created_at': '2026-08-26T10:00:00.000Z',
      'updated_at': '2026-08-26T10:00:00.000Z',
    });
    final taxPolicies = TaxPolicyRepository(dbHelper);
    await taxPolicies.save(TaxProfile(
      countryCode: 'XX',
      regimeCode: 'standard',
      nameAr: 'ضريبة اختبارية',
      rateBasisPoints: 1000,
      calculationMethod: 'exclusive',
      transportTaxable: true,
      validFrom: DateTime.utc(2026, 1, 1),
      requiresConfirmation: false,
      isActive: true,
    ));
    final productId = await db.insert('products', {
      'item_code': 'TAX-POST-001',
      'name_ar': 'صنف ضريبي',
      'name_en': 'Tax product',
      'cost_price': 100,
      'average_cost': 100,
      'sell_price': 1000,
      'current_stock': 1.0,
      'track_stock': 1,
      'product_kind': 'stock',
      'is_active': 1,
      'is_sellable': 1,
      'is_purchasable': 1,
      'allow_negative': 0,
      'currency': 'YER',
      'costing_method': 'weighted_average',
      'created_at': '2026-08-26T10:00:00.000Z',
      'updated_at': '2026-08-26T10:00:00.000Z',
    });
    final invoices = InvoiceRepository(
      dbHelper,
      taxPolicyResolver: TaxPolicyResolver(taxPolicies),
    );

    await invoices.saveInvoiceWithJournalEntries(
      {
        'id': 'INV-TAX-POST-1',
        'type': 'sale',
        'payment_mechanism': 'cash',
        'payment_method': 'cash',
        'is_return': 0,
        'subtotal': 10.0,
        'discount_amount': 0.0,
        'tax_amount': 1.10,
        'total': 12.10,
        'paid_amount': 12.10,
        'remaining': 0.0,
        'status': 'posted',
        'currency': 'YER',
        'exchange_rate': 1.0,
        'transport_charges': 1.0,
        'created_at': '2026-08-26T10:00:00.000Z',
      },
      [
        {
          'invoice_id': 'INV-TAX-POST-1',
          'product_id': productId,
          'product_name': 'صنف ضريبي',
          'quantity': 1.0,
          'unit_price': 10.0,
          'total_price': 10.0,
          'unit_cost': 1.0,
          'conversion_factor': 1.0,
          'base_quantity': 1.0,
        },
      ],
      invoiceType: 'sale',
      paymentMechanism: 'cash',
      isReturn: false,
      paidAmount: 12.10,
    );

    final snapshot = (await db.query(
      'document_tax_snapshots',
      where: 'document_type = ? AND document_id = ?',
      whereArgs: ['invoice', 'INV-TAX-POST-1'],
    )).single;
    expect(snapshot['rate_bps'], 1000);
    expect(snapshot['transport_taxable'], 1);
    expect(snapshot['taxable_subtotal_minor'], 1000);
    expect(snapshot['taxable_transport_minor'], 100);
    expect(snapshot['tax_minor'], 110);
  });
}
