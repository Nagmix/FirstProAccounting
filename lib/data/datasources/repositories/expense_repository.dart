import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/core/utils/journal_id_helper.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/services/base_currency_service.dart';

class ExpenseRepository {
  final DatabaseHelper _dbHelper;
  ExpenseRepository(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  // ══════════════════════════════════════════════════════════════
  //  Expense CRUD methods
  // ══════════════════════════════════════════════════════════════

  static const Map<String, String> _expenseOrderByWhitelist = {
    'expense_date DESC': 'expense_date DESC',
    'expense_date ASC': 'expense_date ASC',
    'created_at DESC': 'created_at DESC',
    'created_at ASC': 'created_at ASC',
    'amount DESC': 'amount DESC',
    'amount ASC': 'amount ASC',
  };

  String _safeExpenseOrderBy(String orderBy) =>
      _expenseOrderByWhitelist[orderBy] ??
      _expenseOrderByWhitelist['expense_date DESC']!;

  /// Backward-compatible safe entry point.
  ///
  /// Direct data-only expense inserts are forbidden because they bypass journal
  /// entries, account balances, cash-box balances, and audit traceability.
  Future<int> insertExpense(Map<String, dynamic> expenseMap) async {
    return saveExpenseWithJournalEntry(expenseMap);
  }

  Future<List<Map<String, dynamic>>> getAllExpenses(
      {String orderBy = 'expense_date DESC'}) async {
    final db = await _db;
    return await db.query('expenses', orderBy: _safeExpenseOrderBy(orderBy));
  }

  Future<List<Map<String, dynamic>>> getExpensesByCategory(
      String category) async {
    final db = await _db;
    return await db.query('expenses',
        where: 'category = ?',
        whereArgs: [category],
        orderBy: 'expense_date DESC');
  }

  Future<List<Map<String, dynamic>>> getExpensesByDateRange(
      String startDate, String endDate) async {
    final db = await _db;
    return await db.query('expenses',
        where: 'expense_date >= ? AND expense_date <= ?',
        whereArgs: [startDate, endDate],
        orderBy: 'expense_date DESC');
  }

  Future<Map<String, dynamic>?> getExpenseById(int id) async {
    final db = await _db;
    final results =
        await db.query('expenses', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateExpense(int id, Map<String, dynamic> expenseMap) async {
    final existing = await getExpenseById(id);
    if (existing == null) return 0;
    final expenseAccountId = (expenseMap['expense_account_id'] as int?) ??
        (expenseMap['account_id'] as int?);
    await updateExpenseWithJournalEntry(
      id,
      existing,
      expenseMap,
      expenseAccountId,
    );
    return 1;
  }

  Future<int> deleteExpense(int id) async {
    throw UnsupportedError(
      'Direct expense deletion is unsafe because it bypasses journal reversal. '
      'Implement/use a journal-aware cancellation or reversal workflow instead.',
    );
  }

  Future<double> getTotalExpensesThisMonth() async {
    final db = await _db;
    final now = DateTime.now();
    final monthStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final result = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM(amount_base), 0) AS INTEGER) AS total FROM expenses WHERE date(expense_date) >= ?",
        [monthStart]);
    return MoneyHelper.readCalculatedMoney(result.first['total']);
  }

  Future<double> getTotalExpensesByCategory(String category) async {
    final db = await _db;
    final result = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM(amount_base), 0) AS INTEGER) AS total FROM expenses WHERE category = ?",
        [category]);
    return MoneyHelper.readCalculatedMoney(result.first['total']);
  }

  Future<double> getTotalExpensesForDate(DateTime date) async {
    final db = await _db;
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM(amount_base), 0) AS INTEGER) AS total FROM expenses WHERE date(expense_date) = ?",
        [dateStr]);
    return MoneyHelper.readCalculatedMoney(result.first['total']);
  }

  /// Get total expenses for a specific date range and currency.
  /// Used by DashboardViewModel instead of raw SQL.
  Future<double> getTotalExpensesForDateRange(
      String currency, String startStr, String endStr) async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT CAST(COALESCE(SUM(amount_base), 0) AS INTEGER) AS total FROM expenses "
      "WHERE currency = ? AND expense_date >= ? AND expense_date < ? "
      "AND operation_type = 'صرف'",
      [currency, startStr, endStr],
    );
    return MoneyHelper.readCalculatedMoney(result.first['total']);
  }

  /// Save expense with journal entry.
  /// Supports operation_type: 'صرف' (disburse - debit expense, credit cash) or 'قبض' (receive - debit cash, credit expense).
  ///
  /// Multi-currency handling (aligned with invoice_repository pattern):
  /// - Journal entries are posted in the expense's native currency against
  ///   that currency's chart of accounts.
  /// - `amount_base` stores the converted base-currency value for consolidated
  ///   reporting.
  /// - Cash box balance is always updated in the expense's native currency (`amount`).
  Future<int> saveExpenseWithJournalEntry(
      Map<String, dynamic> expenseMap) async {
    // Check if fiscal period is closed before creating expense
    final expenseDate = expenseMap['expense_date'] as String? ??
        DateTime.now().toIso8601String();
    await _dbHelper.journal.checkFiscalPeriodOpen(expenseDate);

    final db = await _db;
    // B-06: Auto-calculate amount_base if exchange_rate is provided and amount_base seems wrong
    final amount = MoneyHelper.readMoney(expenseMap['amount']);
    final exchangeRate =
        (expenseMap['exchange_rate'] as num?)?.toDouble() ?? 1.0;
    final expectedBase = amount * exchangeRate;
    final amountBase = MoneyHelper.readMoney(expenseMap['amount_base']) > 0
        ? MoneyHelper.readMoney(expenseMap['amount_base'])
        : expectedBase;
    if (MoneyHelper.readMoney(expenseMap['amount_base']) <= 0 &&
        expectedBase > 0) {
      expenseMap['amount_base'] = MoneyHelper.toCents(expectedBase);
    }
    final expenseCurrency = (expenseMap['currency'] as String?) ?? 'YER';
    final operationType = (expenseMap['operation_type'] as String?) ?? 'صرف';
    final now = DateTime.now().toIso8601String();
    final transactionDate = expenseDate;

    // ── Multi-currency policy (Option A) ─────────────────────────
    // Expenses are posted in their native currency against the chart of
    // accounts for that currency, while amount_base preserves the converted
    // value for consolidated reports. This matches invoice posting behavior.
    final int codeOffset =
        await locator<BaseCurrencyService>().getOffsetForCurrency(expenseCurrency);
    final double journalAmount = amount;
    int expenseId = 0;

    await db.transaction((txn) async {
      // Insert expense (convert money fields to cents)
      final dbExpenseMap = MoneyHelper.toCentsMap(
          expenseMap, [...MoneyHelper.expenseMoneyFields, 'amount_base']);
      expenseId = await txn.insert('expenses', dbExpenseMap);
      final referenceId = expenseId.toString();

      // Post journal entry
      final journalId = generateUniqueJournalId();

      // Get expense account in the expense's native currency.
      int? expenseAccId = (expenseMap['expense_account_id'] as int?) ??
          (expenseMap['account_id'] as int?);
      if (expenseAccId == null) {
        final expenseAccount = await txn.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [(5000 + codeOffset).toString(), expenseCurrency],
            limit: 1);
        expenseAccId =
            expenseAccount.isNotEmpty ? expenseAccount.first['id'] as int : null;
      }

      // ── C-06: منع إنشاء قيد غير متوازن إذا لم يوجد حساب المصروفات ──
      if (expenseAccId == null) {
        throw Exception(
            'لا يوجد حساب مصروفات للعملة $expenseCurrency. يرجى إنشاء حساب مصروفات أولاً.');
      }

      // Get cash/bank account in the expense's native currency. Prefer a linked
      // cash-box account only if it belongs to the same currency.
      int? cashAccountId;
      final cashBoxId = expenseMap['cash_box_id'] as int?;
      if (cashBoxId != null) {
        final cashBox = await txn.query('cash_boxes',
            where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
        if (cashBox.isNotEmpty) {
          final linkedAccountId = cashBox.first['linked_account_id'] as int?;
          if (linkedAccountId != null) {
            final linkedAccount = await txn.query('accounts',
                columns: ['id', 'currency'],
                where: 'id = ?',
                whereArgs: [linkedAccountId],
                limit: 1);
            if (linkedAccount.isNotEmpty &&
                linkedAccount.first['currency'] == expenseCurrency) {
              cashAccountId = linkedAccountId;
            }
          }
        }
      }
      if (cashAccountId == null) {
        final cashBanksAccount = await txn.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [(1100 + codeOffset).toString(), expenseCurrency],
            limit: 1);
        cashAccountId = cashBanksAccount.isNotEmpty
            ? cashBanksAccount.first['id'] as int
            : null;
      }

      // Prevent unbalanced entry if cash account not found
      if (cashAccountId == null) {
        throw Exception(
            'لا يوجد حساب نقدية/بنك للعملة $expenseCurrency. يرجى إنشاء حساب صناديق وبنوك أولاً.');
      }

      final title = expenseMap['title'] as String? ?? 'مصروف';
      final isSarf = operationType == 'صرف';

      if (isSarf) {
        // صرف (disburse): Debit expense account, Credit cash/bank
        if (journalAmount > 0) {
          await txn.insert('transactions', {
            'account_id': expenseAccId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(journalAmount),
            'credit': 0,
            'description': 'مصروف: $title',
            'date': transactionDate,
            'created_at': now,
            'currency_code': expenseCurrency,
            'exchange_rate': exchangeRate,
            'amount_base': MoneyHelper.toCents(amountBase),
            'reference_type': 'expense',
            'reference_id': referenceId,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, expenseAccId, journalAmount, 0.0, now);
        }
        if (journalAmount > 0) {
          await txn.insert('transactions', {
            'account_id': cashAccountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(journalAmount),
            'description': 'مصروف: $title',
            'date': transactionDate,
            'created_at': now,
            'currency_code': expenseCurrency,
            'exchange_rate': exchangeRate,
            'amount_base': MoneyHelper.toCents(amountBase),
            'reference_type': 'expense',
            'reference_id': referenceId,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, cashAccountId, 0.0, journalAmount, now);
        }
      } else {
        // ── A-05: قبض (استرداد مصروف) — خصم من حساب المصروفات الأصلي ──
        // القيد الصحيح: مدين النقدية / دائن حساب المصروفات (تخفيض المصروف)
        // هذا يقلل المصروفات الفعلية بدلاً من إنشاء إيراد وهمي
        if (journalAmount > 0) {
          await txn.insert('transactions', {
            'account_id': cashAccountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(journalAmount),
            'credit': 0,
            'description': 'استرداد مصروف: $title',
            'date': transactionDate,
            'created_at': now,
            'currency_code': expenseCurrency,
            'exchange_rate': exchangeRate,
            'amount_base': MoneyHelper.toCents(amountBase),
            'reference_type': 'expense',
            'reference_id': referenceId,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, cashAccountId, journalAmount, 0.0, now);
        }
        // Credit the expense account to reduce the expense (reverse of disbursement)
        if (journalAmount > 0) {
          await txn.insert('transactions', {
            'account_id': expenseAccId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(journalAmount),
            'description': 'استرداد مصروف: $title',
            'date': transactionDate,
            'created_at': now,
            'currency_code': expenseCurrency,
            'exchange_rate': exchangeRate,
            'amount_base': MoneyHelper.toCents(amountBase),
            'reference_type': 'expense',
            'reference_id': referenceId,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, expenseAccId, 0.0, journalAmount, now);
        }
      }

      await _dbHelper.journal.validateJournalBalanceInTransaction(
        txn,
        journalId,
      );

      // Update cash box balance (respecting balance_type)
      // FIX: Cash box balance is always updated in the expense's native currency (`amount`),
      // NOT in base currency (`amountBase`). Each cash box tracks its own currency.
      if (cashBoxId != null && amount > 0) {
        final cashBoxRow = await txn.query('cash_boxes',
            where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
        final cashBalanceType = cashBoxRow.isNotEmpty
            ? (cashBoxRow.first['balance_type'] as String? ?? 'credit')
            : 'credit';
        final cashBoxAmountCents =
            MoneyHelper.toCents(amount); // native currency
        if (isSarf) {
          // صرف: النقدية تخرج من الصندوق
          if (cashBalanceType == 'credit') {
            await txn.rawUpdate(
                'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
                [cashBoxAmountCents, now, cashBoxId]);
          } else {
            await txn.rawUpdate(
                'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
                [cashBoxAmountCents, now, cashBoxId]);
          }
        } else {
          // قبض: النقدية تدخل الصندوق
          if (cashBalanceType == 'credit') {
            await txn.rawUpdate(
                'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
                [cashBoxAmountCents, now, cashBoxId]);
          } else {
            await txn.rawUpdate(
                'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
                [cashBoxAmountCents, now, cashBoxId]);
          }
        }
      }
    });
    return expenseId;
  }

  /// Update an existing expense with journal entry reversal and new entries.
  /// Reverses old journal entries, updates the record, and creates new entries.
  /// [existingExpense] is the current expense data (used for reversing old entries).
  /// [newExpenseMap] is the updated expense data.
  /// [newExpenseAccountId] is the expense account ID for the new entry.
  ///
  /// Multi-currency: follows the same pattern as saveExpenseWithJournalEntry —
  /// foreign-currency expenses post journal entries in their native currency
  /// and keep the converted amount in `amount_base` for consolidated reports.
  Future<void> updateExpenseWithJournalEntry(
    int expenseId,
    Map<String, dynamic> existingExpense,
    Map<String, dynamic> newExpenseMap,
    int? newExpenseAccountId,
  ) async {
    // Check if fiscal periods are open before updating. The old period is
    // affected by reversal entries, and the new period receives the new entry.
    final expenseDate = newExpenseMap['expense_date'] as String? ??
        DateTime.now().toIso8601String();
    await _dbHelper.journal.checkFiscalPeriodOpen(expenseDate);
    final oldExpenseDateForGuard = existingExpense['expense_date'] as String?;
    if (oldExpenseDateForGuard != null) {
      await _dbHelper.journal.checkFiscalPeriodOpen(oldExpenseDateForGuard);
    }

    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final newTransactionDate = expenseDate;
    final newAmountBase = MoneyHelper.readMoney(newExpenseMap['amount_base']);
    final newAmount = MoneyHelper.readMoney(newExpenseMap['amount']);

    await db.transaction((txn) async {
      // ── 1. Reverse old journal entries ──
      final oldAmountBase =
          MoneyHelper.readMoney(existingExpense['amount_base']);
      final oldAmount = MoneyHelper.readMoney(existingExpense['amount']);
      final oldOperationType =
          existingExpense['operation_type'] as String? ?? 'صرف';
      final oldCurrency = existingExpense['currency'] as String? ?? 'YER';
      final oldExchangeRate =
          (existingExpense['exchange_rate'] as num?)?.toDouble() ?? 1.0;
      final oldCodeOffset = await locator<BaseCurrencyService>()
          .getOffsetForCurrency(oldCurrency);
      final oldExpenseAccountId =
          (existingExpense['expense_account_id'] as int?) ??
              (existingExpense['account_id'] as int?);
      final oldCashBoxId = existingExpense['cash_box_id'] as int?;
      final oldTitle = existingExpense['title'] as String? ?? 'مصروف';
      final oldIsSarf = oldOperationType == 'صرف';
      final oldTransactionDate =
          existingExpense['expense_date'] as String? ?? now;
      final oldReferenceId = expenseId.toString();

      // Prefer exact reversal for entries created after reference tracking was
      // added. This avoids guessing whether a legacy foreign-currency expense
      // was posted in native or base currency.
      final linkedOldTransactions = await txn.query(
        'transactions',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['expense', oldReferenceId],
      );
      final didReverseLinkedTransactions = linkedOldTransactions.isNotEmpty;
      if (didReverseLinkedTransactions) {
        final reverseJournalId = generateUniqueJournalId();
        for (final oldTxn in linkedOldTransactions) {
          final accountId = (oldTxn['account_id'] as num?)?.toInt();
          if (accountId == null) continue;
          final debit = MoneyHelper.readMoney(oldTxn['debit']);
          final credit = MoneyHelper.readMoney(oldTxn['credit']);
          final txnAmountBase = (oldTxn['amount_base'] as num?)?.toInt() ??
              MoneyHelper.toCents(
                  (debit > 0 ? debit : credit) * oldExchangeRate);
          await txn.insert('transactions', {
            'account_id': accountId,
            'journal_id': reverseJournalId,
            'debit': MoneyHelper.toCents(credit),
            'credit': MoneyHelper.toCents(debit),
            'description': 'تعديل/عكس مصروف: $oldTitle',
            'date': oldTxn['date'] as String? ?? oldTransactionDate,
            'created_at': now,
            'currency_code': oldTxn['currency_code'] as String? ?? oldCurrency,
            'exchange_rate':
                (oldTxn['exchange_rate'] as num?)?.toDouble() ?? oldExchangeRate,
            'amount_base': txnAmountBase,
            'reference_type': 'expense_reversal',
            'reference_id': oldReferenceId,
          });
          await txn.update(
            'transactions',
            {'reference_type': 'expense_reversed'},
            where: 'id = ?',
            whereArgs: [oldTxn['id']],
          );
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, accountId, credit, debit, now);
        }
      }

      if (didReverseLinkedTransactions &&
          oldCashBoxId != null &&
          oldAmount > 0) {
        final oldCashBoxRow = await txn.query('cash_boxes',
            where: 'id = ?', whereArgs: [oldCashBoxId], limit: 1);
        final oldCashBalanceType = oldCashBoxRow.isNotEmpty
            ? (oldCashBoxRow.first['balance_type'] as String? ?? 'credit')
            : 'credit';
        final oldCashBoxAmountCents = MoneyHelper.toCents(oldAmount);
        if (oldIsSarf) {
          // Original was صرف (cash out): reverse = cash in
          if (oldCashBalanceType == 'credit') {
            await txn.rawUpdate(
                'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
                [oldCashBoxAmountCents, now, oldCashBoxId]);
          } else {
            await txn.rawUpdate(
                'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
                [oldCashBoxAmountCents, now, oldCashBoxId]);
          }
        } else {
          // Original was قبض (cash in): reverse = cash out
          if (oldCashBalanceType == 'credit') {
            await txn.rawUpdate(
                'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
                [oldCashBoxAmountCents, now, oldCashBoxId]);
          } else {
            await txn.rawUpdate(
                'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
                [oldCashBoxAmountCents, now, oldCashBoxId]);
          }
        }
      }

      if (!didReverseLinkedTransactions &&
          oldAmountBase > 0 &&
          oldExpenseAccountId != null) {
        // Get old cash/bank account — use the same lookup as the original entry
        // so the reversal hits the same accounts.
        int? oldCashBankAccountId;
        if (oldCashBoxId != null) {
          final cashBox = await txn.query('cash_boxes',
              where: 'id = ?', whereArgs: [oldCashBoxId], limit: 1);
          if (cashBox.isNotEmpty) {
            final linkedAccountId = cashBox.first['linked_account_id'] as int?;
            if (linkedAccountId != null) {
              oldCashBankAccountId = linkedAccountId;
            }
          }
        }
        if (oldCashBankAccountId == null) {
          final cashBanksAccount = await txn.query('accounts',
              where: 'account_code = ? AND currency = ?',
              whereArgs: [(1100 + oldCodeOffset).toString(), oldCurrency],
              limit: 1);
          oldCashBankAccountId = cashBanksAccount.isNotEmpty
              ? cashBanksAccount.first['id'] as int
              : null;
        }

        final reverseJournalId = generateUniqueJournalId();

        // Reverse: swap debit ↔ credit of the original entry
        if (oldIsSarf) {
          // Original was: Debit expense, Credit cash → Reverse: Credit expense, Debit cash
          await txn.insert('transactions', {
            'account_id': oldExpenseAccountId,
            'journal_id': reverseJournalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(oldAmountBase),
            'description': 'تعديل/عكس مصروف: $oldTitle',
            'date': oldTransactionDate,
            'created_at': now,
            'currency_code': oldCurrency,
            'exchange_rate': oldExchangeRate,
            'amount_base': MoneyHelper.toCents(oldAmountBase),
                    'reference_type': 'expense_legacy_reversal',
          'reference_id': reverseJournalId.toString(),
});
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, oldExpenseAccountId, 0.0, oldAmountBase, now);

          if (oldCashBankAccountId != null) {
            await txn.insert('transactions', {
              'account_id': oldCashBankAccountId,
              'journal_id': reverseJournalId,
              'debit': MoneyHelper.toCents(oldAmountBase),
              'credit': 0,
              'description': 'تعديل/عكس مصروف: $oldTitle',
              'date': oldTransactionDate,
              'created_at': now,
              'currency_code': oldCurrency,
              'exchange_rate': oldExchangeRate,
              'amount_base': MoneyHelper.toCents(oldAmountBase),
                      'reference_type': 'expense_legacy_reversal',
          'reference_id': reverseJournalId.toString(),
});
            await _dbHelper.journal.updateAccountBalanceWithJournal(
                txn, oldCashBankAccountId, oldAmountBase, 0.0, now);
          }
        } else {
          // Original was: Debit cash, Credit expense → Reverse: Credit cash, Debit expense
          if (oldCashBankAccountId != null) {
            await txn.insert('transactions', {
              'account_id': oldCashBankAccountId,
              'journal_id': reverseJournalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(oldAmountBase),
              'description': 'تعديل/عكس قبض: $oldTitle',
              'date': oldTransactionDate,
              'created_at': now,
              'currency_code': oldCurrency,
              'exchange_rate': oldExchangeRate,
              'amount_base': MoneyHelper.toCents(oldAmountBase),
                      'reference_type': 'expense_legacy_reversal',
          'reference_id': reverseJournalId.toString(),
});
            await _dbHelper.journal.updateAccountBalanceWithJournal(
                txn, oldCashBankAccountId, 0.0, oldAmountBase, now);
          }
          await txn.insert('transactions', {
            'account_id': oldExpenseAccountId,
            'journal_id': reverseJournalId,
            'debit': MoneyHelper.toCents(oldAmountBase),
            'credit': 0,
            'description': 'تعديل/عكس قبض: $oldTitle',
            'date': oldTransactionDate,
            'created_at': now,
            'currency_code': oldCurrency,
            'exchange_rate': oldExchangeRate,
            'amount_base': MoneyHelper.toCents(oldAmountBase),
                    'reference_type': 'expense_legacy_reversal',
          'reference_id': reverseJournalId.toString(),
});
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, oldExpenseAccountId, oldAmountBase, 0.0, now);
        }

        // Reverse old cash box balance change (respecting balance_type)
        // FIX: Reverse using the same amount the original used.
        // Old entries may have used oldAmountBase; reverse with oldAmountBase to
        // exactly undo the original.  For entries created after the fix, oldAmount
        // == oldAmountBase when currency is YER, so this is safe either way.
        if (oldCashBoxId != null && oldAmountBase > 0) {
          final oldCashBoxRow = await txn.query('cash_boxes',
              where: 'id = ?', whereArgs: [oldCashBoxId], limit: 1);
          final oldCashBalanceType = oldCashBoxRow.isNotEmpty
              ? (oldCashBoxRow.first['balance_type'] as String? ?? 'credit')
              : 'credit';
          // Use oldAmount (native currency) for cash box reversal to match the
          // original cash box update which should have been in native currency.
          final oldCashBoxAmountCents =
              MoneyHelper.toCents(oldAmount > 0 ? oldAmount : oldAmountBase);
          if (oldIsSarf) {
            // Original was صرف (cash out): reverse = cash in
            if (oldCashBalanceType == 'credit') {
              await txn.rawUpdate(
                  'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
                  [oldCashBoxAmountCents, now, oldCashBoxId]);
            } else {
              await txn.rawUpdate(
                  'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
                  [oldCashBoxAmountCents, now, oldCashBoxId]);
            }
          } else {
            // Original was قبض (cash in): reverse = cash out
            if (oldCashBalanceType == 'credit') {
              await txn.rawUpdate(
                  'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
                  [oldCashBoxAmountCents, now, oldCashBoxId]);
            } else {
              await txn.rawUpdate(
                  'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
                  [oldCashBoxAmountCents, now, oldCashBoxId]);
            }
          }
        }
      }

      // ── 2. Update expense record ──
      await txn.update(
          'expenses',
          MoneyHelper.toCentsMap(newExpenseMap,
              [...MoneyHelper.expenseMoneyFields, 'amount_base']),
          where: 'id = ?',
          whereArgs: [expenseId]);

      // ── 3. Create new journal entries ──
      // Apply the same native-currency posting policy as saveExpenseWithJournalEntry.
      final newCurrency = (newExpenseMap['currency'] as String?) ?? 'YER';
      final newExchangeRate =
          (newExpenseMap['exchange_rate'] as num?)?.toDouble() ?? 1.0;
      final int codeOffset =
          await locator<BaseCurrencyService>().getOffsetForCurrency(newCurrency);
      final double journalAmount = newAmount;
      final double newBaseAmount = newAmountBase > 0
          ? newAmountBase
          : newAmount * newExchangeRate;
      final newReferenceId = expenseId.toString();

      if (journalAmount > 0) {
        final journalId = generateUniqueJournalId();
        final title = newExpenseMap['title'] as String? ?? 'مصروف';
        final isSarf = newExpenseMap['operation_type'] == 'صرف';

        // Resolve expense account for the new native-currency entry.
        int? effectiveExpenseAccountId = newExpenseAccountId ??
            (newExpenseMap['expense_account_id'] as int?) ??
            (newExpenseMap['account_id'] as int?);
        if (effectiveExpenseAccountId == null) {
          final expenseAccount = await txn.query('accounts',
              where: 'account_code = ? AND currency = ?',
              whereArgs: [(5000 + codeOffset).toString(), newCurrency],
              limit: 1);
          effectiveExpenseAccountId = expenseAccount.isNotEmpty
              ? expenseAccount.first['id'] as int
              : null;
        }
        if (effectiveExpenseAccountId == null) {
          throw Exception(
              'لا يوجد حساب مصروفات للعملة $newCurrency. يرجى إنشاء حساب مصروفات أولاً.');
        }

        // Get cash/bank account for the new native-currency entry.
        int? cashBankAccountId;
        final cashBoxId = newExpenseMap['cash_box_id'] as int?;
        if (cashBoxId != null) {
          final cashBox = await txn.query('cash_boxes',
              where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
          if (cashBox.isNotEmpty) {
            final linkedAccountId = cashBox.first['linked_account_id'] as int?;
            if (linkedAccountId != null) {
              final linkedAccount = await txn.query('accounts',
                  columns: ['id', 'currency'],
                  where: 'id = ?',
                  whereArgs: [linkedAccountId],
                  limit: 1);
              if (linkedAccount.isNotEmpty &&
                  linkedAccount.first['currency'] == newCurrency) {
                cashBankAccountId = linkedAccountId;
              }
            }
          }
        }
        if (cashBankAccountId == null) {
          final cashBanksAccount = await txn.query('accounts',
              where: 'account_code = ? AND currency = ?',
              whereArgs: [(1100 + codeOffset).toString(), newCurrency],
              limit: 1);
          cashBankAccountId = cashBanksAccount.isNotEmpty
              ? cashBanksAccount.first['id'] as int
              : null;
        }
        if (cashBankAccountId == null) {
          throw Exception(
              'لا يوجد حساب نقدية/بنك للعملة $newCurrency. يرجى إنشاء حساب صناديق وبنوك أولاً.');
        }

        if (isSarf) {
          // صرف (disburse): Debit expense account, Credit cash/bank
          await txn.insert('transactions', {
            'account_id': effectiveExpenseAccountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(journalAmount),
            'credit': 0,
            'description': 'مصروف: $title',
            'date': newTransactionDate,
            'created_at': now,
            'currency_code': newCurrency,
            'exchange_rate': newExchangeRate,
            'amount_base': MoneyHelper.toCents(newBaseAmount),
            'reference_type': 'expense',
            'reference_id': newReferenceId,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, effectiveExpenseAccountId, journalAmount, 0.0, now);

          if (cashBankAccountId != null) {
            await txn.insert('transactions', {
              'account_id': cashBankAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(journalAmount),
              'description': 'مصروف: $title',
              'date': newTransactionDate,
              'created_at': now,
              'currency_code': newCurrency,
              'exchange_rate': newExchangeRate,
              'amount_base': MoneyHelper.toCents(newBaseAmount),
              'reference_type': 'expense',
              'reference_id': newReferenceId,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(
                txn, cashBankAccountId, 0.0, journalAmount, now);
          }
        } else {
          // قبض (receive): Debit cash/bank, Credit expense account
          if (cashBankAccountId != null) {
            await txn.insert('transactions', {
              'account_id': cashBankAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(journalAmount),
              'credit': 0,
              'description': 'قبض: $title',
              'date': newTransactionDate,
              'created_at': now,
              'currency_code': newCurrency,
              'exchange_rate': newExchangeRate,
              'amount_base': MoneyHelper.toCents(newBaseAmount),
              'reference_type': 'expense',
              'reference_id': newReferenceId,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(
                txn, cashBankAccountId, journalAmount, 0.0, now);
          }
          await txn.insert('transactions', {
            'account_id': effectiveExpenseAccountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(journalAmount),
            'description': 'قبض: $title',
            'date': newTransactionDate,
            'created_at': now,
            'currency_code': newCurrency,
            'exchange_rate': newExchangeRate,
            'amount_base': MoneyHelper.toCents(newBaseAmount),
            'reference_type': 'expense',
            'reference_id': newReferenceId,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, effectiveExpenseAccountId, 0.0, journalAmount, now);
        }

        // Update cash box balance for the new entry (respecting balance_type)
        // FIX: Cash box balance is always updated in the expense's native currency (`amount`),
        // NOT in base currency (`amountBase`). Each cash box tracks its own currency.
        if (cashBoxId != null && newAmount > 0) {
          final cashBoxRow = await txn.query('cash_boxes',
              where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
          final cashBalanceType = cashBoxRow.isNotEmpty
              ? (cashBoxRow.first['balance_type'] as String? ?? 'credit')
              : 'credit';
          final cashBoxAmountCents =
              MoneyHelper.toCents(newAmount); // native currency
          if (isSarf) {
            // صرف: النقدية تخرج
            if (cashBalanceType == 'credit') {
              await txn.rawUpdate(
                  'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
                  [cashBoxAmountCents, now, cashBoxId]);
            } else {
              await txn.rawUpdate(
                  'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
                  [cashBoxAmountCents, now, cashBoxId]);
            }
          } else {
            // قبض: النقدية تدخل
            if (cashBalanceType == 'credit') {
              await txn.rawUpdate(
                  'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
                  [cashBoxAmountCents, now, cashBoxId]);
            } else {
              await txn.rawUpdate(
                  'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
                  [cashBoxAmountCents, now, cashBoxId]);
            }
          }
        }
      }
    });
  }

  /// Get all expenses for a specific expense account
  Future<List<Map<String, dynamic>>> getExpensesByAccountId(int accountId,
      {String orderBy = 'expense_date DESC'}) async {
    final db = await _db;
    return await db.query('expenses',
        where: 'expense_account_id = ?',
        whereArgs: [accountId],
        orderBy: _safeExpenseOrderBy(orderBy));
  }

  /// Get all expenses for a specific expense sub-account
  Future<List<Map<String, dynamic>>> getExpensesBySubAccountId(int subAccountId,
      {String orderBy = 'expense_date DESC'}) async {
    final db = await _db;
    return await db.query('expenses',
        where: 'expense_sub_account_id = ?',
        whereArgs: [subAccountId],
        orderBy: _safeExpenseOrderBy(orderBy));
  }
}
