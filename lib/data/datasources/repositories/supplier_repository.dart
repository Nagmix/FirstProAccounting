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

    // Strip the virtual key before updating so SQLite doesn't try to
    // write to a non-existent column.
    final updateMap = Map<String, dynamic>.from(supplierMap)
      ..remove('opening_balance_currency');

    // Create journal entry for balance change when updating supplier.
    // Run the entire update (journal entries + supplier row) inside a
    // single transaction to guarantee data integrity.
    final oldSupplier = await getSupplierById(id);
    if (oldSupplier != null && supplierMap.containsKey('balance')) {
      final oldBalance = MoneyHelper.readMoney(oldSupplier['balance']);
      final newBalance = MoneyHelper.readMoney(supplierMap['balance']);
      final oldBalanceType = oldSupplier['balance_type'] as String? ?? 'credit';
      final newBalanceType = supplierMap['balance_type'] as String? ?? oldBalanceType;

      // Convert to signed values: credit (له) = positive, debit (عليه) = negative
      final oldSigned = oldBalanceType == 'credit' ? oldBalance : -oldBalance;
      final newSigned = newBalanceType == 'credit' ? newBalance : -newBalance;
      final signedDiff = newSigned - oldSigned;

      if (signedDiff.abs() >= 0.005) {
        // Use opening_balance_currency if provided (new multi-currency flow),
        // otherwise fall back to the stored currency (legacy), then 'YER'.
        final newCurrency = supplierMap['opening_balance_currency'] as String?
            ?? supplierMap['currency'] as String?
            ?? oldSupplier['currency'] as String?
            ?? 'YER';
        final oldCurrency = oldSupplier['currency'] as String? ?? 'YER';

        // ── Handle currency change ──
        // When the opening balance currency changes, we must:
        // 1. Reverse the FULL old signed balance in the OLD currency's accounts
        // 2. Create the FULL new signed balance in the NEW currency's accounts
        // Otherwise, the old currency's accounts retain stale entries.
        final currencyChanged = newCurrency != oldCurrency;

        if (currencyChanged) {
          // Step 1: Reverse old opening balance in old currency
          final oldCodeOffset = oldCurrency == 'SAR' ? 1 : (oldCurrency == 'USD' ? 2 : 0);
          final oldSuppliersAccount = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2100 + oldCodeOffset).toString(), oldCurrency], limit: 1);
          final oldOpeningBalanceAccount = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2901 + oldCodeOffset).toString(), oldCurrency], limit: 1);
          final oldSuppliersAccountId = oldSuppliersAccount.isNotEmpty ? oldSuppliersAccount.first['id'] as int : null;
          final oldOpeningBalanceAccountId = oldOpeningBalanceAccount.isNotEmpty ? oldOpeningBalanceAccount.first['id'] as int : null;

          // Step 2: Create new opening balance in new currency
          final newCodeOffset = newCurrency == 'SAR' ? 1 : (newCurrency == 'USD' ? 2 : 0);
          final newSuppliersAccount = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2100 + newCodeOffset).toString(), newCurrency], limit: 1);
          final newOpeningBalanceAccount = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2901 + newCodeOffset).toString(), newCurrency], limit: 1);
          final newSuppliersAccountId = newSuppliersAccount.isNotEmpty ? newSuppliersAccount.first['id'] as int : null;
          final newOpeningBalanceAccountId = newOpeningBalanceAccount.isNotEmpty ? newOpeningBalanceAccount.first['id'] as int : null;

          if (oldSuppliersAccountId == null || oldOpeningBalanceAccountId == null) {
            // Old currency accounts missing — skip reversal but continue with new
          }
          if (newSuppliersAccountId == null || newOpeningBalanceAccountId == null) {
            // New currency accounts missing — cannot create new entries
            updateMap.remove('balance');
            updateMap.remove('balance_type');
            await db.update('suppliers', MoneyHelper.toCentsMap(updateMap, MoneyHelper.supplierMoneyFields), where: 'id = ?', whereArgs: [id]);
            throw Exception('لم يتم العثور على حساب الموردين (2100) أو حساب الرصيد الافتتاحي (2901) بعملة $newCurrency في شجرة الحسابات. لا يمكن تعديل الرصيد بدون قيود محاسبية.');
          }

          return await db.transaction((txn) async {
            // Reverse old signed balance in old currency
            if (oldSuppliersAccountId != null && oldOpeningBalanceAccountId != null && oldSigned.abs() >= 0.005) {
              final reverseJournalId = generateUniqueJournalId();
              if (oldSigned > 0) {
                // Old was credit (له) → reverse with debit on supplier, credit on OB
                await _insertOpeningBalanceEntry(txn, oldSuppliersAccountId, oldOpeningBalanceAccountId, reverseJournalId, oldSigned, true, 'عكس رصيد افتتاحي مورد (تغيير عملة) - ${supplierMap['name'] ?? oldSupplier['name']}', now, id);
              } else {
                // Old was debit (عليه) → reverse with credit on supplier, debit on OB
                await _insertOpeningBalanceEntry(txn, oldSuppliersAccountId, oldOpeningBalanceAccountId, reverseJournalId, oldSigned.abs(), false, 'عكس رصيد افتتاحي مورد (تغيير عملة) - ${supplierMap['name'] ?? oldSupplier['name']}', now, id);
              }
            }

            // Create new signed balance in new currency
            if (newSigned.abs() >= 0.005) {
              final newJournalId = generateUniqueJournalId();
              if (newSigned > 0) {
                // New is credit (له)
                await _insertOpeningBalanceEntry(txn, newSuppliersAccountId!, newOpeningBalanceAccountId!, newJournalId, newSigned, false, 'رصيد افتتاحي مورد (عملة جديدة) - ${supplierMap['name'] ?? oldSupplier['name']}', now, id);
              } else {
                // New is debit (عليه)
                await _insertOpeningBalanceEntry(txn, newSuppliersAccountId!, newOpeningBalanceAccountId!, newJournalId, newSigned.abs(), true, 'رصيد افتتاحي مورد (عملة جديدة) - ${supplierMap['name'] ?? oldSupplier['name']}', now, id);
              }
            }

            return await txn.update('suppliers', MoneyHelper.toCentsMap(updateMap, MoneyHelper.supplierMoneyFields), where: 'id = ?', whereArgs: [id]);
          });
        }

        // ── Same currency — simple adjustment ──
        final codeOffset = newCurrency == 'SAR' ? 1 : (newCurrency == 'USD' ? 2 : 0);
        final journalId = generateUniqueJournalId();

        final suppliersAccount = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2100 + codeOffset).toString(), newCurrency], limit: 1);
        final openingBalanceAccount = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2901 + codeOffset).toString(), newCurrency], limit: 1);

        final suppliersAccountId = suppliersAccount.isNotEmpty ? suppliersAccount.first['id'] as int : null;
        final openingBalanceAccountId = openingBalanceAccount.isNotEmpty ? openingBalanceAccount.first['id'] as int : null;

        if (suppliersAccountId != null && openingBalanceAccountId != null) {
          return await db.transaction((txn) async {
            if (signedDiff > 0) {
              // Signed balance increased (more credit/له or less debit/عليه):
              // Credit Suppliers account, Debit Opening Balance Equity
              await _insertOpeningBalanceEntry(txn, suppliersAccountId, openingBalanceAccountId, journalId, signedDiff, false, 'تعديل رصيد مورد - ${supplierMap['name'] ?? oldSupplier['name']}', now, id);
            } else {
              // Signed balance decreased (more debit/عليه or less credit/له):
              // Debit Suppliers account, Credit Opening Balance Equity
              await _insertOpeningBalanceEntry(txn, suppliersAccountId, openingBalanceAccountId, journalId, signedDiff.abs(), true, 'تعديل رصيد مورد - ${supplierMap['name'] ?? oldSupplier['name']}', now, id);
            }

            return await txn.update('suppliers', MoneyHelper.toCentsMap(updateMap, MoneyHelper.supplierMoneyFields), where: 'id = ?', whereArgs: [id]);
          });
        } else {
          // Balance changed but required accounts not found in chart of accounts.
          // Do NOT silently update the stored balance without journal entries —
          // that would break accounting integrity (computed balance from
          // getSupplierBalanceForCurrency would diverge from stored balance).
          // Instead, strip balance fields from the update so only non-balance
          // fields are saved, and throw a descriptive error.
          updateMap.remove('balance');
          updateMap.remove('balance_type');
          await db.update('suppliers', MoneyHelper.toCentsMap(updateMap, MoneyHelper.supplierMoneyFields), where: 'id = ?', whereArgs: [id]);
          throw Exception('لم يتم العثور على حساب الموردين (2100) أو حساب الرصيد الافتتاحي (2901) بعملة $newCurrency في شجرة الحسابات. لا يمكن تعديل الرصيد بدون قيود محاسبية. يرجى التأكد من إعداد الحسابات.');
        }
      }
    }

    // No balance change (or no journal entries needed) — simple update
    return await db.update('suppliers', MoneyHelper.toCentsMap(updateMap, MoneyHelper.supplierMoneyFields), where: 'id = ?', whereArgs: [id]);
  }

  /// Helper: Insert a pair of opening balance journal entries for suppliers.
  /// [isDebitSupplier] true = Debit Supplier / Credit OB, false = Credit Supplier / Debit OB
  Future<void> _insertOpeningBalanceEntry(
    Transaction txn,
    int suppliersAccountId,
    int openingBalanceAccountId,
    int journalId,
    double amount,
    bool isDebitSupplier,
    String description,
    String now,
    int supplierId,
  ) async {
    await txn.insert('transactions', {
      'account_id': suppliersAccountId,
      'journal_id': journalId,
      'debit': isDebitSupplier ? MoneyHelper.toCents(amount) : 0,
      'credit': isDebitSupplier ? 0 : MoneyHelper.toCents(amount),
      'description': description,
      'date': now,
      'created_at': now,
      'reference_type': 'opening_balance',
      'reference_id': 'supplier_$supplierId',
    });
    await txn.insert('transactions', {
      'account_id': openingBalanceAccountId,
      'journal_id': journalId,
      'debit': isDebitSupplier ? 0 : MoneyHelper.toCents(amount),
      'credit': isDebitSupplier ? MoneyHelper.toCents(amount) : 0,
      'description': description,
      'date': now,
      'created_at': now,
      'reference_type': 'opening_balance',
      'reference_id': 'supplier_$supplierId',
    });
    await _dbHelper.journal.updateAccountBalanceWithJournal(
      txn, suppliersAccountId,
      isDebitSupplier ? amount : 0.0,
      isDebitSupplier ? 0.0 : amount,
      now,
    );
    await _dbHelper.journal.updateAccountBalanceWithJournal(
      txn, openingBalanceAccountId,
      isDebitSupplier ? 0.0 : amount,
      isDebitSupplier ? amount : 0.0,
      now,
    );
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
    // Before deleting, reverse opening balance transactions to keep
    // account balances consistent. The transactions themselves are
    // left in place (audit trail) but their effect is neutralized.
    // Wrap reversal + deletion in a single transaction so that a crash
    // between the two cannot leave the books in an inconsistent state.
    return await db.transaction((txn) async {
      await _reverseOpeningBalanceOnDeleteTxn(txn, id);
      return await txn.delete('suppliers', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Reverse the accounting effect of a supplier's opening balance transactions
  /// so that deleting the supplier doesn't leave orphaned balance changes.
  /// This version works inside an existing transaction (for atomicity with deletion).
  Future<void> _reverseOpeningBalanceOnDeleteTxn(Transaction txn, int supplierId) async {
    final referenceId = 'supplier_$supplierId';
    // Find all opening balance transactions for this supplier
    final obTxns = await txn.query(
      'transactions',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['opening_balance', referenceId],
    );
    if (obTxns.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    final journalId = generateUniqueJournalId();

    // Group by account_id and reverse the net effect
    final accountNet = <int, double>{};
    for (final t in obTxns) {
      final accountId = t['account_id'] as int;
      final debit = MoneyHelper.readMoney(t['debit']);
      final credit = MoneyHelper.readMoney(t['credit']);
      // Net signed change per account: credit - debit (from the original entry)
      accountNet[accountId] = (accountNet[accountId] ?? 0.0) + (credit - debit);
    }

    // Create reversing entries
    for (final entry in accountNet.entries) {
      final accountId = entry.key;
      final netCredit = entry.value; // positive = original was credit, negative = original was debit
      if (netCredit.abs() < 0.005) continue;

      if (netCredit > 0) {
        // Original was credit → reverse with debit
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
        // Original was debit → reverse with credit
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
  }

  /// Legacy version kept for backward compatibility — wraps in its own transaction.
  Future<void> _reverseOpeningBalanceOnDelete(Database db, int supplierId) async {
    await db.transaction((txn) async {
      await _reverseOpeningBalanceOnDeleteTxn(txn, supplierId);
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
  Future<bool> isSupplierOverDebtCeiling(int supplierId, double additionalAmount, {String? currency}) async {
    final db = await _db;
    final supplier = await db.query('suppliers', where: 'id = ?', whereArgs: [supplierId], limit: 1);
    if (supplier.isEmpty) return false;

    final debtCeiling = MoneyHelper.readMoney(supplier.first['debt_ceiling']);
    if (debtCeiling <= 0) return false;

    double effectiveDebt;
    if (currency != null && currency.isNotEmpty) {
      // Use computed balance for the specific currency — accurate for multi-currency
      final signedBalance = await getSupplierBalanceForCurrency(supplierId, currency);
      // Positive signedBalance means credit (له) — we owe the supplier
      effectiveDebt = signedBalance > 0 ? signedBalance : 0.0;
    } else {
      // Fallback: use stored single-currency balance
      final currentBalance = MoneyHelper.readMoney(supplier.first['balance']);
      final balanceType = supplier.first['balance_type'] as String? ?? 'credit';
      // Only credit balance (له) counts as debt we owe the supplier.
      // Debit balance (عليه) means the supplier owes us.
      final signedBalance = balanceType == 'credit' ? currentBalance : -currentBalance;
      effectiveDebt = signedBalance > 0 ? signedBalance : 0.0;
    }
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
