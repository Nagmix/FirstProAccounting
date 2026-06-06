import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/utils/money_helper.dart';
import '../database_helper.dart';

class ExpenseSubAccountRepository {
  final DatabaseHelper _dbHelper;
  ExpenseSubAccountRepository(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  /// Money fields for the expense_sub_accounts table (stored as cents).
  static const moneyFields = ['debt_ceiling'];

  // ══════════════════════════════════════════════════════════════
  //  Expense Sub-Account CRUD methods
  // ══════════════════════════════════════════════════════════════

  /// Insert a new expense sub-account.
  Future<int> insertSubAccount(Map<String, dynamic> subAccountMap) async {
    final db = await _db;
    final dbMap = MoneyHelper.toCentsMap(subAccountMap, moneyFields);
    return await db.insert('expense_sub_accounts', dbMap);
  }

  /// Get all active sub-accounts ordered by name.
  Future<List<Map<String, dynamic>>> getAllSubAccounts() async {
    final db = await _db;
    return await db.query(
      'expense_sub_accounts',
      where: 'is_active = 1',
      orderBy: 'name ASC',
    );
  }

  /// Get a single sub-account by ID.
  Future<Map<String, dynamic>?> getSubAccountById(int id) async {
    final db = await _db;
    final results = await db.query(
      'expense_sub_accounts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Update a sub-account.
  Future<int> updateSubAccount(int id, Map<String, dynamic> subAccountMap) async {
    final db = await _db;
    final dbMap = MoneyHelper.toCentsMap(subAccountMap, moneyFields);
    return await db.update(
      'expense_sub_accounts',
      dbMap,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete a sub-account (only if no expenses reference it).
  /// Returns the number of rows deleted, or 0 if blocked by existing expenses.
  Future<int> deleteSubAccount(int id) async {
    final db = await _db;
    // Check if any expenses reference this sub-account
    final refs = await db.query(
      'expenses',
      where: 'expense_sub_account_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (refs.isNotEmpty) {
      // Cannot delete — expenses still reference this sub-account
      return 0;
    }
    return await db.delete(
      'expense_sub_accounts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Balance & Expense Query Methods
  // ══════════════════════════════════════════════════════════════

  /// Calculate the balance of a sub-account for a specific currency
  /// by summing expenses.
  ///
  /// Balance = sum of amount_base where operation_type='صرف'
  ///         - sum of amount_base where operation_type='قبض'
  ///
  /// Amounts are stored as cents in the database — converted via
  /// [MoneyHelper.readCalculatedMoney].
  Future<double> getSubAccountBalance(int subAccountId, String currency) async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT "
      "  CAST(COALESCE(SUM(CASE WHEN operation_type = 'صرف' THEN amount_base ELSE 0 END), 0) AS INTEGER) AS total_sarf, "
      "  CAST(COALESCE(SUM(CASE WHEN operation_type = 'قبض' THEN amount_base ELSE 0 END), 0) AS INTEGER) AS total_qabd "
      "FROM expenses "
      "WHERE expense_sub_account_id = ? AND currency = ?",
      [subAccountId, currency],
    );
    if (result.isEmpty) return 0.0;
    final totalSarf = MoneyHelper.readCalculatedMoney(result.first['total_sarf']);
    final totalQabd = MoneyHelper.readCalculatedMoney(result.first['total_qabd']);
    return totalSarf - totalQabd;
  }

  /// Get the total balance across all currencies for a sub-account.
  /// Returns a Map<String, double> mapping currency code to balance.
  Future<Map<String, double>> getSubAccountTotalBalance(int subAccountId) async {
    final db = await _db;
    final results = await db.rawQuery(
      "SELECT "
      "  currency, "
      "  CAST(COALESCE(SUM(CASE WHEN operation_type = 'صرف' THEN amount_base ELSE 0 END), 0) AS INTEGER) AS total_sarf, "
      "  CAST(COALESCE(SUM(CASE WHEN operation_type = 'قبض' THEN amount_base ELSE 0 END), 0) AS INTEGER) AS total_qabd "
      "FROM expenses "
      "WHERE expense_sub_account_id = ? "
      "GROUP BY currency",
      [subAccountId],
    );
    final balances = <String, double>{};
    for (final row in results) {
      final currencyCode = row['currency'] as String? ?? 'YER';
      final totalSarf = MoneyHelper.readCalculatedMoney(row['total_sarf']);
      final totalQabd = MoneyHelper.readCalculatedMoney(row['total_qabd']);
      balances[currencyCode] = totalSarf - totalQabd;
    }
    return balances;
  }

  /// Count the number of expenses for a sub-account.
  Future<int> getSubAccountExpenseCount(int subAccountId) async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM expenses WHERE expense_sub_account_id = ?",
      [subAccountId],
    );
    if (result.isEmpty) return 0;
    return (result.first['cnt'] as int?) ?? 0;
  }
}
