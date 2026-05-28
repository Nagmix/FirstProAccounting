import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/utils/money_helper.dart';
import '../database_helper.dart';

/// Service responsible for journal-entry operations, account-balance updates,
/// fiscal-period validation, and exchange-rate gain/loss accounting.
///
/// Extracted from [DatabaseHelper] as part of the God-class decomposition (C-08).
class JournalService {
  final DatabaseHelper _dbHelper;

  JournalService(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  // ══════════════════════════════════════════════════════════════
  //  Account-balance helpers
  // ══════════════════════════════════════════════════════════════

  /// Public helper to update account balance by amount.
  ///
  /// [isDebit] = true means this is a debit entry (increase for debit-balance accounts).
  /// [isDebit] = false means this is a credit entry (increase for credit-balance accounts).
  Future<void> updateAccountBalance(
    int accountId,
    double amount, {
    required bool isDebit,
  }) async {
    final db = await _db;
    final account = await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    if (account.isNotEmpty) {
      final currentBalance = MoneyHelper.readMoney(account.first['balance']);
      final balanceType =
          account.first['balance_type'] as String? ?? 'credit';
      double newBalance;
      if (balanceType == 'credit') {
        // Credit-balance accounts: credit increases, debit decreases
        newBalance = isDebit ? currentBalance - amount : currentBalance + amount;
      } else {
        // Debit-balance accounts: debit increases, credit decreases
        newBalance = isDebit ? currentBalance + amount : currentBalance - amount;
      }
      await db.update(
        'accounts',
        {
          'balance': newBalance,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [accountId],
      );
    }
  }

  /// Update an account's balance considering its balance_type within a
  /// database transaction.
  ///
  /// For credit-balance accounts (LIABILITY, REVENUE, most EXPENSE):
  ///   balance = balance + credit - debit
  /// For debit-balance accounts (ASSET, COST):
  ///   balance = balance + debit - credit
  Future<void> updateAccountBalanceWithJournal(
    Transaction txn,
    int accountId,
    double debit,
    double credit,
    String now,
  ) async {
    final account = await txn.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    if (account.isNotEmpty) {
      final currentBalance = MoneyHelper.readMoney(account.first['balance']);
      final balanceType =
          account.first['balance_type'] as String? ?? 'credit';
      double newBalance;
      if (balanceType == 'credit') {
        newBalance = currentBalance + credit - debit;
      } else {
        newBalance = currentBalance + debit - credit;
      }
      await txn.update(
        'accounts',
        {
          'balance': MoneyHelper.toCents(newBalance),
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [accountId],
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  Journal-balance validation
  // ══════════════════════════════════════════════════════════════

  /// Validate that total debits equal total credits for a journal entry (C-03).
  ///
  /// Throws an exception if the journal entry is unbalanced.
  void validateJournalBalance(List<Map<String, dynamic>> entries) {
    double totalDebit = 0.0;
    double totalCredit = 0.0;
    for (final entry in entries) {
      totalDebit += MoneyHelper.readMoney(entry['debit']);
      totalCredit += MoneyHelper.readMoney(entry['credit']);
    }
    final difference = (totalDebit - totalCredit).abs();
    if (difference > 0.01) {
      debugPrint(
        '⚠️ UNBALANCED JOURNAL ENTRY: Debit=$totalDebit, Credit=$totalCredit, Diff=$difference',
      );
      throw Exception(
        'قيد محاسبي غير متوازن: المدين=$totalDebit, الدائن=$totalCredit, الفرق=$difference',
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  Account-balance queries
  // ══════════════════════════════════════════════════════════════

  /// Reconcile an account's balance column with the actual computed balance
  /// from transactions.
  ///
  /// Computes SUM(debit) - SUM(credit) and updates the `balance` column.
  Future<void> reconcileAccountBalance(int accountId) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    // Get the account's balance_type to compute balance correctly
    final accountRow = await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    if (accountRow.isEmpty) return;
    final balanceType =
        accountRow.first['balance_type'] as String? ?? 'credit';

    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(debit) - SUM(credit), 0.0) AS net_debit, '
      'COALESCE(SUM(credit) - SUM(debit), 0.0) AS net_credit '
      'FROM transactions WHERE account_id = ?',
      [accountId],
    );
    final netDebit = MoneyHelper.readMoney(result.first['net_debit']);
    final netCredit = MoneyHelper.readMoney(result.first['net_credit']);

    // For debit-balance accounts (ASSET, COST): balance = debit - credit
    // For credit-balance accounts (LIABILITY, REVENUE, EXPENSE): balance = credit - debit
    final computedBalance = (balanceType == 'debit') ? netDebit : netCredit;
    await db.update(
      'accounts',
      {
        'balance': MoneyHelper.toCents(computedBalance),
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [accountId],
    );
  }

  /// Get current balance of an account (computed from transactions).
  Future<double> getAccountBalance(int accountId) async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(debit) - SUM(credit), 0) AS balance FROM transactions WHERE account_id = ?",
      [accountId],
    );
    return MoneyHelper.readMoney(result.first['balance']);
  }

  /// Get all transactions for an account with running balance calculated.
  Future<List<Map<String, dynamic>>> getAccountTransactions(
    int accountId,
  ) async {
    final db = await _db;
    return await db.query(
      'transactions',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'date ASC, id ASC',
    );
  }

  /// Get transactions by account ordered by date descending.
  Future<List<Map<String, dynamic>>> getTransactionsByAccount(
    int accountId,
  ) async {
    final db = await _db;
    return await db.query(
      'transactions',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'date DESC',
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Exchange gain/loss accounting
  // ══════════════════════════════════════════════════════════════

  /// Calculate foreign-exchange gains or losses.
  ///
  /// Used when closing a period or settling an account in a different
  /// currency.  Formula: gain/loss = (base_amount / current_rate) -
  /// (base_amount / original_rate).
  ///
  /// A positive result = exchange gain; negative = exchange loss.
  Future<double> calculateExchangeGainLoss({
    required double baseAmount,
    required double originalRate,
    required double currentRate,
  }) async {
    if (originalRate <= 0 || currentRate <= 0) return 0.0;
    final valueAtOriginalRate = baseAmount / originalRate;
    final valueAtCurrentRate = baseAmount / currentRate;
    // إذا كان الفرق إيجابياً = مكسب صرف، سلبياً = خسارة صرف
    return valueAtCurrentRate - valueAtOriginalRate;
  }

  /// Create a journal entry for foreign-exchange gains/losses.
  Future<void> recordExchangeGainLoss({
    required int accountId,
    required double gainLossAmount,
    required String currency,
    required String referenceId,
  }) async {
    if (gainLossAmount.abs() < 0.01) return;

    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final journalId = DateTime.now().millisecondsSinceEpoch;

    // البحث عن حساب مكاسب/خسائر الصرف (إن وجد) أو استخدام حساب المصاريف
    var exchangeAccountId = await getOrCreateExchangeAccount();

    await db.transaction((txn) async {
      if (gainLossAmount > 0) {
        // مكسب صرف: مدين = الحساب الأصلي، دائن = حساب مكاسب الصرف
        await txn.insert('transactions', {
          'account_id': accountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(gainLossAmount.abs()),
          'credit': 0,
          'description': 'مكاسب صرف $currency - $referenceId',
          'date': now.substring(0, 10),
          'created_at': now,
        });
        await txn.insert('transactions', {
          'account_id': exchangeAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(gainLossAmount.abs()),
          'description': 'مكاسب صرف $currency - $referenceId',
          'date': now.substring(0, 10),
          'created_at': now,
        });
        await updateAccountBalanceWithJournal(
          txn, accountId, gainLossAmount.abs(), 0.0, now,
        );
        await updateAccountBalanceWithJournal(
          txn, exchangeAccountId, 0.0, gainLossAmount.abs(), now,
        );
      } else {
        // خسارة صرف: مدين = حساب خسائر الصرف، دائن = الحساب الأصلي
        await txn.insert('transactions', {
          'account_id': exchangeAccountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(gainLossAmount.abs()),
          'credit': 0,
          'description': 'خسائر صرف $currency - $referenceId',
          'date': now.substring(0, 10),
          'created_at': now,
        });
        await txn.insert('transactions', {
          'account_id': accountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(gainLossAmount.abs()),
          'description': 'خسائر صرف $currency - $referenceId',
          'date': now.substring(0, 10),
          'created_at': now,
        });
        await updateAccountBalanceWithJournal(
          txn, exchangeAccountId, gainLossAmount.abs(), 0.0, now,
        );
        await updateAccountBalanceWithJournal(
          txn, accountId, 0.0, gainLossAmount.abs(), now,
        );
      }
    });
  }

  // ══════════════════════════════════════════════════════════════
  //  Fiscal-period & exchange-account helpers
  // ══════════════════════════════════════════════════════════════

  /// Check that the fiscal period is open before making any changes.
  ///
  /// Throws an exception if the fiscal year for the given [dateStr] is
  /// closed, preventing modifications in closed periods.
  Future<void> checkFiscalPeriodOpen(String dateStr) async {
    final db = await _db;
    final date = DateTime.tryParse(dateStr);
    if (date == null) return;
    final year = date.year;

    // تحقق من وجود سنة مالية مقفلة لهذه الفترة
    final result = await db.query(
      'fiscal_years',
      where: 'year = ? AND status = ?',
      whereArgs: [year, 'closed'],
      limit: 1,
    );
    if (result.isNotEmpty) {
      throw Exception(
        'الفترة المحاسبية للعام $year مغلقة. لا يمكن إجراء عمليات في فترة مقفلة.',
      );
    }
  }

  /// Get or create the exchange-rate gains/losses system account.
  ///
  /// Returns the account id of the existing or newly-created account.
  Future<int> getOrCreateExchangeAccount() async {
    final db = await _db;
    // البحث عن حساب مكاسب/خسائر الصرف
    final existing = await db.query(
      'accounts',
      where: "account_code LIKE '53%' AND is_system = 1",
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.first['id'] as int;

    // إنشاء حساب جديد
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('accounts', {
      'name_ar': 'مكاسب/خسائر فروقات الصرف',
      'name_en': 'Exchange Rate Gains/Losses',
      'account_code': '5300',
      'account_type': 'EXPENSE',
      'balance': 0,
      'currency': 'YER',
      'balance_type': 'credit',
      'is_active': 1,
      'is_system': 1,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  /// Get account by code and currency.
  Future<Map<String, dynamic>?> getAccountByCodeAndCurrency(
    String code,
    String currency,
  ) async {
    final db = await _db;
    final results = await db.query(
      'accounts',
      where: 'account_code = ? AND currency = ?',
      whereArgs: [code, currency],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Find an account by its base code and currency within an active
  /// database transaction.
  ///
  /// Applies the standard code-offset convention:
  ///   - YER: +0, SAR: +1, USD: +2
  Future<Map<String, dynamic>?> findAccountByCodeAndCurrency(
    Transaction txn,
    String baseCode,
    String currency,
  ) async {
    // Determine code offset based on currency
    String codeOffset = '0';
    if (currency == 'SAR') {
      codeOffset = '1';
    } else if (currency == 'USD') {
      codeOffset = '2';
    }
    final actualCode =
        (int.parse(baseCode) + int.parse(codeOffset)).toString();
    final result = await txn.query(
      'accounts',
      where: 'account_code = ? AND currency = ?',
      whereArgs: [actualCode, currency],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }
}
