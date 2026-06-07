import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/utils/journal_id_helper.dart';
import '../../../core/utils/money_helper.dart';
import '../database_helper.dart';

class EmployeeRepository {
  final DatabaseHelper _dbHelper;
  EmployeeRepository(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  /// Insert a new employee with optional opening balance.
  ///
  /// Handles `opening_balance_currency` from the data map:
  /// - Strips it before DB insert (not a real column).
  /// - Uses it to resolve the correct currency accounts for the journal entry.
  /// - Sets `currency` and `account_id` to null on the employee record
  ///   (currency is per-transaction, not per-employee).
  Future<int> insertEmployeeWithOpeningBalance(
      Map<String, dynamic> employeeData) async {
    final db = await _db;

    // Extract opening balance currency before inserting
    final openingBalanceCurrency =
        employeeData.remove('opening_balance_currency') as String?;
    final balance = MoneyHelper.readMoney(employeeData['balance']);
    final balanceType =
        employeeData['balance_type'] as String? ?? 'credit';
    final employeeName = employeeData['name'] as String? ?? '';

    // Currency is only for opening balance; the employee is currency-agnostic.
    // However, the DB column is NOT NULL, so we keep the opening-balance currency
    // as the stored default. It does NOT permanently bind the employee to that currency.
    // account_id is NOT permanently set on the employee.
    employeeData['account_id'] = null;

    // Insert employee (convert money fields to cents)
    final employeeId = await db.insert(
        'employees', MoneyHelper.toCentsMap(employeeData, ['balance']));

    // If opening balance > 0, create the journal entry against the
    // appropriate currency accounts
    if (balance > 0 && openingBalanceCurrency != null) {
      final codeOffset = openingBalanceCurrency == 'SAR'
          ? 1
          : (openingBalanceCurrency == 'USD' ? 2 : 0);
      final employeeAccountCode = (5100 + codeOffset).toString();
      final cashAccountCode = (1100 + codeOffset).toString();

      // Resolve employee account (5100+offset)
      final empAccountRows = await db.query(
        'accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [employeeAccountCode, openingBalanceCurrency],
        limit: 1,
      );
      final empAccountId =
          empAccountRows.isNotEmpty ? empAccountRows.first['id'] as int : null;

      // Resolve cash account (1100+offset)
      final cashAccountRows = await db.query(
        'accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [cashAccountCode, openingBalanceCurrency],
        limit: 1,
      );
      final cashAccountId =
          cashAccountRows.isNotEmpty ? cashAccountRows.first['id'] as int : null;

      if (empAccountId != null && cashAccountId != null) {
        await recordSalaryPayment(
          accountId: empAccountId,
          cashAccountId: cashAccountId,
          balance: balance,
          balanceType: balanceType,
          employeeName: employeeName,
          employeeId: employeeId,
        );
      }
    }

    return employeeId;
  }

  /// Record a salary payment (opening balance) for a new employee.
  ///
  /// Creates double-entry transactions and updates account balances:
  /// - For credit balance (له): Debit employee account, Credit cash account
  /// - For debit balance (عليه): Debit cash account, Credit employee account
  Future<void> recordSalaryPayment({
    required int accountId,
    required int cashAccountId,
    required double balance,
    required String balanceType,
    required String employeeName,
    int? employeeId,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final journalId = generateUniqueJournalId();

    await db.transaction((txn) async {
      if (balanceType == 'credit') {
        // له - الموظف له رصيد: مدين = الموظف، دائن = الصندوق
        await txn.insert('transactions', {
          'account_id': accountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(balance),
          'credit': 0,
          'description': 'رصيد افتتاحي موظف - $employeeName',
          'date': now,
          'created_at': now,
          'reference_type': 'opening_balance',
          'reference_id': employeeId != null ? 'employee_$employeeId' : null,
        });
        await txn.insert('transactions', {
          'account_id': cashAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(balance),
          'description': 'رصيد افتتاحي موظف - $employeeName',
          'date': now,
          'created_at': now,
          'reference_type': 'opening_balance',
          'reference_id': employeeId != null ? 'employee_$employeeId' : null,
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, accountId, balance, 0.0, now);
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cashAccountId, 0.0, balance, now);
      } else {
        // عليه - الموظف عليه رصيد: مدين = الصندوق، دائن = الموظف
        await txn.insert('transactions', {
          'account_id': cashAccountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(balance),
          'credit': 0,
          'description': 'رصيد افتتاحي موظف (عليه) - $employeeName',
          'date': now,
          'created_at': now,
          'reference_type': 'opening_balance',
          'reference_id': employeeId != null ? 'employee_$employeeId' : null,
        });
        await txn.insert('transactions', {
          'account_id': accountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(balance),
          'description': 'رصيد افتتاحي موظف (عليه) - $employeeName',
          'date': now,
          'created_at': now,
          'reference_type': 'opening_balance',
          'reference_id': employeeId != null ? 'employee_$employeeId' : null,
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cashAccountId, balance, 0.0, now);
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, accountId, 0.0, balance, now);
      }
    });
  }

  /// Get all transactions from the transactions table for the employee's
  /// account (account_id = the employee's linked account_id).
  Future<List<Map<String, dynamic>>> getEmployeeTransactions(int accountId) async {
    final db = await _db;
    return await db.query(
      'transactions',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'date ASC, id ASC',
    );
  }

  /// Get vouchers that have items referencing the employee's account.
  Future<List<Map<String, dynamic>>> getEmployeeVouchers(int employeeId) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT DISTINCT v.* FROM vouchers v 
      INNER JOIN voucher_items vi ON v.id = vi.voucher_id 
      INNER JOIN employees e ON e.account_id = vi.account_id 
      WHERE e.id = ?
      ORDER BY v.date ASC
    ''', [employeeId]);
  }

  /// جلب معاملات القيد الافتتاحي للموظف — find opening balance transactions
  /// linked to this employee via reference_id.
  /// Returns transaction rows with account currency info.
  Future<List<Map<String, dynamic>>> getEmployeeOpeningBalanceTransactions(int employeeId) async {
    final db = await _db;
    // First try: search by reference_id (new data with 'employee_{id}')
    final byRef = await db.rawQuery('''
      SELECT t.*, a.currency AS account_currency
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE t.reference_type = 'opening_balance'
        AND t.reference_id = ?
        AND a.account_code LIKE '51%'
    ''', ['employee_$employeeId']);
    
    if (byRef.isNotEmpty) return byRef;
    
    // Fallback: search by description pattern (legacy data without reference_id)
    return await db.rawQuery('''
      SELECT t.*, a.currency AS account_currency
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE t.reference_type = 'opening_balance'
        AND a.account_code LIKE '51%'
        AND t.description LIKE 'رصيد افتتاحي موظف%'
      ORDER BY t.date ASC
    ''');
  }

  /// Record a transaction for an employee (له or عليه).
  ///
  /// Accounting logic:
  /// - For 'credit' (له - employee is owed money):
  ///   Debit employee account (5100+offset), Credit cash account (1100+offset)
  /// - For 'debit' (عليه - employee owes money):
  ///   Debit cash account (1100+offset), Credit employee account (5100+offset)
  ///
  /// Also updates the employee's balance in the employees table and the
  /// cash box balance.
  Future<void> recordEmployeeTransaction({
    required int employeeId,
    required double amount,
    required String balanceType,
    required String currency,
    required int? cashBoxId,
    String? description,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    // Check fiscal period
    await _dbHelper.journal.checkFiscalPeriodOpen(now);

    // Get employee data
    final employeeRows = await db.query('employees', where: 'id = ?', whereArgs: [employeeId], limit: 1);
    if (employeeRows.isEmpty) return;
    final employee = employeeRows.first;
    final employeeName = employee['name'] as String? ?? '';
    final accountId = employee['account_id'] as int?;

    // Determine account codes based on currency
    final codeOffset = currency == 'SAR' ? 1 : (currency == 'USD' ? 2 : 0);
    final employeeAccountCode = (5100 + codeOffset).toString();
    final cashAccountCode = (1100 + codeOffset).toString();

    // Resolve employee account ID
    int? empAccountId = accountId;
    if (empAccountId == null) {
      final empAccountRows = await db.query(
        'accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [employeeAccountCode, currency],
        limit: 1,
      );
      empAccountId = empAccountRows.isNotEmpty ? empAccountRows.first['id'] as int : null;
    }

    // Resolve cash account ID from the selected cash box
    int? cashAccountId;
    if (cashBoxId != null) {
      final cashBoxRows = await db.query('cash_boxes', where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
      if (cashBoxRows.isNotEmpty) {
        cashAccountId = cashBoxRows.first['linked_account_id'] as int?;
      }
    }
    if (cashAccountId == null) {
      final cashAccountRows = await db.query(
        'accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [cashAccountCode, currency],
        limit: 1,
      );
      cashAccountId = cashAccountRows.isNotEmpty ? cashAccountRows.first['id'] as int : null;
    }

    if (empAccountId == null || cashAccountId == null) return;

    final journalId = generateUniqueJournalId();
    final desc = description?.trim().isNotEmpty == true
        ? description!.trim()
        : '${balanceType == 'credit' ? 'له' : 'عليه'} - $employeeName';

    await db.transaction((txn) async {
      if (balanceType == 'credit') {
        // له - الموظف له مبلغ: مدين = حساب الموظف، دائن = الصندوق
        await txn.insert('transactions', {
          'account_id': empAccountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(amount),
          'credit': 0,
          'description': desc,
          'date': now,
          'created_at': now,
        });
        await txn.insert('transactions', {
          'account_id': cashAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(amount),
          'description': desc,
          'date': now,
          'created_at': now,
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, empAccountId!, amount, 0.0, now);
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cashAccountId!, 0.0, amount, now);
      } else {
        // عليه - الموظف عليه مبلغ: مدين = الصندوق، دائن = حساب الموظف
        await txn.insert('transactions', {
          'account_id': cashAccountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(amount),
          'credit': 0,
          'description': desc,
          'date': now,
          'created_at': now,
        });
        await txn.insert('transactions', {
          'account_id': empAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(amount),
          'description': desc,
          'date': now,
          'created_at': now,
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cashAccountId!, amount, 0.0, now);
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, empAccountId!, 0.0, amount, now);
      }

      // Update cash box balance
      if (cashBoxId != null) {
        final cashBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
        if (cashBox.isNotEmpty) {
          final currentBalance = MoneyHelper.readMoney(cashBox.first['balance']);
          final cbBalanceType = cashBox.first['balance_type'] as String? ?? 'credit';
          final isCashIn = balanceType == 'debit'; // عليه = cash comes in
          double newCashBalance;
          if (cbBalanceType == 'credit') {
            newCashBalance = isCashIn ? currentBalance + amount : currentBalance - amount;
          } else {
            newCashBalance = isCashIn ? currentBalance - amount : currentBalance + amount;
          }
          await txn.update('cash_boxes', {
            'balance': MoneyHelper.toCents(newCashBalance),
            'updated_at': now,
          }, where: 'id = ?', whereArgs: [cashBoxId]);
        }
      }

      // Update employee balance
      final currentEmpBalance = MoneyHelper.readMoney(employee['balance']);
      final currentEmpBalanceType = employee['balance_type'] as String? ?? 'credit';
      double newEmpBalance;
      String newEmpBalanceType;

      if (balanceType == 'credit') {
        // له increases credit (employee is owed more)
        if (currentEmpBalanceType == 'credit') {
          newEmpBalance = currentEmpBalance + amount;
          newEmpBalanceType = 'credit';
        } else {
          newEmpBalance = currentEmpBalance - amount;
          newEmpBalanceType = newEmpBalance < 0 ? 'credit' : 'debit';
          newEmpBalance = newEmpBalance.abs();
        }
      } else {
        // عليه increases debit (employee owes more)
        if (currentEmpBalanceType == 'debit') {
          newEmpBalance = currentEmpBalance + amount;
          newEmpBalanceType = 'debit';
        } else {
          newEmpBalance = currentEmpBalance - amount;
          newEmpBalanceType = newEmpBalance < 0 ? 'debit' : 'credit';
          newEmpBalance = newEmpBalance.abs();
        }
      }

      await txn.update('employees', {
        'balance': MoneyHelper.toCents(newEmpBalance),
        'balance_type': newEmpBalanceType,
        'updated_at': now,
      }, where: 'id = ?', whereArgs: [employeeId]);
    });
  }

  /// Update the employee's balance in the employees table.
  Future<void> updateEmployeeBalance(int employeeId, double newBalance, String balanceType) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'employees',
      {
        'balance': MoneyHelper.toCents(newBalance),
        'balance_type': balanceType,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [employeeId],
    );
  }
}
