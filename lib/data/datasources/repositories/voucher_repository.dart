import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/services/cash_box_service.dart';

class VoucherRepository {
  final DatabaseHelper _dbHelper;
  VoucherRepository(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  /// Save a voucher with its journal entries and update account/cash box balances.
  ///
  /// This method delegates to [CashBoxService.insertVoucher] which handles:
  /// - Fiscal period validation
  /// - Debit/credit balance check
  /// - Transaction insertion with journal entries
  /// - Account balance updates
  /// - Cash box balance updates
  /// - Customer/supplier balance updates
  Future<int> saveVoucherWithJournalEntry(
    Map<String, dynamic> voucherMap,
    List<Map<String, dynamic>> items,
  ) async {
    return await _dbHelper.cashBoxes.insertVoucher(voucherMap, items);
  }

  /// Get an account by its ID.
  ///
  /// Returns the account map or null if not found.
  Future<Map<String, dynamic>?> getAccountById(int accountId) async {
    final db = await _db;
    final results = await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }
}
