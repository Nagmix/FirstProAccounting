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
    final expenseDate = expenseMap['expense_date'] as String? ?? DateTime.now().toIso8601String();
    await _dbHelper.journal.checkFiscalPeriodOpen(expenseDate);
    final db = await _db;
    final dbMap = MoneyHelper.toCentsMap(expenseMap, [...MoneyHelper.expenseMoneyFields, 'amount_base']);
    return await db.insert('expenses', dbMap);
  }

  Future<List<Map<String, dynamic>>> getAllExpenses({String orderBy = 'expense_date DESC'}) async {
    final db = await _db;
    return await db.query('expenses', orderBy: orderBy);
  }

  Future<List<Map<String, dynamic>>> getExpensesByCategory(String category) async {
    final db = await _db;
    return await db.query('expenses', where: 'category = ?', whereArgs: [category], orderBy: 'expense_date DESC');
  }

  Future<List<Map<String, dynamic>>> getExpensesByDateRange(String startDate, String endDate) async {
    final db = await _db;
    return await db.query('expenses', where: 'expense_date >= ? AND expense_date <= ?', whereArgs: [startDate, endDate], orderBy: 'expense_date DESC');
  }

  Future<Map<String, dynamic>?> getExpenseById(int id) async {
    final db = await _db;
    final results = await db.query('expenses', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateExpense(int id, Map<String, dynamic> expenseMap) async {
    // ── M-10: تحقق من الفترة المالية قبل التحديث ──
    final existing = await getExpenseById(id);
    if (existing != null) {
      final expenseDate = existing['expense_date'] as String? ?? DateTime.now().toIso8601String();
      await _dbHelper.journal.checkFiscalPeriodOpen(expenseDate);
    }
    final db = await _db;
    final dbMap = MoneyHelper.toCentsMap(expenseMap, [...MoneyHelper.expenseMoneyFields, 'amount_base']);
    return await db.update('expenses', dbMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteExpense(int id) async {
    // ── M-10: تحقق من الفترة المالية قبل الحذف ──
    final existing = await getExpenseById(id);
    if (existing != null) {
      final expenseDate = existing['expense_date'] as String? ?? DateTime.now().toIso8601String();
      await _dbHelper.journal.checkFiscalPeriodOpen(expenseDate);
    }
    final db = await _db;
    return await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getTotalExpensesThisMonth() async {
    final db = await _db;
    final now = DateTime.now();
    final monthStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final result = await db.rawQuery("SELECT CAST(COALESCE(SUM(amount_base), 0) AS INTEGER) AS total FROM expenses WHERE date(expense_date) >= ?", [monthStart]);
    return MoneyHelper.readCalculatedMoney(result.first['total']);
  }

  Future<double> getTotalExpensesByCategory(String category) async {
    final db = await _db;
    final result = await db.rawQuery("SELECT CAST(COALESCE(SUM(amount_base), 0) AS INTEGER) AS total FROM expenses WHERE category = ?", [category]);
    return MoneyHelper.readCalculatedMoney(result.first['total']);
  }

  Future<double> getTotalExpensesForDate(DateTime date) async {
    final db = await _db;
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final result = await db.rawQuery("SELECT CAST(COALESCE(SUM(amount_base), 0) AS INTEGER) AS total FROM expenses WHERE date(expense_date) = ?", [dateStr]);
    return MoneyHelper.readCalculatedMoney(result.first['total']);
  }

  /// Save expense with journal entry.
  /// Supports operation_type: 'صرف' (disburse - debit expense, credit cash) or 'قبض' (receive - debit cash, credit expense).
  Future<void> saveExpenseWithJournalEntry(Map<String, dynamic> expenseMap) async {
    // Check if fiscal period is closed before creating expense
    final expenseDate = expenseMap['expense_date'] as String? ?? DateTime.now().toIso8601String();
    await _dbHelper.journal.checkFiscalPeriodOpen(expenseDate);

    final db = await _db;
    final amountBase = MoneyHelper.readMoney(expenseMap['amount_base']);
    // B-06: Auto-calculate amount_base if exchange_rate is provided and amount_base seems wrong
    final amount = MoneyHelper.readMoney(expenseMap['amount']);
    final exchangeRate = (expenseMap['exchange_rate'] as num?)?.toDouble() ?? 1.0;
    final expectedBase = amount * exchangeRate;
    if (amountBase <= 0 && expectedBase > 0) {
      expenseMap['amount_base'] = MoneyHelper.toCents(expectedBase);
    }
    final expenseCurrency = (expenseMap['currency'] as String?) ?? 'YER';
    final operationType = (expenseMap['operation_type'] as String?) ?? 'صرف';
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      // Insert expense (convert money fields to cents)
      final dbExpenseMap = MoneyHelper.toCentsMap(expenseMap, [...MoneyHelper.expenseMoneyFields, 'amount_base']);
      await txn.insert('expenses', dbExpenseMap);

      // Post journal entry
      final journalId = generateUniqueJournalId();

      // Determine currency-specific account code offset
      final codeOffset = expenseCurrency == 'SAR' ? 1 : (expenseCurrency == 'USD' ? 2 : 0);

      // Get expense account (code 5000+offset) or use provided account_id
      final expenseAccountId = expenseMap['account_id'] as int?;
      int? expenseAccId = expenseAccountId;

      if (expenseAccId == null) {
        final expenseAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(5000 + codeOffset).toString(), expenseCurrency], limit: 1);
        expenseAccId = expenseAccount.isNotEmpty ? expenseAccount.first['id'] as int : null;
      }

      // ── C-06: منع إنشاء قيد غير متوازن إذا لم يوجد حساب المصروفات ──
      if (expenseAccId == null) {
        throw Exception('لا يوجد حساب مصروفات للعملة $expenseCurrency. يرجى إنشاء حساب مصروفات أولاً.');
      }

      // Get cash/bank account (code 1100+offset) or use cash box linked account
      int? cashAccountId;
      final cashBoxId = expenseMap['cash_box_id'] as int?;
      if (cashBoxId != null) {
        final cashBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
        if (cashBox.isNotEmpty) {
          final linkedAccountId = cashBox.first['linked_account_id'] as int?;
          if (linkedAccountId != null) {
            cashAccountId = linkedAccountId;
          }
        }
      }
      if (cashAccountId == null) {
        final cashBanksAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1100 + codeOffset).toString(), expenseCurrency], limit: 1);
        cashAccountId = cashBanksAccount.isNotEmpty ? cashBanksAccount.first['id'] as int : null;
      }

      // Prevent unbalanced entry if cash account not found
      if (cashAccountId == null) {
        throw Exception('لا يوجد حساب نقدية/بنك للعملة $expenseCurrency. يرجى إنشاء حساب صناديق وبنوك أولاً.');
      }

      final title = expenseMap['title'] as String? ?? 'مصروف';
      final isSarf = operationType == 'صرف';

      if (isSarf) {
        // صرف (disburse): Debit expense account, Credit cash/bank
        if (expenseAccId != null && amountBase > 0) {
          await txn.insert('transactions', {
            'account_id': expenseAccId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(amountBase),
            'credit': 0,
            'description': 'مصروف: $title',
            'date': now,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, expenseAccId, amountBase, 0.0, now);
        }
        if (cashAccountId != null && amountBase > 0) {
          await txn.insert('transactions', {
            'account_id': cashAccountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(amountBase),
            'description': 'مصروف: $title',
            'date': now,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cashAccountId, 0.0, amountBase, now);
        }
      } else {
        // ── A-05: قبض (استرداد مصروف) — خصم من حساب المصروفات الأصلي ──
        // القيد الصحيح: مدين النقدية / دائن حساب المصروفات (تخفيض المصروف)
        // هذا يقلل المصروفات الفعلية بدلاً من إنشاء إيراد وهمي
        if (cashAccountId != null && amountBase > 0) {
          await txn.insert('transactions', {
            'account_id': cashAccountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(amountBase),
            'credit': 0,
            'description': 'استرداد مصروف: $title',
            'date': now,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cashAccountId, amountBase, 0.0, now);
        }
        // Credit the expense account to reduce the expense (reverse of disbursement)
        if (expenseAccId != null && amountBase > 0) {
          await txn.insert('transactions', {
            'account_id': expenseAccId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(amountBase),
            'description': 'استرداد مصروف: $title',
            'date': now,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, expenseAccId, 0.0, amountBase, now);
        }
      }

      // Update cash box balance
      if (cashBoxId != null && amountBase > 0) {
        if (isSarf) {
          await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(amountBase), now, cashBoxId]);
        } else {
          await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(amountBase), now, cashBoxId]);
        }
      }
    });
  }

  /// Get all expenses for a specific expense account
  Future<List<Map<String, dynamic>>> getExpensesByAccountId(int accountId, {String orderBy = 'expense_date DESC'}) async {
    final db = await _db;
    return await db.query('expenses', where: 'expense_account_id = ?', whereArgs: [accountId], orderBy: orderBy);
  }
}
