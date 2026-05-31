import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/utils/journal_id_helper.dart';
import '../../../core/utils/money_helper.dart';
import '../../models/account_model.dart';
import '../database_helper.dart';

class AccountRepository {
  final DatabaseHelper _dbHelper;
  AccountRepository(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  // ══════════════════════════════════════════════════════════════
  //  Account CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getAllAccounts() async {
    final db = await _db;
    return await db.query('accounts', where: 'is_active = ?', whereArgs: [1], orderBy: 'account_code ASC');
  }

  Future<List<Map<String, dynamic>>> getAccountsByType(String accountType) async {
    final db = await _db;
    return await db.query('accounts', where: 'is_active = ? AND account_type = ?', whereArgs: [1, accountType], orderBy: 'account_code ASC');
  }

  Future<List<Map<String, dynamic>>> getAccountsByCurrency(String currencyCode) async {
    final db = await _db;
    return await db.query('accounts', where: 'is_active = ? AND currency = ?', whereArgs: [1, currencyCode], orderBy: 'account_code ASC');
  }

  Future<int> insertAccount(Map<String, dynamic> accountMap) async {
    final db = await _db;
    return await db.insert('accounts', MoneyHelper.toCentsMap(accountMap, MoneyHelper.accountMoneyFields));
  }

  Future<int> updateAccount(int id, Map<String, dynamic> accountMap) async {
    final db = await _db;
    return await db.update('accounts', MoneyHelper.toCentsMap(accountMap, MoneyHelper.accountMoneyFields), where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAccount(int id) async {
    final db = await _db;
    // Check if it's a system account
    final account = await db.query('accounts', where: 'id = ?', whereArgs: [id], limit: 1);
    if (account.isEmpty) return 0;
    if ((account.first['is_system'] as int?) == 1) {
      return -1; // Cannot delete system account
    }
    // Check for child accounts
    final children = await db.query('accounts', where: 'parent_id = ?', whereArgs: [id], limit: 1);
    if (children.isNotEmpty) {
      return -2; // Cannot delete account with child accounts
    }
    // Check for transactions referencing this account
    final transactions = await db.query('transactions', where: 'account_id = ?', whereArgs: [id], limit: 1);
    if (transactions.isNotEmpty) {
      return -3; // Cannot delete account with transactions
    }
    // Check for voucher items referencing this account
    try {
      final voucherItems = await db.query('voucher_items', where: 'account_id = ?', whereArgs: [id], limit: 1);
      if (voucherItems.isNotEmpty) {
        return -4; // Cannot delete account with voucher items
      }
    } catch (_) {
      // voucher_items table may not exist in older databases
    }
    // Remove linked_cash_box_id references
    await db.rawUpdate('UPDATE cash_boxes SET linked_account_id = NULL WHERE linked_account_id = ?', [id]);
    return await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  /// Get the next available account code for a given account type.
  /// Uses 4-digit numeric codes where the first digit is the type prefix.
  /// Steps by 10 to leave room for sub-accounts.
  Future<String> getNextAccountCode(String accountType) async {
    final db = await _db;
    final prefixMap = {
      'ASSET': '1',
      'LIABILITY': '2',
      'EQUITY': '2',  // Equity shares the 2xxx range with Liabilities
      'COST': '3',
      'REVENUE': '4',
      'EXPENSE': '5',
    };
    final prefix = prefixMap[accountType] ?? '9';
    final result = await db.rawQuery(
      'SELECT COALESCE(MAX(CAST(account_code AS INTEGER)), 0) AS max_code FROM accounts WHERE account_code LIKE ? AND account_type = ?',
      ['$prefix%', accountType],
    );
    final maxCode = (result.first['max_code'] as num?)?.toInt() ?? 0;
    // If no existing codes, start at prefix*1000 + 10 (e.g. 1010 for ASSET)
    final nextCode = maxCode == 0 ? (int.parse(prefix) * 1000 + 10) : maxCode + 10;
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

    // Get next account code for EXPENSE type
    final codeOffset = currency == 'SAR' ? 1 : (currency == 'USD' ? 2 : 0);
    final currencySymbol = currency == 'SAR' ? 'ر.س' : (currency == 'USD' ? r'$' : 'ر.ي');

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
      final lastCode = int.tryParse(existingExpenseAccounts.first['account_code'] as String) ?? 5000;
      newCode = (lastCode + 1).toString();
    } else {
      newCode = (5000 + codeOffset).toString();
    }

    // Create the account inside a transaction for atomicity
    return await db.transaction((txn) async {
      // Create account with initial balance = 0 (will be updated via journal)
      final accountId = await txn.insert('accounts', MoneyHelper.toCentsMap({
        'name_ar': '$nameAr ($currencySymbol)',
        'name_en': nameAr,
        'account_code': newCode,
        'account_type': 'EXPENSE',
        'balance': 0,  // Start at 0, will be updated via _updateAccountBalanceWithJournal
        'currency': currency,
        'is_active': 1,
        'is_system': 0,
        'debt_ceiling': debtCeiling ?? 0.0,
        'balance_type': balanceType,
        'created_at': now,
        'updated_at': now,
      }, MoneyHelper.accountMoneyFields));

      // Create double-entry opening balance transaction if > 0
      // Must include contra-entry to Opening Balance Equity account (2901+offset)
      if (openingBalance > 0) {
        final journalId = generateUniqueJournalId();

        // Find the Opening Balance Equity account for this currency
        final codeOffset = {'YER': 0, 'SAR': 1, 'USD': 2}[currency] ?? 0;
        final obCode = (2901 + codeOffset).toString();
        final obAccounts = await txn.query(
          'accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [obCode, currency],
          limit: 1,
        );

        if (obAccounts.isNotEmpty) {
          final obAccountId = obAccounts.first['id'] as int;

          if (balanceType == 'credit') {
            // Expense account has credit balance (unlikely but possible)
            // Credit the expense account, Debit the Opening Balance Equity
            await txn.insert('transactions', {
              'account_id': accountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(openingBalance),
              'description': 'رصيد افتتاحي - $nameAr',
              'date': now,
              'created_at': now,
            });
            await txn.insert('transactions', {
              'account_id': obAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(openingBalance),
              'credit': 0,
              'description': 'مقابل رصيد افتتاحي - $nameAr',
              'date': now,
              'created_at': now,
            });
            // Update both account balances
            await _updateAccountBalanceWithJournal(txn, accountId, 0.0, openingBalance, now);
            await _updateAccountBalanceWithJournal(txn, obAccountId, openingBalance, 0.0, now);
          } else {
            // Expense account has debit balance (normal for expenses)
            // Debit the expense account, Credit the Opening Balance Equity
            await txn.insert('transactions', {
              'account_id': accountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(openingBalance),
              'credit': 0,
              'description': 'رصيد افتتاحي - $nameAr',
              'date': now,
              'created_at': now,
            });
            await txn.insert('transactions', {
              'account_id': obAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(openingBalance),
              'description': 'مقابل رصيد افتتاحي - $nameAr',
              'date': now,
              'created_at': now,
            });
            // Update both account balances
            await _updateAccountBalanceWithJournal(txn, accountId, openingBalance, 0.0, now);
            await _updateAccountBalanceWithJournal(txn, obAccountId, 0.0, openingBalance, now);
          }
        } else {
          // Fallback: if no Opening Balance Equity account found, create single-sided entry
          // but log a warning since this means the double-entry is incomplete
          debugPrint('WARNING: No Opening Balance Equity account found for currency $currency. Creating single-sided entry for $nameAr.');
          if (balanceType == 'credit') {
            await txn.insert('transactions', {
              'account_id': accountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(openingBalance),
              'description': 'رصيد افتتاحي - $nameAr',
              'date': now,
              'created_at': now,
            });
          } else {
            await txn.insert('transactions', {
              'account_id': accountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(openingBalance),
              'credit': 0,
              'description': 'رصيد افتتاحي - $nameAr',
              'date': now,
              'created_at': now,
            });
          }
          await _updateAccountBalanceWithJournal(txn, accountId,
            balanceType == 'debit' ? openingBalance : 0.0,
            balanceType == 'credit' ? openingBalance : 0.0, now);
        }
      }

      return accountId;
    });
  }

  Future<List<Map<String, dynamic>>> getExpenseAccounts() async {
    final db = await _db;
    return await db.query('accounts', where: 'is_active = ? AND account_type = ?', whereArgs: [1, 'EXPENSE'], orderBy: 'account_code ASC');
  }

  /// Get expense accounts filtered by currency
  Future<List<Map<String, dynamic>>> getExpenseAccountsByCurrency(String currency) async {
    final db = await _db;
    return await db.query('accounts', where: 'is_active = ? AND account_type = ? AND currency = ?', whereArgs: [1, 'EXPENSE', currency], orderBy: 'account_code ASC');
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
    final yearEnd = '$year-12-31';

    // REVENUE accounts have credit normal balance → revenue = credit - debit
    final revenueResult = await db.rawQuery('''
      SELECT CAST(COALESCE(SUM(t.credit) - SUM(t.debit), 0) AS INTEGER) as total
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE a.account_type = 'REVENUE' AND a.is_active = 1
      AND t.date >= ? AND t.date <= ?
    ''', [yearStart, yearEnd]);
    final totalRevenue = MoneyHelper.readCalculatedMoney(revenueResult.first['total']);

    // COST accounts have debit normal balance → cost = debit - credit
    final costResult = await db.rawQuery('''
      SELECT CAST(COALESCE(SUM(t.debit) - SUM(t.credit), 0) AS INTEGER) as total
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE a.account_type = 'COST' AND a.is_active = 1
      AND t.date >= ? AND t.date <= ?
    ''', [yearStart, yearEnd]);
    final totalCosts = MoneyHelper.readCalculatedMoney(costResult.first['total']);

    // EXPENSE accounts have debit normal balance → expense = debit - credit
    final expenseResult = await db.rawQuery('''
      SELECT CAST(COALESCE(SUM(t.debit) - SUM(t.credit), 0) AS INTEGER) as total
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE a.account_type = 'EXPENSE' AND a.is_active = 1
      AND t.date >= ? AND t.date <= ?
    ''', [yearStart, yearEnd]);
    final totalExpenses = MoneyHelper.readCalculatedMoney(expenseResult.first['total']);

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
    final result = await db.query('fiscal_years', where: 'year = ? AND status = ?', whereArgs: [year, 'closed'], limit: 1);
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
    final yearEnd = '$year-12-31';

    await db.transaction((txn) async {
      // Check if already closed
      final existing = await txn.query('fiscal_years', where: 'year = ? AND status = ?', whereArgs: [year, 'closed'], limit: 1);
      if (existing.isNotEmpty) {
        throw Exception('السنة المالية $year مغلقة بالفعل');
      }

      // B-03: Check for existing annual posting entries to prevent double-posting
      // If closing entries already exist for this year (journal entries on Dec 31 with closing descriptions),
      // throw an error to prevent double-posting retained earnings
      final existingClosingEntries = await txn.rawQuery(
        "SELECT COUNT(*) as cnt FROM transactions WHERE date = ? AND (description LIKE ? OR description LIKE ? OR description LIKE ?)",
        ['$year-12-31', '%إقفال إيرادات السنة $year%', '%إقفال تكاليف السنة $year%', '%إقفال مصاريف السنة $year%'],
      );
      final closingCount = (existingClosingEntries.first['cnt'] as num?)?.toInt() ?? 0;
      if (closingCount > 0) {
        throw Exception('يوجد قيود إقفال سابقة للسنة $year. لا يمكن إعادة الترحيل.');
      }

      // Get all revenue accounts
      final revenueAccounts = await txn.query('accounts', where: 'account_type = ? AND is_active = 1', whereArgs: ['REVENUE']);

      // Get all cost accounts
      final costAccounts = await txn.query('accounts', where: 'account_type = ? AND is_active = 1', whereArgs: ['COST']);

      // Get all expense accounts
      final expenseAccounts = await txn.query('accounts', where: 'account_type = ? AND is_active = 1', whereArgs: ['EXPENSE']);

      // Get retained earnings accounts (one per currency)
      final retainedEarningsAccounts = await txn.query('accounts', where: 'account_code LIKE ? AND is_active = 1', whereArgs: ['290%']);

      /// Calculate account balance from transactions table for the fiscal year
      /// Returns the NORMAL balance: positive for debit-type (ASSET, EXPENSE, COST),
      /// positive for credit-type (REVENUE, LIABILITY, EQUITY).
      Future<double> calcNormalBalance(int accountId, String accountType) async {
        final result = await txn.rawQuery(
          "SELECT CAST(COALESCE(SUM(debit), 0) AS INTEGER) AS total_debit, CAST(COALESCE(SUM(credit), 0) AS INTEGER) AS total_credit "
          "FROM transactions "
          "WHERE account_id = ? AND date >= ? AND date <= ?",
          [accountId, yearStart, yearEnd],
        );
        final totalDebit = MoneyHelper.readCalculatedMoney(result.first['total_debit']);
        final totalCredit = MoneyHelper.readCalculatedMoney(result.first['total_credit']);
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
        revenuePerCurrency[currency] = (revenuePerCurrency[currency] ?? 0.0) + balance;
      }

      for (final acc in costAccounts) {
        final currency = acc['currency'] as String? ?? 'YER';
        final accId = acc['id'] as int;
        final balance = await calcNormalBalance(accId, 'COST');
        costPerCurrency[currency] = (costPerCurrency[currency] ?? 0.0) + balance;
      }

      for (final acc in expenseAccounts) {
        final currency = acc['currency'] as String? ?? 'YER';
        final accId = acc['id'] as int;
        final balance = await calcNormalBalance(accId, 'EXPENSE');
        expensePerCurrency[currency] = (expensePerCurrency[currency] ?? 0.0) + balance;
      }

      // All currencies that have activity
      final allCurrencies = {...revenuePerCurrency.keys, ...costPerCurrency.keys, ...expensePerCurrency.keys};

      double totalNetProfitYER = 0.0;

      for (final currency in allCurrencies) {
        final rev = revenuePerCurrency[currency] ?? 0.0;
        final cost = costPerCurrency[currency] ?? 0.0;
        final exp = expensePerCurrency[currency] ?? 0.0;
        final netForCurrency = rev - cost - exp;

        // Find retained earnings account for this currency
        final reAccount = retainedEarningsAccounts.where((a) => a['currency'] == currency).firstOrNull;
        if (reAccount == null) continue;
        final reAccId = reAccount['id'] as int;

        // Close revenue accounts: Debit Revenue, Credit Retained Earnings
        for (final acc in revenueAccounts.where((a) => a['currency'] == currency)) {
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
          });
          await _updateAccountBalanceWithJournal(txn, reAccId, 0.0, balance, now);
        }

        // Close cost accounts: Debit Retained Earnings, Credit Cost
        for (final acc in costAccounts.where((a) => a['currency'] == currency)) {
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
          });
          await _updateAccountBalanceWithJournal(txn, reAccId, balance, 0.0, now);
        }

        // Close expense accounts: Debit Retained Earnings, Credit Expense
        for (final acc in expenseAccounts.where((a) => a['currency'] == currency)) {
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
          });
          await _updateAccountBalanceWithJournal(txn, reAccId, balance, 0.0, now);
        }

        // A-08: Accumulate for total, converting foreign currencies to YER
        if (currency == 'YER') {
          totalNetProfitYER += netForCurrency;
        } else {
          // Convert foreign currency profit to YER using exchange rate from currencies table
          try {
            final currencyRow = await txn.query('currencies', where: 'code = ?', whereArgs: [currency], limit: 1);
            if (currencyRow.isNotEmpty) {
              final rate = (currencyRow.first['exchange_rate'] as num?)?.toDouble() ?? 1.0;
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
      final existingFY = await txn.query('fiscal_years', where: 'year = ?', whereArgs: [year], limit: 1);
      if (existingFY.isNotEmpty) {
        await txn.update('fiscal_years', {
          'status': 'closed',
          'net_profit': MoneyHelper.toCents(totalNetProfitYER),
          'closed_at': now,
          'updated_at': now,
        }, where: 'year = ?', whereArgs: [year]);
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

  Future<List<Account>> getExpenseAccountObjectsByCurrency(String currency) async {
    final maps = await getExpenseAccountsByCurrency(currency);
    return maps.map((m) => Account.fromMap(m)).toList();
  }

  Future<Account?> getAccountObjectById(int id) async {
    final db = await _db;
    final results = await db.query('accounts', where: 'id = ?', whereArgs: [id], limit: 1);
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
    final account = await txn.query('accounts', where: 'id = ?', whereArgs: [accountId], limit: 1);
    if (account.isNotEmpty) {
      final currentBalance = MoneyHelper.readMoney(account.first['balance']);
      final balanceType = account.first['balance_type'] as String? ?? 'credit';
      double newBalance;
      if (balanceType == 'credit') {
        newBalance = currentBalance + credit - debit;
      } else {
        newBalance = currentBalance + debit - credit;
      }
      await txn.update('accounts', {'balance': MoneyHelper.toCents(newBalance), 'updated_at': now}, where: 'id = ?', whereArgs: [accountId]);
    }
  }
}
