import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/utils/journal_id_helper.dart';
import '../../../core/utils/money_helper.dart';
import '../../models/customer_model.dart';
import '../database_helper.dart';

class CustomerRepository {
  final DatabaseHelper _dbHelper;
  CustomerRepository(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  // ══════════════════════════════════════════════════════════════
  //  Customer CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertCustomer(Map<String, dynamic> customerMap) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final openingBalance = MoneyHelper.readMoney(customerMap['balance']);
    final balanceType = customerMap['balance_type'] as String? ?? 'credit';
    // opening_balance_currency is a virtual key used only for the journal
    // entry — it is NOT stored in the customers table. Fall back to the
    // customer's currency field (for legacy callers) then to 'YER'.
    final customerCurrency = customerMap['opening_balance_currency'] as String?
        ?? customerMap['currency'] as String?
        ?? 'YER';

    int? customerId;
    await db.transaction((txn) async {
      // Strip the virtual key before inserting into the DB so SQLite
      // doesn't try to write to a non-existent column.
      final insertMap = Map<String, dynamic>.from(customerMap)
        ..remove('opening_balance_currency');
      customerId = await txn.insert('customers', MoneyHelper.toCentsMap(insertMap, MoneyHelper.customerMoneyFields));

      // ── Opening Balance Journal Entry ──
      if (openingBalance > 0) {
        final journalId = generateUniqueJournalId();
        final codeOffset = customerCurrency == 'SAR' ? 1 : (customerCurrency == 'USD' ? 2 : 0);
        final referenceId = 'customer_$customerId';

        final customersAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1200 + codeOffset).toString(), customerCurrency], limit: 1);
        final openingBalanceAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2901 + codeOffset).toString(), customerCurrency], limit: 1);

        final customersAccountId = customersAccount.isNotEmpty ? customersAccount.first['id'] as int : null;
        final openingBalanceAccountId = openingBalanceAccount.isNotEmpty ? openingBalanceAccount.first['id'] as int : null;

        if (customersAccountId != null && openingBalanceAccountId != null) {
          if (balanceType == 'debit') {
            // Customer has debit (عليه) opening balance: Debit Customers, Credit Opening Balance Equity
            await txn.insert('transactions', {
              'account_id': customersAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(openingBalance),
              'credit': 0,
              'description': 'رصيد افتتاحي عميل - ${customerMap['name']}',
              'date': now,
              'created_at': now,
              'reference_type': 'opening_balance',
              'reference_id': referenceId,
            });
            await txn.insert('transactions', {
              'account_id': openingBalanceAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(openingBalance),
              'description': 'رصيد افتتاحي عميل - ${customerMap['name']}',
              'date': now,
              'created_at': now,
              'reference_type': 'opening_balance',
              'reference_id': referenceId,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, customersAccountId, openingBalance, 0.0, now);
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, openingBalanceAccountId, 0.0, openingBalance, now);
          } else {
            // Customer has credit (له) opening balance: Credit Customers, Debit Opening Balance Equity
            await txn.insert('transactions', {
              'account_id': customersAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(openingBalance),
              'description': 'رصيد افتتاحي عميل - ${customerMap['name']}',
              'date': now,
              'created_at': now,
              'reference_type': 'opening_balance',
              'reference_id': referenceId,
            });
            await txn.insert('transactions', {
              'account_id': openingBalanceAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(openingBalance),
              'credit': 0,
              'description': 'رصيد افتتاحي عميل - ${customerMap['name']}',
              'date': now,
              'created_at': now,
              'reference_type': 'opening_balance',
              'reference_id': referenceId,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, customersAccountId, 0.0, openingBalance, now);
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, openingBalanceAccountId, openingBalance, 0.0, now);
          }
        }
      }
    });
    return customerId!;
  }

  Future<List<Map<String, dynamic>>> getAllCustomers({String orderBy = 'name', int? limit, int offset = 0}) async {
    final db = await _db;
    return await db.query('customers', orderBy: orderBy, limit: limit, offset: offset > 0 ? offset : null);
  }

  Future<List<Map<String, dynamic>>> searchCustomers(String query) async {
    final db = await _db;
    final likeQuery = '%$query%';
    return await db.query('customers', where: 'name LIKE ? OR phone LIKE ?', whereArgs: [likeQuery, likeQuery], orderBy: 'created_at DESC');
  }

  Future<Map<String, dynamic>?> getCustomerById(int id) async {
    final db = await _db;
    final results = await db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateCustomer(int id, Map<String, dynamic> customerMap) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    // Strip the virtual key before updating so SQLite doesn't try to
    // write to a non-existent column.
    final updateMap = Map<String, dynamic>.from(customerMap)
      ..remove('opening_balance_currency');

    // B-04: Create journal entry for balance change when updating customer.
    // Run the entire update (journal entries + customer row) inside a
    // single transaction to guarantee data integrity.
    final oldCustomer = await getCustomerById(id);
    if (oldCustomer != null && customerMap.containsKey('balance')) {
      final oldBalance = MoneyHelper.readMoney(oldCustomer['balance']);
      final newBalance = MoneyHelper.readMoney(customerMap['balance']);
      final oldBalanceType = oldCustomer['balance_type'] as String? ?? 'credit';
      final newBalanceType = customerMap['balance_type'] as String? ?? oldBalanceType;

      // Convert to signed values: credit (له) = positive, debit (عليه) = negative
      final oldSigned = oldBalanceType == 'credit' ? oldBalance : -oldBalance;
      final newSigned = newBalanceType == 'credit' ? newBalance : -newBalance;
      final signedDiff = newSigned - oldSigned;

      if (signedDiff.abs() >= 0.005) {
        // Use opening_balance_currency if provided (new multi-currency flow),
        // otherwise fall back to the stored currency (legacy), then 'YER'.
        final customerCurrency = customerMap['opening_balance_currency'] as String?
            ?? customerMap['currency'] as String?
            ?? oldCustomer['currency'] as String?
            ?? 'YER';
        final codeOffset = customerCurrency == 'SAR' ? 1 : (customerCurrency == 'USD' ? 2 : 0);
        final journalId = generateUniqueJournalId();

        final customersAccount = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1200 + codeOffset).toString(), customerCurrency], limit: 1);
        final openingBalanceAccount = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2901 + codeOffset).toString(), customerCurrency], limit: 1);

        final customersAccountId = customersAccount.isNotEmpty ? customersAccount.first['id'] as int : null;
        final openingBalanceAccountId = openingBalanceAccount.isNotEmpty ? openingBalanceAccount.first['id'] as int : null;

        if (customersAccountId != null && openingBalanceAccountId != null) {
          // Wrap both journal entries AND the customer row update in one
          // transaction so that a failure in either rolls everything back.
          return await db.transaction((txn) async {
            if (signedDiff > 0) {
              // Signed balance increased (more credit/له or less debit/عليه):
              // Credit Customers account, Debit Opening Balance Equity
              await txn.insert('transactions', {
                'account_id': customersAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(signedDiff),
                'description': 'تعديل رصيد عميل - ${customerMap['name'] ?? oldCustomer['name']}',
                'date': now,
                'created_at': now,
                'reference_type': 'opening_balance',
                'reference_id': 'customer_$id',
              });
              await txn.insert('transactions', {
                'account_id': openingBalanceAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(signedDiff),
                'credit': 0,
                'description': 'تعديل رصيد عميل - ${customerMap['name'] ?? oldCustomer['name']}',
                'date': now,
                'created_at': now,
                'reference_type': 'opening_balance',
                'reference_id': 'customer_$id',
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, customersAccountId, 0.0, signedDiff, now);
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, openingBalanceAccountId, signedDiff, 0.0, now);
            } else {
              // Signed balance decreased (more debit/عليه or less credit/له):
              // Debit Customers account, Credit Opening Balance Equity
              final absDiff = signedDiff.abs();
              await txn.insert('transactions', {
                'account_id': customersAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(absDiff),
                'credit': 0,
                'description': 'تعديل رصيد عميل - ${customerMap['name'] ?? oldCustomer['name']}',
                'date': now,
                'created_at': now,
                'reference_type': 'opening_balance',
                'reference_id': 'customer_$id',
              });
              await txn.insert('transactions', {
                'account_id': openingBalanceAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(absDiff),
                'description': 'تعديل رصيد عميل - ${customerMap['name'] ?? oldCustomer['name']}',
                'date': now,
                'created_at': now,
                'reference_type': 'opening_balance',
                'reference_id': 'customer_$id',
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, customersAccountId, absDiff, 0.0, now);
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, openingBalanceAccountId, 0.0, absDiff, now);
            }

            // Update the customer row INSIDE the same transaction
            return await txn.update('customers', MoneyHelper.toCentsMap(updateMap, MoneyHelper.customerMoneyFields), where: 'id = ?', whereArgs: [id]);
          });
        }
      }
    }

    // No balance change (or no journal entries needed) — simple update
    return await db.update('customers', MoneyHelper.toCentsMap(updateMap, MoneyHelper.customerMoneyFields), where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCustomer(int id) async {
    final db = await _db;
    // Check if customer is referenced in invoices
    final invRefs = await db.query('invoices', where: 'customer_id = ?', whereArgs: [id], limit: 1);
    if (invRefs.isNotEmpty) {
      // Soft-delete not supported by schema — just prevent deletion
      return 0;
    }
    // Check if customer is referenced in vouchers
    final vchRefs = await db.query('vouchers', where: 'customer_id = ?', whereArgs: [id], limit: 1);
    if (vchRefs.isNotEmpty) {
      return 0;
    }
    // Check if customer is referenced in quotations
    try {
      final quotRefs = await db.query('quotations', where: 'customer_id = ?', whereArgs: [id], limit: 1);
      if (quotRefs.isNotEmpty) {
        return 0;
      }
    } catch (_) {
      // quotations table may not exist in older schemas
    }
    // Check if customer is referenced in sales orders
    try {
      final orderRefs = await db.query('sales_orders', where: 'customer_id = ?', whereArgs: [id], limit: 1);
      if (orderRefs.isNotEmpty) {
        return 0;
      }
    } catch (_) {
      // sales_orders table may not exist in older schemas
    }
    // Before deleting, reverse opening balance transactions to keep
    // account balances consistent. The transactions themselves are
    // left in place (audit trail) but their effect is neutralized.
    await _reverseOpeningBalanceOnDelete(db, id);
    return await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  /// Reverse the accounting effect of a customer's opening balance transactions
  /// so that deleting the customer doesn't leave orphaned balance changes.
  Future<void> _reverseOpeningBalanceOnDelete(Database db, int customerId) async {
    final referenceId = 'customer_$customerId';
    // Find all opening balance transactions for this customer
    final obTxns = await db.query(
      'transactions',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['opening_balance', referenceId],
    );
    if (obTxns.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    final journalId = generateUniqueJournalId();

    // Group by account_id and reverse the net effect
    final accountNet = <int, double>{};
    for (final txn in obTxns) {
      final accountId = txn['account_id'] as int;
      final debit = MoneyHelper.readMoney(txn['debit']);
      final credit = MoneyHelper.readMoney(txn['credit']);
      // Net signed change per account: credit - debit (from the original entry)
      accountNet[accountId] = (accountNet[accountId] ?? 0.0) + (credit - debit);
    }

    // Create reversing entries
    await db.transaction((txn) async {
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
            'description': 'عكس قيد افتتاحي عميل محذوف - ID:$customerId',
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
            'description': 'عكس قيد افتتاحي عميل محذوف - ID:$customerId',
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

  Future<int> getCustomerCount() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM customers');
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<bool> isCustomerOverDebtCeiling(int customerId, double additionalAmount) async {
    final db = await _db;
    final customer = await db.query('customers', where: 'id = ?', whereArgs: [customerId], limit: 1);
    if (customer.isEmpty) return false;

    final debtCeiling = MoneyHelper.readMoney(customer.first['debt_ceiling']);
    if (debtCeiling <= 0) return false; // لا يوجد سقف محدد

    final currentBalance = MoneyHelper.readMoney(customer.first['balance']);
    final balanceType = customer.first['balance_type'] as String? ?? 'credit';
    // Only debit balance (عليه) counts as debt that the customer owes us.
    // Credit balance (له) means we owe the customer, so it reduces their debt.
    final signedBalance = balanceType == 'debit' ? currentBalance : -currentBalance;
    // signedBalance > 0 means customer owes us; < 0 means we owe customer
    final effectiveDebt = signedBalance > 0 ? signedBalance : 0.0;
    return (effectiveDebt + additionalAmount) > debtCeiling;
  }

  Future<List<Map<String, dynamic>>> getTopCustomerBalances(int limit) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT name, balance, balance_type, currency
      FROM customers
      WHERE balance > 0
      ORDER BY balance DESC
      LIMIT ?
    ''', [limit]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Typed getters (C-09: domain model alternatives to raw maps)
  // ══════════════════════════════════════════════════════════════

  Future<List<Customer>> getAllCustomerObjects({String orderBy = 'name', int? limit, int offset = 0}) async {
    final maps = await getAllCustomers(orderBy: orderBy, limit: limit, offset: offset);
    return maps.map((m) => Customer.fromMap(m)).toList();
  }

  Future<List<Customer>> searchCustomerObjects(String query) async {
    final maps = await searchCustomers(query);
    return maps.map((m) => Customer.fromMap(m)).toList();
  }

  Future<Customer?> getCustomerObjectById(int id) async {
    final map = await getCustomerById(id);
    return map != null ? Customer.fromMap(map) : null;
  }

  // ══════════════════════════════════════════════════════════════
  //  Customer detail / ledger query methods
  //  Extracted from customer_detail_screen.dart — raw SQL, no MoneyHelper.
  //  All monetary values are returned as raw DB values.
  //  The caller is responsible for converting using
  //  MoneyHelper.readMoney / readCalculatedMoney.
  // ══════════════════════════════════════════════════════════════

  /// جلب فواتير العميل — all invoices for a specific customer, ordered by date.
  /// Returns raw invoice rows.
  Future<List<Map<String, dynamic>>> getCustomerInvoices(int customerId) async {
    final db = await _db;
    return await db.rawQuery(
      'SELECT * FROM invoices WHERE customer_id = ? ORDER BY created_at ASC',
      [customerId],
    );
  }

  /// جلب سندات العميل — all vouchers linked to a specific customer.
  /// Returns raw voucher rows.
  Future<List<Map<String, dynamic>>> getCustomerVouchers(int customerId) async {
    final db = await _db;
    return await db.rawQuery(
      'SELECT * FROM vouchers WHERE customer_id = ? ORDER BY date ASC',
      [customerId],
    );
  }

  /// جلب حسابات العملاء — find customer receivable accounts by currency.
  /// Returns account rows with matching name pattern.
  Future<List<Map<String, dynamic>>> getCustomerReceivableAccounts(String currency) async {
    final db = await _db;
    return await db.rawQuery(
      "SELECT id FROM accounts WHERE name_ar LIKE ? AND account_type = 'ASSET' AND currency = ?",
      ['%العملاء%', currency],
    );
  }

  /// جلب معاملات القيد الافتتاحي للعميل — find opening balance transactions
  /// linked to this customer via reference_id.
  /// Returns transaction rows with account currency info.
  Future<List<Map<String, dynamic>>> getCustomerOpeningBalanceTransactions(int customerId) async {
    final db = await _db;
    // Search by reference_id — each customer's opening balance is tagged
    // with reference_id = 'customer_{id}' at creation time.
    // The old fallback query that searched by description pattern without
    // filtering by reference_id was returning ALL customers' opening
    // balance entries for any customer that had none of its own.
    return await db.rawQuery('''
      SELECT t.*, a.currency AS account_currency
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE t.reference_type = 'opening_balance'
        AND t.reference_id = ?
        AND a.account_code LIKE '12%'
      ORDER BY t.date ASC
    ''', ['customer_$customerId']);
  }

  /// جلب السندات غير المرتبطة — find unlinked vouchers (NULL customer_id)
  /// that reference a customer's receivable account.
  /// Returns raw voucher rows.
  Future<List<Map<String, dynamic>>> getUnlinkedVouchers() async {
    final db = await _db;
    return await db.rawQuery(
      'SELECT * FROM vouchers WHERE customer_id IS NULL ORDER BY date ASC',
    );
  }

  /// جلب حسابات العملاء لجميع العملات — find customer receivable accounts
  /// across all supported currencies.
  Future<List<Map<String, dynamic>>> getCustomerReceivableAccountsAllCurrencies() async {
    final db = await _db;
    return await db.rawQuery(
      "SELECT id, currency FROM accounts WHERE name_ar LIKE ? AND account_type = 'ASSET' AND account_code LIKE '12%'",
      ['%العملاء%'],
    );
  }

  /// Calculate the balance of a specific customer for a given currency
  /// by summing all financial movements in that currency.
  /// Uses voucher_items to determine debit/credit effect for ALL voucher
  /// types (receipt, payment, settlement, compound, transfers), not just
  /// receipt and payment.
  Future<double> getCustomerBalanceForCurrency(int customerId, String currency) async {
    final db = await _db;
    double balance = 0.0;

    // 1. Opening balance for this customer in this currency
    final obByRef = await db.rawQuery('''
      SELECT COALESCE(SUM(t.credit), 0) - COALESCE(SUM(t.debit), 0) AS net
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE t.reference_type = 'opening_balance'
        AND t.reference_id = ?
        AND a.account_code LIKE '12%'
        AND a.currency = ?
    ''', ['customer_$customerId', currency]);
    balance += MoneyHelper.readCalculatedMoney(obByRef.first['net']);

    // 2. Invoices
    final invoices = await db.rawQuery('''
      SELECT type, is_return, total FROM invoices
      WHERE customer_id = ? AND currency = ?
    ''', [customerId, currency]);
    for (final inv in invoices) {
      final type = inv['type'] as String? ?? 'sale';
      final isReturn = (inv['is_return'] as int? ?? 0) == 1;
      final total = MoneyHelper.readMoney(inv['total']);
      if (type == 'sale' && !isReturn) {
        balance -= total; // Sale = debit (عليه)
      } else if (type == 'sale' && isReturn) {
        balance += total; // Return = credit (له)
      } else if (type == 'purchase' && !isReturn) {
        balance += total; // Purchase = credit (له)
      } else if (type == 'purchase' && isReturn) {
        balance -= total; // Purchase return = debit (عليه)
      }
    }

    // 3. Vouchers — use voucher_items joined with the customer's
    //    receivable account (code 12xx) to determine the actual
    //    debit/credit effect regardless of voucher type.
    //    This correctly handles settlement, compound, and transfer
    //    vouchers where the customer account may be on either side.
    final voucherNet = await db.rawQuery('''
      SELECT COALESCE(SUM(vi.credit), 0) - COALESCE(SUM(vi.debit), 0) AS net
      FROM vouchers v
      INNER JOIN voucher_items vi ON v.id = vi.voucher_id
      INNER JOIN accounts a ON vi.account_id = a.id
      WHERE v.customer_id = ?
        AND v.currency = ?
        AND a.account_code LIKE '12%'
    ''', [customerId, currency]);
    balance += MoneyHelper.readCalculatedMoney(voucherNet.first['net']);

    return balance;
  }
}
