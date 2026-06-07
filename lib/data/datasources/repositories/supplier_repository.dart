import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/utils/journal_id_helper.dart';
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
    // Currency is now specific to the opening balance entry only, NOT the supplier.
    final openingBalanceCurrency = supplierMap['opening_balance_currency'] as String? ?? 'YER';

    // Remove opening_balance_currency from supplier map before insert (it's not a supplier column)
    supplierMap.remove('opening_balance_currency');

    int? supplierId;
    await db.transaction((txn) async {
      supplierId = await txn.insert('suppliers', MoneyHelper.toCentsMap(supplierMap, MoneyHelper.supplierMoneyFields));

      // ── Opening Balance Journal Entry ──
      if (openingBalance > 0) {
        final journalId = generateUniqueJournalId();
        final codeOffset = openingBalanceCurrency == 'SAR' ? 1 : (openingBalanceCurrency == 'USD' ? 2 : 0);

        final suppliersAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2100 + codeOffset).toString(), openingBalanceCurrency], limit: 1);
        final openingBalanceAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2901 + codeOffset).toString(), openingBalanceCurrency], limit: 1);

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
              'reference_type': 'opening_balance',
              'reference_id': 'supplier_$supplierId',
            });
            await txn.insert('transactions', {
              'account_id': openingBalanceAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(openingBalance),
              'credit': 0,
              'description': 'رصيد افتتاحي مورد - ${supplierMap['name']}',
              'date': now,
              'created_at': now,
              'reference_type': 'opening_balance',
              'reference_id': 'supplier_$supplierId',
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
              'reference_type': 'opening_balance',
              'reference_id': 'supplier_$supplierId',
            });
            await txn.insert('transactions', {
              'account_id': openingBalanceAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(openingBalance),
              'description': 'رصيد افتتاحي مورد - ${supplierMap['name']}',
              'date': now,
              'created_at': now,
              'reference_type': 'opening_balance',
              'reference_id': 'supplier_$supplierId',
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
    final now = DateTime.now().toIso8601String();

    // Currency for opening balance journal entry — separate from the supplier record
    final openingBalanceCurrency = supplierMap['opening_balance_currency'] as String? ?? 'YER';

    // Remove opening_balance_currency from supplier map before update (it's not a supplier column)
    supplierMap.remove('opening_balance_currency');

    // Create journal entry for balance change when updating supplier
    final oldSupplier = await getSupplierById(id);
    if (oldSupplier != null && supplierMap.containsKey('balance')) {
      final oldBalance = MoneyHelper.readMoney(oldSupplier['balance']);
      final newBalance = MoneyHelper.readMoney(supplierMap['balance']);
      final balanceDiff = newBalance - oldBalance;

      if (balanceDiff.abs() >= 0.005) {
        // Use opening_balance_currency for the journal entry, falling back to the old supplier currency if needed
        final journalCurrency = openingBalanceCurrency.isNotEmpty
            ? openingBalanceCurrency
            : (oldSupplier['currency'] as String? ?? 'YER');
        final codeOffset = journalCurrency == 'SAR' ? 1 : (journalCurrency == 'USD' ? 2 : 0);
        final journalId = generateUniqueJournalId();

        final suppliersAccount = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2100 + codeOffset).toString(), journalCurrency], limit: 1);
        final openingBalanceAccount = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2901 + codeOffset).toString(), journalCurrency], limit: 1);

        final suppliersAccountId = suppliersAccount.isNotEmpty ? suppliersAccount.first['id'] as int : null;
        final openingBalanceAccountId = openingBalanceAccount.isNotEmpty ? openingBalanceAccount.first['id'] as int : null;

        if (suppliersAccountId != null && openingBalanceAccountId != null) {
          await db.transaction((txn) async {
            if (balanceDiff > 0) {
              // Balance increased: Credit Suppliers, Debit Opening Balance
              await txn.insert('transactions', {
                'account_id': suppliersAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(balanceDiff),
                'description': 'تعديل رصيد مورد - ${supplierMap['name'] ?? oldSupplier['name']}',
                'date': now,
                'created_at': now,
                'reference_type': 'opening_balance',
                'reference_id': 'supplier_$id',
              });
              await txn.insert('transactions', {
                'account_id': openingBalanceAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(balanceDiff),
                'credit': 0,
                'description': 'تعديل رصيد مورد - ${supplierMap['name'] ?? oldSupplier['name']}',
                'date': now,
                'created_at': now,
                'reference_type': 'opening_balance',
                'reference_id': 'supplier_$id',
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, suppliersAccountId, 0.0, balanceDiff, now);
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, openingBalanceAccountId, balanceDiff, 0.0, now);
            } else {
              // Balance decreased: Debit Suppliers, Credit Opening Balance
              final absDiff = balanceDiff.abs();
              await txn.insert('transactions', {
                'account_id': suppliersAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(absDiff),
                'credit': 0,
                'description': 'تعديل رصيد مورد - ${supplierMap['name'] ?? oldSupplier['name']}',
                'date': now,
                'created_at': now,
                'reference_type': 'opening_balance',
                'reference_id': 'supplier_$id',
              });
              await txn.insert('transactions', {
                'account_id': openingBalanceAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(absDiff),
                'description': 'تعديل رصيد مورد - ${supplierMap['name'] ?? oldSupplier['name']}',
                'date': now,
                'created_at': now,
                'reference_type': 'opening_balance',
                'reference_id': 'supplier_$id',
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, suppliersAccountId, absDiff, 0.0, now);
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, openingBalanceAccountId, 0.0, absDiff, now);
            }
          });
        }
      }
    }

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

  /// جلب معاملات القيد الافتتاحي للمورد — find opening balance transactions
  /// linked to this supplier via reference_id.
  /// Returns transaction rows with account currency info.
  Future<List<Map<String, dynamic>>> getSupplierOpeningBalanceTransactions(int supplierId) async {
    final db = await _db;
    // First try: search by reference_id (new data with 'supplier_{id}')
    final byRef = await db.rawQuery('''
      SELECT t.*, a.currency AS account_currency
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE t.reference_type = 'opening_balance'
        AND t.reference_id = ?
        AND a.account_code LIKE '21%'
    ''', ['supplier_$supplierId']);
    
    if (byRef.isNotEmpty) return byRef;
    
    // Fallback: search by description pattern (legacy data without reference_id)
    return await db.rawQuery('''
      SELECT t.*, a.currency AS account_currency
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE t.reference_type = 'opening_balance'
        AND a.account_code LIKE '21%'
        AND t.description LIKE 'رصيد افتتاحي مورد%'
      ORDER BY t.date ASC
    ''');
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

  // ══════════════════════════════════════════════════════════════
  //  Supplier detail / ledger query methods
  //  Extracted from supplier_detail_screen.dart — raw SQL, no MoneyHelper.
  //  All monetary values are returned as raw DB values.
  //  The caller is responsible for converting using
  //  MoneyHelper.readMoney / readCalculatedMoney.
  // ══════════════════════════════════════════════════════════════

  /// جلب رصيد المورد بعملة معينة — get supplier balance for a specific currency.
  /// Combines opening balance, invoices, and vouchers for the given currency.
  Future<double> getSupplierBalanceForCurrency(int supplierId, String currency) async {
    final db = await _db;
    double balance = 0.0;

    // 1. Opening balance
    final obByRef = await db.rawQuery('''
      SELECT COALESCE(SUM(t.credit), 0) - COALESCE(SUM(t.debit), 0) AS net
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE t.reference_type = 'opening_balance'
        AND t.reference_id = ?
        AND a.account_code LIKE '21%'
        AND a.currency = ?
    ''', ['supplier_$supplierId', currency]);
    balance += MoneyHelper.readCalculatedMoney(obByRef.first['net']);

    // 2. Invoices
    final invoices = await db.rawQuery('''
      SELECT type, is_return, total FROM invoices
      WHERE supplier_id = ? AND currency = ?
    ''', [supplierId, currency]);
    for (final inv in invoices) {
      final type = inv['type'] as String? ?? 'purchase';
      final isReturn = (inv['is_return'] as int? ?? 0) == 1;
      final total = MoneyHelper.readMoney(inv['total']);
      if (type == 'purchase' && !isReturn) {
        balance += total; // Purchase = credit (له)
      } else if (type == 'purchase' && isReturn) {
        balance -= total; // Purchase return = debit (عليه)
      } else if (type == 'sale' && !isReturn) {
        balance -= total; // Sale = debit (عليه)
      } else if (type == 'sale' && isReturn) {
        balance += total; // Sale return = credit (له)
      }
    }

    // 3. Vouchers
    final vouchers = await db.rawQuery('''
      SELECT voucher_type, total_amount FROM vouchers
      WHERE supplier_id = ? AND currency = ?
    ''', [supplierId, currency]);
    for (final v in vouchers) {
      final vType = v['voucher_type'] as String? ?? '';
      final amount = MoneyHelper.readMoney(v['total_amount']);
      if (vType == 'payment') {
        balance -= amount; // Payment = debit (عليه)
      } else if (vType == 'receipt') {
        balance += amount; // Receipt = credit (له)
      }
    }

    return balance;
  }

  /// جلب حسابات الموردين — find supplier payable accounts by currency.
  /// Returns account rows with matching name pattern.
  Future<List<Map<String, dynamic>>> getSupplierPayableAccounts(String currency) async {
    final db = await _db;
    return await db.rawQuery(
      "SELECT id FROM accounts WHERE name_ar LIKE ? AND account_type = 'LIABILITY' AND currency = ?",
      ['%الموردين%', currency],
    );
  }
}
