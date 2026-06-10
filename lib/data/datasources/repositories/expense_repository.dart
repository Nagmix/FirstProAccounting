import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/utils/journal_id_helper.dart';
import '../../../core/utils/money_helper.dart';
import '../database_helper.dart';

class ExpenseRepository {
  final DatabaseHelper _dbHelper;
  ExpenseRepository(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  // ══════════════════════════════════════════════════════════════
  //  Expense CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertExpense(Map<String, dynamic> expenseMap) async {
    // H-12: تحقق من الفترة المالية قبل إدراج مصروف
    final expenseDate = expenseMap['expense_date'] as String? ??
        DateTime.now().toIso8601String();
    await _dbHelper.journal.checkFiscalPeriodOpen(expenseDate);
    final db = await _db;
    final dbMap = MoneyHelper.toCentsMap(
        expenseMap, [...MoneyHelper.expenseMoneyFields, 'amount_base']);
    return await db.insert('expenses', dbMap);
  }

  Future<List<Map<String, dynamic>>> getAllExpenses(
      {String orderBy = 'expense_date DESC'}) async {
    final db = await _db;
    return await db.query('expenses', orderBy: orderBy);
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
    // ── M-10: تحقق من الفترة المالية قبل التحديث ──
    final existing = await getExpenseById(id);
    if (existing != null) {
      final expenseDate = existing['expense_date'] as String? ??
          DateTime.now().toIso8601String();
      await _dbHelper.journal.checkFiscalPeriodOpen(expenseDate);
    }
    final db = await _db;
    final dbMap = MoneyHelper.toCentsMap(
        expenseMap, [...MoneyHelper.expenseMoneyFields, 'amount_base']);
    return await db.update('expenses', dbMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteExpense(int id) async {
    // ── M-10: تحقق من الفترة المالية قبل الحذف ──
    final existing = await getExpenseById(id);
    if (existing != null) {
      final expenseDate = existing['expense_date'] as String? ??
          DateTime.now().toIso8601String();
      await _dbHelper.journal.checkFiscalPeriodOpen(expenseDate);
    }
    final db = await _db;
    return await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
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
  /// - When expense is in a foreign currency, journal entries are posted to YER (base)
  ///   accounts using amountBase, so the general ledger stays in the functional currency.
  /// - Cash box balance is always updated in the expense's native currency (`amount`),
  ///   because each cash box tracks its own currency.
  Future<void> saveExpenseWithJournalEntry(
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

    // ── Multi-currency: Journal entries use base currency (YER) accounts ──
    // When the expense is in a foreign currency, convert amounts to YER
    // using the expense's exchange rate, and use YER accounts.
    // This matches the pattern in invoice_repository.
    final bool needsYerConversion =
        expenseCurrency != 'YER' && exchangeRate > 0;
    final int codeOffset = needsYerConversion
        ? 0
        : (expenseCurrency == 'SAR' ? 1 : (expenseCurrency == 'USD' ? 2 : 0));
    final String journalCurrency = needsYerConversion ? 'YER' : expenseCurrency;
    // Journal amount: amountBase (YER) when converting, amount (native) otherwise
    final double journalAmount = needsYerConversion ? amountBase : amount;

    await db.transaction((txn) async {
      // Insert expense (convert money fields to cents)
      final dbExpenseMap = MoneyHelper.toCentsMap(
          expenseMap, [...MoneyHelper.expenseMoneyFields, 'amount_base']);
      await txn.insert('expenses', dbExpenseMap);

      // Post journal entry
      final journalId = generateUniqueJournalId();

      // Get expense account — when converting to YER, use YER expense account (5000)
      int? expenseAccId;
      if (needsYerConversion) {
        // Foreign currency expense: journal entries go to YER account
        final expenseAccount = await txn.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: ['5000', 'YER'],
            limit: 1);
        expenseAccId = expenseAccount.isNotEmpty
            ? expenseAccount.first['id'] as int
            : null;
      } else {
        // YER expense: use provided account_id or look up currency-specific account
        final expenseAccountId = expenseMap['account_id'] as int?;
        expenseAccId = expenseAccountId;
        if (expenseAccId == null) {
          final expenseAccount = await txn.query('accounts',
              where: 'account_code = ? AND currency = ?',
              whereArgs: [(5000 + codeOffset).toString(), expenseCurrency],
              limit: 1);
          expenseAccId = expenseAccount.isNotEmpty
              ? expenseAccount.first['id'] as int
              : null;
        }
      }

      // ── C-06: منع إنشاء قيد غير متوازن إذا لم يوجد حساب المصروفات ──
      if (expenseAccId == null) {
        throw Exception(
            'لا يوجد حساب مصروفات للعملة ${needsYerConversion ? "YER" : expenseCurrency}. يرجى إنشاء حساب مصروفات أولاً.');
      }

      // Get cash/bank account — when converting to YER, use YER cash account (1100)
      // and skip the cash box's linked foreign-currency account
      int? cashAccountId;
      final cashBoxId = expenseMap['cash_box_id'] as int?;
      if (!needsYerConversion && cashBoxId != null) {
        // Same-currency: use cash box's linked account
        final cashBox = await txn.query('cash_boxes',
            where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
        if (cashBox.isNotEmpty) {
          final linkedAccountId = cashBox.first['linked_account_id'] as int?;
          if (linkedAccountId != null) {
            cashAccountId = linkedAccountId;
          }
        }
      }
      if (cashAccountId == null) {
        final cashBanksAccount = await txn.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [(1100 + codeOffset).toString(), journalCurrency],
            limit: 1);
        cashAccountId = cashBanksAccount.isNotEmpty
            ? cashBanksAccount.first['id'] as int
            : null;
      }

      // Prevent unbalanced entry if cash account not found
      if (cashAccountId == null) {
        throw Exception(
            'لا يوجد حساب نقدية/بنك للعملة $journalCurrency. يرجى إنشاء حساب صناديق وبنوك أولاً.');
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
            'date': now,
            'created_at': now,
            'currency_code': expenseCurrency,
            'exchange_rate': exchangeRate,
            'amount_base': MoneyHelper.toCents(amountBase),
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
            'date': now,
            'created_at': now,
            'currency_code': expenseCurrency,
            'exchange_rate': exchangeRate,
            'amount_base': MoneyHelper.toCents(amountBase),
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
            'date': now,
            'created_at': now,
            'currency_code': expenseCurrency,
            'exchange_rate': exchangeRate,
            'amount_base': MoneyHelper.toCents(amountBase),
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
            'date': now,
            'created_at': now,
            'currency_code': expenseCurrency,
            'exchange_rate': exchangeRate,
            'amount_base': MoneyHelper.toCents(amountBase),
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, expenseAccId, 0.0, journalAmount, now);
        }
      }

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
  }

  /// Update an existing expense with journal entry reversal and new entries.
  /// Reverses old journal entries, updates the record, and creates new entries.
  /// [existingExpense] is the current expense data (used for reversing old entries).
  /// [newExpenseMap] is the updated expense data.
  /// [newExpenseAccountId] is the expense account ID for the new entry.
  ///
  /// Multi-currency: follows the same pattern as saveExpenseWithJournalEntry —
  /// foreign-currency expenses post journal entries to YER accounts and update
  /// cash boxes in the expense's native currency.
  Future<void> updateExpenseWithJournalEntry(
    int expenseId,
    Map<String, dynamic> existingExpense,
    Map<String, dynamic> newExpenseMap,
    int? newExpenseAccountId,
  ) async {
    // Check if fiscal period is closed before updating
    final expenseDate = newExpenseMap['expense_date'] as String? ??
        DateTime.now().toIso8601String();
    await _dbHelper.journal.checkFiscalPeriodOpen(expenseDate);

    final db = await _db;
    final now = DateTime.now().toIso8601String();
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
      final oldCodeOffset =
          oldCurrency == 'SAR' ? 1 : (oldCurrency == 'USD' ? 2 : 0);
      final oldExpenseAccountId =
          (existingExpense['expense_account_id'] as int?) ??
              (existingExpense['account_id'] as int?);
      final oldCashBoxId = existingExpense['cash_box_id'] as int?;
      final oldTitle = existingExpense['title'] as String? ?? 'مصروف';
      final oldIsSarf = oldOperationType == 'صرف';

      if (oldAmountBase > 0 && oldExpenseAccountId != null) {
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
            'date': now,
            'created_at': now,
            'currency_code': oldCurrency,
            'exchange_rate': oldExchangeRate,
            'amount_base': MoneyHelper.toCents(oldAmountBase),
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
              'date': now,
              'created_at': now,
              'currency_code': oldCurrency,
              'exchange_rate': oldExchangeRate,
              'amount_base': MoneyHelper.toCents(oldAmountBase),
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
              'date': now,
              'created_at': now,
              'currency_code': oldCurrency,
              'exchange_rate': oldExchangeRate,
              'amount_base': MoneyHelper.toCents(oldAmountBase),
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
            'date': now,
            'created_at': now,
            'currency_code': oldCurrency,
            'exchange_rate': oldExchangeRate,
            'amount_base': MoneyHelper.toCents(oldAmountBase),
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
      // Apply the same multi-currency fix as saveExpenseWithJournalEntry
      final newCurrency = (newExpenseMap['currency'] as String?) ?? 'YER';
      final newExchangeRate =
          (newExpenseMap['exchange_rate'] as num?)?.toDouble() ?? 1.0;
      final bool needsYerConversion =
          newCurrency != 'YER' && newExchangeRate > 0;
      final int codeOffset = needsYerConversion
          ? 0
          : (newCurrency == 'SAR' ? 1 : (newCurrency == 'USD' ? 2 : 0));
      final String journalCurrency = needsYerConversion ? 'YER' : newCurrency;
      final double journalAmount =
          needsYerConversion ? newAmountBase : newAmount;

      if (newExpenseAccountId != null && newAmountBase > 0) {
        final journalId = generateUniqueJournalId();
        final title = newExpenseMap['title'] as String? ?? 'مصروف';
        final isSarf = newExpenseMap['operation_type'] == 'صرف';

        // Resolve expense account for new entry — when converting to YER, use YER account
        int? effectiveExpenseAccountId = newExpenseAccountId;
        if (needsYerConversion) {
          final expenseAccount = await txn.query('accounts',
              where: 'account_code = ? AND currency = ?',
              whereArgs: ['5000', 'YER'],
              limit: 1);
          effectiveExpenseAccountId = expenseAccount.isNotEmpty
              ? expenseAccount.first['id'] as int
              : null;
          if (effectiveExpenseAccountId == null) {
            effectiveExpenseAccountId = newExpenseAccountId; // fallback
          }
        }

        // Get cash/bank account for the new entry
        int? cashBankAccountId;
        final cashBoxId = newExpenseMap['cash_box_id'] as int?;
        if (!needsYerConversion && cashBoxId != null) {
          // Same-currency: use cash box's linked account
          final cashBox = await txn.query('cash_boxes',
              where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
          if (cashBox.isNotEmpty) {
            final linkedAccountId = cashBox.first['linked_account_id'] as int?;
            if (linkedAccountId != null) {
              cashBankAccountId = linkedAccountId;
            }
          }
        }
        if (cashBankAccountId == null) {
          final cashBanksAccount = await txn.query('accounts',
              where: 'account_code = ? AND currency = ?',
              whereArgs: [(1100 + codeOffset).toString(), journalCurrency],
              limit: 1);
          cashBankAccountId = cashBanksAccount.isNotEmpty
              ? cashBanksAccount.first['id'] as int
              : null;
        }

        if (isSarf) {
          // صرف (disburse): Debit expense account, Credit cash/bank
          await txn.insert('transactions', {
            'account_id': effectiveExpenseAccountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(journalAmount),
            'credit': 0,
            'description': 'مصروف: $title',
            'date': now,
            'created_at': now,
            'currency_code': newCurrency,
            'exchange_rate': newExchangeRate,
            'amount_base': MoneyHelper.toCents(newAmountBase),
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
              'date': now,
              'created_at': now,
              'currency_code': newCurrency,
              'exchange_rate': newExchangeRate,
              'amount_base': MoneyHelper.toCents(newAmountBase),
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
              'date': now,
              'created_at': now,
              'currency_code': newCurrency,
              'exchange_rate': newExchangeRate,
              'amount_base': MoneyHelper.toCents(newAmountBase),
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
            'date': now,
            'created_at': now,
            'currency_code': newCurrency,
            'exchange_rate': newExchangeRate,
            'amount_base': MoneyHelper.toCents(newAmountBase),
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
        orderBy: orderBy);
  }

  /// Get all expenses for a specific expense sub-account
  Future<List<Map<String, dynamic>>> getExpensesBySubAccountId(int subAccountId,
      {String orderBy = 'expense_date DESC'}) async {
    final db = await _db;
    return await db.query('expenses',
        where: 'expense_sub_account_id = ?',
        whereArgs: [subAccountId],
        orderBy: orderBy);
  }
}
