import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/utils/journal_id_helper.dart';
import '../../../core/utils/money_helper.dart';
import '../database_helper.dart';

class EmployeeRepository {
  final DatabaseHelper _dbHelper;
  EmployeeRepository(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

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
        });
        await txn.insert('transactions', {
          'account_id': cashAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(balance),
          'description': 'رصيد افتتاحي موظف - $employeeName',
          'date': now,
          'created_at': now,
        });
        await txn.rawUpdate(
          'UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?',
          [MoneyHelper.toCents(balance), now, accountId],
        );
        await txn.rawUpdate(
          'UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?',
          [MoneyHelper.toCents(balance), now, cashAccountId],
        );
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
        });
        await txn.insert('transactions', {
          'account_id': accountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(balance),
          'description': 'رصيد افتتاحي موظف (عليه) - $employeeName',
          'date': now,
          'created_at': now,
        });
        await txn.rawUpdate(
          'UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?',
          [MoneyHelper.toCents(balance), now, cashAccountId],
        );
        await txn.rawUpdate(
          'UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?',
          [MoneyHelper.toCents(balance), now, accountId],
        );
      }
    });
  }
}
