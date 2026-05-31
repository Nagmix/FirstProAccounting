import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/utils/money_helper.dart';
import '../database_helper.dart';

class SupplierRepository {
  final DatabaseHelper _dbHelper;
  SupplierRepository(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  // ══════════════════════════════════════════════════════════════
  //  Supplier CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getAllSuppliers() async {
    final db = await _db;
    return await db.query('suppliers', orderBy: 'name ASC');
  }

  Future<int> insertSupplier(Map<String, dynamic> supplierMap) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final openingBalance = MoneyHelper.readMoney(supplierMap['balance']);
    final balanceType = supplierMap['balance_type'] as String? ?? 'credit';
    final supplierCurrency = supplierMap['currency'] as String? ?? 'YER';

    int? supplierId;
    await db.transaction((txn) async {
      supplierId = await txn.insert('suppliers', MoneyHelper.toCentsMap(supplierMap, MoneyHelper.supplierMoneyFields));

      // ── Opening Balance Journal Entry ──
      if (openingBalance > 0) {
        final journalId = DateTime.now().millisecondsSinceEpoch;
        final codeOffset = supplierCurrency == 'SAR' ? 1 : (supplierCurrency == 'USD' ? 2 : 0);

        final suppliersAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2100 + codeOffset).toString(), supplierCurrency], limit: 1);
        final openingBalanceAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2901 + codeOffset).toString(), supplierCurrency], limit: 1);

        final suppliersAccountId = suppliersAccount.isNotEmpty ? suppliersAccount.first['id'] as int : null;
        final openingBalanceAccountId = openingBalanceAccount.isNotEmpty ? openingBalanceAccount.first['id'] as int : null;

        if (suppliersAccountId != null && openingBalanceAccountId != null) {
          if (balanceType == 'credit') {
            // Supplier has credit (له) opening balance: Credit Suppliers, Debit Opening Balance Equity
            await txn.insert('transactions', {
              'account_id': suppliersAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(openingBalance),
              'description': 'رصيد افتتاحي مورد - ${supplierMap['name']}',
              'date': now,
              'created_at': now,
            });
            await txn.insert('transactions', {
              'account_id': openingBalanceAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(openingBalance),
              'credit': 0,
              'description': 'رصيد افتتاحي مورد - ${supplierMap['name']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, suppliersAccountId, 0.0, openingBalance, now);
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, openingBalanceAccountId, openingBalance, 0.0, now);
          } else {
            // Supplier has debit (عليه) opening balance: Debit Suppliers, Credit Opening Balance Equity
            await txn.insert('transactions', {
              'account_id': suppliersAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(openingBalance),
              'credit': 0,
              'description': 'رصيد افتتاحي مورد - ${supplierMap['name']}',
              'date': now,
              'created_at': now,
            });
            await txn.insert('transactions', {
              'account_id': openingBalanceAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(openingBalance),
              'description': 'رصيد افتتاحي مورد - ${supplierMap['name']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, suppliersAccountId, openingBalance, 0.0, now);
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, openingBalanceAccountId, 0.0, openingBalance, now);
          }
        }
      }
    });
    return supplierId!;
  }

  Future<List<Map<String, dynamic>>> searchSuppliers(String query) async {
    final db = await _db;
    final likeQuery = '%$query%';
    return await db.query('suppliers', where: 'name LIKE ? OR phone LIKE ?', whereArgs: [likeQuery, likeQuery], orderBy: 'name ASC');
  }

  Future<Map<String, dynamic>?> getSupplierById(int id) async {
    final db = await _db;
    final results = await db.query('suppliers', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateSupplier(int id, Map<String, dynamic> supplierMap) async {
    final db = await _db;
    return await db.update('suppliers', MoneyHelper.toCentsMap(supplierMap, MoneyHelper.supplierMoneyFields), where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteSupplier(int id) async {
    final db = await _db;
    // Check if supplier is referenced in invoices
    final refs = await db.query('invoices', where: 'supplier_id = ?', whereArgs: [id], limit: 1);
    if (refs.isNotEmpty) {
      // Soft-delete not supported by schema — just prevent deletion
      return 0;
    }
    return await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
  }

  /// Get all invoices for a specific supplier.
  Future<List<Map<String, dynamic>>> getSupplierInvoices(int supplierId) async {
    final db = await _db;
    return await db.query(
      'invoices',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'created_at DESC',
    );
  }

  /// Get all vouchers for a specific supplier.
  Future<List<Map<String, dynamic>>> getSupplierVouchers(int supplierId) async {
    final db = await _db;
    return await db.query(
      'vouchers',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'date DESC',
    );
  }

  /// Get all financial movements for a supplier (invoices + vouchers) sorted by date.
  Future<List<Map<String, dynamic>>> getSupplierMovements(int supplierId) async {
    final db = await _db;

    // Get invoices for this supplier
    final invoices = await db.query(
      'invoices',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'created_at DESC',
    );

    // Get vouchers for this supplier
    final vouchers = await db.query(
      'vouchers',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'date DESC',
    );

    // Tag each entry with its source
    final movements = <Map<String, dynamic>>[];
    for (final inv in invoices) {
      movements.add({
        ...inv,
        '_source': 'invoice',
        '_sort_date': inv['created_at'] ?? '',
      });
    }
    for (final v in vouchers) {
      movements.add({
        ...v,
        '_source': 'voucher',
        '_sort_date': v['date'] ?? v['created_at'] ?? '',
      });
    }

    // Sort by date descending
    movements.sort((a, b) {
      final dateA = a['_sort_date'] as String? ?? '';
      final dateB = b['_sort_date'] as String? ?? '';
      return dateB.compareTo(dateA);
    });

    return movements;
  }

  /// التحقق من تجاوز سقف الدين للمورد
  Future<bool> isSupplierOverDebtCeiling(int supplierId, double additionalAmount) async {
    final db = await _db;
    final supplier = await db.query('suppliers', where: 'id = ?', whereArgs: [supplierId], limit: 1);
    if (supplier.isEmpty) return false;

    final debtCeiling = MoneyHelper.readMoney(supplier.first['debt_ceiling']);
    if (debtCeiling <= 0) return false;

    final currentBalance = MoneyHelper.readMoney(supplier.first['balance']);
    return (currentBalance + additionalAmount) > debtCeiling;
  }
}
