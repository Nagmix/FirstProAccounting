import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/core/utils/journal_id_helper.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/services/base_currency_service.dart';

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
  ///
  /// **Fix (7.3):** Uses an atomic SQL UPDATE with CASE expressions instead of
  /// the previous read-then-write pattern, eliminating the race condition where
  /// two concurrent operations could read the same stale balance and both write
  /// based on it, causing one update to be lost.
  ///
  /// The logic is embedded entirely in SQL:
  ///   - Credit-balance accounts: credit increases (+amount), debit decreases (-amount)
  ///   - Debit-balance accounts:  debit increases (+amount), credit decreases (-amount)
  Future<void> updateAccountBalance(
    int accountId,
    double amount, {
    required bool isDebit,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final amountCents = MoneyHelper.toCents(amount);
    // isDebitInt: 1 = debit entry, 0 = credit entry
    final isDebitInt = isDebit ? 1 : 0;

    // Atomic UPDATE: the delta is computed inside SQL based on balance_type
    // and the isDebit flag, so no separate SELECT is needed.
    //   credit + isDebit  → -amount (debit decreases credit accounts)
    //   credit + !isDebit → +amount (credit increases credit accounts)
    //   debit  + isDebit  → +amount (debit increases debit accounts)
    //   debit  + !isDebit → -amount (credit decreases debit accounts)
    await db.rawUpdate('''
      UPDATE accounts SET
        balance = balance + CASE
          WHEN balance_type = 'credit' AND ? = 1 THEN -?
          WHEN balance_type = 'credit' AND ? = 0 THEN ?
          WHEN balance_type = 'debit'  AND ? = 1 THEN ?
          WHEN balance_type = 'debit'  AND ? = 0 THEN -?
          WHEN balance_type = 'auto' AND account_type IN ('LIABILITY','EQUITY','REVENUE') AND ? = 1 THEN -?
          WHEN balance_type = 'auto' AND account_type IN ('LIABILITY','EQUITY','REVENUE') AND ? = 0 THEN ?
          WHEN balance_type = 'auto' AND account_type IN ('ASSET','COST','EXPENSE') AND ? = 1 THEN ?
          WHEN balance_type = 'auto' AND account_type IN ('ASSET','COST','EXPENSE') AND ? = 0 THEN -?
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
      isDebitInt,
      amountCents,
      isDebitInt,
      amountCents,
      isDebitInt,
      amountCents,
      isDebitInt,
      amountCents,
      now,
      accountId,
    ]);
  }

  /// Update an account's balance considering its balance_type within a
  /// database transaction.
  ///
  /// For credit-balance accounts (LIABILITY, REVENUE, EQUITY):
  ///   balance = balance + credit - debit
  /// For debit-balance accounts (ASSET, EXPENSE, COST):
  ///   balance = balance + debit - credit
  ///
  /// **Fix (7.3):** Uses an atomic SQL UPDATE with CASE expressions instead of
  /// the previous read-then-write pattern. Even though this method is already
  /// called within a `db.transaction()`, the SELECT-then-UPDATE pattern is
  /// still vulnerable to concurrent reads from other transactions (WAL mode)
  /// and is unnecessary. The atomic approach is both safer and faster.
  Future<void> updateAccountBalanceWithJournal(
    Transaction txn,
    int accountId,
    double debit,
    double credit,
    String now,
  ) async {
    final debitCents = MoneyHelper.toCents(debit);
    final creditCents = MoneyHelper.toCents(credit);
    // Net delta in cents for each balance_type:
    //   credit-balance: +credit - debit  (credit increases, debit decreases)
    //   debit-balance:  +debit - credit  (debit increases, credit decreases)
    await txn.rawUpdate('''
      UPDATE accounts SET
        balance = balance + CASE
          WHEN balance_type = 'credit' THEN ? - ?
          WHEN balance_type = 'debit'  THEN ? - ?
          WHEN balance_type = 'auto' AND account_type IN ('LIABILITY','EQUITY','REVENUE') THEN ? - ?
          WHEN balance_type = 'auto' AND account_type IN ('ASSET','COST','EXPENSE') THEN ? - ?
          ELSE 0
        END,
        updated_at = ?
      WHERE id = ?
    ''', [
      creditCents,
      debitCents,
      debitCents,
      creditCents,
      creditCents,
      debitCents,
      debitCents,
      creditCents,
      now,
      accountId,
    ]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Journal-balance validation
  // ══════════════════════════════════════════════════════════════

  /// Validate that total debits equal total credits for a journal entry (C-03).
  /// ── W-03: في نظام cents (أعداد صحيحة)، الفرق يجب أن يكون صفراً ──
  /// Throws an exception if the journal entry is unbalanced.
  void validateJournalBalance(List<Map<String, dynamic>> entries) {
    double totalDebit = 0.0;
    double totalCredit = 0.0;
    for (final entry in entries) {
      totalDebit += MoneyHelper.readMoney(entry['debit']);
      totalCredit += MoneyHelper.readMoney(entry['credit']);
    }
    final difference = (totalDebit - totalCredit).abs();
    // W-03: في نظام التخزين بالسنتات (أعداد صحيحة)، لا يجب وجود أي فرق
    if (difference > 0.005) {
      debugPrint(
        '⚠️ UNBALANCED JOURNAL ENTRY: Debit=$totalDebit, Credit=$totalCredit, Diff=$difference',
      );
      throw Exception(
        'قيد محاسبي غير متوازن: المدين=$totalDebit, الدائن=$totalCredit, الفرق=$difference',
      );
    }
  }

  /// Validate a journal entry inside an active transaction using the original
  /// transaction currency amounts. Use this when all rows are in the same
  /// currency or when each multi-currency pair is separately balanced by its
  /// original amounts.
  Future<void> validateJournalBalanceInTransaction(
    Transaction txn,
    int journalId,
  ) async {
    final entries = await txn.query(
      'transactions',
      where: 'journal_id = ?',
      whereArgs: [journalId],
    );
    validateJournalBalance(entries);
  }

  /// Validate journal balance in the base currency using `amount_base`.
  /// This is required for genuine multi-currency operations such as currency
  /// exchange, where original debit/credit amounts are in different currencies.
  Future<void> validateJournalBaseBalanceInTransaction(
    Transaction txn,
    int journalId,
  ) async {
    final debitRows = await txn.rawQuery(
      'SELECT CAST(COALESCE(SUM(amount_base), 0) AS INTEGER) AS total '
      'FROM transactions WHERE journal_id = ? AND debit > 0',
      [journalId],
    );
    final creditRows = await txn.rawQuery(
      'SELECT CAST(COALESCE(SUM(amount_base), 0) AS INTEGER) AS total '
      'FROM transactions WHERE journal_id = ? AND credit > 0',
      [journalId],
    );
    final totalDebitBase =
        MoneyHelper.readCalculatedMoney(debitRows.first['total']);
    final totalCreditBase =
        MoneyHelper.readCalculatedMoney(creditRows.first['total']);
    final difference = (totalDebitBase - totalCreditBase).abs();
    if (difference > 0.005) {
      debugPrint(
        '⚠️ UNBALANCED BASE JOURNAL ENTRY: DebitBase=$totalDebitBase, CreditBase=$totalCreditBase, Diff=$difference',
      );
      throw Exception(
        'قيد محاسبي غير متوازن بالعملة الأساسية: المدين=$totalDebitBase, الدائن=$totalCreditBase, الفرق=$difference',
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
    final balanceType = accountRow.first['balance_type'] as String? ?? 'credit';

    final result = await db.rawQuery(
      'SELECT CAST(COALESCE(SUM(debit) - SUM(credit), 0) AS INTEGER) AS net_debit, '
      'CAST(COALESCE(SUM(credit) - SUM(debit), 0) AS INTEGER) AS net_credit '
      'FROM transactions WHERE account_id = ?',
      [accountId],
    );
    final netDebit = MoneyHelper.readCalculatedMoney(result.first['net_debit']);
    final netCredit =
        MoneyHelper.readCalculatedMoney(result.first['net_credit']);

    // For debit-balance accounts (ASSET, EXPENSE, COST): balance = debit - credit
    // For credit-balance accounts (LIABILITY, REVENUE, EQUITY): balance = credit - debit
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
  /// ── W-02: يعتبر طبيعة الحساب (مدين/دائن) ──
  /// لحسابات ذات طبيعة دائنة (إيرادات، خصوم، حقوق ملكية): الرصيد = دائن - مدين
  /// لحسابات ذات طبيعة مدينة (أصول، تكاليف): الرصيد = مدين - دائن
  Future<double> getAccountBalance(int accountId) async {
    final db = await _db;
    // جلب نوع رصيد الحساب
    final accountRow = await db.query('accounts',
        where: 'id = ?', whereArgs: [accountId], limit: 1);
    if (accountRow.isEmpty) return 0.0;
    final balanceType = accountRow.first['balance_type'] as String? ?? 'credit';

    final result = await db.rawQuery(
      "SELECT CAST(COALESCE(SUM(debit), 0) AS INTEGER) AS total_debit, CAST(COALESCE(SUM(credit), 0) AS INTEGER) AS total_credit FROM transactions WHERE account_id = ?",
      [accountId],
    );
    final totalDebit =
        MoneyHelper.readCalculatedMoney(result.first['total_debit']);
    final totalCredit =
        MoneyHelper.readCalculatedMoney(result.first['total_credit']);

    // الرصيد حسب طبيعة الحساب
    if (balanceType == 'debit') {
      return totalDebit - totalCredit; // أصول وتكاليف: الرصيد الطبيعي مدين
    } else {
      return totalCredit -
          totalDebit; // خصوم وإيرادات وحقوق ملكية: الرصيد الطبيعي دائن
    }
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
  /// currency.
  ///
  /// [baseAmount] is in LOCAL currency (YER).
  /// [originalRate] and [currentRate] are quoted as local units per foreign unit
  /// (e.g. 500 YER/USD).
  ///
  /// Fix #3: The result must be in LOCAL currency (YER), not foreign.
  /// Correct formula:
  ///   foreignAmount = baseAmount / originalRate
  ///   valueAtCurrentRate = foreignAmount * currentRate = (baseAmount / originalRate) * currentRate
  ///   gainLoss = valueAtCurrentRate - baseAmount
  ///
  /// A positive result = exchange gain; negative = exchange loss.
  Future<double> calculateExchangeGainLoss({
    required double baseAmount,
    required double originalRate,
    required double currentRate,
  }) async {
    if (originalRate <= 0 || currentRate <= 0) return 0.0;
    // Fix #3: Convert to local currency correctly
    // baseAmount is in local currency (YER)
    // We convert to foreign: foreignAmount = baseAmount / originalRate
    // Then convert back at current rate: valueNow = foreignAmount * currentRate
    // The difference in local currency = valueNow - baseAmount
    final foreignAmount = baseAmount / originalRate;
    final valueAtCurrentRate = foreignAmount * currentRate;
    return valueAtCurrentRate - baseAmount;
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
    final journalId = generateUniqueJournalId();

    // Fix #5: Use separate gain/loss accounts with correct account types
    final exchangeAccountId =
        await getOrCreateExchangeAccount(isGain: gainLossAmount > 0);

    await db.transaction((txn) async {
      if (gainLossAmount > 0) {
        // مكسب صرف: مدين = الحساب الأصلي، دائن = حساب مكاسب الصرف (REVENUE/credit)
        await txn.insert('transactions', {
          'account_id': accountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(gainLossAmount.abs()),
          'credit': 0,
          'description': 'مكاسب صرف $currency - $referenceId',
          'date': now.substring(0, 10),
          'created_at': now,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': MoneyHelper.toCents(gainLossAmount.abs()),
                  'reference_type': 'exchange_gain_loss',
          'reference_id': journalId.toString(),
});
        await txn.insert('transactions', {
          'account_id': exchangeAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(gainLossAmount.abs()),
          'description': 'مكاسب صرف $currency - $referenceId',
          'date': now.substring(0, 10),
          'created_at': now,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': MoneyHelper.toCents(gainLossAmount.abs()),
                  'reference_type': 'exchange_gain_loss',
          'reference_id': journalId.toString(),
});
        await updateAccountBalanceWithJournal(
          txn,
          accountId,
          gainLossAmount.abs(),
          0.0,
          now,
        );
        await updateAccountBalanceWithJournal(
          txn,
          exchangeAccountId,
          0.0,
          gainLossAmount.abs(),
          now,
        );
      } else {
        // خسارة صرف: مدين = حساب خسائر الصرف (EXPENSE/debit)، دائن = الحساب الأصلي
        await txn.insert('transactions', {
          'account_id': exchangeAccountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(gainLossAmount.abs()),
          'credit': 0,
          'description': 'خسائر صرف $currency - $referenceId',
          'date': now.substring(0, 10),
          'created_at': now,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': MoneyHelper.toCents(gainLossAmount.abs()),
                  'reference_type': 'exchange_gain_loss',
          'reference_id': journalId.toString(),
});
        await txn.insert('transactions', {
          'account_id': accountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(gainLossAmount.abs()),
          'description': 'خسائر صرف $currency - $referenceId',
          'date': now.substring(0, 10),
          'created_at': now,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': MoneyHelper.toCents(gainLossAmount.abs()),
                  'reference_type': 'exchange_gain_loss',
          'reference_id': journalId.toString(),
});
        await updateAccountBalanceWithJournal(
          txn,
          exchangeAccountId,
          gainLossAmount.abs(),
          0.0,
          now,
        );
        await updateAccountBalanceWithJournal(
          txn,
          accountId,
          0.0,
          gainLossAmount.abs(),
          now,
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
    // C-04: Reject invalid dates instead of allowing the operation
    if (date == null) {
      throw Exception(
          'تاريخ غير صالح: "$dateStr". لا يمكن إجراء عمليات بتاريخ غير معروف.');
    }
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
  /// Fix #5: Separate gain and loss into two accounts with correct types:
  /// - Exchange Gains: REVENUE / balance_type: 'credit'
  /// - Exchange Losses: EXPENSE / balance_type: 'debit'
  /// Both share code prefix 53xx to be findable together.
  ///
  /// Returns the account id of the GAINS account (for credits) or the
  /// LOSSES account (for debits), depending on [isGain].
  ///
  /// A-02 verification (2026-06-19):
  /// Exchange gain/loss accounts are ALWAYS in the base currency (YER).
  /// This is correct per IAS 21 — exchange differences arise from
  /// converting a foreign-currency amount to the functional (base)
  /// currency, so they are recognized IN the base currency, not in the
  /// foreign currency. The account_code is fixed (4700 for gains,
  /// 5300 for losses) WITHOUT the per-currency offset, because there
  /// is only one base currency and one gain/loss account per base
  /// currency. Callers (recordExchangeGainLoss,
  /// VoucherAutoMappingService._handleExchangeDifference) correctly
  /// stamp transactions with currency_code='YER', exchange_rate=1.0,
  /// and amount_base = the gain/loss amount (already in YER).
  Future<int> getOrCreateExchangeAccount({bool isGain = true}) async {
    final db = await _db;
    final code = isGain ? '4700' : '5300';
    final existing = await db.query(
      'accounts',
      where: 'account_code = ? AND is_system = 1',
      whereArgs: [code],
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.first['id'] as int;

    // Create new account
    final now = DateTime.now().toIso8601String();
    if (isGain) {
      // Exchange Gains → REVENUE / credit nature (code 4700 under Revenue root 4000)
      // Find parent REVENUE root account
      final parentRows = await db.query('accounts',
          where: 'account_code = ? AND account_type = ?',
          whereArgs: ['4000', 'REVENUE'],
          limit: 1);
      final parentId =
          parentRows.isNotEmpty ? parentRows.first['id'] as int : null;
      final id = await db.insert('accounts', {
        'name_ar': 'مكاسب فروقات الصرف',
        'name_en': 'Exchange Rate Gains',
        'account_code': '4700',
        'account_type': 'REVENUE',
        'balance': 0,
        'currency': 'YER',
        'balance_type': 'credit',
        'parent_id': parentId,
        'is_active': 1,
        'is_system': 1,
        'created_at': now,
        'updated_at': now,
      });
      return id;
    } else {
      // Exchange Losses → EXPENSE / debit nature (code 5300 under Expenses root 5000)
      final parentRows = await db.query('accounts',
          where: 'account_code = ? AND account_type = ?',
          whereArgs: ['5000', 'EXPENSE'],
          limit: 1);
      final parentId =
          parentRows.isNotEmpty ? parentRows.first['id'] as int : null;
      final id = await db.insert('accounts', {
        'name_ar': 'خسائر فروقات الصرف',
        'name_en': 'Exchange Rate Losses',
        'account_code': '5300',
        'account_type': 'EXPENSE',
        'balance': 0,
        'currency': 'YER',
        'balance_type': 'debit',
        'parent_id': parentId,
        'is_active': 1,
        'is_system': 1,
        'created_at': now,
        'updated_at': now,
      });
      return id;
    }
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
    final offset = await locator<BaseCurrencyService>().getOffsetForCurrency(currency);
    final actualCode = (int.parse(baseCode) + offset).toString();
    final result = await txn.query(
      'accounts',
      where: 'account_code = ? AND currency = ?',
      whereArgs: [actualCode, currency],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }
}
