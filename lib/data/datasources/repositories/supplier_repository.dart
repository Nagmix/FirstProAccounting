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
    final invRefs = await db.query('invoices', where: 'supplier_id = ?', whereArgs: [id], limit: 1);
    if (invRefs.isNotEmpty) {
      return 0;
    }
    // Check if supplier is referenced in vouchers
    final vchRefs = await db.query('vouchers', where: 'supplier_id = ?', whereArgs: [id], limit: 1);
    if (vchRefs.isNotEmpty) {
      return 0;
    }
    // Reverse opening balance transactions before deletion
    await _reverseOpeningBalanceOnDelete(db, id);
    return await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
  }

  /// Reverse the accounting effect of a supplier's opening balance transactions
  /// so that deleting the supplier doesn't leave orphaned balance changes.
  Future<void> _reverseOpeningBalanceOnDelete(Database db, int supplierId) async {
    final referenceId = 'supplier_$supplierId';
    final obTxns = await db.query(
      'transactions',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['opening_balance', referenceId],
    );
    if (obTxns.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    final journalId = generateUniqueJournalId();

    final accountNet = <int, double>{};
    for (final txn in obTxns) {
      final accountId = txn['account_id'] as int;
      final debit = MoneyHelper.readMoney(txn['debit']);
      final credit = MoneyHelper.readMoney(txn['credit']);
      accountNet[accountId] = (accountNet[accountId] ?? 0.0) + (credit - debit);
    }

    await db.transaction((txn) async {
      for (final entry in accountNet.entries) {
        final accountId = entry.key;
        final netCredit = entry.value;
        if (netCredit.abs() < 0.005) continue;

        if (netCredit > 0) {
          await txn.insert('transactions', {
            'account_id': accountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(netCredit),
            'credit': 0,
            'description': 'عكس قيد افتتاحي مورد محذوف - ID:$supplierId',
            'date': now,
            'created_at': now,
            'reference_type': 'opening_balance_reversal',
            'reference_id': referenceId,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, accountId, netCredit, 0.0, now);
        } else {
          final absAmount = netCredit.abs();
          await txn.insert('transactions', {
            'account_id': accountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(absAmount),
            'description': 'عكس قيد افتتاحي مورد محذوف - ID:$supplierId',
            'date': now,
            'created_at': now,
            'reference_type': 'opening_balance_reversal',
            'reference_id': referenceId,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, accountId, 0.0, absAmount, now);
        }
      }
    });
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
    // Search by reference_id — each supplier's opening balance is tagged
    // with reference_id = 'supplier_{id}' at creation time.
    // The old fallback query that searched by description pattern without
    // filtering by reference_id was returning ALL suppliers' opening
    // balance entries for any supplier that had none of its own.
    return await db.rawQuery('''
      SELECT t.*, a.currency AS account_currency
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE t.reference_type = 'opening_balance'
        AND t.reference_id = ?
        AND a.account_code LIKE '21%'
      ORDER BY t.date ASC
    ''', ['supplier_$supplierId']);
  }

  /// التحقق من تجاوز سقف الدين للمورد
  Future<bool> isSupplierOverDebtCeiling(int supplierId, double additionalAmount) async {
    final db = await _db;
    final supplier = await db.query('suppliers', where: 'id = ?', whereArgs: [supplierId], limit: 1);
    if (supplier.isEmpty) return false;

    final debtCeiling = MoneyHelper.readMoney(supplier.first['debt_ceiling']);
    if (debtCeiling <= 0) return false;

    final currentBalance = MoneyHelper.readMoney(supplier.first['balance']);
    final balanceType = supplier.first['balance_type'] as String? ?? 'credit';
    // Only credit balance (له) counts as debt we owe the supplier.
    // Debit balance (عليه) means the supplier owes us.
    final signedBalance = balanceType == 'credit' ? currentBalance : -currentBalance;
    final effectiveDebt = signedBalance > 0 ? signedBalance : 0.0;
    return (effectiveDebt + additionalAmount) > debtCeiling;
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

    // 3. Vouchers — use voucher_items joined with the supplier's
    //    payable account (code 21xx) to determine the actual
    //    debit/credit effect regardless of voucher type.
    //    This correctly handles settlement, compound, and transfer
    //    vouchers where the supplier account may be on either side.
    final voucherNet = await db.rawQuery('''
      SELECT COALESCE(SUM(vi.credit), 0) - COALESCE(SUM(vi.debit), 0) AS net
      FROM vouchers v
      INNER JOIN voucher_items vi ON v.id = vi.voucher_id
      INNER JOIN accounts a ON vi.account_id = a.id
      WHERE v.supplier_id = ?
        AND v.currency = ?
        AND a.account_code LIKE '21%'
    ''', [supplierId, currency]);
    balance += MoneyHelper.readCalculatedMoney(voucherNet.first['net']);

    return balance;
  }

  /// جلب حسابات الموردين لجميع العملات — find supplier payable accounts
  /// across all supported currencies.
  Future<List<Map<String, dynamic>>> getSupplierPayableAccountsAllCurrencies() async {
    final db = await _db;
    return await db.rawQuery(
      "SELECT id, currency FROM accounts WHERE name_ar LIKE ? AND account_type = 'LIABILITY' AND account_code LIKE '21%'",
      ['%الموردين%'],
    );
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
