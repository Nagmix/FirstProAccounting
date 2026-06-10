import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/utils/entity_balance_helper.dart';
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
  ///
  /// After resolving the employee's account (5100+offset), the account_id
  /// is stored on the employee record so that vouchers can be linked back.
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
    // We set account_id to the employee account (5100+offset) for the opening
    // balance currency so vouchers can be linked back.
    final codeOffset = openingBalanceCurrency == 'SAR'
        ? 1
        : (openingBalanceCurrency == 'USD' ? 2 : 0);
    final employeeAccountCode = (5100 + codeOffset).toString();

    // Resolve employee account to get account_id
    final empAccountRows = await db.query(
      'accounts',
      where: 'account_code = ? AND currency = ?',
      whereArgs: [employeeAccountCode, openingBalanceCurrency ?? 'YER'],
      limit: 1,
    );
    final empAccountId =
        empAccountRows.isNotEmpty ? empAccountRows.first['id'] as int : null;

    employeeData['account_id'] = empAccountId;

    // Insert employee (convert money fields to cents)
    final employeeId = await db.insert(
        'employees', MoneyHelper.toCentsMap(employeeData, ['balance']));

    // If opening balance > 0, create the journal entry against the
    // appropriate currency accounts
    if (balance > 0 && openingBalanceCurrency != null) {
      final obCodeOffset = openingBalanceCurrency == 'SAR'
          ? 1
          : (openingBalanceCurrency == 'USD' ? 2 : 0);
      final obEmployeeAccountCode = (5100 + obCodeOffset).toString();
      final obEquityAccountCode = (2901 + obCodeOffset).toString();

      // Resolve employee account (5100+offset)
      final obEmpAccountRows = await db.query(
        'accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [obEmployeeAccountCode, openingBalanceCurrency],
        limit: 1,
      );
      final obEmpAccountId =
          obEmpAccountRows.isNotEmpty ? obEmpAccountRows.first['id'] as int : null;

      // Resolve Opening Balance Equity account (2901+offset)
      final obEquityAccountRows = await db.query(
        'accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [obEquityAccountCode, openingBalanceCurrency],
        limit: 1,
      );
      final obEquityAccountId =
          obEquityAccountRows.isNotEmpty ? obEquityAccountRows.first['id'] as int : null;

      if (obEmpAccountId != null && obEquityAccountId != null) {
        await recordSalaryPayment(
          accountId: obEmpAccountId,
          equityAccountId: obEquityAccountId,
          balance: balance,
          balanceType: balanceType,
          employeeName: employeeName,
          employeeId: employeeId,
          currency: openingBalanceCurrency,
        );
      }
    }

    return employeeId;
  }

  /// Record a salary payment (opening balance) for a new employee.
  ///
  /// Creates double-entry transactions and updates account balances.
  /// Uses Opening Balance Equity (2901) as contra account (same pattern as suppliers).
  ///
  /// Correct accounting per Arabic accounting standards:
  /// - For credit balance (له): Credit employee account, Debit OB Equity
  ///   → Employee has credit position (company owes employee)
  /// - For debit balance (عليه): Debit employee account, Credit OB Equity
  ///   → Employee has debit position (employee owes company)
  Future<void> recordSalaryPayment({
    required int accountId,
    required int equityAccountId,
    required double balance,
    required String balanceType,
    required String employeeName,
    int? employeeId,
    String currency = 'YER',
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final journalId = generateUniqueJournalId();

    // Resolve exchange rate for the given currency
    final exchangeRate = await _getExchangeRate(currency);
    final baseAmount = currency == 'YER' ? balance : balance * exchangeRate;

    await db.transaction((txn) async {
      if (balanceType == 'credit') {
        // له - الموظف له رصيد (دائن): دائن = حساب الموظف، مدين = حقوق الملكية
        // Credit employee account → increases credit side → له
        await txn.insert('transactions', {
          'account_id': accountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(balance),
          'description': 'رصيد افتتاحي موظف - $employeeName',
          'date': now,
          'created_at': now,
          'reference_type': 'opening_balance',
          'reference_id': employeeId != null ? 'employee_$employeeId' : null,
          'currency_code': currency,
          'exchange_rate': exchangeRate,
          'amount_base': MoneyHelper.toCents(baseAmount),
        });
        await txn.insert('transactions', {
          'account_id': equityAccountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(balance),
          'credit': 0,
          'description': 'رصيد افتتاحي موظف - $employeeName',
          'date': now,
          'created_at': now,
          'reference_type': 'opening_balance',
          'reference_id': employeeId != null ? 'employee_$employeeId' : null,
          'currency_code': currency,
          'exchange_rate': exchangeRate,
          'amount_base': MoneyHelper.toCents(baseAmount),
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, accountId, 0.0, balance, now);
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, equityAccountId, balance, 0.0, now);
      } else {
        // عليه - الموظف عليه رصيد (مدين): مدين = حساب الموظف، دائن = حقوق الملكية
        // Debit employee account → increases debit side → عليه
        await txn.insert('transactions', {
          'account_id': accountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(balance),
          'credit': 0,
          'description': 'رصيد افتتاحي موظف (عليه) - $employeeName',
          'date': now,
          'created_at': now,
          'reference_type': 'opening_balance',
          'reference_id': employeeId != null ? 'employee_$employeeId' : null,
          'currency_code': currency,
          'exchange_rate': exchangeRate,
          'amount_base': MoneyHelper.toCents(baseAmount),
        });
        await txn.insert('transactions', {
          'account_id': equityAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(balance),
          'description': 'رصيد افتتاحي موظف (عليه) - $employeeName',
          'date': now,
          'created_at': now,
          'reference_type': 'opening_balance',
          'reference_id': employeeId != null ? 'employee_$employeeId' : null,
          'currency_code': currency,
          'exchange_rate': exchangeRate,
          'amount_base': MoneyHelper.toCents(baseAmount),
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, accountId, balance, 0.0, now);
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, equityAccountId, 0.0, balance, now);
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

  /// Get vouchers linked to this employee.
  /// Uses employee_id on the vouchers table (v47+) for direct lookup,
  /// falls back to account-based join for legacy data.
  Future<List<Map<String, dynamic>>> getEmployeeVouchers(int employeeId) async {
    final db = await _db;

    // Try employee_id column first (v47+)
    try {
      final byEmployeeId = await db.query(
        'vouchers',
        where: 'employee_id = ?',
        whereArgs: [employeeId],
        orderBy: 'date ASC',
      );
      if (byEmployeeId.isNotEmpty) return byEmployeeId;
    } catch (_) {
      // Column may not exist yet (pre-v47)
    }

    // Fallback: join through account_id (legacy)
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
  /// Correct accounting per Arabic accounting standards:
  /// - For 'credit' (له - employee is owed money / receipt from employee):
  ///   Credit employee account (5100+offset), Debit cash account (1100+offset)
  ///   → Employee account is credited → employee's credit position increases → له
  ///   → Cash comes IN (employee pays the company)
  ///
  /// - For 'debit' (عليه - employee owes money / payment to employee):
  ///   Debit employee account (5100+offset), Credit cash account (1100+offset)
  ///   → Employee account is debited → employee's debit position increases → عليه
  ///   → Cash goes OUT (company pays the employee)
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

    // Determine account codes based on currency
    final codeOffset = currency == 'SAR' ? 1 : (currency == 'USD' ? 2 : 0);
    final employeeAccountCode = (5100 + codeOffset).toString();
    final cashAccountCode = (1100 + codeOffset).toString();

    // Resolve employee account ID
    int? empAccountId = employee['account_id'] as int?;
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
        : '${balanceType == 'credit' ? 'له' : 'عليه'} - ${employee['name'] ?? ''}';

    // Resolve exchange rate for the given currency
    final exchangeRate = await _getExchangeRate(currency);
    final baseAmount = currency == 'YER' ? amount : amount * exchangeRate;

    await db.transaction((txn) async {
      if (balanceType == 'credit') {
        // له - الموظف له مبلغ (سند قبض من الموظف):
        // دائن = حساب الموظف (5100), مدين = الصندوق (1100)
        // Credit employee account → increases credit side → له
        await txn.insert('transactions', {
          'account_id': empAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(amount),
          'description': desc,
          'date': now,
          'created_at': now,
          'currency_code': currency,
          'exchange_rate': exchangeRate,
          'amount_base': MoneyHelper.toCents(baseAmount),
        });
        await txn.insert('transactions', {
          'account_id': cashAccountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(amount),
          'credit': 0,
          'description': desc,
          'date': now,
          'created_at': now,
          'currency_code': currency,
          'exchange_rate': exchangeRate,
          'amount_base': MoneyHelper.toCents(baseAmount),
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, empAccountId!, 0.0, amount, now);
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cashAccountId!, amount, 0.0, now);
      } else {
        // عليه - الموظف عليه مبلغ (سند صرف للموظف):
        // مدين = حساب الموظف (5100), دائن = الصندوق (1100)
        // Debit employee account → increases debit side → عليه
        await txn.insert('transactions', {
          'account_id': empAccountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(amount),
          'credit': 0,
          'description': desc,
          'date': now,
          'created_at': now,
          'currency_code': currency,
          'exchange_rate': exchangeRate,
          'amount_base': MoneyHelper.toCents(baseAmount),
        });
        await txn.insert('transactions', {
          'account_id': cashAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(amount),
          'description': desc,
          'date': now,
          'created_at': now,
          'currency_code': currency,
          'exchange_rate': exchangeRate,
          'amount_base': MoneyHelper.toCents(baseAmount),
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, empAccountId!, amount, 0.0, now);
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cashAccountId!, 0.0, amount, now);
      }

      // Update cash box balance
      if (cashBoxId != null) {
        final cashBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
        if (cashBox.isNotEmpty) {
          final currentBalance = MoneyHelper.readMoney(cashBox.first['balance']);
          final cbBalanceType = cashBox.first['balance_type'] as String? ?? 'credit';
          // credit (له) = cash comes IN from employee (سند قبض)
          // debit (عليه) = cash goes OUT to employee (سند صرف)
          final isCashIn = balanceType == 'credit'; // له = cash comes in (employee pays company)
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

      // Update employee balance using EntityBalanceHelper for consistency
      if (balanceType == 'credit') {
        await EntityBalanceHelper.applyEmployeeBalanceChange(
          txn: txn, employeeId: employeeId, creditEffect: amount, debitEffect: 0, now: now,
        );
      } else {
        await EntityBalanceHelper.applyEmployeeBalanceChange(
          txn: txn, employeeId: employeeId, creditEffect: 0, debitEffect: amount, now: now,
        );
      }
    });
  }

  /// Calculate the balance of a specific employee for a given currency
  Future<double> getEmployeeBalanceForCurrency(int employeeId, String currency) async {
    final db = await _db;
    double balance = 0.0;

    // 1. Opening balance: SUM(credit) - SUM(debit) on employee account (51xx)
    // positive = له (credit), negative = عليه (debit)
    final obByRef = await db.rawQuery('''
      SELECT COALESCE(SUM(t.credit), 0) - COALESCE(SUM(t.debit), 0) AS net
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE t.reference_type = 'opening_balance'
        AND t.reference_id = ?
        AND a.account_code LIKE '51%'
        AND a.currency = ?
    ''', ['employee_$employeeId', currency]);
    balance += MoneyHelper.readCalculatedMoney(obByRef.first['net']);

    // 2. Transactions against employee's account (non-opening-balance)
    final employeeRows = await db.query('employees', where: 'id = ?', whereArgs: [employeeId], limit: 1);
    if (employeeRows.isNotEmpty) {
      final accountId = employeeRows.first['account_id'] as int?;
      if (accountId != null) {
        final transactions = await db.rawQuery('''
          SELECT COALESCE(SUM(credit), 0) - COALESCE(SUM(debit), 0) AS net
          FROM transactions t
          INNER JOIN accounts a ON t.account_id = a.id
          WHERE t.account_id = ? AND a.currency = ?
            AND (t.reference_type IS NULL OR t.reference_type != 'opening_balance')
        ''', [accountId, currency]);
        balance += MoneyHelper.readCalculatedMoney(transactions.first['net']);
      }
    }

    return balance;
  }

  /// Look up the exchange rate for a currency from the currencies table.
  /// Returns 1.0 for YER or if the currency is not found.
  Future<double> _getExchangeRate(String currency) async {
    if (currency == 'YER') return 1.0;
    final db = await _db;
    final rows = await db.query(
      'currencies',
      where: 'code = ?',
      whereArgs: [currency],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return (rows.first['exchange_rate'] as num?)?.toDouble() ?? 1.0;
    }
    return 1.0;
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
