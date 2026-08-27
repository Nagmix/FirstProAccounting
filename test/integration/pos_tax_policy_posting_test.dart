import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/core/finance/tax_policy_resolver.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/repositories/tax_policy_repository.dart';
import 'package:firstpro/data/datasources/services/base_currency_service.dart';
import 'package:firstpro/data/datasources/services/shift_service.dart';
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

  test('posting deferred POS invoice stores policy tax snapshot', () async {
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
    final policies = TaxPolicyRepository(dbHelper);
    await policies.save(TaxProfile(
      countryCode: 'XX',
      regimeCode: 'standard',
      nameAr: 'ضريبة POS',
      rateBasisPoints: 1000,
      calculationMethod: 'exclusive',
      transportTaxable: true,
      validFrom: DateTime.utc(2026, 1, 1),
      requiresConfirmation: false,
      isActive: true,
    ));
    final cashBoxId = await db.insert('cash_boxes', {
      'name': 'صندوق POS',
      'type': 'cash_box',
      'currency': 'YER',
      'balance': 0,
      'balance_type': 'credit',
      'is_active': 1,
      'created_at': '2026-08-26T10:00:00.000Z',
      'updated_at': '2026-08-26T10:00:00.000Z',
    });
    final shiftId = await db.insert('shifts', {
      'shift_number': 'SHIFT-TAX-1',
      'cash_box_id': cashBoxId,
      'opening_amount': 0,
      'status': 'open',
      'opened_at': '2026-08-26T10:00:00.000Z',
      'currency': 'YER',
      'created_at': '2026-08-26T10:00:00.000Z',
      'updated_at': '2026-08-26T10:00:00.000Z',
    });
    await db.insert('invoices', {
      'id': 'POS-TAX-POST-1',
      'type': 'pos',
      'payment_mechanism': 'cash',
      'payment_method': 'cash',
      'is_return': 0,
      'shift_id': shiftId,
      'cash_box_id': cashBoxId,
      'subtotal': 1000,
      'discount_amount': 0,
      'tax_amount': 110,
      'transport_charges': 100,
      'total': 1210,
      'paid_amount': 1210,
      'remaining': 0,
      'status': 'paid',
      'currency': 'YER',
      'exchange_rate': 1.0,
      'is_posted': 0,
      'created_at': '2026-08-26T10:00:00.000Z',
    });

    final service = ShiftService(
      dbHelper,
      taxPolicyResolver: TaxPolicyResolver(policies),
    );
    await service.postShiftInvoices(shiftId);

    final snapshot = (await db.query(
      'document_tax_snapshots',
      where: 'document_type = ? AND document_id = ?',
      whereArgs: ['invoice', 'POS-TAX-POST-1'],
    )).single;
    expect(snapshot['rate_bps'], 1000);
    expect(snapshot['transport_taxable'], 1);
    expect(snapshot['taxable_transport_minor'], 100);
    expect(snapshot['tax_minor'], 110);
  });
}
