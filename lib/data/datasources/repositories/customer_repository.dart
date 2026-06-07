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

    // B-04: Create journal entry for balance change when updating customer
    final oldCustomer = await getCustomerById(id);
    if (oldCustomer != null && customerMap.containsKey('balance')) {
      final oldBalance = MoneyHelper.readMoney(oldCustomer['balance']);
      final newBalance = MoneyHelper.readMoney(customerMap['balance']);
      final balanceDiff = newBalance - oldBalance;

      if (balanceDiff.abs() >= 0.005) {
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
          await db.transaction((txn) async {
            if (balanceDiff > 0) {
              // Balance increased: Debit Customers, Credit Opening Balance
              await txn.insert('transactions', {
                'account_id': customersAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(balanceDiff),
                'credit': 0,
                'description': 'تعديل رصيد عميل - ${customerMap['name'] ?? oldCustomer['name']}',
                'date': now,
                'created_at': now,
              });
              await txn.insert('transactions', {
                'account_id': openingBalanceAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(balanceDiff),
                'description': 'تعديل رصيد عميل - ${customerMap['name'] ?? oldCustomer['name']}',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, customersAccountId, balanceDiff, 0.0, now);
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, openingBalanceAccountId, 0.0, balanceDiff, now);
            } else {
              // Balance decreased: Credit Customers, Debit Opening Balance
              final absDiff = balanceDiff.abs();
              await txn.insert('transactions', {
                'account_id': customersAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(absDiff),
                'description': 'تعديل رصيد عميل - ${customerMap['name'] ?? oldCustomer['name']}',
                'date': now,
                'created_at': now,
              });
              await txn.insert('transactions', {
                'account_id': openingBalanceAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(absDiff),
                'credit': 0,
                'description': 'تعديل رصيد عميل - ${customerMap['name'] ?? oldCustomer['name']}',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, customersAccountId, 0.0, absDiff, now);
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, openingBalanceAccountId, absDiff, 0.0, now);
            }
          });
        }
      }
    }

    // Strip the virtual key before updating so SQLite doesn't try to
    // write to a non-existent column.
    final updateMap = Map<String, dynamic>.from(customerMap)
      ..remove('opening_balance_currency');
    return await db.update('customers', MoneyHelper.toCentsMap(updateMap, MoneyHelper.customerMoneyFields), where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCustomer(int id) async {
    final db = await _db;
    // Check if customer is referenced in invoices
    final refs = await db.query('invoices', where: 'customer_id = ?', whereArgs: [id], limit: 1);
    if (refs.isNotEmpty) {
      // Soft-delete not supported by schema — just prevent deletion
      return 0;
    }
    return await db.delete('customers', where: 'id = ?', whereArgs: [id]);
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
    return (currentBalance + additionalAmount) > debtCeiling;
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
    // First try: search by reference_id (new data with 'customer_{id}')
    final byRef = await db.rawQuery('''
      SELECT t.*, a.currency AS account_currency
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE t.reference_type = 'opening_balance'
        AND t.reference_id = ?
        AND a.account_code LIKE '12%'
    ''', ['customer_$customerId']);
    
    if (byRef.isNotEmpty) return byRef;
    
    // Fallback: search by description pattern (legacy data without reference_id)
    return await db.rawQuery('''
      SELECT t.*, a.currency AS account_currency
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE t.reference_type = 'opening_balance'
        AND a.account_code LIKE '12%'
        AND t.description LIKE 'رصيد افتتاحي عميل%'
      ORDER BY t.date ASC
    ''');
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

  /// Calculate the balance of a specific customer for a given currency
  /// by summing all financial movements in that currency.
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

    // 3. Vouchers
    final vouchers = await db.rawQuery('''
      SELECT voucher_type, total_amount FROM vouchers
      WHERE customer_id = ? AND currency = ?
    ''', [customerId, currency]);
    for (final v in vouchers) {
      final vType = v['voucher_type'] as String? ?? '';
      final amount = MoneyHelper.readMoney(v['total_amount']);
      if (vType == 'receipt') {
        balance += amount; // Receipt = credit (له)
      } else if (vType == 'payment') {
        balance -= amount; // Payment = debit (عليه)
      }
    }

    return balance;
  }
}
