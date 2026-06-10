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

      // Look up exchange rate for the customer's currency
      double customerExchangeRate = 1.0;
      if (customerCurrency != 'YER') {
        final curRows = await txn.query('currencies', where: 'code = ?', whereArgs: [customerCurrency], limit: 1);
        customerExchangeRate = curRows.isNotEmpty ? (curRows.first['exchange_rate'] as num?)?.toDouble() ?? 1.0 : 1.0;
      }
      final customerBaseAmount = customerCurrency == 'YER' ? openingBalance : openingBalance * customerExchangeRate;

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
              'currency_code': customerCurrency,
              'exchange_rate': customerExchangeRate,
              'amount_base': MoneyHelper.toCents(customerBaseAmount),
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
              'currency_code': customerCurrency,
              'exchange_rate': customerExchangeRate,
              'amount_base': MoneyHelper.toCents(customerBaseAmount),
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
              'currency_code': customerCurrency,
              'exchange_rate': customerExchangeRate,
              'amount_base': MoneyHelper.toCents(customerBaseAmount),
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
              'currency_code': customerCurrency,
              'exchange_rate': customerExchangeRate,
              'amount_base': MoneyHelper.toCents(customerBaseAmount),
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
        final newCurrency = customerMap['opening_balance_currency'] as String?
            ?? customerMap['currency'] as String?
            ?? oldCustomer['currency'] as String?
            ?? 'YER';
        final oldCurrency = oldCustomer['currency'] as String? ?? 'YER';

        // ── Handle currency change ──
        // When the opening balance currency changes, we must:
        // 1. Reverse the FULL old signed balance in the OLD currency's accounts
        // 2. Create the FULL new signed balance in the NEW currency's accounts
        // Otherwise, the old currency's accounts retain stale entries.
        final currencyChanged = newCurrency != oldCurrency;

        if (currencyChanged) {
          // Step 1: Reverse old opening balance in old currency
          final oldCodeOffset = oldCurrency == 'SAR' ? 1 : (oldCurrency == 'USD' ? 2 : 0);
          final oldCustomersAccount = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1200 + oldCodeOffset).toString(), oldCurrency], limit: 1);
          final oldOpeningBalanceAccount = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2901 + oldCodeOffset).toString(), oldCurrency], limit: 1);
          final oldCustomersAccountId = oldCustomersAccount.isNotEmpty ? oldCustomersAccount.first['id'] as int : null;
          final oldOpeningBalanceAccountId = oldOpeningBalanceAccount.isNotEmpty ? oldOpeningBalanceAccount.first['id'] as int : null;

          // Step 2: Create new opening balance in new currency
          final newCodeOffset = newCurrency == 'SAR' ? 1 : (newCurrency == 'USD' ? 2 : 0);
          final newCustomersAccount = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1200 + newCodeOffset).toString(), newCurrency], limit: 1);
          final newOpeningBalanceAccount = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2901 + newCodeOffset).toString(), newCurrency], limit: 1);
          final newCustomersAccountId = newCustomersAccount.isNotEmpty ? newCustomersAccount.first['id'] as int : null;
          final newOpeningBalanceAccountId = newOpeningBalanceAccount.isNotEmpty ? newOpeningBalanceAccount.first['id'] as int : null;

          if (oldCustomersAccountId == null || oldOpeningBalanceAccountId == null) {
            // Old currency accounts missing — skip reversal but continue with new
            // (the old entries may have been manually removed or never created)
          }
          if (newCustomersAccountId == null || newOpeningBalanceAccountId == null) {
            // New currency accounts missing — cannot create new entries
            updateMap.remove('balance');
            updateMap.remove('balance_type');
            await db.update('customers', MoneyHelper.toCentsMap(updateMap, MoneyHelper.customerMoneyFields), where: 'id = ?', whereArgs: [id]);
            throw Exception('لم يتم العثور على حساب العملاء (1200) أو حساب الرصيد الافتتاحي (2901) بعملة $newCurrency في شجرة الحسابات. لا يمكن تعديل الرصيد بدون قيود محاسبية.');
          }

          return await db.transaction((txn) async {
            // Look up exchange rates for old and new currencies
            double oldExchangeRate = 1.0;
            if (oldCurrency != 'YER') {
              final curRows = await txn.query('currencies', where: 'code = ?', whereArgs: [oldCurrency], limit: 1);
              oldExchangeRate = curRows.isNotEmpty ? (curRows.first['exchange_rate'] as num?)?.toDouble() ?? 1.0 : 1.0;
            }
            double newExchangeRate = 1.0;
            if (newCurrency != 'YER') {
              final curRows = await txn.query('currencies', where: 'code = ?', whereArgs: [newCurrency], limit: 1);
              newExchangeRate = curRows.isNotEmpty ? (curRows.first['exchange_rate'] as num?)?.toDouble() ?? 1.0 : 1.0;
            }

            // Reverse old signed balance in old currency
            if (oldCustomersAccountId != null && oldOpeningBalanceAccountId != null && oldSigned.abs() >= 0.005) {
              final reverseJournalId = generateUniqueJournalId();
              if (oldSigned > 0) {
                // Old was credit → reverse with debit on customer, credit on OB
                await _insertOpeningBalanceEntry(txn, oldCustomersAccountId, oldOpeningBalanceAccountId, reverseJournalId, oldSigned, true, 'عكس رصيد افتتاحي عميل (تغيير عملة) - ${customerMap['name'] ?? oldCustomer['name']}', now, id, oldCurrency, oldExchangeRate);
              } else {
                // Old was debit → reverse with credit on customer, debit on OB
                await _insertOpeningBalanceEntry(txn, oldCustomersAccountId, oldOpeningBalanceAccountId, reverseJournalId, oldSigned.abs(), false, 'عكس رصيد افتتاحي عميل (تغيير عملة) - ${customerMap['name'] ?? oldCustomer['name']}', now, id, oldCurrency, oldExchangeRate);
              }
            }

            // Create new signed balance in new currency
            if (newSigned.abs() >= 0.005) {
              final newJournalId = generateUniqueJournalId();
              if (newSigned > 0) {
                // New is credit (له)
                await _insertOpeningBalanceEntry(txn, newCustomersAccountId, newOpeningBalanceAccountId, newJournalId, newSigned, false, 'رصيد افتتاحي عميل (عملة جديدة) - ${customerMap['name'] ?? oldCustomer['name']}', now, id, newCurrency, newExchangeRate);
              } else {
                // New is debit (عليه)
                await _insertOpeningBalanceEntry(txn, newCustomersAccountId, newOpeningBalanceAccountId, newJournalId, newSigned.abs(), true, 'رصيد افتتاحي عميل (عملة جديدة) - ${customerMap['name'] ?? oldCustomer['name']}', now, id, newCurrency, newExchangeRate);
              }
            }

            return await txn.update('customers', MoneyHelper.toCentsMap(updateMap, MoneyHelper.customerMoneyFields), where: 'id = ?', whereArgs: [id]);
          });
        }

        // ── Same currency — simple adjustment ──
        final codeOffset = newCurrency == 'SAR' ? 1 : (newCurrency == 'USD' ? 2 : 0);
        final journalId = generateUniqueJournalId();

        final customersAccount = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1200 + codeOffset).toString(), newCurrency], limit: 1);
        final openingBalanceAccount = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2901 + codeOffset).toString(), newCurrency], limit: 1);

        final customersAccountId = customersAccount.isNotEmpty ? customersAccount.first['id'] as int : null;
        final openingBalanceAccountId = openingBalanceAccount.isNotEmpty ? openingBalanceAccount.first['id'] as int : null;

        if (customersAccountId != null && openingBalanceAccountId != null) {
          return await db.transaction((txn) async {
            // Look up exchange rate for the currency
            double exchangeRate = 1.0;
            if (newCurrency != 'YER') {
              final curRows = await txn.query('currencies', where: 'code = ?', whereArgs: [newCurrency], limit: 1);
              exchangeRate = curRows.isNotEmpty ? (curRows.first['exchange_rate'] as num?)?.toDouble() ?? 1.0 : 1.0;
            }

            if (signedDiff > 0) {
              // Signed balance increased (more credit/له or less debit/عليه):
              // Credit Customers account, Debit Opening Balance Equity
              await _insertOpeningBalanceEntry(txn, customersAccountId, openingBalanceAccountId, journalId, signedDiff, false, 'تعديل رصيد عميل - ${customerMap['name'] ?? oldCustomer['name']}', now, id, newCurrency, exchangeRate);
            } else {
              // Signed balance decreased (more debit/عليه or less credit/له):
              // Debit Customers account, Credit Opening Balance Equity
              await _insertOpeningBalanceEntry(txn, customersAccountId, openingBalanceAccountId, journalId, signedDiff.abs(), true, 'تعديل رصيد عميل - ${customerMap['name'] ?? oldCustomer['name']}', now, id, newCurrency, exchangeRate);
            }

            return await txn.update('customers', MoneyHelper.toCentsMap(updateMap, MoneyHelper.customerMoneyFields), where: 'id = ?', whereArgs: [id]);
          });
        } else {
          // Balance changed but required accounts not found in chart of accounts.
          // Do NOT silently update the stored balance without journal entries —
          // that would break accounting integrity (computed balance from
          // getCustomerBalanceForCurrency would diverge from stored balance).
          // Instead, strip balance fields from the update so only non-balance
          // fields are saved, and throw a descriptive error.
          updateMap.remove('balance');
          updateMap.remove('balance_type');
          await db.update('customers', MoneyHelper.toCentsMap(updateMap, MoneyHelper.customerMoneyFields), where: 'id = ?', whereArgs: [id]);
          throw Exception('لم يتم العثور على حساب العملاء (1200) أو حساب الرصيد الافتتاحي (2901) بعملة $newCurrency في شجرة الحسابات. لا يمكن تعديل الرصيد بدون قيود محاسبية. يرجى التأكد من إعداد الحسابات.');
        }
      }
    }

    // No balance change (or no journal entries needed) — simple update
    return await db.update('customers', MoneyHelper.toCentsMap(updateMap, MoneyHelper.customerMoneyFields), where: 'id = ?', whereArgs: [id]);
  }

  /// Helper: Insert a pair of opening balance journal entries.
  /// [isDebitCustomer] true = Debit Customer / Credit OB, false = Credit Customer / Debit OB
  /// [currencyCode] the currency of the transaction
  /// [exchangeRate] the exchange rate to convert to base currency (YER)
  Future<void> _insertOpeningBalanceEntry(
    Transaction txn,
    int customersAccountId,
    int openingBalanceAccountId,
    int journalId,
    double amount,
    bool isDebitCustomer,
    String description,
    String now,
    int customerId,
    String currencyCode,
    double exchangeRate,
  ) async {
    final baseAmount = currencyCode == 'YER' ? amount : amount * exchangeRate;
    await txn.insert('transactions', {
      'account_id': customersAccountId,
      'journal_id': journalId,
      'debit': isDebitCustomer ? MoneyHelper.toCents(amount) : 0,
      'credit': isDebitCustomer ? 0 : MoneyHelper.toCents(amount),
      'description': description,
      'date': now,
      'created_at': now,
      'reference_type': 'opening_balance',
      'reference_id': 'customer_$customerId',
      'currency_code': currencyCode,
      'exchange_rate': exchangeRate,
      'amount_base': MoneyHelper.toCents(baseAmount),
    });
    await txn.insert('transactions', {
      'account_id': openingBalanceAccountId,
      'journal_id': journalId,
      'debit': isDebitCustomer ? 0 : MoneyHelper.toCents(amount),
      'credit': isDebitCustomer ? MoneyHelper.toCents(amount) : 0,
      'description': description,
      'date': now,
      'created_at': now,
      'reference_type': 'opening_balance',
      'reference_id': 'customer_$customerId',
      'currency_code': currencyCode,
      'exchange_rate': exchangeRate,
      'amount_base': MoneyHelper.toCents(baseAmount),
    });
    await _dbHelper.journal.updateAccountBalanceWithJournal(
      txn, customersAccountId,
      isDebitCustomer ? amount : 0.0,
      isDebitCustomer ? 0.0 : amount,
      now,
    );
    await _dbHelper.journal.updateAccountBalanceWithJournal(
      txn, openingBalanceAccountId,
      isDebitCustomer ? 0.0 : amount,
      isDebitCustomer ? amount : 0.0,
      now,
    );
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
    // Wrap reversal + deletion in a single transaction so that a crash
    // between the two cannot leave the books in an inconsistent state.
    return await db.transaction((txn) async {
      await _reverseOpeningBalanceOnDeleteTxn(txn, id);
      return await txn.delete('customers', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Reverse the accounting effect of a customer's opening balance transactions
  /// so that deleting the customer doesn't leave orphaned balance changes.
  /// This version works inside an existing transaction (for atomicity with deletion).
  Future<void> _reverseOpeningBalanceOnDeleteTxn(Transaction txn, int customerId) async {
    final referenceId = 'customer_$customerId';
    // Find all opening balance transactions for this customer
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

    // Pre-fetch currencies table for exchange rate lookups
    final currenciesRows = await txn.query('currencies');
    final currencyRates = <String, double>{'YER': 1.0};
    for (final c in currenciesRows) {
      final code = c['code'] as String? ?? '';
      final rate = (c['exchange_rate'] as num?)?.toDouble() ?? 1.0;
      if (code.isNotEmpty) currencyRates[code] = rate;
    }

    // Create reversing entries
    for (final entry in accountNet.entries) {
      final accountId = entry.key;
      final netCredit = entry.value; // positive = original was credit, negative = original was debit
      if (netCredit.abs() < 0.005) continue;

      // Look up the account's currency for currency_code and exchange_rate
      final accountRow = await txn.query('accounts', where: 'id = ?', whereArgs: [accountId], limit: 1);
      final accountCurrency = accountRow.isNotEmpty ? (accountRow.first['currency'] as String? ?? 'YER') : 'YER';
      final accountExchangeRate = currencyRates[accountCurrency] ?? 1.0;
      final baseAmount = accountCurrency == 'YER' ? netCredit.abs() : netCredit.abs() * accountExchangeRate;

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
          'currency_code': accountCurrency,
          'exchange_rate': accountExchangeRate,
          'amount_base': MoneyHelper.toCents(baseAmount),
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
          'currency_code': accountCurrency,
          'exchange_rate': accountExchangeRate,
          'amount_base': MoneyHelper.toCents(baseAmount),
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, accountId, 0.0, absAmount, now);
      }
    }
  }

  Future<int> getCustomerCount() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM customers');
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<bool> isCustomerOverDebtCeiling(int customerId, double additionalAmount, {String? currency}) async {
    final db = await _db;
    final customer = await db.query('customers', where: 'id = ?', whereArgs: [customerId], limit: 1);
    if (customer.isEmpty) return false;

    final debtCeiling = MoneyHelper.readMoney(customer.first['debt_ceiling']);
    if (debtCeiling <= 0) return false; // لا يوجد سقف محدد

    double effectiveDebt;
    if (currency != null && currency.isNotEmpty) {
      // Use computed balance for the specific currency — accurate for multi-currency
      final signedBalance = await getCustomerBalanceForCurrency(customerId, currency);
      // Negative signedBalance means debit (عليه) — customer owes us
      effectiveDebt = signedBalance < 0 ? signedBalance.abs() : 0.0;
    } else {
      // Fallback: use stored single-currency balance
      final currentBalance = MoneyHelper.readMoney(customer.first['balance']);
      final balanceType = customer.first['balance_type'] as String? ?? 'credit';
      // Only debit balance (عليه) counts as debt that the customer owes us.
      // Credit balance (له) means we owe the customer, so it reduces their debt.
      final signedBalance = balanceType == 'debit' ? currentBalance : -currentBalance;
      // signedBalance > 0 means customer owes us; < 0 means we owe customer
      effectiveDebt = signedBalance > 0 ? signedBalance : 0.0;
    }
    return (effectiveDebt + additionalAmount) > debtCeiling;
  }

  /// Get top customer balances, separated by currency.
  ///
  /// FIX: Previous version ordered by raw `balance` across all currencies,
  /// which incorrectly compared YER cents against USD cents against SAR cents.
  /// Now returns results grouped by currency, ordered within each currency.
  Future<List<Map<String, dynamic>>> getTopCustomerBalances(int limit) async {
    final db = await _db;
    // Get distinct currencies first
    final currencies = await db.rawQuery(
      'SELECT DISTINCT currency FROM customers WHERE balance > 0 AND currency IS NOT NULL',
    );
    final results = <Map<String, dynamic>>[];
    for (final cur in currencies) {
      final currency = cur['currency'] as String? ?? 'YER';
      final rows = await db.rawQuery('''
        SELECT name, balance, balance_type, currency
        FROM customers
        WHERE balance > 0 AND currency = ?
        ORDER BY balance DESC
        LIMIT ?
      ''', [currency, limit]);
      results.addAll(rows);
    }
    return results;
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
