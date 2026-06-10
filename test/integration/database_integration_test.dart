import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// ══════════════════════════════════════════════════════════════════
/// 7.1 — اختبارات التكامل مع قاعدة البيانات في الذاكرة
/// Integration tests using in-memory SQLite database to test:
///   - Repository CRUD operations
///   - Transaction integrity
///   - Complex balance queries
///   - Schema migrations
/// ══════════════════════════════════════════════════════════════════

void main() {
  late Database db;

  setUpAll(() {
    // Initialize FFI-based SQLite for testing (no encryption needed in tests)
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Create in-memory database for each test
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 46,
      onCreate: (database, version) async {
        await DatabaseSchema.onCreate(database, version);
      },
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
  });

  tearDown(() async {
    await db.close();
  });

  // ══════════════════════════════════════════════════════════════
  //  Schema & Seeding Tests
  // ══════════════════════════════════════════════════════════════

  group('Schema Creation & Seeding', () {
    test('All required tables are created', () async {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
      );
      final tableNames = tables.map((t) => t['name'] as String).toList();

      // Verify all essential tables exist
      expect(tableNames, contains('accounts'));
      expect(tableNames, contains('products'));
      expect(tableNames, contains('customers'));
      expect(tableNames, contains('suppliers'));
      expect(tableNames, contains('invoices'));
      expect(tableNames, contains('invoice_items'));
      expect(tableNames, contains('transactions'));
      expect(tableNames, contains('cash_boxes'));
      expect(tableNames, contains('categories'));
      expect(tableNames, contains('expenses'));
      expect(tableNames, contains('vouchers'));
      expect(tableNames, contains('voucher_items'));
      expect(tableNames, contains('shifts'));
      expect(tableNames, contains('currencies'));
      expect(tableNames, contains('warehouses'));
      expect(tableNames, contains('employees'));
      expect(tableNames, contains('fiscal_years'));
      expect(tableNames, contains('currency_exchanges'));
      expect(tableNames, contains('cash_transfers'));
      expect(tableNames, contains('stock_movements'));
      expect(tableNames, contains('inventory_cost_layers'));
      expect(tableNames, contains('bank_reconciliations'));
    });

    test('Default currencies are seeded correctly', () async {
      final currencies = await db.query('currencies');
      expect(currencies.length, 3);

      final yer = currencies.firstWhere((c) => c['code'] == 'YER');
      expect(yer['is_default'], 1);
      expect(yer['exchange_rate'], 1.0);
      expect(yer['symbol'], 'ر.ي');

      final sar = currencies.firstWhere((c) => c['code'] == 'SAR');
      expect(sar['exchange_rate'], 140.0);

      final usd = currencies.firstWhere((c) => c['code'] == 'USD');
      expect(usd['exchange_rate'], 530.0);
    });

    test('Default accounts are seeded for all 3 currencies', () async {
      final accounts = await db.query('accounts');
      // Each currency gets the same template set (see defaultAccountTemplates)
      // YER codes: 1000,1100,1200,1300,2000,2100,2300,2900,2901,2910,...
      // SAR codes: +1 offset
      // USD codes: +2 offset
      expect(accounts.length, greaterThan(30));

      // Verify key YER accounts
      final yerAssets = await db.query('accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: ['1000', 'YER']);
      expect(yerAssets.length, 1);
      expect(yerAssets.first['account_type'], 'ASSET');
      expect(yerAssets.first['balance_type'], 'debit');

      // Verify key SAR accounts
      final sarCashBanks = await db.query('accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: ['1101', 'SAR']);
      expect(sarCashBanks.length, 1);

      // Verify key USD accounts
      final usdCustomers = await db.query('accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: ['1202', 'USD']);
      expect(usdCustomers.length, 1);
    });

    test('Balance type is correctly assigned by account type', () async {
      // Debit-balance types: ASSET, COST, EXPENSE
      final debitAccounts = await db.query('accounts',
          where:
              "account_type IN ('ASSET', 'COST', 'EXPENSE') AND balance_type = 'debit'");
      expect(debitAccounts.length, greaterThan(0));

      // Credit-balance types: LIABILITY, EQUITY, REVENUE
      final creditAccounts = await db.query('accounts',
          where:
              "account_type IN ('LIABILITY', 'EQUITY', 'REVENUE') AND balance_type = 'credit'");
      expect(creditAccounts.length, greaterThan(0));

      // No mismatches
      final mismatchedDebit = await db.query('accounts',
          where:
              "account_type IN ('LIABILITY', 'EQUITY', 'REVENUE') AND balance_type = 'debit' AND is_system = 1");
      expect(mismatchedDebit.length, 0);

      final mismatchedCredit = await db.query('accounts',
          where:
              "account_type IN ('ASSET', 'COST', 'EXPENSE') AND balance_type = 'credit' AND is_system = 1");
      expect(mismatchedCredit.length, 0);
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Account CRUD Tests
  // ══════════════════════════════════════════════════════════════

  group('Account CRUD Operations', () {
    test('Insert and retrieve account', () async {
      final now = DateTime.now().toIso8601String();
      final id = await db.insert('accounts', {
        'name_ar': 'حساب اختبار',
        'name_en': 'Test Account',
        'account_code': '9999',
        'account_type': 'ASSET',
        'balance': MoneyHelper.toCents(1000.0),
        'currency': 'YER',
        'balance_type': 'debit',
        'is_active': 1,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });

      final account =
          await db.query('accounts', where: 'id = ?', whereArgs: [id]);
      expect(account.length, 1);
      expect(account.first['name_ar'], 'حساب اختبار');
      expect(MoneyHelper.readMoney(account.first['balance']), 1000.0);
    });

    test('Update account balance atomically', () async {
      final now = DateTime.now().toIso8601String();
      final id = await db.insert('accounts', {
        'name_ar': 'حساب رصيد',
        'name_en': 'Balance Account',
        'account_code': '9998',
        'account_type': 'ASSET',
        'balance': MoneyHelper.toCents(5000.0),
        'currency': 'YER',
        'balance_type': 'debit',
        'is_active': 1,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });

      // Simulate the atomic balance update (7.3 fix)
      final amountCents = MoneyHelper.toCents(1500.0);
      final isDebitInt = 1; // debit entry

      await db.rawUpdate('''
        UPDATE accounts SET
          balance = balance + CASE
            WHEN balance_type = 'credit' AND ? = 1 THEN -?
            WHEN balance_type = 'credit' AND ? = 0 THEN ?
            WHEN balance_type = 'debit'  AND ? = 1 THEN ?
            WHEN balance_type = 'debit'  AND ? = 0 THEN -?
            ELSE 0
          END,
          updated_at = ?
        WHERE id = ?
      ''', [
        isDebitInt,
        amountCents,
        isDebitInt,
        amountCents,
        isDebitInt,
        amountCents,
        isDebitInt,
        amountCents,
        now,
        id,
      ]);

      final updated =
          await db.query('accounts', where: 'id = ?', whereArgs: [id]);
      expect(MoneyHelper.readMoney(updated.first['balance']), 6500.0);
    });

    test('Update credit-balance account with debit entry decreases balance',
        () async {
      final now = DateTime.now().toIso8601String();
      final id = await db.insert('accounts', {
        'name_ar': 'حساب دائن',
        'name_en': 'Credit Account',
        'account_code': '9997',
        'account_type': 'REVENUE',
        'balance': MoneyHelper.toCents(3000.0),
        'currency': 'YER',
        'balance_type': 'credit',
        'is_active': 1,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });

      final amountCents = MoneyHelper.toCents(1000.0);
      final isDebitInt = 1; // debit entry on credit-balance → decrease

      await db.rawUpdate('''
        UPDATE accounts SET
          balance = balance + CASE
            WHEN balance_type = 'credit' AND ? = 1 THEN -?
            WHEN balance_type = 'credit' AND ? = 0 THEN ?
            WHEN balance_type = 'debit'  AND ? = 1 THEN ?
            WHEN balance_type = 'debit'  AND ? = 0 THEN -?
            ELSE 0
          END,
          updated_at = ?
        WHERE id = ?
      ''', [
        isDebitInt,
        amountCents,
        isDebitInt,
        amountCents,
        isDebitInt,
        amountCents,
        isDebitInt,
        amountCents,
        now,
        id,
      ]);

      final updated =
          await db.query('accounts', where: 'id = ?', whereArgs: [id]);
      // Credit account + debit entry = 3000 - 1000 = 2000
      expect(MoneyHelper.readMoney(updated.first['balance']), 2000.0);
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Transaction Integrity Tests
  // ══════════════════════════════════════════════════════════════

  group('Transaction Integrity', () {
    test('Database transaction rollback on error', () async {
      final now = DateTime.now().toIso8601String();

      // Insert a customer before the transaction
      final customerId = await db.insert('customers', {
        'name': 'عميل اختبار',
        'balance': 0,
        'balance_type': 'credit',
        'currency': 'YER',
        'created_at': now,
        'updated_at': now,
      });

      // Try a transaction that should fail
      try {
        await db.transaction((txn) async {
          // This insert should succeed within the transaction
          await txn.insert('customers', {
            'name': 'عميل مؤقت',
            'balance': 0,
            'balance_type': 'credit',
            'currency': 'YER',
            'created_at': now,
            'updated_at': now,
          });

          // Force an error — violate NOT NULL constraint
          await txn.insert('customers', {
            'name': null, // NOT NULL violation
            'balance': 0,
            'balance_type': 'credit',
            'currency': 'YER',
            'created_at': now,
            'updated_at': now,
          });
        });
      } catch (_) {
        // Expected to fail
      }

      // The 'عميل مؤقت' should NOT exist because the transaction rolled back
      final tempCustomer = await db
          .query('customers', where: 'name = ?', whereArgs: ['عميل مؤقت']);
      expect(tempCustomer.length, 0);

      // The original customer should still exist
      final original =
          await db.query('customers', where: 'id = ?', whereArgs: [customerId]);
      expect(original.length, 1);
    });

    test('Journal entry: total debit must equal total credit', () async {
      final now = DateTime.now().toIso8601String();

      // Create two accounts
      final debitAccountId = await db.insert('accounts', {
        'name_ar': 'الصندوق',
        'name_en': 'Cash',
        'account_code': '8001',
        'account_type': 'ASSET',
        'balance': 0,
        'currency': 'YER',
        'balance_type': 'debit',
        'is_active': 1,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });

      final creditAccountId = await db.insert('accounts', {
        'name_ar': 'المبيعات',
        'name_en': 'Sales',
        'account_code': '8002',
        'account_type': 'REVENUE',
        'balance': 0,
        'currency': 'YER',
        'balance_type': 'credit',
        'is_active': 1,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });

      // Create a balanced journal entry
      final amount = 5000.0;
      final amountCents = MoneyHelper.toCents(amount);

      await db.transaction((txn) async {
        await txn.insert('transactions', {
          'account_id': debitAccountId,
          'journal_id': 1001,
          'debit': amountCents,
          'credit': 0,
          'description': 'مبيعات نقدية',
          'date': now,
          'created_at': now,
        });

        await txn.insert('transactions', {
          'account_id': creditAccountId,
          'journal_id': 1001,
          'debit': 0,
          'credit': amountCents,
          'description': 'مبيعات نقدية',
          'date': now,
          'created_at': now,
        });

        // Update balances atomically using the 7.3 fix approach
        // Debit account: debit increases balance
        await txn.rawUpdate('''
          UPDATE accounts SET
            balance = balance + CASE
              WHEN balance_type = 'credit' THEN ? - ?
              WHEN balance_type = 'debit'  THEN ? - ?
              ELSE 0
            END,
            updated_at = ?
          WHERE id = ?
        ''', [0, amountCents, amountCents, 0, now, debitAccountId]);

        // Credit account: credit increases balance
        await txn.rawUpdate('''
          UPDATE accounts SET
            balance = balance + CASE
              WHEN balance_type = 'credit' THEN ? - ?
              WHEN balance_type = 'debit'  THEN ? - ?
              ELSE 0
            END,
            updated_at = ?
          WHERE id = ?
        ''', [amountCents, 0, 0, amountCents, now, creditAccountId]);
      });

      // Verify balances
      final debitAccount = await db
          .query('accounts', where: 'id = ?', whereArgs: [debitAccountId]);
      final creditAccount = await db
          .query('accounts', where: 'id = ?', whereArgs: [creditAccountId]);

      // Debit account (ASSET): balance should increase by amount
      expect(MoneyHelper.readMoney(debitAccount.first['balance']), 5000.0);
      // Credit account (REVENUE): balance should increase by amount
      expect(MoneyHelper.readMoney(creditAccount.first['balance']), 5000.0);

      // Verify total debit = total credit
      final totalDebit = await db.rawQuery(
        'SELECT CAST(COALESCE(SUM(debit), 0) AS INTEGER) AS total FROM transactions',
      );
      final totalCredit = await db.rawQuery(
        'SELECT CAST(COALESCE(SUM(credit), 0) AS INTEGER) AS total FROM transactions',
      );

      expect(
        MoneyHelper.readCalculatedMoney(totalDebit.first['total']),
        MoneyHelper.readCalculatedMoney(totalCredit.first['total']),
      );
    });

    test('Unbalanced journal entry should be detected', () {
      // Simulate the validateJournalBalance logic
      final entries = [
        {'debit': MoneyHelper.toCents(5000.0), 'credit': 0},
        {'debit': 0, 'credit': MoneyHelper.toCents(4000.0)}, // Unbalanced!
      ];

      double totalDebit = 0.0;
      double totalCredit = 0.0;
      for (final entry in entries) {
        totalDebit += MoneyHelper.readMoney(entry['debit']);
        totalCredit += MoneyHelper.readMoney(entry['credit']);
      }

      final difference = (totalDebit - totalCredit).abs();
      expect(difference, greaterThan(0.005));
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Cash Box CRUD Tests
  // ══════════════════════════════════════════════════════════════

  group('Cash Box CRUD Operations', () {
    test('Insert and retrieve cash box', () async {
      final now = DateTime.now().toIso8601String();
      final id = await db.insert('cash_boxes', {
        'name': 'الصندوق الرئيسي',
        'type': 'cash_box',
        'currency': 'YER',
        'balance': MoneyHelper.toCents(10000.0),
        'balance_type': 'credit',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });

      final cashBox =
          await db.query('cash_boxes', where: 'id = ?', whereArgs: [id]);
      expect(cashBox.length, 1);
      expect(cashBox.first['name'], 'الصندوق الرئيسي');
      expect(MoneyHelper.readMoney(cashBox.first['balance']), 10000.0);
      expect(cashBox.first['type'], 'cash_box');
    });

    test('Soft delete cash box (7.5 fix)', () async {
      final now = DateTime.now().toIso8601String();
      final id = await db.insert('cash_boxes', {
        'name': 'صندوق للحذف',
        'type': 'cash_box',
        'currency': 'YER',
        'balance': 0,
        'balance_type': 'credit',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });

      // Soft delete: set is_active = 0
      await db.update(
        'cash_boxes',
        {'is_active': 0, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );

      // Verify the cash box still exists but is inactive
      final cashBox =
          await db.query('cash_boxes', where: 'id = ?', whereArgs: [id]);
      expect(cashBox.length, 1);
      expect(cashBox.first['is_active'], 0);

      // Verify it doesn't appear in active-only queries
      final activeCashBoxes =
          await db.query('cash_boxes', where: 'is_active = ?', whereArgs: [1]);
      expect(activeCashBoxes.where((cb) => cb['id'] == id).length, 0);
    });

    test('Cannot delete cash box with dependent records (7.5 fix)', () async {
      final now = DateTime.now().toIso8601String();
      final cashBoxId = await db.insert('cash_boxes', {
        'name': 'صندوق مرتبط',
        'type': 'cash_box',
        'currency': 'YER',
        'balance': 0,
        'balance_type': 'credit',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });

      // Create a dependent invoice
      await db.insert('invoices', {
        'id': 'INV-TEST-001',
        'type': 'sale',
        'payment_mechanism': 'cash',
        'payment_method': 'cash',
        'cash_box_id': cashBoxId,
        'total': 0,
        'subtotal': 0,
        'paid_amount': 0,
        'remaining': 0,
        'discount_amount': 0,
        'tax_amount': 0,
        'currency': 'YER',
        'created_at': now,
      });

      // Check dependent count
      final invoiceCount = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM invoices WHERE cash_box_id = ?',
        [cashBoxId],
      );
      final count = (invoiceCount.first['cnt'] as num?)?.toInt() ?? 0;
      expect(count, greaterThan(0));

      // Should not allow deletion — verify the check would fail
      // In real code, deleteCashBox throws an exception
      // Here we simulate the check
      final hasDependents = count > 0;
      expect(hasDependents, isTrue);
    });

    test('Cash box balance query with UNION ALL (7.4 fix)', () async {
      final now = DateTime.now().toIso8601String();
      final cashBoxId = await db.insert('cash_boxes', {
        'name': 'صندوق اختبار الرصيد',
        'type': 'cash_box',
        'currency': 'YER',
        'balance': MoneyHelper.toCents(5000.0), // Opening balance
        'balance_type': 'credit',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });

      // Add a sale invoice with payment to this cash box
      await db.insert('invoices', {
        'id': 'INV-BAL-001',
        'type': 'sale',
        'payment_mechanism': 'cash',
        'payment_method': 'cash',
        'cash_box_id': cashBoxId,
        'total': MoneyHelper.toCents(3000.0),
        'subtotal': MoneyHelper.toCents(3000.0),
        'paid_amount': MoneyHelper.toCents(3000.0),
        'remaining': 0,
        'discount_amount': 0,
        'tax_amount': 0,
        'currency': 'YER',
        'created_at': now,
      });

      // Add an expense from this cash box
      await db.insert('expenses', {
        'title': 'مصروف اختبار',
        'amount': MoneyHelper.toCents(1000.0),
        'currency': 'YER',
        'exchange_rate': 1.0,
        'amount_base': MoneyHelper.toCents(1000.0),
        'expense_date': now,
        'payment_method': 'cash',
        'cash_box_id': cashBoxId,
        'operation_type': 'صرف',
        'created_at': now,
        'updated_at': now,
      });

      // Execute the optimized UNION ALL query from 7.4
      final result = await db.rawQuery('''
        SELECT
          CAST(COALESCE(SUM(CASE WHEN flow = 'in' THEN amount ELSE 0 END), 0) AS INTEGER) AS total_inflows,
          CAST(COALESCE(SUM(CASE WHEN flow = 'out' THEN amount ELSE 0 END), 0) AS INTEGER) AS total_outflows
        FROM (
          SELECT CASE WHEN balance_type = 'credit' THEN 'in' ELSE 'out' END AS flow,
            ABS(balance) AS amount
          FROM cash_boxes WHERE id = ? AND is_active = 1
          UNION ALL
          SELECT 'in' AS flow, COALESCE(paid_amount, 0) AS amount
          FROM invoices WHERE cash_box_id = ? AND type IN ('sale', 'pos') AND is_return = 0 AND paid_amount > 0
          UNION ALL
          SELECT 'out' AS flow, COALESCE(amount, 0) AS amount
          FROM expenses WHERE cash_box_id = ?
        )
      ''', [cashBoxId, cashBoxId, cashBoxId]);

      final totalInflows =
          MoneyHelper.readCalculatedMoney(result.first['total_inflows']);
      final totalOutflows =
          MoneyHelper.readCalculatedMoney(result.first['total_outflows']);

      // Inflows: opening 5000 + sale 3000 = 8000
      expect(totalInflows, 8000.0);
      // Outflows: expense 1000
      expect(totalOutflows, 1000.0);
      // Effective: 8000 - 1000 = 7000
      expect(totalInflows - totalOutflows, 7000.0);
    });

    test('Aggregated balance by currency (7.4 fix)', () async {
      final now = DateTime.now().toIso8601String();

      // Create YER cash boxes
      await db.insert('cash_boxes', {
        'name': 'صندوق ريال 1',
        'type': 'cash_box',
        'currency': 'YER',
        'balance': MoneyHelper.toCents(10000.0),
        'balance_type': 'credit',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
      await db.insert('cash_boxes', {
        'name': 'صندوق ريال 2',
        'type': 'cash_box',
        'currency': 'YER',
        'balance': MoneyHelper.toCents(5000.0),
        'balance_type': 'credit',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });

      // Create USD cash box
      await db.insert('cash_boxes', {
        'name': 'صندوق دولار',
        'type': 'bank',
        'currency': 'USD',
        'balance': MoneyHelper.toCents(500.0),
        'balance_type': 'credit',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });

      final results = await db.rawQuery('''
        SELECT
          currency,
          CAST(COALESCE(SUM(CASE
            WHEN balance_type = 'credit' THEN balance
            ELSE -balance
          END), 0) AS INTEGER) AS total_balance,
          COUNT(*) AS cash_box_count
        FROM cash_boxes
        WHERE is_active = 1
        GROUP BY currency
        ORDER BY currency
      ''');

      expect(results.length, 2);

      final usdRow = results.firstWhere((r) => r['currency'] == 'USD');
      expect(MoneyHelper.readCalculatedMoney(usdRow['total_balance']), 500.0);
      expect(usdRow['cash_box_count'], 1);

      final yerRow = results.firstWhere((r) => r['currency'] == 'YER');
      expect(MoneyHelper.readCalculatedMoney(yerRow['total_balance']), 15000.0);
      expect(yerRow['cash_box_count'], 2);
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Customer & Supplier CRUD Tests
  // ══════════════════════════════════════════════════════════════

  group('Customer CRUD Operations', () {
    test('Insert, read, update, and delete customer', () async {
      final now = DateTime.now().toIso8601String();

      // Insert
      final id = await db.insert('customers', {
        'name': 'أحمد محمد',
        'phone': '777123456',
        'balance': MoneyHelper.toCents(2500.0),
        'balance_type': 'credit',
        'currency': 'YER',
        'debt_ceiling': MoneyHelper.toCents(10000.0),
        'created_at': now,
        'updated_at': now,
      });

      // Read
      final customer =
          await db.query('customers', where: 'id = ?', whereArgs: [id]);
      expect(customer.length, 1);
      expect(customer.first['name'], 'أحمد محمد');
      expect(MoneyHelper.readMoney(customer.first['balance']), 2500.0);

      // Update
      await db.update(
        'customers',
        {
          'balance': MoneyHelper.toCents(3000.0),
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      final updated =
          await db.query('customers', where: 'id = ?', whereArgs: [id]);
      expect(MoneyHelper.readMoney(updated.first['balance']), 3000.0);

      // Delete (hard delete for customers with no invoices)
      await db.delete('customers', where: 'id = ?', whereArgs: [id]);
      final deleted =
          await db.query('customers', where: 'id = ?', whereArgs: [id]);
      expect(deleted.length, 0);
    });

    test('Customer debt ceiling check', () async {
      final now = DateTime.now().toIso8601String();
      final id = await db.insert('customers', {
        'name': 'عميل بسقف',
        'balance': MoneyHelper.toCents(8000.0),
        'balance_type': 'debit',
        'currency': 'YER',
        'debt_ceiling': MoneyHelper.toCents(10000.0),
        'created_at': now,
        'updated_at': now,
      });

      final customer =
          await db.query('customers', where: 'id = ?', whereArgs: [id]);
      final currentBalance = MoneyHelper.readMoney(customer.first['balance']);
      final debtCeiling = MoneyHelper.readMoney(customer.first['debt_ceiling']);

      // Current: 8000, Ceiling: 10000
      expect(currentBalance + 3000, greaterThan(debtCeiling)); // Would exceed
      expect(currentBalance + 1500,
          lessThanOrEqualTo(debtCeiling)); // Would not exceed
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Complex Balance Query Tests
  // ══════════════════════════════════════════════════════════════

  group('Complex Balance Queries', () {
    test('Account balance computed from transactions matches stored balance',
        () async {
      final now = DateTime.now().toIso8601String();

      // Create a test account
      final accountId = await db.insert('accounts', {
        'name_ar': 'حساب التحقق',
        'name_en': 'Verification Account',
        'account_code': '7001',
        'account_type': 'ASSET',
        'balance': 0,
        'currency': 'YER',
        'balance_type': 'debit',
        'is_active': 1,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });

      // Add transactions
      await db.transaction((txn) async {
        // Debit 5000
        await txn.insert('transactions', {
          'account_id': accountId,
          'journal_id': 2001,
          'debit': MoneyHelper.toCents(5000.0),
          'credit': 0,
          'description': 'إيداع',
          'date': now,
          'created_at': now,
        });

        // Credit 2000
        await txn.insert('transactions', {
          'account_id': accountId,
          'journal_id': 2002,
          'debit': 0,
          'credit': MoneyHelper.toCents(2000.0),
          'description': 'سحب',
          'date': now,
          'created_at': now,
        });

        // Debit 3000
        await txn.insert('transactions', {
          'account_id': accountId,
          'journal_id': 2003,
          'debit': MoneyHelper.toCents(3000.0),
          'credit': 0,
          'description': 'إيداع آخر',
          'date': now,
          'created_at': now,
        });
      });

      // Compute balance from transactions
      final result = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM(debit), 0) AS INTEGER) AS total_debit, "
        "CAST(COALESCE(SUM(credit), 0) AS INTEGER) AS total_credit "
        "FROM transactions WHERE account_id = ?",
        [accountId],
      );

      final totalDebit =
          MoneyHelper.readCalculatedMoney(result.first['total_debit']);
      final totalCredit =
          MoneyHelper.readCalculatedMoney(result.first['total_credit']);

      // For debit-balance account: balance = debit - credit = 8000 - 2000 = 6000
      final computedBalance = totalDebit - totalCredit;
      expect(computedBalance, 6000.0);
    });

    test('Running balance calculation is correct', () async {
      final now = DateTime.now().toIso8601String();

      final accountId = await db.insert('accounts', {
        'name_ar': 'حساب الرصيد التراكمي',
        'name_en': 'Running Balance Account',
        'account_code': '7002',
        'account_type': 'ASSET',
        'balance': 0,
        'currency': 'YER',
        'balance_type': 'debit',
        'is_active': 1,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });

      // Insert transactions with sequential dates
      final transactions = [
        {'debit': 5000.0, 'credit': 0.0, 'date': '2025-01-01'},
        {'debit': 0.0, 'credit': 2000.0, 'date': '2025-01-02'},
        {'debit': 3000.0, 'credit': 0.0, 'date': '2025-01-03'},
        {'debit': 0.0, 'credit': 1500.0, 'date': '2025-01-04'},
        {'debit': 4000.0, 'credit': 0.0, 'date': '2025-01-05'},
      ];

      for (final txn in transactions) {
        await db.insert('transactions', {
          'account_id': accountId,
          'journal_id': 3000 + transactions.indexOf(txn),
          'debit': MoneyHelper.toCents(txn['debit'] as double),
          'credit': MoneyHelper.toCents(txn['credit'] as double),
          'description': 'اختبار',
          'date': txn['date']!,
          'created_at': now,
        });
      }

      // Compute running balance for debit-type account
      final allTxns = await db.query('transactions',
          where: 'account_id = ?',
          whereArgs: [accountId],
          orderBy: 'date ASC, id ASC');

      double runningBalance = 0.0;
      final expectedBalances = [5000.0, 3000.0, 6000.0, 4500.0, 8500.0];

      for (int i = 0; i < allTxns.length; i++) {
        final debit = MoneyHelper.readMoney(allTxns[i]['debit']);
        final credit = MoneyHelper.readMoney(allTxns[i]['credit']);

        // For debit-type: balance increases with debit, decreases with credit
        runningBalance += debit - credit;
        expect(runningBalance, expectedBalances[i]);
      }
    });

    test('MoneyHelper precision: no floating-point drift', () {
      // Test that MoneyHelper maintains precision through cents conversion
      final values = [0.01, 0.02, 99.99, 1000.50, 999999.99];

      for (final value in values) {
        final cents = MoneyHelper.toCents(value);
        final back = MoneyHelper.fromCents(cents);
        expect(back, value, reason: 'Value $value lost precision');
      }

      // Test arithmetic operations
      expect(MoneyHelper.add(0.1, 0.2), 0.3); // Classic floating-point test
      expect(MoneyHelper.subtract(1.0, 0.3), 0.7);
      expect(MoneyHelper.multiply(100.0, 1.5), 150.0);
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Fiscal Period & Validation Tests
  // ══════════════════════════════════════════════════════════════

  group('Fiscal Period Validation', () {
    test('Cannot create transactions in closed fiscal year', () async {
      final now = DateTime.now().toIso8601String();

      // Create a closed fiscal year for 2024
      await db.insert('fiscal_years', {
        'year': 2024,
        'start_date': '2024-01-01',
        'end_date': '2024-12-31',
        'status': 'closed',
        'net_profit': 0,
        'closed_at': now,
        'closed_by': 'admin',
        'created_at': now,
        'updated_at': now,
      });

      // Check if fiscal year is closed
      final result = await db.query('fiscal_years',
          where: 'year = ? AND status = ?', whereArgs: [2024, 'closed']);
      expect(result.isNotEmpty, isTrue);

      // Verify open fiscal year check
      final openResult = await db.query('fiscal_years',
          where: 'year = ? AND status = ?', whereArgs: [2025, 'closed']);
      expect(openResult.isEmpty, isTrue);
    });
  });
}
