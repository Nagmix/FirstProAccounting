import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/repositories/invoice_repository.dart';
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
    await db.update('business_profile', {
      'business_name': null,
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
    }, where: 'id = ?', whereArgs: [1]);
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
    for (final code in const ['1100', '1300', '2300', '3200', '4100']) {
      final existing = await db.query(
        'accounts',
        columns: ['id'],
        where: 'account_code = ? AND currency = ?',
        whereArgs: [code, 'YER'],
        limit: 1,
      );
      if (existing.isNotEmpty) continue;
      final accountType = code.startsWith('4')
          ? 'REVENUE'
          : (code.startsWith('2') ? 'LIABILITY' : (code.startsWith('3') ? 'EXPENSE' : 'ASSET'));
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
        'created_at': '2026-08-26T10:00:00.000Z',
        'updated_at': '2026-08-26T10:00:00.000Z',
      });
    }
    final productId = await db.insert('products', {
      'item_code': 'POS-TAX-ITEM-1',
      'name_ar': 'صنف POS ضريبي',
      'name_en': 'POS taxed item',
      'cost_price': MoneyHelper.toCents(20),
      'average_cost': MoneyHelper.toCents(20),
      'sell_price': MoneyHelper.toCents(1000),
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
    await db.insert('invoice_items', {
      'invoice_id': 'POS-TAX-POST-1',
      'product_id': productId,
      'product_name': 'صنف POS ضريبي',
      'quantity': 1.0,
      'unit_price': 1000,
      'total_price': 1000,
      'unit_cost': 20,
      'base_quantity': 1.0,
      'conversion_factor': 1.0,
    });
    await db.insert('stock_movements', {
      'product_id': productId,
      'movement_type': 'sale',
      'quantity': -1.0,
      'reference_type': 'pos',
      'reference_id': 'POS-TAX-POST-1',
      'unit_cost': 20,
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

    await InvoiceRepository(dbHelper).cancelInvoice('POS-TAX-POST-1');
    final reversalRecord = (await db.query(
      'document_reversals',
      columns: ['reversal_journal_id'],
      where: 'document_type = ? AND document_id = ?',
      whereArgs: ['invoice', 'POS-TAX-POST-1'],
    )).single;
    final reversalRows = await db.query(
      'transactions',
      where: 'journal_id = ?',
      whereArgs: [reversalRecord['reversal_journal_id']],
    );
    int totalFor(String code, String side) => reversalRows
        .where((row) => row['account_id'] != null)
        .where((row) => (side == 'debit' ? row['debit'] : row['credit']) != 0)
        .fold<int>(0, (sum, row) => sum + ((side == 'debit' ? row['debit'] : row['credit']) as num).toInt());
    final accountRows = await db.query('accounts', columns: ['id', 'account_code']);
    int amountForCode(String code, String side) {
      final accountId = accountRows.singleWhere((row) => row['account_code'] == code)['id'];
      return reversalRows
          .where((row) => row['account_id'] == accountId)
          .fold<int>(0, (sum, row) => sum + ((side == 'debit' ? row['debit'] : row['credit']) as num).toInt());
    }
    expect(totalFor('ignored', 'debit'), 1230);
    expect(totalFor('ignored', 'credit'), 1230);
    expect(amountForCode('4100', 'debit'), 1100);
    expect(amountForCode('2300', 'debit'), 110);
    expect(amountForCode('1100', 'credit'), 1210);
    expect((await db.query('products', where: 'id = ?', whereArgs: [productId])).single['current_stock'], 2.0);
    final snapshotAfter = (await db.query(
      'document_tax_snapshots',
      where: 'document_type = ? AND document_id = ?',
      whereArgs: ['invoice', 'POS-TAX-POST-1'],
    )).single;
    expect(snapshotAfter, snapshot);
  });
}
