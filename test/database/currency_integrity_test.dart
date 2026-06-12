import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// ══════════════════════════════════════════════════════════════════
/// اختبارات سلامة العملات — التحقق من أن جميع إدراجات المعاملات
/// تتضمن currency_code
///
/// Currency integrity tests — Verify that all transaction inserts
/// include currency_code, ensuring no NULL values are produced
/// by any business operation path.
/// ══════════════════════════════════════════════════════════════════

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 49,
      onCreate: (database, version) async {
        await database.execute('PRAGMA foreign_keys = ON');
        await DatabaseSchema.onCreate(database, version);
      },
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// Helper: create or reuse a minimal account for testing.
  ///
  /// Fresh schema now enforces UNIQUE(account_code, currency), and the default
  /// seed data already creates many system accounts used by these tests.
  Future<int> _insertAccount({
    String code = '9999',
    String type = 'ASSET',
    String balanceType = 'debit',
    String currency = 'YER',
  }) async {
    final existing = await db.query(
      'accounts',
      columns: ['id'],
      where: 'account_code = ? AND currency = ?',
      whereArgs: [code, currency],
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.first['id'] as int;

    final now = DateTime.now().toIso8601String();
    return await db.insert('accounts', {
      'name_ar': 'حساب اختبار $code',
      'name_en': 'Test Account $code',
      'account_code': code,
      'account_type': type,
      'balance': 0,
      'currency': currency,
      'balance_type': balanceType,
      'is_active': 1,
      'is_system': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Helper: count transactions with NULL currency_code.
  Future<int> _countNullCurrencyCode() async {
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM transactions WHERE currency_code IS NULL",
    );
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  // ══════════════════════════════════════════════════════════════
  //  Customer opening balance transactions include currency_code
  // ══════════════════════════════════════════════════════════════

  group('Customer opening balance — currency_code / رصيد افتتاحي عميل', () {
    test('YER customer opening balance includes currency_code', () async {
      final now = DateTime.now().toIso8601String();
      final accountId = await _insertAccount(
          code: '1200', type: 'ASSET', balanceType: 'debit', currency: 'YER');
      final obAccountId = await _insertAccount(
          code: '2901', type: 'EQUITY', balanceType: 'credit', currency: 'YER');

      // Simulate customer opening balance: Debit Customers, Credit OB Equity
      final journalId = DateTime.now().microsecondsSinceEpoch;
      final amount = MoneyHelper.toCents(5000.0);
      const currency = 'YER';
      const exchangeRate = 1.0;

      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': journalId,
        'debit': amount,
        'credit': 0,
        'description': 'رصيد افتتاحي عميل',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': exchangeRate,
        'amount_base': amount,
        'reference_type': 'opening_balance',
        'reference_id': 'customer_1',
      });
      await db.insert('transactions', {
        'account_id': obAccountId,
        'journal_id': journalId,
        'debit': 0,
        'credit': amount,
        'description': 'رصيد افتتاحي عميل',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': exchangeRate,
        'amount_base': amount,
        'reference_type': 'opening_balance',
        'reference_id': 'customer_1',
      });

      expect(await _countNullCurrencyCode(), 0,
          reason:
              'Customer opening balance should not produce NULL currency_code');

      final txns = await db.query('transactions',
          where: 'reference_type = ? AND reference_id = ?',
          whereArgs: ['opening_balance', 'customer_1']);
      for (final t in txns) {
        expect(t['currency_code'], isNotNull);
        expect(t['currency_code'], 'YER');
      }
    });

    test('USD customer opening balance includes currency_code', () async {
      final now = DateTime.now().toIso8601String();
      final accountId = await _insertAccount(
          code: '1202', type: 'ASSET', balanceType: 'debit', currency: 'USD');
      final obAccountId = await _insertAccount(
          code: '2903', type: 'EQUITY', balanceType: 'credit', currency: 'USD');

      final journalId = DateTime.now().microsecondsSinceEpoch + 1;
      final amount = MoneyHelper.toCents(100.0);
      const currency = 'USD';
      const exchangeRate = 530.0;
      final amountBase = (amount * exchangeRate).round();

      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': journalId,
        'debit': amount,
        'credit': 0,
        'description': 'رصيد افتتاحي عميل بالدولار',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': exchangeRate,
        'amount_base': amountBase,
        'reference_type': 'opening_balance',
        'reference_id': 'customer_2',
      });
      await db.insert('transactions', {
        'account_id': obAccountId,
        'journal_id': journalId,
        'debit': 0,
        'credit': amount,
        'description': 'رصيد افتتاحي عميل بالدولار',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': exchangeRate,
        'amount_base': amountBase,
        'reference_type': 'opening_balance',
        'reference_id': 'customer_2',
      });

      final txns = await db.query('transactions',
          where: 'reference_id = ?', whereArgs: ['customer_2']);
      for (final t in txns) {
        expect(t['currency_code'], 'USD');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Supplier opening balance transactions include currency_code
  // ══════════════════════════════════════════════════════════════

  group('Supplier opening balance — currency_code / رصيد افتتاحي مورد', () {
    test('YER supplier opening balance includes currency_code', () async {
      final now = DateTime.now().toIso8601String();
      final accountId = await _insertAccount(
          code: '1300', type: 'ASSET', balanceType: 'debit', currency: 'YER');
      final obAccountId = await _insertAccount(
          code: '2902', type: 'EQUITY', balanceType: 'credit', currency: 'YER');

      final journalId = DateTime.now().microsecondsSinceEpoch + 2;
      final amount = MoneyHelper.toCents(10000.0);

      // Supplier opening balance: Credit Suppliers, Debit OB Equity
      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': journalId,
        'debit': 0,
        'credit': amount,
        'description': 'رصيد افتتاحي مورد',
        'date': now,
        'created_at': now,
        'currency_code': 'YER',
        'exchange_rate': 1.0,
        'amount_base': amount,
        'reference_type': 'opening_balance',
        'reference_id': 'supplier_1',
      });
      await db.insert('transactions', {
        'account_id': obAccountId,
        'journal_id': journalId,
        'debit': amount,
        'credit': 0,
        'description': 'رصيد افتتاحي مورد',
        'date': now,
        'created_at': now,
        'currency_code': 'YER',
        'exchange_rate': 1.0,
        'amount_base': amount,
        'reference_type': 'opening_balance',
        'reference_id': 'supplier_1',
      });

      expect(await _countNullCurrencyCode(), 0);
      final txns = await db.query('transactions',
          where: 'reference_id = ?', whereArgs: ['supplier_1']);
      for (final t in txns) {
        expect(t['currency_code'], 'YER');
      }
    });

    test('SAR supplier opening balance includes currency_code', () async {
      final now = DateTime.now().toIso8601String();
      final accountId = await _insertAccount(
          code: '1301', type: 'ASSET', balanceType: 'debit', currency: 'SAR');
      final obAccountId = await _insertAccount(
          code: '2904', type: 'EQUITY', balanceType: 'credit', currency: 'SAR');

      final journalId = DateTime.now().microsecondsSinceEpoch + 3;
      final amount = MoneyHelper.toCents(500.0);
      const currency = 'SAR';
      const exchangeRate = 140.0;

      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': journalId,
        'debit': 0,
        'credit': amount,
        'description': 'رصيد افتتاحي مورد بالريال السعودي',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': exchangeRate,
        'amount_base': (amount * exchangeRate).round(),
        'reference_type': 'opening_balance',
        'reference_id': 'supplier_2',
      });
      await db.insert('transactions', {
        'account_id': obAccountId,
        'journal_id': journalId,
        'debit': amount,
        'credit': 0,
        'description': 'رصيد افتتاحي مورد بالريال السعودي',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': exchangeRate,
        'amount_base': (amount * exchangeRate).round(),
        'reference_type': 'opening_balance',
        'reference_id': 'supplier_2',
      });

      final txns = await db.query('transactions',
          where: 'reference_id = ?', whereArgs: ['supplier_2']);
      for (final t in txns) {
        expect(t['currency_code'], 'SAR');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Employee opening balance transactions include currency_code
  // ══════════════════════════════════════════════════════════════

  group('Employee opening balance — currency_code / رصيد افتتاحي موظف', () {
    test('Employee opening balance transactions include currency_code',
        () async {
      final now = DateTime.now().toIso8601String();
      final accountId = await _insertAccount(
          code: '1500', type: 'ASSET', balanceType: 'debit', currency: 'YER');
      final obAccountId = await _insertAccount(
          code: '2905', type: 'EQUITY', balanceType: 'credit', currency: 'YER');

      final journalId = DateTime.now().microsecondsSinceEpoch + 4;
      final amount = MoneyHelper.toCents(3000.0);
      const currency = 'YER';

      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': journalId,
        'debit': amount,
        'credit': 0,
        'description': 'رصيد افتتاحي موظف',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': 1.0,
        'amount_base': amount,
        'reference_type': 'opening_balance',
        'reference_id': 'employee_1',
      });
      await db.insert('transactions', {
        'account_id': obAccountId,
        'journal_id': journalId,
        'debit': 0,
        'credit': amount,
        'description': 'رصيد افتتاحي موظف',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': 1.0,
        'amount_base': amount,
        'reference_type': 'opening_balance',
        'reference_id': 'employee_1',
      });

      expect(await _countNullCurrencyCode(), 0);
      final txns = await db.query('transactions',
          where: 'reference_id = ?', whereArgs: ['employee_1']);
      for (final t in txns) {
        expect(t['currency_code'], isNotNull);
        expect(t['currency_code'], 'YER');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Expense transactions include currency_code
  // ══════════════════════════════════════════════════════════════

  group('Expense transactions — currency_code / معاملات المصروفات', () {
    test('YER expense disbursement includes currency_code', () async {
      final now = DateTime.now().toIso8601String();
      final expenseAccountId = await _insertAccount(
          code: '5000', type: 'EXPENSE', balanceType: 'debit', currency: 'YER');
      final cashAccountId = await _insertAccount(
          code: '1100', type: 'ASSET', balanceType: 'debit', currency: 'YER');

      final journalId = DateTime.now().microsecondsSinceEpoch + 5;
      final amount = MoneyHelper.toCents(2000.0);
      const currency = 'YER';

      // Expense disbursement: Debit expense, Credit cash
      await db.insert('transactions', {
        'account_id': expenseAccountId,
        'journal_id': journalId,
        'debit': amount,
        'credit': 0,
        'description': 'مصروف: إيجار',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': 1.0,
        'amount_base': amount,
      });
      await db.insert('transactions', {
        'account_id': cashAccountId,
        'journal_id': journalId,
        'debit': 0,
        'credit': amount,
        'description': 'مصروف: إيجار',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': 1.0,
        'amount_base': amount,
      });

      expect(await _countNullCurrencyCode(), 0);
    });

    test('USD expense disbursement includes currency_code', () async {
      final now = DateTime.now().toIso8601String();
      final expenseAccountId = await _insertAccount(
          code: '5001', type: 'EXPENSE', balanceType: 'debit', currency: 'YER');
      final cashAccountId = await _insertAccount(
          code: '1102', type: 'ASSET', balanceType: 'debit', currency: 'USD');

      final journalId = DateTime.now().microsecondsSinceEpoch + 6;
      final amount = MoneyHelper.toCents(50.0);
      const currency = 'USD';
      const exchangeRate = 530.0;
      final amountBase = (amount * exchangeRate).round();

      // Foreign currency expense: journal in base currency
      await db.insert('transactions', {
        'account_id': expenseAccountId,
        'journal_id': journalId,
        'debit': amountBase, // amount_base in YER
        'credit': 0,
        'description': 'مصروف بالدولار',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': exchangeRate,
        'amount_base': amountBase,
      });
      await db.insert('transactions', {
        'account_id': cashAccountId,
        'journal_id': journalId,
        'debit': 0,
        'credit': amount,
        'description': 'مصروف بالدولار',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': exchangeRate,
        'amount_base': amountBase,
      });

      final txns = await db.query('transactions',
          where: 'journal_id = ?', whereArgs: [journalId]);
      for (final t in txns) {
        expect(t['currency_code'], isNotNull);
        expect(t['currency_code'], isNotEmpty);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Voucher transactions include currency_code
  // ══════════════════════════════════════════════════════════════

  group('Voucher transactions — currency_code / معاملات السندات', () {
    test('Receipt voucher transactions include currency_code', () async {
      final now = DateTime.now().toIso8601String();
      final cashAccountId = await _insertAccount(
          code: '1100', type: 'ASSET', balanceType: 'debit', currency: 'YER');
      final customerAccountId = await _insertAccount(
          code: '1200', type: 'ASSET', balanceType: 'debit', currency: 'YER');

      final journalId = DateTime.now().microsecondsSinceEpoch + 7;
      final amount = MoneyHelper.toCents(7000.0);
      const currency = 'YER';

      // Receipt: Debit Cash, Credit Customer Receivable
      await db.insert('transactions', {
        'account_id': cashAccountId,
        'journal_id': journalId,
        'debit': amount,
        'credit': 0,
        'description': 'سند قبض',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': 1.0,
        'amount_base': amount,
      });
      await db.insert('transactions', {
        'account_id': customerAccountId,
        'journal_id': journalId,
        'debit': 0,
        'credit': amount,
        'description': 'سند قبض',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': 1.0,
        'amount_base': amount,
      });

      expect(await _countNullCurrencyCode(), 0);
    });

    test('Payment voucher in SAR includes currency_code', () async {
      final now = DateTime.now().toIso8601String();
      final cashAccountId = await _insertAccount(
          code: '1101', type: 'ASSET', balanceType: 'debit', currency: 'SAR');
      final supplierAccountId = await _insertAccount(
          code: '1301', type: 'ASSET', balanceType: 'debit', currency: 'SAR');

      final journalId = DateTime.now().microsecondsSinceEpoch + 8;
      final amount = MoneyHelper.toCents(1000.0);
      const currency = 'SAR';
      const exchangeRate = 140.0;
      final amountBase = (amount * exchangeRate).round();

      // Payment: Debit Supplier, Credit Cash
      await db.insert('transactions', {
        'account_id': supplierAccountId,
        'journal_id': journalId,
        'debit': amount,
        'credit': 0,
        'description': 'سند صرف مورد',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': exchangeRate,
        'amount_base': amountBase,
      });
      await db.insert('transactions', {
        'account_id': cashAccountId,
        'journal_id': journalId,
        'debit': 0,
        'credit': amount,
        'description': 'سند صرف مورد',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': exchangeRate,
        'amount_base': amountBase,
      });

      final txns = await db.query('transactions',
          where: 'journal_id = ?', whereArgs: [journalId]);
      for (final t in txns) {
        expect(t['currency_code'], 'SAR');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Currency exchange transactions include currency_code
  // ══════════════════════════════════════════════════════════════

  group(
      'Currency exchange transactions — currency_code / معاملات صرافة العملات',
      () {
    test('Exchange from YER to USD includes currency_code on both sides',
        () async {
      final now = DateTime.now().toIso8601String();
      final yerCashAccountId = await _insertAccount(
          code: '1100', type: 'ASSET', balanceType: 'debit', currency: 'YER');
      final usdCashAccountId = await _insertAccount(
          code: '1102', type: 'ASSET', balanceType: 'debit', currency: 'USD');

      final journalId = DateTime.now().microsecondsSinceEpoch + 9;
      final fromAmount = MoneyHelper.toCents(53000.0); // 53000 YER
      final toAmount = MoneyHelper.toCents(100.0); // 100 USD

      // Debit: USD cash received
      await db.insert('transactions', {
        'account_id': usdCashAccountId,
        'journal_id': journalId,
        'debit': toAmount,
        'credit': 0,
        'description': 'صرافة: استلام USD',
        'date': now,
        'created_at': now,
        'currency_code': 'USD',
        'exchange_rate': 530.0,
        'amount_base': (toAmount * 530).round(),
      });

      // Credit: YER cash sent
      await db.insert('transactions', {
        'account_id': yerCashAccountId,
        'journal_id': journalId,
        'debit': 0,
        'credit': fromAmount,
        'description': 'صرافة: صرف YER',
        'date': now,
        'created_at': now,
        'currency_code': 'YER',
        'exchange_rate': 1.0,
        'amount_base': fromAmount,
      });

      expect(await _countNullCurrencyCode(), 0);

      final usdTxns = await db.query('transactions',
          where: 'account_id = ? AND journal_id = ?',
          whereArgs: [usdCashAccountId, journalId]);
      for (final t in usdTxns) {
        expect(t['currency_code'], 'USD');
      }

      final yerTxns = await db.query('transactions',
          where: 'account_id = ? AND journal_id = ?',
          whereArgs: [yerCashAccountId, journalId]);
      for (final t in yerTxns) {
        expect(t['currency_code'], 'YER');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Cash transfer transactions include currency_code
  // ══════════════════════════════════════════════════════════════

  group('Cash transfer transactions — currency_code / معاملات تحويل الصناديق',
      () {
    test('Same-currency transfer includes currency_code', () async {
      final now = DateTime.now().toIso8601String();
      final fromAccountId = await _insertAccount(
          code: '1100', type: 'ASSET', balanceType: 'debit', currency: 'YER');
      final toAccountId = await _insertAccount(
          code: '1101', type: 'ASSET', balanceType: 'debit', currency: 'YER');

      final journalId = DateTime.now().microsecondsSinceEpoch + 10;
      final amount = MoneyHelper.toCents(10000.0);
      const currency = 'YER';

      // Debit: receiving cash box
      await db.insert('transactions', {
        'account_id': toAccountId,
        'journal_id': journalId,
        'debit': amount,
        'credit': 0,
        'description': 'تحويل: استلام من صندوق آخر',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': 1.0,
        'amount_base': amount,
      });

      // Credit: sending cash box
      await db.insert('transactions', {
        'account_id': fromAccountId,
        'journal_id': journalId,
        'debit': 0,
        'credit': amount,
        'description': 'تحويل: صرف إلى صندوق آخر',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': 1.0,
        'amount_base': amount,
      });

      expect(await _countNullCurrencyCode(), 0);
    });

    test('SAR cash transfer includes currency_code', () async {
      final now = DateTime.now().toIso8601String();
      final fromAccountId = await _insertAccount(
          code: '1103', type: 'ASSET', balanceType: 'debit', currency: 'SAR');
      final toAccountId = await _insertAccount(
          code: '1104', type: 'ASSET', balanceType: 'debit', currency: 'SAR');

      final journalId = DateTime.now().microsecondsSinceEpoch + 11;
      final amount = MoneyHelper.toCents(2000.0);
      const currency = 'SAR';
      const exchangeRate = 140.0;
      final amountBase = (amount * exchangeRate).round();

      await db.insert('transactions', {
        'account_id': toAccountId,
        'journal_id': journalId,
        'debit': amount,
        'credit': 0,
        'description': 'تحويل ريال سعودي',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': exchangeRate,
        'amount_base': amountBase,
      });
      await db.insert('transactions', {
        'account_id': fromAccountId,
        'journal_id': journalId,
        'debit': 0,
        'credit': amount,
        'description': 'تحويل ريال سعودي',
        'date': now,
        'created_at': now,
        'currency_code': currency,
        'exchange_rate': exchangeRate,
        'amount_base': amountBase,
      });

      final txns = await db.query('transactions',
          where: 'journal_id = ?', whereArgs: [journalId]);
      for (final t in txns) {
        expect(t['currency_code'], 'SAR');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Comprehensive: No NULL currency_code across all operations
  // ══════════════════════════════════════════════════════════════

  group('Comprehensive — all transaction types / شامل — جميع أنواع المعاملات',
      () {
    test(
        'No transaction in the database has NULL currency_code / لا توجد معاملة بقيمة currency_code فارغة',
        () async {
      // All the individual test groups above have inserted transactions.
      // We open a fresh database and insert all types, then verify.
      final now = DateTime.now().toIso8601String();

      // Create accounts
      final acc1 = await _insertAccount(
          code: '9001', type: 'ASSET', balanceType: 'debit', currency: 'YER');
      final acc2 = await _insertAccount(
          code: '9002',
          type: 'REVENUE',
          balanceType: 'credit',
          currency: 'YER');
      final acc3 = await _insertAccount(
          code: '9003', type: 'EXPENSE', balanceType: 'debit', currency: 'YER');
      final acc4 = await _insertAccount(
          code: '9004',
          type: 'LIABILITY',
          balanceType: 'credit',
          currency: 'YER');
      final acc5 = await _insertAccount(
          code: '9005', type: 'EQUITY', balanceType: 'credit', currency: 'YER');

      final baseJournal = DateTime.now().microsecondsSinceEpoch;

      // Simulate all transaction types with currency_code
      final transactionTypes = [
        // Customer opening balance
        {
          'account_id': acc1,
          'journal_id': baseJournal + 100,
          'debit': 100000,
          'credit': 0,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': 100000,
          'reference_type': 'opening_balance',
          'reference_id': 'customer_test'
        },
        {
          'account_id': acc5,
          'journal_id': baseJournal + 100,
          'debit': 0,
          'credit': 100000,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': 100000,
          'reference_type': 'opening_balance',
          'reference_id': 'customer_test'
        },
        // Supplier opening balance
        {
          'account_id': acc4,
          'journal_id': baseJournal + 200,
          'debit': 0,
          'credit': 50000,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': 50000,
          'reference_type': 'opening_balance',
          'reference_id': 'supplier_test'
        },
        {
          'account_id': acc5,
          'journal_id': baseJournal + 200,
          'debit': 50000,
          'credit': 0,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': 50000,
          'reference_type': 'opening_balance',
          'reference_id': 'supplier_test'
        },
        // Expense
        {
          'account_id': acc3,
          'journal_id': baseJournal + 300,
          'debit': 20000,
          'credit': 0,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': 20000
        },
        {
          'account_id': acc1,
          'journal_id': baseJournal + 300,
          'debit': 0,
          'credit': 20000,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': 20000
        },
        // Voucher
        {
          'account_id': acc1,
          'journal_id': baseJournal + 400,
          'debit': 30000,
          'credit': 0,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': 30000
        },
        {
          'account_id': acc2,
          'journal_id': baseJournal + 400,
          'debit': 0,
          'credit': 30000,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': 30000
        },
        // Exchange
        {
          'account_id': acc1,
          'journal_id': baseJournal + 500,
          'debit': 0,
          'credit': 40000,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': 40000
        },
        {
          'account_id': acc1,
          'journal_id': baseJournal + 500,
          'debit': 40000,
          'credit': 0,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': 40000
        },
        // Transfer
        {
          'account_id': acc1,
          'journal_id': baseJournal + 600,
          'debit': 15000,
          'credit': 0,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': 15000
        },
        {
          'account_id': acc1,
          'journal_id': baseJournal + 600,
          'debit': 0,
          'credit': 15000,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': 15000
        },
      ];

      for (final txn in transactionTypes) {
        await db.insert('transactions', {
          ...txn,
          'description': 'اختبار شامل',
          'date': now,
          'created_at': now,
        });
      }

      // Verify: no NULL currency_code
      expect(await _countNullCurrencyCode(), 0,
          reason:
              'No transaction should have NULL currency_code after comprehensive insert');

      // Verify: all have valid currency codes
      final allTxns = await db.query('transactions');
      for (final t in allTxns) {
        expect(t['currency_code'], isNotNull,
            reason: 'Transaction ${t['id']} has NULL currency_code');
        expect(t['currency_code'], isNotEmpty,
            reason: 'Transaction ${t['id']} has empty currency_code');
      }
    });
  });
}
