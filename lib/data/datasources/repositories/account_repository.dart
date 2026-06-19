import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/core/utils/journal_id_helper.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/models/account_model.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/services/base_currency_service.dart';

class AccountRepository {
  final DatabaseHelper _dbHelper;
  AccountRepository(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  // ══════════════════════════════════════════════════════════════
  //  Account CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getAllAccounts() async {
    final db = await _db;
    return await db.query('accounts',
        where: 'is_active = ?', whereArgs: [1], orderBy: 'account_code ASC');
  }

  Future<List<Map<String, dynamic>>> getAccountsByType(
      String accountType) async {
    final db = await _db;
    return await db.query('accounts',
        where: 'is_active = ? AND account_type = ?',
        whereArgs: [1, accountType],
        orderBy: 'account_code ASC');
  }

  Future<List<Map<String, dynamic>>> getAccountsByCurrency(
      String currencyCode) async {
    final db = await _db;
    return await db.query('accounts',
        where: 'is_active = ? AND currency = ?',
        whereArgs: [1, currencyCode],
        orderBy: 'account_code ASC');
  }

  Future<int> insertAccount(Map<String, dynamic> accountMap) async {
    final db = await _db;
    return await db.insert('accounts',
        MoneyHelper.toCentsMap(accountMap, MoneyHelper.accountMoneyFields));
  }

  Future<int> updateAccount(int id, Map<String, dynamic> accountMap) async {
    final db = await _db;
    return await db.update('accounts',
        MoneyHelper.toCentsMap(accountMap, MoneyHelper.accountMoneyFields),
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAccount(int id) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    final account =
        await db.query('accounts', where: 'id = ?', whereArgs: [id], limit: 1);
    if (account.isEmpty) return 0;
    if ((account.first['is_system'] as int?) == 1) {
      throw Exception('لا يمكن حذف حساب نظامي.');
    }

    final children = await db.query('accounts',
        where: 'parent_id = ?', whereArgs: [id], limit: 1);
    if (children.isNotEmpty) {
      throw Exception('لا يمكن حذف حساب يحتوي على حسابات فرعية.');
    }

    final blockingChecks = <String, Future<bool> Function()>{
      'transactions': () async => (await db.query('transactions',
              where: 'account_id = ?', whereArgs: [id], limit: 1))
          .isNotEmpty,
      'voucher_items': () async => (await db.query('voucher_items',
              where: 'account_id = ?', whereArgs: [id], limit: 1))
          .isNotEmpty,
      'cash_boxes': () async => (await db.query('cash_boxes',
              where: 'linked_account_id = ?', whereArgs: [id], limit: 1))
          .isNotEmpty,
      'expenses': () async => (await db.query('expenses',
              where: 'account_id = ? OR expense_account_id = ?',
              whereArgs: [id, id],
              limit: 1))
          .isNotEmpty,
      'products': () async => (await db.query('products',
              where:
                  'sales_account_id = ? OR purchase_account_id = ? OR inventory_account_id = ? OR cogs_account_id = ? OR vat_account_id = ?',
              whereArgs: [id, id, id, id, id],
              limit: 1))
          .isNotEmpty,
    };

    for (final entry in blockingChecks.entries) {
      try {
        if (await entry.value()) {
          return await db.update(
            'accounts',
            {'is_active': 0, 'updated_at': now},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      } catch (_) {
        // Optional/legacy table may not exist.
      }
    }

    return await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  /// Get the next available account code for a given account type and currency.
  /// Uses 4-digit numeric codes where the first digit is the type prefix.
  /// Steps by 10 to leave room for sub-accounts.
  Future<String> getNextAccountCode(String accountType, {String? currency}) async {
    final db = await _db;
    final prefixMap = {
      'ASSET': '1',
      'LIABILITY': '2',
      'EQUITY': '2', // Equity shares the 2xxx range with Liabilities
      'COST': '3',
      'REVENUE': '4',
      'EXPENSE': '5',
    };
    final prefix = prefixMap[accountType] ?? '9';
    final args = <Object>['$prefix%', accountType];
    var currencyFilter = '';
    if (currency != null && currency.isNotEmpty) {
      currencyFilter = ' AND currency = ?';
      args.add(currency);
    }
    final result = await db.rawQuery(
      'SELECT COALESCE(MAX(CAST(account_code AS INTEGER)), 0) AS max_code '
      'FROM accounts WHERE account_code LIKE ? AND account_type = ?$currencyFilter',
      args,
    );
    final maxCode = (result.first['max_code'] as num?)?.toInt() ?? 0;
    final nextCode =
        maxCode == 0 ? (int.parse(prefix) * 1000 + 10) : maxCode + 10;
    return nextCode.toString();
  }

  /// Create an expense account with optional opening balance
  Future<int> createExpenseAccount({
    required String nameAr,
    required String currency,
    double? debtCeiling,
    double openingBalance = 0.0,
    String balanceType = 'debit', // 'debit' = عليه (EXPENSE is debit-nature)
    String? notes,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    final codeOffset =
        await locator<BaseCurrencyService>().getOffsetForCurrency(currency);
    final currencySymbol =
        currency == 'SAR' ? 'ر.س' : (currency == 'USD' ? r'$' : 'ر.ي');

    // Find the max existing expense account code for this currency
    final existingExpenseAccounts = await db.query(
      'accounts',
      where: 'account_type = ? AND currency = ?',
      whereArgs: ['EXPENSE', currency],
      orderBy: 'account_code DESC',
      limit: 1,
    );

    String newCode;
    if (existingExpenseAccounts.isNotEmpty) {
      final lastCode = int.tryParse(
              existingExpenseAccounts.first['account_code'] as String) ??
          (5000 + codeOffset);
      newCode = (lastCode + 1).toString();
    } else {
      newCode = (5000 + codeOffset).toString();
    }

    return await db.transaction((txn) async {
      final accountId = await txn.insert(
        'accounts',
        MoneyHelper.toCentsMap({
          'name_ar': '$nameAr ($currencySymbol)',
          'name_en': nameAr,
          'account_code': newCode,
          'account_type': 'EXPENSE',
          'balance': 0,
          'currency': currency,
          'is_active': 1,
          'is_system': 0,
          'debt_ceiling': debtCeiling ?? 0.0,
          'balance_type': balanceType,
          'created_at': now,
          'updated_at': now,
        }, MoneyHelper.accountMoneyFields),
      );

      if (openingBalance > 0) {
        final journalId = generateUniqueJournalId();
        final referenceId = 'account_$accountId';
        final obCode = (2901 + codeOffset).toString();
        final obAccounts = await txn.query(
          'accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [obCode, currency],
          limit: 1,
        );
        final obAccountId = obAccounts.isNotEmpty
            ? obAccounts.first['id'] as int
            : await txn.insert(
                'accounts',
                MoneyHelper.toCentsMap({
                  'name_ar': 'رصيد افتتاحي ($currencySymbol)',
                  'name_en': 'Opening Balance Equity ($currency)',
                  'account_code': obCode,
                  'account_type': 'EQUITY',
                  'balance': 0,
                  'currency': currency,
                  'is_active': 1,
                  'is_system': 1,
                  'balance_type': 'credit',
                  'created_at': now,
                  'updated_at': now,
                }, MoneyHelper.accountMoneyFields),
              );

        if (balanceType == 'credit') {
          await txn.insert('transactions', {
            'account_id': accountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(openingBalance),
            'description': 'رصيد افتتاحي - $nameAr',
            'date': now,
            'created_at': now,
            'currency_code': currency,
            'exchange_rate': 1.0,
            'amount_base': MoneyHelper.toCents(openingBalance),
            'reference_type': 'opening_balance',
            'reference_id': referenceId,
          });
          await txn.insert('transactions', {
            'account_id': obAccountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(openingBalance),
            'credit': 0,
            'description': 'مقابل رصيد افتتاحي - $nameAr',
            'date': now,
            'created_at': now,
            'currency_code': currency,
            'exchange_rate': 1.0,
            'amount_base': MoneyHelper.toCents(openingBalance),
            'reference_type': 'opening_balance',
            'reference_id': referenceId,
          });
          await _updateAccountBalanceWithJournal(
              txn, accountId, 0.0, openingBalance, now);
          await _updateAccountBalanceWithJournal(
              txn, obAccountId, openingBalance, 0.0, now);
        } else {
          await txn.insert('transactions', {
            'account_id': accountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(openingBalance),
            'credit': 0,
            'description': 'رصيد افتتاحي - $nameAr',
            'date': now,
            'created_at': now,
            'currency_code': currency,
            'exchange_rate': 1.0,
            'amount_base': MoneyHelper.toCents(openingBalance),
            'reference_type': 'opening_balance',
            'reference_id': referenceId,
          });
          await txn.insert('transactions', {
            'account_id': obAccountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(openingBalance),
            'description': 'مقابل رصيد افتتاحي - $nameAr',
            'date': now,
            'created_at': now,
            'currency_code': currency,
            'exchange_rate': 1.0,
            'amount_base': MoneyHelper.toCents(openingBalance),
            'reference_type': 'opening_balance',
            'reference_id': referenceId,
          });
          await _updateAccountBalanceWithJournal(
              txn, accountId, openingBalance, 0.0, now);
          await _updateAccountBalanceWithJournal(
              txn, obAccountId, 0.0, openingBalance, now);
        }
        await _dbHelper.journal.validateJournalBalanceInTransaction(
          txn,
          journalId,
        );
      }

      return accountId;
    });
  }

  Future<List<Map<String, dynamic>>> getExpenseAccounts() async {
    final db = await _db;
    return await db.query('accounts',
        where: 'is_active = ? AND account_type = ?',
        whereArgs: [1, 'EXPENSE'],
        orderBy: 'account_code ASC');
  }

  /// Get expense accounts filtered by currency
  Future<List<Map<String, dynamic>>> getExpenseAccountsByCurrency(
      String currency) async {
    final db = await _db;
    return await db.query('accounts',
        where: 'is_active = ? AND account_type = ? AND currency = ?',
        whereArgs: [1, 'EXPENSE', currency],
        orderBy: 'account_code ASC');
  }

  Future<List<Map<String, dynamic>>> getAccountsWithoutMovements() async {
    final db = await _db;
    return await db.rawQuery(
      "SELECT a.id, a.name_ar, a.account_code, a.account_type, a.currency, a.balance "
      "FROM accounts a "
      "LEFT JOIN transactions t ON a.id = t.account_id "
      "WHERE a.is_active = 1 AND t.id IS NULL "
      "ORDER BY a.account_code",
    );
  }

  Future<Map<String, double>> getYearProfitLoss(int year) async {
    final db = await _db;
    final yearStart = '$year-01-01';
    // B-1: use an EXCLUSIVE upper bound. With full timestamps
    // ('2026-12-31T10:30') a textual `date <= '2026-12-31'` would wrongly
    // exclude Dec-31 entries, because the timestamp sorts after the day.
    final yearEndExclusive = '${year + 1}-01-01';

    // REVENUE accounts have credit normal balance → revenue = credit - debit
    final revenueResult = await db.rawQuery('''
      SELECT CAST(COALESCE(SUM(t.credit) - SUM(t.debit), 0) AS INTEGER) as total
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE a.account_type = 'REVENUE' AND a.is_active = 1
      AND t.date >= ? AND t.date < ?
    ''', [yearStart, yearEndExclusive]);
    final totalRevenue =
        MoneyHelper.readCalculatedMoney(revenueResult.first['total']);

    // COST accounts have debit normal balance → cost = debit - credit
    final costResult = await db.rawQuery('''
      SELECT CAST(COALESCE(SUM(t.debit) - SUM(t.credit), 0) AS INTEGER) as total
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE a.account_type = 'COST' AND a.is_active = 1
      AND t.date >= ? AND t.date < ?
    ''', [yearStart, yearEndExclusive]);
    final totalCosts =
        MoneyHelper.readCalculatedMoney(costResult.first['total']);

    // EXPENSE accounts have debit normal balance → expense = debit - credit
    final expenseResult = await db.rawQuery('''
      SELECT CAST(COALESCE(SUM(t.debit) - SUM(t.credit), 0) AS INTEGER) as total
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE a.account_type = 'EXPENSE' AND a.is_active = 1
      AND t.date >= ? AND t.date < ?
    ''', [yearStart, yearEndExclusive]);
    final totalExpenses =
        MoneyHelper.readCalculatedMoney(expenseResult.first['total']);

    final netProfit = totalRevenue - totalCosts - totalExpenses;

    return {
      'revenue': totalRevenue,
      'costs': totalCosts,
      'expenses': totalExpenses,
      'netProfit': netProfit,
    };
  }

  Future<List<Map<String, dynamic>>> getFiscalYears() async {
    final db = await _db;
    return await db.query('fiscal_years', orderBy: 'year DESC');
  }

  Future<bool> isFiscalYearClosed(int year) async {
    final db = await _db;
    final result = await db.query('fiscal_years',
        where: 'year = ? AND status = ?',
        whereArgs: [year, 'closed'],
        limit: 1);
    return result.isNotEmpty;
  }

  /// Check if a date falls in a closed fiscal year
  Future<bool> isDateInClosedPeriod(DateTime date) async {
    final db = await _db;
    final year = date.year;
    final result = await db.query(
      'fiscal_years',
      where: 'year = ? AND status = ?',
      whereArgs: [year, 'closed'],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> performAnnualPosting(int year) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final journalId = generateUniqueJournalId();
    final yearStart = '$year-01-01';
    // B-1: exclusive upper bound — see getYearProfitLoss note.
    final yearEndExclusive = '${year + 1}-01-01';

    await db.transaction((txn) async {
      // Pre-load exchange rates for all currencies
      final currencyRates = <String, double>{'YER': 1.0};
      final currencyRows = await txn.query('currencies');
      for (final c in currencyRows) {
        final code = c['code'] as String? ?? '';
        final rate = (c['exchange_rate'] as num?)?.toDouble() ?? 1.0;
        if (code.isNotEmpty) currencyRates[code] = rate;
      }
      // Check if already closed
      final existing = await txn.query('fiscal_years',
          where: 'year = ? AND status = ?',
          whereArgs: [year, 'closed'],
          limit: 1);
      if (existing.isNotEmpty) {
        throw Exception('السنة المالية $year مغلقة بالفعل');
      }

      // B-03: Check for existing annual posting entries to prevent double-posting
      // If closing entries already exist for this year (journal entries on Dec 31 with closing descriptions),
      // throw an error to prevent double-posting retained earnings
      final existingClosingEntries = await txn.rawQuery(
        "SELECT COUNT(*) as cnt FROM transactions WHERE date = ? AND (description LIKE ? OR description LIKE ? OR description LIKE ?)",
        [
          '$year-12-31',
          '%إقفال إيرادات السنة $year%',
          '%إقفال تكاليف السنة $year%',
          '%إقفال مصاريف السنة $year%'
        ],
      );
      final closingCount =
          (existingClosingEntries.first['cnt'] as num?)?.toInt() ?? 0;
      if (closingCount > 0) {
        throw Exception(
            'يوجد قيود إقفال سابقة للسنة $year. لا يمكن إعادة الترحيل.');
      }

      // Get all revenue accounts
      final revenueAccounts = await txn.query('accounts',
          where: 'account_type = ? AND is_active = 1', whereArgs: ['REVENUE']);

      // Get all cost accounts
      final costAccounts = await txn.query('accounts',
          where: 'account_type = ? AND is_active = 1', whereArgs: ['COST']);

      // Get all expense accounts
      final expenseAccounts = await txn.query('accounts',
          where: 'account_type = ? AND is_active = 1', whereArgs: ['EXPENSE']);

      // Get retained earnings accounts (one per currency)
      final retainedEarningsAccounts = await txn.query('accounts',
          where: 'account_code LIKE ? AND is_active = 1', whereArgs: ['290%']);

      /// Calculate account balance from transactions table for the fiscal year
      /// Returns the NORMAL balance: positive for debit-type (ASSET, EXPENSE, COST),
      /// positive for credit-type (REVENUE, LIABILITY, EQUITY).
      Future<double> calcNormalBalance(
          int accountId, String accountType) async {
        final result = await txn.rawQuery(
          "SELECT CAST(COALESCE(SUM(debit), 0) AS INTEGER) AS total_debit, CAST(COALESCE(SUM(credit), 0) AS INTEGER) AS total_credit "
          "FROM transactions "
          "WHERE account_id = ? AND date >= ? AND date < ?",
          [accountId, yearStart, yearEndExclusive],
        );
        final totalDebit =
            MoneyHelper.readCalculatedMoney(result.first['total_debit']);
        final totalCredit =
            MoneyHelper.readCalculatedMoney(result.first['total_credit']);
        // Credit-type accounts: normal balance = credit - debit (positive)
        // Debit-type accounts: normal balance = debit - credit (positive)
        const creditTypes = ['REVENUE', 'LIABILITY', 'EQUITY'];
        return creditTypes.contains(accountType)
            ? (totalCredit - totalDebit)
            : (totalDebit - totalCredit);
      }

      // Calculate net profit per currency using transaction-derived balances
      final Map<String, double> revenuePerCurrency = {};
      final Map<String, double> costPerCurrency = {};
      final Map<String, double> expensePerCurrency = {};

      for (final acc in revenueAccounts) {
        final currency = acc['currency'] as String? ?? 'YER';
        final accId = acc['id'] as int;
        final balance = await calcNormalBalance(accId, 'REVENUE');
        revenuePerCurrency[currency] =
            (revenuePerCurrency[currency] ?? 0.0) + balance;
      }

      for (final acc in costAccounts) {
        final currency = acc['currency'] as String? ?? 'YER';
        final accId = acc['id'] as int;
        final balance = await calcNormalBalance(accId, 'COST');
        costPerCurrency[currency] =
            (costPerCurrency[currency] ?? 0.0) + balance;
      }

      for (final acc in expenseAccounts) {
        final currency = acc['currency'] as String? ?? 'YER';
        final accId = acc['id'] as int;
        final balance = await calcNormalBalance(accId, 'EXPENSE');
        expensePerCurrency[currency] =
            (expensePerCurrency[currency] ?? 0.0) + balance;
      }

      // All currencies that have activity
      final allCurrencies = {
        ...revenuePerCurrency.keys,
        ...costPerCurrency.keys,
        ...expensePerCurrency.keys
      };

      double totalNetProfitYER = 0.0;

      for (final currency in allCurrencies) {
        final rate = currencyRates[currency] ?? 1.0;
        final rev = revenuePerCurrency[currency] ?? 0.0;
        final cost = costPerCurrency[currency] ?? 0.0;
        final exp = expensePerCurrency[currency] ?? 0.0;
        final netForCurrency = rev - cost - exp;

        // Find retained earnings account for this currency.
        // A-03 fix (2026-06-19): previously, if the Retained Earnings
        // account (2910+offset) was missing for a currency, the code
        // silently `continue`d — skipping the closing entries for that
        // currency entirely. This left REVENUE/COST/EXPENSE accounts
        // un-closed and the net profit for that currency was lost.
        //
        // Now we auto-create the Retained Earnings account (and its
        // parent Equity root 2900+offset if missing) using the same
        // pattern as DatabaseSeeds.seedAccountsForCurrency. This
        // ensures the annual posting always succeeds for every
        // currency that has activity, matching the IAS 1 requirement
        // that closing entries must transfer net profit to retained
        // earnings.
        Map<String, dynamic>? reAccount = retainedEarningsAccounts
            .where((a) => a['currency'] == currency)
            .firstOrNull;
        int reAccId;
        if (reAccount != null) {
          reAccId = reAccount['id'] as int;
        } else {
          // Get the code offset for this currency.
          final codeOffset = await _getOrCreateCodeOffsetForCurrency(txn, currency);
          // Ensure the Equity root (2900+offset) exists.
          final equityRootCode = (2900 + codeOffset).toString();
          var equityRootRows = await txn.query('accounts',
              where: 'account_code = ? AND currency = ?',
              whereArgs: [equityRootCode, currency],
              limit: 1);
          int? equityRootId;
          if (equityRootRows.isNotEmpty) {
            equityRootId = equityRootRows.first['id'] as int;
          } else {
            // Get the currency symbol for the account name.
            final curRows = await txn.query('currencies',
                where: 'code = ?', whereArgs: [currency], limit: 1);
            final symbol = curRows.isNotEmpty
                ? (curRows.first['symbol'] as String? ?? currency)
                : currency;
            equityRootId = await txn.insert('accounts', {
              'name_ar': 'حقوق الملكية ($symbol)',
              'name_en': 'Equity ($currency)',
              'account_code': equityRootCode,
              'account_type': 'EQUITY',
              'balance': 0,
              'currency': currency,
              'balance_type': 'credit',
              'base_code': 2900,
              'parent_id': null,
              'is_active': 1,
              'is_system': 1,
              'debt_ceiling': 0,
              'created_at': now,
              'updated_at': now,
            });
          }
          // Create the Retained Earnings account (2910+offset).
          final reCode = (2910 + codeOffset).toString();
          final curRows = await txn.query('currencies',
              where: 'code = ?', whereArgs: [currency], limit: 1);
          final symbol = curRows.isNotEmpty
              ? (curRows.first['symbol'] as String? ?? currency)
              : currency;
          reAccId = await txn.insert('accounts', {
            'name_ar': 'الأرباح المحتجزة ($symbol)',
            'name_en': 'Retained Earnings ($currency)',
            'account_code': reCode,
            'account_type': 'EQUITY',
            'balance': 0,
            'currency': currency,
            'balance_type': 'credit',
            'base_code': 2910,
            'parent_id': equityRootId,
            'is_active': 1,
            'is_system': 1,
            'debt_ceiling': 0,
            'created_at': now,
            'updated_at': now,
          });
        }

        // Close revenue accounts: Debit Revenue, Credit Retained Earnings
        for (final acc
            in revenueAccounts.where((a) => a['currency'] == currency)) {
          final accId = acc['id'] as int;
          final balance = await calcNormalBalance(accId, 'REVENUE');
          if (balance == 0.0) continue;

          // Revenue accounts have credit normal balance, to close we debit them
          await txn.insert('transactions', {
            'account_id': accId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(balance),
            'credit': 0,
            'description': 'إقفال إيرادات السنة $year',
            'date': '$year-12-31',
            'created_at': now,
            'currency_code': currency,
            'exchange_rate': rate,
            'amount_base': MoneyHelper.toCents(balance * rate),
                    'reference_type': 'account_journal',
          'reference_id': journalId.toString(),
});
          await _updateAccountBalanceWithJournal(txn, accId, balance, 0.0, now);

          // Credit Retained Earnings
          await txn.insert('transactions', {
            'account_id': reAccId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(balance),
            'description': 'ترحيل أرباح السنة $year',
            'date': '$year-12-31',
            'created_at': now,
            'currency_code': currency,
            'exchange_rate': rate,
            'amount_base': MoneyHelper.toCents(balance * rate),
                    'reference_type': 'account_journal',
          'reference_id': journalId.toString(),
});
          await _updateAccountBalanceWithJournal(
              txn, reAccId, 0.0, balance, now);
        }

        // Close cost accounts: Debit Retained Earnings, Credit Cost
        for (final acc
            in costAccounts.where((a) => a['currency'] == currency)) {
          final accId = acc['id'] as int;
          final balance = await calcNormalBalance(accId, 'COST');
          if (balance == 0.0) continue;

          // Cost accounts have debit normal balance, to close we credit them
          await txn.insert('transactions', {
            'account_id': accId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(balance),
            'description': 'إقفال تكاليف السنة $year',
            'date': '$year-12-31',
            'created_at': now,
            'currency_code': currency,
            'exchange_rate': rate,
            'amount_base': MoneyHelper.toCents(balance * rate),
                    'reference_type': 'account_journal',
          'reference_id': journalId.toString(),
});
          await _updateAccountBalanceWithJournal(txn, accId, 0.0, balance, now);

          // Debit Retained Earnings
          await txn.insert('transactions', {
            'account_id': reAccId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(balance),
            'credit': 0,
            'description': 'ترحيل تكاليف السنة $year',
            'date': '$year-12-31',
            'created_at': now,
            'currency_code': currency,
            'exchange_rate': rate,
            'amount_base': MoneyHelper.toCents(balance * rate),
                    'reference_type': 'account_journal',
          'reference_id': journalId.toString(),
});
          await _updateAccountBalanceWithJournal(
              txn, reAccId, balance, 0.0, now);
        }

        // Close expense accounts: Debit Retained Earnings, Credit Expense
        for (final acc
            in expenseAccounts.where((a) => a['currency'] == currency)) {
          final accId = acc['id'] as int;
          final balance = await calcNormalBalance(accId, 'EXPENSE');
          if (balance == 0.0) continue;

          // Expense accounts have debit balance, to close we credit them
          await txn.insert('transactions', {
            'account_id': accId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(balance),
            'description': 'إقفال مصاريف السنة $year',
            'date': '$year-12-31',
            'created_at': now,
            'currency_code': currency,
            'exchange_rate': rate,
            'amount_base': MoneyHelper.toCents(balance * rate),
                    'reference_type': 'account_journal',
          'reference_id': journalId.toString(),
});
          await _updateAccountBalanceWithJournal(txn, accId, 0.0, balance, now);

          // Debit Retained Earnings
          await txn.insert('transactions', {
            'account_id': reAccId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(balance),
            'credit': 0,
            'description': 'ترحيل مصاريف السنة $year',
            'date': '$year-12-31',
            'created_at': now,
            'currency_code': currency,
            'exchange_rate': rate,
            'amount_base': MoneyHelper.toCents(balance * rate),
                    'reference_type': 'account_journal',
          'reference_id': journalId.toString(),
});
          await _updateAccountBalanceWithJournal(
              txn, reAccId, balance, 0.0, now);
        }

        // A-08: Accumulate for total, converting foreign currencies to YER
        if (currency == 'YER') {
          totalNetProfitYER += netForCurrency;
        } else {
          // Convert foreign currency profit to YER using exchange rate from currencies table
          try {
            final currencyRow = await txn.query('currencies',
                where: 'code = ?', whereArgs: [currency], limit: 1);
            if (currencyRow.isNotEmpty) {
              final rate =
                  (currencyRow.first['exchange_rate'] as num?)?.toDouble() ??
                      1.0;
              if (rate > 0) {
                totalNetProfitYER += netForCurrency * rate;
              }
            }
          } catch (_) {
            // If currency table or rate not available, accumulate without conversion
            totalNetProfitYER += netForCurrency;
          }
        }
      }

      // Create or update fiscal year record
      final existingFY = await txn.query('fiscal_years',
          where: 'year = ?', whereArgs: [year], limit: 1);
      if (existingFY.isNotEmpty) {
        await txn.update(
            'fiscal_years',
            {
              'status': 'closed',
              'net_profit': MoneyHelper.toCents(totalNetProfitYER),
              'closed_at': now,
              'updated_at': now,
            },
            where: 'year = ?',
            whereArgs: [year]);
      } else {
        await txn.insert('fiscal_years', {
          'year': year,
          'start_date': '$year-01-01',
          'end_date': '$year-12-31',
          'status': 'closed',
          'net_profit': MoneyHelper.toCents(totalNetProfitYER),
          'closed_at': now,
          'notes': 'ترحيل سنوي تلقائي',
          'created_at': now,
          'updated_at': now,
        });
      }
    });
  }

  // ══════════════════════════════════════════════════════════════
  //  Typed getters (C-09: domain model alternatives to raw maps)
  // ══════════════════════════════════════════════════════════════

  Future<List<Account>> getAllAccountObjects() async {
    final maps = await getAllAccounts();
    return maps.map((m) => Account.fromMap(m)).toList();
  }

  Future<List<Account>> getAccountObjectsByType(String accountType) async {
    final maps = await getAccountsByType(accountType);
    return maps.map((m) => Account.fromMap(m)).toList();
  }

  Future<List<Account>> getExpenseAccountObjects() async {
    final maps = await getExpenseAccounts();
    return maps.map((m) => Account.fromMap(m)).toList();
  }

  Future<List<Account>> getExpenseAccountObjectsByCurrency(
      String currency) async {
    final maps = await getExpenseAccountsByCurrency(currency);
    return maps.map((m) => Account.fromMap(m)).toList();
  }

  Future<Account?> getAccountObjectById(int id) async {
    final db = await _db;
    final results =
        await db.query('accounts', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? Account.fromMap(results.first) : null;
  }

  // ══════════════════════════════════════════════════════════════
  //  Private helpers
  // ══════════════════════════════════════════════════════════════

  Future<void> _updateAccountBalanceWithJournal(
    Transaction txn,
    int accountId,
    double debit,
    double credit,
    String now,
  ) async {
    final account = await txn.query('accounts',
        where: 'id = ?', whereArgs: [accountId], limit: 1);
    if (account.isNotEmpty) {
      final currentBalance = MoneyHelper.readMoney(account.first['balance']);
      final balanceTypeRaw = account.first['balance_type'] as String? ?? 'auto';
      final accountType = account.first['account_type'] as String? ?? 'ASSET';
      final bool isCreditBalance = balanceTypeRaw == 'credit' ||
          (balanceTypeRaw == 'auto' &&
              (accountType == 'LIABILITY' ||
                  accountType == 'EQUITY' ||
                  accountType == 'REVENUE'));
      double newBalance;
      if (isCreditBalance) {
        newBalance = currentBalance + credit - debit;
      } else {
        newBalance = currentBalance + debit - credit;
      }
      await txn.update('accounts',
          {'balance': MoneyHelper.toCents(newBalance), 'updated_at': now},
          where: 'id = ?', whereArgs: [accountId]);
    }
  }

  /// Get the code_offset for a currency from the currencies table.
  ///
  /// Used by [performAnnualPosting] (A-03 fix) to compute the correct
  /// account_code for the Retained Earnings account (2910+offset) and
  /// its parent Equity root (2900+offset) when auto-creating them for
  /// a currency that has activity but no Equity accounts yet.
  ///
  /// Returns 0 for YER (base currency), or the stored code_offset for
  /// other currencies. Returns 0 as a fallback if the currency row is
  /// missing or the column is NULL (defensive — should not happen after
  /// migration v51 + the fresh-install seed fix in BaseCurrencyService).
  Future<int> _getOrCreateCodeOffsetForCurrency(
    Transaction txn, String currency) async {
  final rows = await txn.query('currencies',
      where: 'code = ?', whereArgs: [currency], limit: 1);
  if (rows.isEmpty) return 0;
  final offset = rows.first['code_offset'];
  if (offset == null) return 0;
  if (offset is int) return offset;
  // SQLite may return num for INTEGER columns in some drivers.
  return (offset as num).toInt();
  }
}
