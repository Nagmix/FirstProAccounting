import 'package:sqflite_sqlcipher/sqflite.dart';

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
    final customerCurrency = customerMap['currency'] as String? ?? 'YER';

    int? customerId;
    await db.transaction((txn) async {
      customerId = await txn.insert('customers', MoneyHelper.toCentsMap(customerMap, MoneyHelper.customerMoneyFields));

      // ── Opening Balance Journal Entry ──
      if (openingBalance > 0) {
        final journalId = DateTime.now().millisecondsSinceEpoch;
        final codeOffset = customerCurrency == 'SAR' ? 1 : (customerCurrency == 'USD' ? 2 : 0);

        final customersAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1200 + codeOffset).toString(), customerCurrency], limit: 1);
        final openingBalanceAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2200 + codeOffset).toString(), customerCurrency], limit: 1);

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
            });
            await txn.insert('transactions', {
              'account_id': openingBalanceAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(openingBalance),
              'description': 'رصيد افتتاحي عميل - ${customerMap['name']}',
              'date': now,
              'created_at': now,
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
            });
            await txn.insert('transactions', {
              'account_id': openingBalanceAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(openingBalance),
              'credit': 0,
              'description': 'رصيد افتتاحي عميل - ${customerMap['name']}',
              'date': now,
              'created_at': now,
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
    return await db.update('customers', MoneyHelper.toCentsMap(customerMap, MoneyHelper.customerMoneyFields), where: 'id = ?', whereArgs: [id]);
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
}
