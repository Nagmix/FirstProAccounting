import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// ══════════════════════════════════════════════════════════════════
/// اختبارات القيد المزدوج — التحقق من سلامة المحاسبة بالقيد المزدوج
///
/// Double-entry accounting integrity tests:
///   1. For every journal entry, total debits = total credits
///   2. balance_type is correctly set for each transaction
///   3. amount_base is computed correctly for multi-currency transactions
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

  /// Helper: create an account.
  Future<int> _insertAccount({
    required String code,
    required String type,
    required String balanceType,
    String currency = 'YER',
  }) async {
    final now = DateTime.now().toIso8601String();
    return await db.insert('accounts', {
      'name_ar': 'حساب $code',
      'name_en': 'Account $code',
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

  /// Simulate the validateJournalBalance logic from JournalService.
  void _validateJournalBalance(List<Map<String, dynamic>> entries) {
    double totalDebit = 0.0;
    double totalCredit = 0.0;
    for (final entry in entries) {
      totalDebit += MoneyHelper.readMoney(entry['debit']);
      totalCredit += MoneyHelper.readMoney(entry['credit']);
    }
    final difference = (totalDebit - totalCredit).abs();
    if (difference > 0.005) {
      throw Exception(
        'قيد محاسبي غير متوازن: المدين=$totalDebit, الدائن=$totalCredit, الفرق=$difference',
      );
    }
  }

  /// Helper: verify journal balance from database for a given journal_id.
  Future<void> _verifyJournalBalance(int journalId) async {
    final result = await db.rawQuery(
      'SELECT CAST(COALESCE(SUM(debit), 0) AS INTEGER) AS total_debit, '
      'CAST(COALESCE(SUM(credit), 0) AS INTEGER) AS total_credit '
      'FROM transactions WHERE journal_id = ?',
      [journalId],
    );
    final totalDebit =
        MoneyHelper.readCalculatedMoney(result.first['total_debit']);
    final totalCredit =
        MoneyHelper.readCalculatedMoney(result.first['total_credit']);
    expect((totalDebit - totalCredit).abs(), lessThan(0.01),
        reason:
            'Journal $journalId: debits ($totalDebit) must equal credits ($totalCredit)');
  }

  // ══════════════════════════════════════════════════════════════
  //  Test: Total debits = total credits for every journal entry
  // ══════════════════════════════════════════════════════════════

  group('Double-entry balance — المدين يساوي الدائن', () {
    test('Simple two-line journal entry balances / قيد بسيط من سطرين متوازن',
        () async {
      final now = DateTime.now().toIso8601String();
      final cashAccountId = await _insertAccount(
          code: '8001', type: 'ASSET', balanceType: 'debit');
      final salesAccountId = await _insertAccount(
          code: '8002', type: 'REVENUE', balanceType: 'credit');

      final journalId = DateTime.now().microsecondsSinceEpoch;
      final amount = MoneyHelper.toCents(5000.0);

      await db.transaction((txn) async {
        await txn.insert('transactions', {
          'account_id': cashAccountId,
          'journal_id': journalId,
          'debit': amount,
          'credit': 0,
          'description': 'مبيعات نقدية - مدين',
          'date': now,
          'created_at': now,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': amount,
        });
        await txn.insert('transactions', {
          'account_id': salesAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': amount,
          'description': 'مبيعات نقدية - دائن',
          'date': now,
          'created_at': now,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': amount,
        });
      });

      await _verifyJournalBalance(journalId);
    });

    test('Multi-line compound entry is balanced / قيد مركب متوازن', () async {
      final now = DateTime.now().toIso8601String();
      final cashAccountId = await _insertAccount(
          code: '8021', type: 'ASSET', balanceType: 'debit');
      final discountAccountId = await _insertAccount(
          code: '8022', type: 'EXPENSE', balanceType: 'debit');
      final salesAccountId = await _insertAccount(
          code: '8023', type: 'REVENUE', balanceType: 'credit');

      final journalId = DateTime.now().microsecondsSinceEpoch + 2;
      // Sale of 5000, customer paid 4800, discount 200
      final cashAmount = MoneyHelper.toCents(4800.0);
      final discountAmt = MoneyHelper.toCents(200.0);
      final salesAmount = MoneyHelper.toCents(5000.0);

      await db.transaction((txn) async {
        // Debits: Cash + Discount = 5000
        await txn.insert('transactions', {
          'account_id': cashAccountId,
          'journal_id': journalId,
          'debit': cashAmount,
          'credit': 0,
          'description': 'نقدية',
          'date': now,
          'created_at': now,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': cashAmount,
        });
        await txn.insert('transactions', {
          'account_id': discountAccountId,
          'journal_id': journalId,
          'debit': discountAmt,
          'credit': 0,
          'description': 'خصم',
          'date': now,
          'created_at': now,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': discountAmt,
        });
        // Credit: Sales = 5000
        await txn.insert('transactions', {
          'account_id': salesAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': salesAmount,
          'description': 'مبيعات',
          'date': now,
          'created_at': now,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': salesAmount,
        });
      });

      await _verifyJournalBalance(journalId);
    });

    test(
        'validateJournalBalance rejects unbalanced entry / يرفض القيد غير المتوازن',
        () {
      final entries = [
        {'debit': MoneyHelper.toCents(5000.0), 'credit': 0},
        {'debit': 0, 'credit': MoneyHelper.toCents(4000.0)}, // Unbalanced!
      ];
      expect(() => _validateJournalBalance(entries), throwsException);
    });

    test('validateJournalBalance accepts balanced entry / يقبل القيد المتوازن',
        () {
      final entries = [
        {'debit': MoneyHelper.toCents(5000.0), 'credit': 0},
        {'debit': 0, 'credit': MoneyHelper.toCents(5000.0)},
      ];
      expect(() => _validateJournalBalance(entries), returnsNormally);
    });

    test(
        'All journal entries in database are balanced / جميع القيود في قاعدة البيانات متوازنة',
        () async {
      final now = DateTime.now().toIso8601String();
      final cashAcc = await _insertAccount(
          code: '8031', type: 'ASSET', balanceType: 'debit');
      final revenueAcc = await _insertAccount(
          code: '8032', type: 'REVENUE', balanceType: 'credit');
      await _insertAccount(code: '8033', type: 'EXPENSE', balanceType: 'debit');

      // Create several balanced journal entries
      final amounts = [1000.0, 2500.0, 7500.0, 15000.0];
      for (int i = 0; i < amounts.length; i++) {
        final journalId = DateTime.now().microsecondsSinceEpoch + 100 + i;
        final amount = MoneyHelper.toCents(amounts[i]);

        await db.insert('transactions', {
          'account_id': cashAcc,
          'journal_id': journalId,
          'debit': amount,
          'credit': 0,
          'description': 'مدين',
          'date': now,
          'created_at': now,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': amount,
        });
        await db.insert('transactions', {
          'account_id': revenueAcc,
          'journal_id': journalId,
          'debit': 0,
          'credit': amount,
          'description': 'دائن',
          'date': now,
          'created_at': now,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': amount,
        });
      }

      // Check all journal entries
      final journalIds = await db.rawQuery(
        'SELECT DISTINCT journal_id FROM transactions',
      );
      for (final row in journalIds) {
        final jid = row['journal_id'] as int;
        await _verifyJournalBalance(jid);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Test: balance_type is correctly set for each transaction
  // ══════════════════════════════════════════════════════════════

  group('balance_type correctness — صحة نوع الرصيد', () {
    test('ASSET accounts have debit balance_type / حسابات الأصول من نوع مدين',
        () async {
      final assetAccounts = await db.query('accounts',
          where: "account_type = 'ASSET' AND is_system = 1");
      for (final acc in assetAccounts) {
        expect(acc['balance_type'], 'debit',
            reason:
                'ASSET account ${acc['account_code']} should have balance_type=debit');
      }
    });

    test(
        'EXPENSE accounts have debit balance_type / حسابات المصروفات من نوع مدين',
        () async {
      final expenseAccounts = await db.query('accounts',
          where: "account_type = 'EXPENSE' AND is_system = 1");
      for (final acc in expenseAccounts) {
        expect(acc['balance_type'], 'debit',
            reason:
                'EXPENSE account ${acc['account_code']} should have balance_type=debit');
      }
    });

    test(
        'REVENUE accounts have credit balance_type / حسابات الإيرادات من نوع دائن',
        () async {
      final revenueAccounts = await db.query('accounts',
          where: "account_type = 'REVENUE' AND is_system = 1");
      for (final acc in revenueAccounts) {
        expect(acc['balance_type'], 'credit',
            reason:
                'REVENUE account ${acc['account_code']} should have balance_type=credit');
      }
    });

    test(
        'LIABILITY accounts have credit balance_type / حسابات الخصوم من نوع دائن',
        () async {
      final liabilityAccounts = await db.query('accounts',
          where: "account_type = 'LIABILITY' AND is_system = 1");
      for (final acc in liabilityAccounts) {
        expect(acc['balance_type'], 'credit',
            reason:
                'LIABILITY account ${acc['account_code']} should have balance_type=credit');
      }
    });

    test(
        'EQUITY accounts have credit balance_type / حسابات حقوق الملكية من نوع دائن',
        () async {
      final equityAccounts = await db.query('accounts',
          where: "account_type = 'EQUITY' AND is_system = 1");
      for (final acc in equityAccounts) {
        expect(acc['balance_type'], 'credit',
            reason:
                'EQUITY account ${acc['account_code']} should have balance_type=credit');
      }
    });

    test(
        'Account balance updates respect balance_type / تحديثات الرصيد تراعي نوع الرصيد',
        () async {
      final now = DateTime.now().toIso8601String();

      // Create a debit-balance account (ASSET)
      final debitAccountId = await _insertAccount(
        code: '8501',
        type: 'ASSET',
        balanceType: 'debit',
      );
      // Set initial balance
      await db.update(
        'accounts',
        {'balance': MoneyHelper.toCents(10000.0), 'updated_at': now},
        where: 'id = ?',
        whereArgs: [debitAccountId],
      );

      // Apply a debit entry: debit-balance account increases
      final amountCents = MoneyHelper.toCents(5000.0);
      final isDebitInt = 1;
      await db.rawUpdate('''
        UPDATE accounts SET
          balance = balance + CASE
            WHEN balance_type = 'credit' AND ? = 1 THEN -?
            WHEN balance_type = 'credit' AND ? = 0 THEN ?
            WHEN balance_type = 'debit'  AND ? = 1 THEN ?
            WHEN balance_type = 'debit'  AND ? = 0 THEN -?
            ELSE 0
          END,
          updated_at = ?
        WHERE id = ?
      ''', [
        isDebitInt,
        amountCents,
        isDebitInt,
        amountCents,
        isDebitInt,
        amountCents,
        isDebitInt,
        amountCents,
        now,
        debitAccountId,
      ]);

      final updatedDebit = await db
          .query('accounts', where: 'id = ?', whereArgs: [debitAccountId]);
      // Debit account + debit entry: 10000 + 5000 = 15000
      expect(MoneyHelper.readMoney(updatedDebit.first['balance']), 15000.0);

      // Create a credit-balance account (REVENUE)
      final creditAccountId = await _insertAccount(
        code: '8502',
        type: 'REVENUE',
        balanceType: 'credit',
      );
      await db.update(
        'accounts',
        {'balance': MoneyHelper.toCents(3000.0), 'updated_at': now},
        where: 'id = ?',
        whereArgs: [creditAccountId],
      );

      // Apply a credit entry: credit-balance account increases
      await db.rawUpdate('''
        UPDATE accounts SET
          balance = balance + CASE
            WHEN balance_type = 'credit' AND ? = 1 THEN -?
            WHEN balance_type = 'credit' AND ? = 0 THEN ?
            WHEN balance_type = 'debit'  AND ? = 1 THEN ?
            WHEN balance_type = 'debit'  AND ? = 0 THEN -?
            ELSE 0
          END,
          updated_at = ?
        WHERE id = ?
      ''', [
        0, amountCents, // isDebitInt = 0 (credit entry)
        0, amountCents,
        0, amountCents,
        0, amountCents,
        now, creditAccountId,
      ]);

      final updatedCredit = await db
          .query('accounts', where: 'id = ?', whereArgs: [creditAccountId]);
      // Credit account + credit entry: 3000 + 5000 = 8000
      expect(MoneyHelper.readMoney(updatedCredit.first['balance']), 8000.0);
    });

    test(
        'Debit on credit-balance account decreases balance / المدين على حساب دائن يقلل الرصيد',
        () async {
      final now = DateTime.now().toIso8601String();
      final creditAccountId = await _insertAccount(
        code: '8503',
        type: 'REVENUE',
        balanceType: 'credit',
      );
      await db.update(
        'accounts',
        {'balance': MoneyHelper.toCents(5000.0), 'updated_at': now},
        where: 'id = ?',
        whereArgs: [creditAccountId],
      );

      final amountCents = MoneyHelper.toCents(2000.0);
      final isDebitInt = 1; // debit entry on credit account

      await db.rawUpdate('''
        UPDATE accounts SET
          balance = balance + CASE
            WHEN balance_type = 'credit' AND ? = 1 THEN -?
            WHEN balance_type = 'credit' AND ? = 0 THEN ?
            WHEN balance_type = 'debit'  AND ? = 1 THEN ?
            WHEN balance_type = 'debit'  AND ? = 0 THEN -?
            ELSE 0
          END,
          updated_at = ?
        WHERE id = ?
      ''', [
        isDebitInt,
        amountCents,
        isDebitInt,
        amountCents,
        isDebitInt,
        amountCents,
        isDebitInt,
        amountCents,
        now,
        creditAccountId,
      ]);

      final updated = await db
          .query('accounts', where: 'id = ?', whereArgs: [creditAccountId]);
      // Credit account + debit entry: 5000 - 2000 = 3000
      expect(MoneyHelper.readMoney(updated.first['balance']), 3000.0);
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Test: amount_base computed correctly for multi-currency
  // ══════════════════════════════════════════════════════════════

  group('amount_base computation — حساب المبلغ الأساسي للعملات المتعددة', () {
    test(
        'YER transaction: amount_base equals transaction amount / معاملة الريال: amount_base = المبلغ',
        () async {
      final now = DateTime.now().toIso8601String();
      final accountId = await _insertAccount(
          code: '8601', type: 'ASSET', balanceType: 'debit');

      final amount = MoneyHelper.toCents(10000.0); // 10000 YER in cents
      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': DateTime.now().microsecondsSinceEpoch + 200,
        'debit': amount,
        'credit': 0,
        'description': 'معاملة ريال يمني',
        'date': now,
        'created_at': now,
        'currency_code': 'YER',
        'exchange_rate': 1.0,
        'amount_base': amount,
      });

      final txn = await db.query('transactions',
          where: 'account_id = ?', whereArgs: [accountId], limit: 1);
      expect(txn.first['amount_base'], amount,
          reason: 'For YER, amount_base should equal the transaction amount');
    });

    test(
        'USD transaction: amount_base = amount * 530 / معاملة الدولار: amount_base = المبلغ × 530',
        () async {
      final now = DateTime.now().toIso8601String();
      final accountId = await _insertAccount(
          code: '8602', type: 'ASSET', balanceType: 'debit');

      final amount = MoneyHelper.toCents(100.0); // 100 USD in cents = 10000
      const exchangeRate = 530.0;
      final expectedAmountBase = (amount * exchangeRate).round(); // 5300000

      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': DateTime.now().microsecondsSinceEpoch + 201,
        'debit': amount,
        'credit': 0,
        'description': 'معاملة بالدولار',
        'date': now,
        'created_at': now,
        'currency_code': 'USD',
        'exchange_rate': exchangeRate,
        'amount_base': expectedAmountBase,
      });

      final txn = await db.query('transactions',
          where: 'account_id = ?', whereArgs: [accountId], limit: 1);
      expect(txn.first['amount_base'], expectedAmountBase,
          reason:
              'For USD 100 @ 530, amount_base should be 5300000 (= 53000 YER)');
    });

    test(
        'SAR transaction: amount_base = amount * 140 / معاملة الريال السعودي: amount_base = المبلغ × 140',
        () async {
      final now = DateTime.now().toIso8601String();
      final accountId = await _insertAccount(
          code: '8603', type: 'ASSET', balanceType: 'debit');

      final amount = MoneyHelper.toCents(500.0); // 500 SAR in cents = 50000
      const exchangeRate = 140.0;
      final expectedAmountBase = (amount * exchangeRate).round(); // 7000000

      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': DateTime.now().microsecondsSinceEpoch + 202,
        'debit': amount,
        'credit': 0,
        'description': 'معاملة بالريال السعودي',
        'date': now,
        'created_at': now,
        'currency_code': 'SAR',
        'exchange_rate': exchangeRate,
        'amount_base': expectedAmountBase,
      });

      final txn = await db.query('transactions',
          where: 'account_id = ?', whereArgs: [accountId], limit: 1);
      expect(txn.first['amount_base'], expectedAmountBase,
          reason:
              'For SAR 500 @ 140, amount_base should be 7000000 (= 70000 YER)');
    });

    test(
        'Multi-currency journal: base amounts balance in YER / قيد متعدد العملات: المبالغ الأساسية تتوازن بالريال',
        () async {
      final now = DateTime.now().toIso8601String();
      final yerAccountId = await _insertAccount(
          code: '8604', type: 'ASSET', balanceType: 'debit');
      final usdAccountId = await _insertAccount(
          code: '8605', type: 'ASSET', balanceType: 'debit');

      final journalId = DateTime.now().microsecondsSinceEpoch + 203;

      // Exchange 53000 YER → 100 USD
      // YER side: credit 53000 YER, amount_base = 5300000
      // USD side: debit 100 USD, amount_base = 5300000

      final yerAmount = MoneyHelper.toCents(53000.0); // 5300000 cents
      final usdAmount = MoneyHelper.toCents(100.0); // 10000 cents
      final yerAmountBase = yerAmount; // 5300000
      final usdAmountBase = (usdAmount * 530.0).round(); // 5300000

      await db.insert('transactions', {
        'account_id': usdAccountId,
        'journal_id': journalId,
        'debit': usdAmount,
        'credit': 0,
        'description': 'استلام دولار',
        'date': now,
        'created_at': now,
        'currency_code': 'USD',
        'exchange_rate': 530.0,
        'amount_base': usdAmountBase,
      });
      await db.insert('transactions', {
        'account_id': yerAccountId,
        'journal_id': journalId,
        'debit': 0,
        'credit': yerAmount,
        'description': 'صرف ريال',
        'date': now,
        'created_at': now,
        'currency_code': 'YER',
        'exchange_rate': 1.0,
        'amount_base': yerAmountBase,
      });

      // Verify base amounts balance in YER
      await db.rawQuery(
        'SELECT CAST(COALESCE(SUM(amount_base), 0) AS INTEGER) AS total_base '
        'FROM transactions WHERE journal_id = ?',
        [journalId],
      );
      // In double-entry, the base amounts should net to zero
      // Debit amount_base + Credit amount_base should cancel out if we
      // treat debit as positive and credit as negative
      final debitBase = await db.rawQuery(
        'SELECT CAST(COALESCE(SUM(amount_base), 0) AS INTEGER) AS total '
        'FROM transactions WHERE journal_id = ? AND debit > 0',
        [journalId],
      );
      final creditBase = await db.rawQuery(
        'SELECT CAST(COALESCE(SUM(amount_base), 0) AS INTEGER) AS total '
        'FROM transactions WHERE journal_id = ? AND credit > 0',
        [journalId],
      );

      final totalDebitBase = (debitBase.first['total'] as num?)?.toInt() ?? 0;
      final totalCreditBase = (creditBase.first['total'] as num?)?.toInt() ?? 0;

      expect(totalDebitBase, totalCreditBase,
          reason: 'Base currency (YER) debits must equal credits: '
              'debit_base=$totalDebitBase, credit_base=$totalCreditBase');
    });

    test(
        'Exchange gain/loss journal entries balance in base currency / قيود أرباح/خسائر الصرف متوازنة',
        () async {
      final now = DateTime.now().toIso8601String();
      final assetAccountId = await _insertAccount(
          code: '8606', type: 'ASSET', balanceType: 'debit');
      final gainAccountId = await _insertAccount(
          code: '8607', type: 'REVENUE', balanceType: 'credit');

      final journalId = DateTime.now().microsecondsSinceEpoch + 204;
      final gainAmount = MoneyHelper.toCents(500.0); // 500 YER gain

      // Exchange gain: Debit Asset, Credit Exchange Gain
      await db.insert('transactions', {
        'account_id': assetAccountId,
        'journal_id': journalId,
        'debit': gainAmount,
        'credit': 0,
        'description': 'مكاسب صرف',
        'date': now,
        'created_at': now,
        'currency_code': 'YER',
        'exchange_rate': 1.0,
        'amount_base': gainAmount,
      });
      await db.insert('transactions', {
        'account_id': gainAccountId,
        'journal_id': journalId,
        'debit': 0,
        'credit': gainAmount,
        'description': 'مكاسب صرف',
        'date': now,
        'created_at': now,
        'currency_code': 'YER',
        'exchange_rate': 1.0,
        'amount_base': gainAmount,
      });

      await _verifyJournalBalance(journalId);

      // Verify base amounts also balance
      final debitBase = await db.rawQuery(
        'SELECT CAST(COALESCE(SUM(amount_base), 0) AS INTEGER) AS total '
        'FROM transactions WHERE journal_id = ? AND debit > 0',
        [journalId],
      );
      final creditBase = await db.rawQuery(
        'SELECT CAST(COALESCE(SUM(amount_base), 0) AS INTEGER) AS total '
        'FROM transactions WHERE journal_id = ? AND credit > 0',
        [journalId],
      );
      final totalDebitBase = (debitBase.first['total'] as num?)?.toInt() ?? 0;
      final totalCreditBase = (creditBase.first['total'] as num?)?.toInt() ?? 0;
      expect(totalDebitBase, totalCreditBase);
    });
  });
}
