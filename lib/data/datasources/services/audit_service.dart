import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/data/datasources/database_helper.dart';

class AuditService {
  final DatabaseHelper _dbHelper;
  AuditService(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  /// Log an audit trail event (non-critical — errors are caught and printed)
  Future<void> logAuditEvent({
    required String action,
    required String tableName,
    int? recordId,
    String? recordType,
    String? oldValues,
    String? newValues,
    String? userName,
    int? shiftId,
  }) async {
    final db = await _db;
    try {
      await db.insert('audit_trail', {
        'action': action,
        'table_name': tableName,
        'record_id': recordId,
        'record_type': recordType,
        'old_values': oldValues,
        'new_values': newValues,
        'user_name': userName,
        'shift_id': shiftId,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Audit log error (non-critical): $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  Accounting Audit query methods
  //  Extracted from accounting_audit_screen.dart — raw SQL, no MoneyHelper.
  //  All monetary values are returned as raw DB values.
  //  The caller is responsible for converting using
  //  MoneyHelper.readMoney / readCalculatedMoney.
  // ══════════════════════════════════════════════════════════════

  /// ميزان المراجعة حسب العملة — trial balance grouped by currency.
  /// Returns rows with: currency, account_count, total_debit, total_credit, balance_diff.
  Future<List<Map<String, dynamic>>> getTrialBalanceByCurrency() async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT a.currency,
             COUNT(DISTINCT a.id) AS account_count,
             COALESCE(SUM(t.debit), 0.0) AS total_debit,
             COALESCE(SUM(t.credit), 0.0) AS total_credit,
             COALESCE(SUM(t.debit), 0.0) - COALESCE(SUM(t.credit), 0.0) AS balance_diff
      FROM accounts a
      LEFT JOIN transactions t ON t.account_id = a.id
      WHERE a.is_active = 1
      GROUP BY a.currency
      ORDER BY a.currency
    ''');
  }

  /// ملخص الحسابات حسب النوع والعملة — account summary by currency and type.
  /// Returns rows with: currency, account_type, count, total_balance.
  Future<List<Map<String, dynamic>>>
      getAccountSummaryByCurrencyAndType() async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT a.currency, a.account_type,
             COUNT(*) AS count,
             COALESCE(SUM(a.balance), 0.0) AS total_balance
      FROM accounts a
      WHERE a.is_active = 1
      GROUP BY a.currency, a.account_type
      ORDER BY a.currency, a.account_type
    ''');
  }

  /// فواتير بدون قيود محاسبية — orphaned invoices (no journal entries).
  /// Uses LIKE matching on transaction descriptions since the transactions
  /// table does not have reference_type/reference_id columns.
  /// Returns up to [limit] rows.
  Future<List<Map<String, dynamic>>> getOrphanedInvoices(
      {int limit = 20}) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT i.id, i.type, i.total, i.currency, i.created_at,
             CASE WHEN i.customer_id IS NOT NULL THEN c.name
                  WHEN i.supplier_id IS NOT NULL THEN s.name
                  ELSE 'بدون عميل/مورد' END AS entity_name
      FROM invoices i
      LEFT JOIN customers c ON c.id = i.customer_id
      LEFT JOIN suppliers s ON s.id = i.supplier_id
      LEFT JOIN transactions t ON t.description LIKE '%' || i.id || '%' AND t.description LIKE 'فاتورة%'
      WHERE i.is_return = 0 AND i.total > 0
        AND t.id IS NULL
      ORDER BY i.created_at DESC
      LIMIT ?
    ''', [limit]);
  }

  /// مصروفات بدون حساب محاسبي — orphaned expenses (no linked accounts).
  /// Returns up to [limit] rows.
  Future<List<Map<String, dynamic>>> getOrphanedExpenses(
      {int limit = 20}) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT e.id, e.title, e.amount, e.currency, e.expense_date, e.operation_type
      FROM expenses e
      WHERE (e.account_id IS NULL AND e.expense_account_id IS NULL)
      ORDER BY e.expense_date DESC
      LIMIT ?
    ''', [limit]);
  }

  /// قيود غير متوازنة — unbalanced journal entries (debit ≠ credit).
  /// Returns up to [limit] rows.
  Future<List<Map<String, dynamic>>> getUnbalancedJournals(
      {int limit = 20}) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT t.journal_id,
             COUNT(*) AS entry_count,
             SUM(t.debit) AS total_debit,
             SUM(t.credit) AS total_credit,
             SUM(t.debit) - SUM(t.credit) AS diff
      FROM transactions t
      WHERE t.journal_id IS NOT NULL
      GROUP BY t.journal_id
      HAVING ABS(SUM(t.debit) - SUM(t.credit)) > 0.01
      ORDER BY ABS(diff) DESC
      LIMIT ?
    ''', [limit]);
  }

  /// عدد القيود — total transaction count.
  Future<int> getTransactionCount() async {
    final db = await _db;
    final result =
        await db.rawQuery('SELECT COUNT(*) AS cnt FROM transactions');
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// عدد الحسابات النشطة — active account count.
  Future<int> getActiveAccountCount() async {
    final db = await _db;
    final result = await db
        .rawQuery('SELECT COUNT(*) AS cnt FROM accounts WHERE is_active = 1');
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// عدد الفواتير — total invoice count.
  Future<int> getInvoiceCount() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM invoices');
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// عدد المصروفات — total expense count.
  Future<int> getExpenseCount() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM expenses');
    return (result.first['cnt'] as int?) ?? 0;
  }
}
