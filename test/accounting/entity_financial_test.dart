import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// ══════════════════════════════════════════════════════════════════
/// اختبارات العمليات المالية للكيانات — Entity Financial Tests
///
/// Comprehensive database-level tests for customer, supplier, employee,
/// and cash box financial operations. Each test is self-contained and
/// verifies accounting integrity at the DB level.
///
/// Coverage:
///   1. Customer CRUD and Financial Operations
///   2. Supplier CRUD and Financial Operations
///   3. Employee Financial Operations
///   4. Cash Box Operations
///   5. Customer Movements / Voucher Impact
///   6. Supplier Movements / Voucher Impact
///   7. Account Balance Integrity
///   8. Trial Balance / ميزان المراجعة
/// ══════════════════════════════════════════════════════════════════

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 49,
      onCreate: (database, version) async {
        await database.execute('PRAGMA foreign_keys = ON');
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

  // ══════════════════════════════════════════════════════════════════
  //  Shared Helpers
  // ══════════════════════════════════════════════════════════════════

  /// Look up a seeded system account by code.
  Future<Map<String, dynamic>?> _findAccountByCode(String code) async {
    final rows = await db.query(
      'accounts',
      where: 'account_code = ?',
      whereArgs: [code],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Insert a transaction row.
  Future<void> _insertTransaction({
    required int accountId,
    required int journalId,
    required int debit,
    required int credit,
    String currencyCode = 'YER',
    double exchangeRate = 1.0,
    int? amountBase,
    String? referenceType,
    String? referenceId,
    String? description,
  }) async {
    final now = DateTime.now().toIso8601String();
    await db.insert('transactions', {
      'account_id': accountId,
      'journal_id': journalId,
      'debit': debit,
      'credit': credit,
      'description': description ?? 'قيد افتتاحي',
      'date': now,
      'created_at': now,
      'currency_code': currencyCode,
      'exchange_rate': exchangeRate,
      'amount_base': amountBase ?? (debit > 0 ? debit : credit),
      'reference_type': referenceType,
      'reference_id': referenceId,
    });
  }

  /// Insert a customer and return its ID.
  Future<int> _insertCustomer({
    required String name,
    double balance = 0.0,
    String balanceType = 'credit',
    String currency = 'YER',
  }) async {
    final now = DateTime.now().toIso8601String();
    return await db.insert('customers', {
      'name': name,
      'balance': MoneyHelper.toCents(balance),
      'balance_type': balanceType,
      'currency': currency,
      'debt_ceiling': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Insert a supplier and return its ID.
  Future<int> _insertSupplier({
    required String name,
    double balance = 0.0,
    String balanceType = 'credit',
    String currency = 'YER',
  }) async {
    final now = DateTime.now().toIso8601String();
    return await db.insert('suppliers', {
      'name': name,
      'balance': MoneyHelper.toCents(balance),
      'balance_type': balanceType,
      'currency': currency,
      'debt_ceiling': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Insert a cash box and return its ID.
  Future<int> _insertCashBox({
    required String name,
    double balance = 0.0,
    String balanceType = 'credit',
    String currency = 'YER',
    int? linkedAccountId,
  }) async {
    final now = DateTime.now().toIso8601String();
    return await db.insert('cash_boxes', {
      'name': name,
      'type': 'cash_box',
      'currency': currency,
      'balance': MoneyHelper.toCents(balance),
      'balance_type': balanceType,
      'linked_account_id': linkedAccountId,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Insert an employee and return its ID.
  Future<int> _insertEmployee({
    required String name,
    double balance = 0.0,
    String balanceType = 'credit',
    String currency = 'YER',
    int? accountId,
  }) async {
    final now = DateTime.now().toIso8601String();
    return await db.insert('employees', {
      'name': name,
      'balance': MoneyHelper.toCents(balance),
      'balance_type': balanceType,
      'currency': currency,
      'account_id': accountId,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Verify that a given journal entry has total debits == total credits.
  Future<void> _assertJournalBalanced(int journalId) async {
    final result = await db.rawQuery(
      'SELECT CAST(COALESCE(SUM(debit), 0) AS INTEGER) AS total_debit, '
      'CAST(COALESCE(SUM(credit), 0) AS INTEGER) AS total_credit '
      'FROM transactions WHERE journal_id = ?',
      [journalId],
    );
    final totalDebit = result.first['total_debit'] as int;
    final totalCredit = result.first['total_credit'] as int;
    expect(totalDebit, equals(totalCredit),
        reason:
            'Journal $journalId: debits ($totalDebit) must equal credits ($totalCredit)');
  }

  /// Verify that total debits == total credits across ALL transactions.
  Future<void> _assertGlobalTrialBalance() async {
    final result = await db.rawQuery(
      'SELECT CAST(COALESCE(SUM(debit), 0) AS INTEGER) AS total_debit, '
      'CAST(COALESCE(SUM(credit), 0) AS INTEGER) AS total_credit '
      'FROM transactions',
    );
    final totalDebit = result.first['total_debit'] as int;
    final totalCredit = result.first['total_credit'] as int;
    expect(totalDebit, equals(totalCredit),
        reason:
            'Trial balance: total debits ($totalDebit) must equal total credits ($totalCredit)');
  }

  /// Apply a signed balance change to an entity (mirrors EntityBalanceHelper).
  Future<void> _applyEntityBalanceChange({
    required String tableName,
    required int entityId,
    required double signedChange,
  }) async {
    final now = DateTime.now().toIso8601String();
    if (signedChange.abs() < 0.005) return;

    final rows = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [entityId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final currentBalance = MoneyHelper.readMoney(rows.first['balance']);
    final currentType = rows.first['balance_type'] as String? ?? 'credit';

    // Convert to signed value
    double signedBalance =
        currentType == 'credit' ? currentBalance : -currentBalance;

    // Apply the change
    signedBalance += signedChange;

    // Convert back to magnitude + direction
    final newBalance = signedBalance.abs();
    final newType = signedBalance >= 0 ? 'credit' : 'debit';

    await db.update(
      tableName,
      {
        'balance': MoneyHelper.toCents(newBalance),
        'balance_type': newType,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [entityId],
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  Group 1: Customer CRUD and Financial Operations
  //  عمليات إنشاء وقراءة وتحديث العملاء
  // ══════════════════════════════════════════════════════════════════

  group('Customer CRUD and Financial Operations — عمليات العملاء', () {
    test(
      'Create customer with YER opening balance → verify balance in DB, verify OB journal is balanced / '
      'إنشاء عميل برصيد افتتاحي بالريال → التحقق من الرصيد وتوازن القيد',
      () async {
        const openingBalance = 5000.0;
        final journalId = DateTime.now().microsecondsSinceEpoch;

        // 1. Create customer with opening balance (debit = عليه = customer owes us)
        final customerId = await _insertCustomer(
          name: 'عميل يمني',
          balance: openingBalance,
          balanceType: 'debit',
          currency: 'YER',
        );

        // 2. Verify customer balance in DB
        final customer = await db
            .query('customers', where: 'id = ?', whereArgs: [customerId]);
        expect(customer, isNotEmpty);
        expect(MoneyHelper.readMoney(customer.first['balance']),
            equals(openingBalance));
        expect(customer.first['balance_type'], equals('debit'));
        expect(customer.first['currency'], equals('YER'));

        // 3. Create opening balance journal entry:
        //    Debit: Customers Receivable (1200) — customer owes us
        //    Credit: Opening Balance Equity (2901)
        final customersAccount = await _findAccountByCode('1200');
        final obEquityAccount = await _findAccountByCode('2901');
        expect(customersAccount, isNotNull,
            reason: 'Seeded account 1200 should exist');
        expect(obEquityAccount, isNotNull,
            reason: 'Seeded account 2901 should exist');

        final amountCents = MoneyHelper.toCents(openingBalance);
        await _insertTransaction(
          accountId: customersAccount!['id'] as int,
          journalId: journalId,
          debit: amountCents,
          credit: 0,
          referenceType: 'opening_balance',
          description: 'رصيد افتتاحي - عميل يمني - مدين',
        );
        await _insertTransaction(
          accountId: obEquityAccount!['id'] as int,
          journalId: journalId,
          debit: 0,
          credit: amountCents,
          referenceType: 'opening_balance',
          description: 'رصيد افتتاحي - عميل يمني - دائن',
        );

        // 4. Verify journal is balanced
        await _assertJournalBalanced(journalId);

        // 5. Verify the specific accounts used
        final txnCustomer = await db.rawQuery(
          "SELECT * FROM transactions WHERE journal_id = ? AND account_id = ?",
          [journalId, customersAccount['id']],
        );
        expect(txnCustomer, hasLength(1));
        expect(txnCustomer.first['debit'], equals(amountCents));

        final txnEquity = await db.rawQuery(
          "SELECT * FROM transactions WHERE journal_id = ? AND account_id = ?",
          [journalId, obEquityAccount['id']],
        );
        expect(txnEquity, hasLength(1));
        expect(txnEquity.first['credit'], equals(amountCents));
      },
    );

    test(
      'Create customer with SAR opening balance → verify balance and correct account codes (1201, 2902) / '
      'إنشاء عميل برصيد افتتاحي بالريال السعودي → التحقق من أكواد الحسابات',
      () async {
        const openingBalance = 3000.0;
        final journalId = DateTime.now().microsecondsSinceEpoch + 1;

        final customerId = await _insertCustomer(
          name: 'عميل سعودي',
          balance: openingBalance,
          balanceType: 'debit',
          currency: 'SAR',
        );

        // Verify customer record
        final customer = await db
            .query('customers', where: 'id = ?', whereArgs: [customerId]);
        expect(MoneyHelper.readMoney(customer.first['balance']),
            equals(openingBalance));
        expect(customer.first['currency'], equals('SAR'));

        // Verify correct account codes: SAR uses offset +1
        final customersSarAccount = await _findAccountByCode('1201');
        final obEquitySarAccount = await _findAccountByCode('2902');
        expect(customersSarAccount, isNotNull,
            reason: 'Seeded account 1201 (SAR Customers) should exist');
        expect(obEquitySarAccount, isNotNull,
            reason: 'Seeded account 2902 (SAR OB Equity) should exist');

        final amountCents = MoneyHelper.toCents(openingBalance);
        await _insertTransaction(
          accountId: customersSarAccount!['id'] as int,
          journalId: journalId,
          debit: amountCents,
          credit: 0,
          currencyCode: 'SAR',
          exchangeRate: 140.0,
          amountBase: amountCents * 140,
          referenceType: 'opening_balance',
          description: 'رصيد افتتاحي - عميل سعودي',
        );
        await _insertTransaction(
          accountId: obEquitySarAccount!['id'] as int,
          journalId: journalId,
          debit: 0,
          credit: amountCents,
          currencyCode: 'SAR',
          exchangeRate: 140.0,
          amountBase: amountCents * 140,
          referenceType: 'opening_balance',
          description: 'رصيد افتتاحي - عميل سعودي',
        );

        await _assertJournalBalanced(journalId);
      },
    );

    test(
      'Create customer with zero opening balance → verify balance is 0 / '
      'إنشاء عميل برصيد افتتاحي صفر → التحقق من أن الرصيد صفر',
      () async {
        final customerId = await _insertCustomer(
          name: 'عميل بدون رصيد',
          balance: 0.0,
          currency: 'YER',
        );

        final customer = await db
            .query('customers', where: 'id = ?', whereArgs: [customerId]);
        expect(MoneyHelper.readMoney(customer.first['balance']), equals(0.0));
        // Default balance_type for customers is 'credit'
        expect(customer.first['balance_type'], equals('credit'));
      },
    );

    test(
      'Update customer balance → verify new balance reflected in DB / '
      'تحديث رصيد العميل → التحقق من انعكاس الرصيد الجديد',
      () async {
        const initialBalance = 10000.0;
        final customerId = await _insertCustomer(
          name: 'عميل للتحديث',
          balance: initialBalance,
          balanceType: 'debit',
          currency: 'YER',
        );

        // Apply a credit change (receipt from customer of 4000)
        // signedChange = creditEffect - debitEffect = 4000 - 0 = +4000
        await _applyEntityBalanceChange(
          tableName: 'customers',
          entityId: customerId,
          signedChange: 4000.0, // receipt = credit effect
        );

        final customer = await db
            .query('customers', where: 'id = ?', whereArgs: [customerId]);
        // Was debit 10000, credit effect +4000 → signed: -10000 + 4000 = -6000 → debit 6000
        expect(
            MoneyHelper.readMoney(customer.first['balance']), equals(6000.0));
        expect(customer.first['balance_type'], equals('debit'));
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════
  //  Group 2: Supplier CRUD and Financial Operations
  //  عمليات إنشاء وقراءة وتحديث الموردين
  // ══════════════════════════════════════════════════════════════════

  group('Supplier CRUD and Financial Operations — عمليات الموردين', () {
    test(
      'Create supplier with YER opening balance → verify balance, verify OB journal (debit 2901, credit 2100) / '
      'إنشاء مورد برصيد افتتاحي بالريال → التحقق من الرصيد والقيد الافتتاحي',
      () async {
        const openingBalance = 8000.0;
        final journalId = DateTime.now().microsecondsSinceEpoch + 10;

        // Supplier opening balance: we owe the supplier → credit (له)
        final supplierId = await _insertSupplier(
          name: 'مورد يمني',
          balance: openingBalance,
          balanceType: 'credit',
          currency: 'YER',
        );

        // Verify supplier balance in DB
        final supplier = await db
            .query('suppliers', where: 'id = ?', whereArgs: [supplierId]);
        expect(MoneyHelper.readMoney(supplier.first['balance']),
            equals(openingBalance));
        expect(supplier.first['balance_type'], equals('credit'));
        expect(supplier.first['currency'], equals('YER'));

        // Opening balance journal for supplier:
        //   Debit: Opening Balance Equity (2901) — source of the obligation
        //   Credit: Suppliers Payable (2100) — we owe the supplier
        final obEquityAccount = await _findAccountByCode('2901');
        final suppliersAccount = await _findAccountByCode('2100');
        expect(obEquityAccount, isNotNull);
        expect(suppliersAccount, isNotNull);

        final amountCents = MoneyHelper.toCents(openingBalance);
        await _insertTransaction(
          accountId: obEquityAccount!['id'] as int,
          journalId: journalId,
          debit: amountCents,
          credit: 0,
          referenceType: 'opening_balance',
          description: 'رصيد افتتاحي - مورد يمني - مدين',
        );
        await _insertTransaction(
          accountId: suppliersAccount!['id'] as int,
          journalId: journalId,
          debit: 0,
          credit: amountCents,
          referenceType: 'opening_balance',
          description: 'رصيد افتتاحي - مورد يمني - دائن',
        );

        await _assertJournalBalanced(journalId);

        // Verify specific account directions
        final txnEquity = await db.rawQuery(
          "SELECT * FROM transactions WHERE journal_id = ? AND account_id = ?",
          [journalId, obEquityAccount['id']],
        );
        expect(txnEquity.first['debit'], equals(amountCents));

        final txnSuppliers = await db.rawQuery(
          "SELECT * FROM transactions WHERE journal_id = ? AND account_id = ?",
          [journalId, suppliersAccount['id']],
        );
        expect(txnSuppliers.first['credit'], equals(amountCents));
      },
    );

    test(
      'Create supplier with USD opening balance → verify balance and correct account codes (2102, 2903) / '
      'إنشاء مورد برصيد افتتاحي بالدولار → التحقق من أكواد الحسابات',
      () async {
        const openingBalance = 2000.0;
        final journalId = DateTime.now().microsecondsSinceEpoch + 11;

        final supplierId = await _insertSupplier(
          name: 'مورد دولاري',
          balance: openingBalance,
          balanceType: 'credit',
          currency: 'USD',
        );

        // Verify supplier record
        final supplier = await db
            .query('suppliers', where: 'id = ?', whereArgs: [supplierId]);
        expect(MoneyHelper.readMoney(supplier.first['balance']),
            equals(openingBalance));
        expect(supplier.first['currency'], equals('USD'));

        // Verify correct account codes: USD uses offset +2
        final suppliersUsdAccount = await _findAccountByCode('2102');
        final obEquityUsdAccount = await _findAccountByCode('2903');
        expect(suppliersUsdAccount, isNotNull,
            reason: 'Seeded account 2102 (USD Suppliers) should exist');
        expect(obEquityUsdAccount, isNotNull,
            reason: 'Seeded account 2903 (USD OB Equity) should exist');

        final amountCents = MoneyHelper.toCents(openingBalance);
        await _insertTransaction(
          accountId: obEquityUsdAccount!['id'] as int,
          journalId: journalId,
          debit: amountCents,
          credit: 0,
          currencyCode: 'USD',
          exchangeRate: 530.0,
          amountBase: amountCents * 530,
          referenceType: 'opening_balance',
        );
        await _insertTransaction(
          accountId: suppliersUsdAccount!['id'] as int,
          journalId: journalId,
          debit: 0,
          credit: amountCents,
          currencyCode: 'USD',
          exchangeRate: 530.0,
          amountBase: amountCents * 530,
          referenceType: 'opening_balance',
        );

        await _assertJournalBalanced(journalId);
      },
    );

    test(
      'Supplier balance direction is correct (credit = له = positive) / '
      'اتجاه رصيد المورد صحيح (الدائن = له = موجب)',
      () async {
        // When we owe the supplier, it's credit (له) — the normal state
        final supplierId = await _insertSupplier(
          name: 'مورد عادي',
          balance: 15000.0,
          balanceType: 'credit',
          currency: 'YER',
        );

        final supplier = await db
            .query('suppliers', where: 'id = ?', whereArgs: [supplierId]);
        expect(
            MoneyHelper.readMoney(supplier.first['balance']), equals(15000.0));
        expect(supplier.first['balance_type'], equals('credit'));

        // After we pay the supplier 5000, signed change = -5000 (debit effect)
        // signed: +15000 - 5000 = +10000 → still credit
        await _applyEntityBalanceChange(
          tableName: 'suppliers',
          entityId: supplierId,
          signedChange: -5000.0,
        );

        final afterPayment = await db
            .query('suppliers', where: 'id = ?', whereArgs: [supplierId]);
        expect(MoneyHelper.readMoney(afterPayment.first['balance']),
            equals(10000.0));
        expect(afterPayment.first['balance_type'], equals('credit'));
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════
  //  Group 3: Employee Financial Operations
  //  العمليات المالية للموظفين
  // ══════════════════════════════════════════════════════════════════

  group('Employee Financial Operations — العمليات المالية للموظفين', () {
    test(
      'Employee with account_id → can record transactions / '
      'موظف بحساب مرتبط → يمكن تسجيل معاملات عليه',
      () async {
        final employeeAccountId = await _findAccountByCode('5100');
        expect(employeeAccountId, isNotNull,
            reason: 'Seeded account 5100 (Employees) should exist');

        final employeeId = await _insertEmployee(
          name: 'أحمد الموظف',
          balance: 0.0,
          currency: 'YER',
          accountId: employeeAccountId!['id'] as int,
        );

        // Verify employee record
        final employee = await db
            .query('employees', where: 'id = ?', whereArgs: [employeeId]);
        expect(employee, isNotEmpty);
        expect(employee.first['account_id'], equals(employeeAccountId['id']));
        expect(MoneyHelper.readMoney(employee.first['balance']), equals(0.0));

        // Record a transaction against the employee's linked account
        final journalId = DateTime.now().microsecondsSinceEpoch + 20;
        final cashAccount = await _findAccountByCode('1100');
        expect(cashAccount, isNotNull);

        final salaryCents = MoneyHelper.toCents(5000.0);
        await _insertTransaction(
          accountId: employeeAccountId['id'] as int,
          journalId: journalId,
          debit: salaryCents,
          credit: 0,
          description: 'سلفة موظف',
        );
        await _insertTransaction(
          accountId: cashAccount!['id'] as int,
          journalId: journalId,
          debit: 0,
          credit: salaryCents,
          description: 'صرف سلفة من الصندوق',
        );

        await _assertJournalBalanced(journalId);

        // Verify the employee account has a debit entry
        final txnEmployee = await db.rawQuery(
          "SELECT * FROM transactions WHERE journal_id = ? AND account_id = ?",
          [journalId, employeeAccountId['id']],
        );
        expect(txnEmployee, hasLength(1));
        expect(txnEmployee.first['debit'], equals(salaryCents));
      },
    );

    test(
      'Employee opening balance creates correct journal entries (debit 5100, credit 2901) / '
      'رصيد افتتاحي للموظف ينشئ قيود صحيحة (مدين 5100، دائن 2901)',
      () async {
        const openingBalance = 7000.0;
        final journalId = DateTime.now().microsecondsSinceEpoch + 21;

        final employeeAccountId = await _findAccountByCode('5100');
        final obEquityAccount = await _findAccountByCode('2901');
        expect(employeeAccountId, isNotNull);
        expect(obEquityAccount, isNotNull);

        // Employee opening balance: employee owes us (advance/salary) → debit
        final employeeId = await _insertEmployee(
          name: 'سعيد الموظف',
          balance: openingBalance,
          balanceType: 'debit',
          currency: 'YER',
          accountId: employeeAccountId!['id'] as int,
        );

        // Verify employee balance
        final employee = await db
            .query('employees', where: 'id = ?', whereArgs: [employeeId]);
        expect(MoneyHelper.readMoney(employee.first['balance']),
            equals(openingBalance));
        expect(employee.first['balance_type'], equals('debit'));

        // Create OB journal: Debit 5100 (Employees expense), Credit 2901 (OB Equity)
        final amountCents = MoneyHelper.toCents(openingBalance);
        await _insertTransaction(
          accountId: employeeAccountId['id'] as int,
          journalId: journalId,
          debit: amountCents,
          credit: 0,
          referenceType: 'opening_balance',
          description: 'رصيد افتتاحي موظف - مدين',
        );
        await _insertTransaction(
          accountId: obEquityAccount!['id'] as int,
          journalId: journalId,
          debit: 0,
          credit: amountCents,
          referenceType: 'opening_balance',
          description: 'رصيد افتتاحي موظف - دائن',
        );

        await _assertJournalBalanced(journalId);

        // Verify correct sides
        final txn5100 = await db.rawQuery(
          "SELECT * FROM transactions WHERE journal_id = ? AND account_id = ?",
          [journalId, employeeAccountId['id']],
        );
        expect(txn5100.first['debit'], equals(amountCents));

        final txn2901 = await db.rawQuery(
          "SELECT * FROM transactions WHERE journal_id = ? AND account_id = ?",
          [journalId, obEquityAccount['id']],
        );
        expect(txn2901.first['credit'], equals(amountCents));
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════
  //  Group 4: Cash Box Operations
  //  عمليات الصناديق النقدية
  // ══════════════════════════════════════════════════════════════════

  group('Cash Box Operations — عمليات الصناديق النقدية', () {
    test(
      'Create cash box with linked account → verify linked_account_id / '
      'إنشاء صندوق بحساب مرتبط → التحقق من linked_account_id',
      () async {
        final cashAccount = await _findAccountByCode('1100');
        expect(cashAccount, isNotNull);

        final cashBoxId = await _insertCashBox(
          name: 'الصندوق الرئيسي',
          balance: 50000.0,
          balanceType: 'credit',
          currency: 'YER',
          linkedAccountId: cashAccount!['id'] as int,
        );

        final cashBox = await db
            .query('cash_boxes', where: 'id = ?', whereArgs: [cashBoxId]);
        expect(cashBox, isNotEmpty);
        expect(cashBox.first['linked_account_id'], equals(cashAccount['id']));
        expect(
            MoneyHelper.readMoney(cashBox.first['balance']), equals(50000.0));
        expect(cashBox.first['currency'], equals('YER'));
      },
    );

    test(
      'Cash box balance is stored in cents / '
      'رصيد الصندوق يُخزن بالقروش',
      () async {
        const humanBalance = 12345.67;
        final cashBoxId = await _insertCashBox(
          name: 'صندوق القروش',
          balance: humanBalance,
          currency: 'YER',
        );

        // Verify raw integer value in DB is in cents
        final cashBox = await db
            .query('cash_boxes', where: 'id = ?', whereArgs: [cashBoxId]);
        final rawBalance = cashBox.first['balance'] as int;
        expect(rawBalance, equals(MoneyHelper.toCents(humanBalance)));
        expect(rawBalance, equals(1234567));

        // Verify read-back via MoneyHelper
        expect(MoneyHelper.readMoney(rawBalance), closeTo(humanBalance, 0.01));
      },
    );

    test(
      'Multiple cash boxes with different currencies / '
      'صناديق متعددة بعملات مختلفة',
      () async {
        final yerAccount = await _findAccountByCode('1100');
        final sarAccount = await _findAccountByCode('1101');
        final usdAccount = await _findAccountByCode('1102');

        expect(yerAccount, isNotNull);
        expect(sarAccount, isNotNull);
        expect(usdAccount, isNotNull);

        final yerBoxId = await _insertCashBox(
          name: 'صندوق الريال اليمني',
          balance: 100000.0,
          currency: 'YER',
          linkedAccountId: yerAccount!['id'] as int,
        );
        final sarBoxId = await _insertCashBox(
          name: 'صندوق الريال السعودي',
          balance: 5000.0,
          currency: 'SAR',
          linkedAccountId: sarAccount!['id'] as int,
        );
        final usdBoxId = await _insertCashBox(
          name: 'صندوق الدولار',
          balance: 2000.0,
          currency: 'USD',
          linkedAccountId: usdAccount!['id'] as int,
        );

        // Verify all three cash boxes
        final yerBox = await db
            .query('cash_boxes', where: 'id = ?', whereArgs: [yerBoxId]);
        expect(yerBox.first['currency'], equals('YER'));
        expect(
            MoneyHelper.readMoney(yerBox.first['balance']), equals(100000.0));
        expect(yerBox.first['linked_account_id'], equals(yerAccount['id']));

        final sarBox = await db
            .query('cash_boxes', where: 'id = ?', whereArgs: [sarBoxId]);
        expect(sarBox.first['currency'], equals('SAR'));
        expect(MoneyHelper.readMoney(sarBox.first['balance']), equals(5000.0));
        expect(sarBox.first['linked_account_id'], equals(sarAccount['id']));

        final usdBox = await db
            .query('cash_boxes', where: 'id = ?', whereArgs: [usdBoxId]);
        expect(usdBox.first['currency'], equals('USD'));
        expect(MoneyHelper.readMoney(usdBox.first['balance']), equals(2000.0));
        expect(usdBox.first['linked_account_id'], equals(usdAccount['id']));
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════
  //  Group 5: Customer Movements / Voucher Impact
  //  حركات العميل / تأثير السندات
  // ══════════════════════════════════════════════════════════════════

  group('Customer Movements / Voucher Impact — حركات العميل وتأثير السندات',
      () {
    test(
      'Receipt voucher for customer → creates balanced journal (debit cash 1100, credit customer 1200) / '
      'سند قبض من عميل → قيد متوازن (مدين الصندوق 1100، دائن العميل 1200)',
      () async {
        const receiptAmount = 3000.0;
        final journalId = DateTime.now().microsecondsSinceEpoch + 30;

        // Create a customer who owes us
        final customerId = await _insertCustomer(
          name: 'عميل سند قبض',
          balance: 5000.0,
          balanceType: 'debit',
          currency: 'YER',
        );

        final cashAccount = await _findAccountByCode('1100');
        final customersAccount = await _findAccountByCode('1200');
        expect(cashAccount, isNotNull);
        expect(customersAccount, isNotNull);

        // Create receipt voucher journal entry
        final amountCents = MoneyHelper.toCents(receiptAmount);
        await _insertTransaction(
          accountId: cashAccount!['id'] as int,
          journalId: journalId,
          debit: amountCents,
          credit: 0,
          description: 'سند قبض - الصندوق مدين',
        );
        await _insertTransaction(
          accountId: customersAccount!['id'] as int,
          journalId: journalId,
          debit: 0,
          credit: amountCents,
          description: 'سند قبض - العميل دائن',
        );

        // Verify journal balanced
        await _assertJournalBalanced(journalId);

        // Verify cash account debited (increases asset)
        final txnCash = await db.rawQuery(
          "SELECT * FROM transactions WHERE journal_id = ? AND account_id = ?",
          [journalId, cashAccount['id']],
        );
        expect(txnCash.first['debit'], equals(amountCents));

        // Verify customer account credited (reduces receivable)
        final txnCustomer = await db.rawQuery(
          "SELECT * FROM transactions WHERE journal_id = ? AND account_id = ?",
          [journalId, customersAccount['id']],
        );
        expect(txnCustomer.first['credit'], equals(amountCents));

        // Apply receipt to customer entity balance
        // Receipt from customer → credit effect (signedChange = +amount)
        await _applyEntityBalanceChange(
          tableName: 'customers',
          entityId: customerId,
          signedChange: receiptAmount, // credit effect = +3000
        );

        // Verify customer balance decreased: 5000 - 3000 = 2000
        final customer = await db
            .query('customers', where: 'id = ?', whereArgs: [customerId]);
        expect(
            MoneyHelper.readMoney(customer.first['balance']), equals(2000.0));
        expect(customer.first['balance_type'], equals('debit'));
      },
    );

    test(
      'Payment voucher for customer → creates balanced journal (debit customer 1200, credit cash 1100) / '
      'سند صرف للعميل → قيد متوازن (مدين العميل 1200، دائن الصندوق 1100)',
      () async {
        const paymentAmount = 2000.0;
        final journalId = DateTime.now().microsecondsSinceEpoch + 31;

        final customerId = await _insertCustomer(
          name: 'عميل سند صرف',
          balance: 0.0,
          currency: 'YER',
        );

        final cashAccount = await _findAccountByCode('1100');
        final customersAccount = await _findAccountByCode('1200');

        // Payment voucher: we pay the customer (e.g., refund, advance)
        // Debit: Customer (1200) — customer owes us more
        // Credit: Cash (1100) — cash goes out
        final amountCents = MoneyHelper.toCents(paymentAmount);
        await _insertTransaction(
          accountId: customersAccount!['id'] as int,
          journalId: journalId,
          debit: amountCents,
          credit: 0,
          description: 'سند صرف - العميل مدين',
        );
        await _insertTransaction(
          accountId: cashAccount!['id'] as int,
          journalId: journalId,
          debit: 0,
          credit: amountCents,
          description: 'سند صرف - الصندوق دائن',
        );

        await _assertJournalBalanced(journalId);

        // Apply payment to customer entity balance (debit effect = -amount)
        await _applyEntityBalanceChange(
          tableName: 'customers',
          entityId: customerId,
          signedChange: -paymentAmount, // debit effect
        );

        final customer = await db
            .query('customers', where: 'id = ?', whereArgs: [customerId]);
        expect(MoneyHelper.readMoney(customer.first['balance']),
            equals(paymentAmount));
        expect(customer.first['balance_type'], equals('debit'));
      },
    );

    test(
      'Customer sale invoice → should increase customer debit balance (عليه) / '
      'فاتورة مبيعات للعميل → تزيد رصيد العميل المدين (عليه)',
      () async {
        const saleAmount = 7500.0;
        final journalId = DateTime.now().microsecondsSinceEpoch + 32;

        final customerId = await _insertCustomer(
          name: 'عميل فاتورة مبيعات',
          balance: 3000.0,
          balanceType: 'debit',
          currency: 'YER',
        );

        final customersAccount = await _findAccountByCode('1200');
        final salesAccount = await _findAccountByCode('4100');
        expect(customersAccount, isNotNull);
        expect(salesAccount, isNotNull);

        // Sale journal entry:
        // Debit: Customers Receivable (1200) — customer owes more
        // Credit: Sales Revenue (4100) — revenue earned
        final amountCents = MoneyHelper.toCents(saleAmount);
        await _insertTransaction(
          accountId: customersAccount!['id'] as int,
          journalId: journalId,
          debit: amountCents,
          credit: 0,
          referenceType: 'sale',
          description: 'فاتورة مبيعات آجلة - العميل مدين',
        );
        await _insertTransaction(
          accountId: salesAccount!['id'] as int,
          journalId: journalId,
          debit: 0,
          credit: amountCents,
          referenceType: 'sale',
          description: 'فاتورة مبيعات آجلة - الإيرادات دائن',
        );

        await _assertJournalBalanced(journalId);

        // Apply sale to customer balance (debit effect = customer owes more)
        await _applyEntityBalanceChange(
          tableName: 'customers',
          entityId: customerId,
          signedChange: -saleAmount, // debit effect = -signed
        );

        final customer = await db
            .query('customers', where: 'id = ?', whereArgs: [customerId]);
        // Was debit 3000, sale adds debit effect 7500 → total debit = 3000 + 7500 = 10500
        expect(
            MoneyHelper.readMoney(customer.first['balance']), equals(10500.0));
        expect(customer.first['balance_type'], equals('debit'));
      },
    );

    test(
      'Customer purchase invoice → should increase customer credit balance (له) / '
      'فاتورة مشتريات للعميل → تزيد رصيد العميل الدائن (له)',
      () async {
        // A "customer purchase invoice" means the customer is returning goods
        // or we're buying from the customer, so we owe them.
        const purchaseAmount = 4000.0;
        final journalId = DateTime.now().microsecondsSinceEpoch + 33;

        final customerId = await _insertCustomer(
          name: 'عميل فاتورة مشتريات',
          balance: 0.0,
          currency: 'YER',
        );

        final customersAccount = await _findAccountByCode('1200');
        final purchasesAccount = await _findAccountByCode('3100');
        expect(customersAccount, isNotNull);
        expect(purchasesAccount, isNotNull);

        // Purchase from customer journal:
        // Debit: Purchases (3100) — cost of goods
        // Credit: Customers (1200) — we owe customer
        final amountCents = MoneyHelper.toCents(purchaseAmount);
        await _insertTransaction(
          accountId: purchasesAccount!['id'] as int,
          journalId: journalId,
          debit: amountCents,
          credit: 0,
          referenceType: 'purchase',
          description: 'مشتريات من عميل - المشتريات مدين',
        );
        await _insertTransaction(
          accountId: customersAccount!['id'] as int,
          journalId: journalId,
          debit: 0,
          credit: amountCents,
          referenceType: 'purchase',
          description: 'مشتريات من عميل - العميل دائن',
        );

        await _assertJournalBalanced(journalId);

        // Purchase → we owe customer → credit effect
        await _applyEntityBalanceChange(
          tableName: 'customers',
          entityId: customerId,
          signedChange: purchaseAmount, // credit effect
        );

        final customer = await db
            .query('customers', where: 'id = ?', whereArgs: [customerId]);
        expect(MoneyHelper.readMoney(customer.first['balance']),
            equals(purchaseAmount));
        expect(customer.first['balance_type'], equals('credit'));
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════
  //  Group 6: Supplier Movements / Voucher Impact
  //  حركات المورد / تأثير السندات
  // ══════════════════════════════════════════════════════════════════

  group('Supplier Movements / Voucher Impact — حركات المورد وتأثير السندات',
      () {
    test(
      'Payment voucher for supplier → creates balanced journal (debit supplier 2100, credit cash 1100) / '
      'سند صرف للمورد → قيد متوازن (مدين المورد 2100، دائن الصندوق 1100)',
      () async {
        const paymentAmount = 6000.0;
        final journalId = DateTime.now().microsecondsSinceEpoch + 40;

        final supplierId = await _insertSupplier(
          name: 'مورد سند صرف',
          balance: 10000.0,
          balanceType: 'credit',
          currency: 'YER',
        );

        final cashAccount = await _findAccountByCode('1100');
        final suppliersAccount = await _findAccountByCode('2100');
        expect(cashAccount, isNotNull);
        expect(suppliersAccount, isNotNull);

        // Payment to supplier journal:
        // Debit: Suppliers Payable (2100) — reduces what we owe
        // Credit: Cash (1100) — cash goes out
        final amountCents = MoneyHelper.toCents(paymentAmount);
        await _insertTransaction(
          accountId: suppliersAccount!['id'] as int,
          journalId: journalId,
          debit: amountCents,
          credit: 0,
          description: 'سند صرف للمورد - المورد مدين',
        );
        await _insertTransaction(
          accountId: cashAccount!['id'] as int,
          journalId: journalId,
          debit: 0,
          credit: amountCents,
          description: 'سند صرف للمورد - الصندوق دائن',
        );

        await _assertJournalBalanced(journalId);

        // Verify supplier account debited (reduces liability)
        final txnSupplier = await db.rawQuery(
          "SELECT * FROM transactions WHERE journal_id = ? AND account_id = ?",
          [journalId, suppliersAccount['id']],
        );
        expect(txnSupplier.first['debit'], equals(amountCents));

        // Apply payment to supplier (debit effect = -amount)
        await _applyEntityBalanceChange(
          tableName: 'suppliers',
          entityId: supplierId,
          signedChange: -paymentAmount,
        );

        // Was credit 10000, debit effect -6000 → signed: 10000 - 6000 = 4000 → credit 4000
        final supplier = await db
            .query('suppliers', where: 'id = ?', whereArgs: [supplierId]);
        expect(
            MoneyHelper.readMoney(supplier.first['balance']), equals(4000.0));
        expect(supplier.first['balance_type'], equals('credit'));
      },
    );

    test(
      'Receipt voucher for supplier → creates balanced journal (debit cash 1100, credit supplier 2100) / '
      'سند قبض من المورد → قيد متوازن (مدين الصندوق 1100، دائن المورد 2100)',
      () async {
        const receiptAmount = 3000.0;
        final journalId = DateTime.now().microsecondsSinceEpoch + 41;

        final supplierId = await _insertSupplier(
          name: 'مورد سند قبض',
          balance: 5000.0,
          balanceType: 'debit', // supplier owes us
          currency: 'YER',
        );

        final cashAccount = await _findAccountByCode('1100');
        final suppliersAccount = await _findAccountByCode('2100');
        expect(cashAccount, isNotNull);
        expect(suppliersAccount, isNotNull);

        // Receipt from supplier (e.g., supplier refunds us for a return):
        // Debit: Cash (1100) — money comes in
        // Credit: Suppliers Payable (2100) — we now owe supplier more
        final amountCents = MoneyHelper.toCents(receiptAmount);
        await _insertTransaction(
          accountId: cashAccount!['id'] as int,
          journalId: journalId,
          debit: amountCents,
          credit: 0,
          description: 'سند قبض من مورد - الصندوق مدين',
        );
        await _insertTransaction(
          accountId: suppliersAccount!['id'] as int,
          journalId: journalId,
          debit: 0,
          credit: amountCents,
          description: 'سند قبض من مورد - المورد دائن',
        );

        await _assertJournalBalanced(journalId);

        // Apply receipt to supplier (credit effect = +amount)
        await _applyEntityBalanceChange(
          tableName: 'suppliers',
          entityId: supplierId,
          signedChange: receiptAmount,
        );

        // Was debit 5000, credit effect +3000 → signed: -5000 + 3000 = -2000 → debit 2000
        final supplier = await db
            .query('suppliers', where: 'id = ?', whereArgs: [supplierId]);
        expect(
            MoneyHelper.readMoney(supplier.first['balance']), equals(2000.0));
        expect(supplier.first['balance_type'], equals('debit'));
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════
  //  Group 7: Account Balance Integrity
  //  سلامة أرصدة الحسابات
  // ══════════════════════════════════════════════════════════════════

  group('Account Balance Integrity — سلامة أرصدة الحسابات', () {
    test(
      'After multiple operations, sum of all account balances equals zero (accounting equation) / '
      'بعد عمليات متعددة، مجموع أرصدة جميع الحسابات يساوي صفراً (معادلة المحاسبة)',
      () async {
        // The accounting equation in signed form:
        //   Assets + Expenses = Liabilities + Equity + Revenue
        //   debit balances = credit balances
        // So: Σ(signed_balance) = 0 where:
        //   debit accounts → +balance, credit accounts → -balance

        final journalId = DateTime.now().microsecondsSinceEpoch + 50;

        final cashAccount = await _findAccountByCode('1100');
        final customersAccount = await _findAccountByCode('1200');
        final suppliersAccount = await _findAccountByCode('2100');
        final obEquityAccount = await _findAccountByCode('2901');
        final salesAccount = await _findAccountByCode('4100');
        final expenseAccount = await _findAccountByCode('5100');

        expect(cashAccount, isNotNull);
        expect(customersAccount, isNotNull);
        expect(suppliersAccount, isNotNull);
        expect(obEquityAccount, isNotNull);
        expect(salesAccount, isNotNull);
        expect(expenseAccount, isNotNull);

        // Operation 1: Opening balance equity of 50000 (credit OB Equity, debit Cash)
        final ob1 = MoneyHelper.toCents(50000.0);
        await _insertTransaction(
          accountId: cashAccount!['id'] as int,
          journalId: journalId,
          debit: ob1,
          credit: 0,
          referenceType: 'opening_balance',
          description: 'رصيد افتتاحي - صندوق',
        );
        await _insertTransaction(
          accountId: obEquityAccount!['id'] as int,
          journalId: journalId,
          debit: 0,
          credit: ob1,
          referenceType: 'opening_balance',
          description: 'رصيد افتتاحي - حقوق ملكية',
        );

        // Operation 2: Sale on credit 15000 (debit Customer, credit Sales)
        final journalId2 = journalId + 1;
        final sale1 = MoneyHelper.toCents(15000.0);
        await _insertTransaction(
          accountId: customersAccount!['id'] as int,
          journalId: journalId2,
          debit: sale1,
          credit: 0,
          referenceType: 'sale',
          description: 'مبيعات آجلة',
        );
        await _insertTransaction(
          accountId: salesAccount!['id'] as int,
          journalId: journalId2,
          debit: 0,
          credit: sale1,
          referenceType: 'sale',
          description: 'إيراد مبيعات',
        );

        // Operation 3: Purchase on credit 8000 (debit Expense, credit Supplier)
        final journalId3 = journalId + 2;
        final purchase1 = MoneyHelper.toCents(8000.0);
        await _insertTransaction(
          accountId: expenseAccount!['id'] as int,
          journalId: journalId3,
          debit: purchase1,
          credit: 0,
          referenceType: 'purchase',
          description: 'مشتريات آجلة - مصروف',
        );
        await _insertTransaction(
          accountId: suppliersAccount!['id'] as int,
          journalId: journalId3,
          debit: 0,
          credit: purchase1,
          referenceType: 'purchase',
          description: 'مشتريات آجلة - مورد',
        );

        // Verify each journal is balanced
        await _assertJournalBalanced(journalId);
        await _assertJournalBalanced(journalId2);
        await _assertJournalBalanced(journalId3);

        // Verify the accounting equation: Σ(signed_balance) = 0
        // For each account: signed_balance = balance * sign
        //   debit accounts: sign = +1
        //   credit accounts: sign = -1
        final allAccounts = await db.query('accounts');
        int totalSignedBalance = 0;
        for (final acc in allAccounts) {
          final balance = acc['balance'] as int;
          final balanceType = acc['balance_type'] as String;
          final sign = balanceType == 'debit' ? 1 : -1;
          totalSignedBalance += balance * sign;
        }
        expect(totalSignedBalance, equals(0),
            reason:
                'Accounting equation: sum of signed account balances must be zero');
      },
    );

    test(
      'Account balance_type flip when balance crosses zero (from credit to debit or vice versa) / '
      'انقلاب نوع الرصيد عند عبور الصفر (من دائن إلى مدين أو العكس)',
      () async {
        // Start with a credit-balance supplier (we owe them 5000)
        final supplierId = await _insertSupplier(
          name: 'مورد اختبار الانقلاب',
          balance: 5000.0,
          balanceType: 'credit',
          currency: 'YER',
        );

        // Verify initial state
        var supplier = await db
            .query('suppliers', where: 'id = ?', whereArgs: [supplierId]);
        expect(
            MoneyHelper.readMoney(supplier.first['balance']), equals(5000.0));
        expect(supplier.first['balance_type'], equals('credit'));

        // Pay 8000 (overpayment) → balance crosses zero → flips to debit
        await _applyEntityBalanceChange(
          tableName: 'suppliers',
          entityId: supplierId,
          signedChange: -8000.0, // debit effect (payment)
        );

        supplier = await db
            .query('suppliers', where: 'id = ?', whereArgs: [supplierId]);
        // Was credit 5000, signed: +5000, after -8000: +5000 - 8000 = -3000 → debit 3000
        expect(
            MoneyHelper.readMoney(supplier.first['balance']), equals(3000.0));
        expect(supplier.first['balance_type'], equals('debit'));

        // Now supplier sends us goods worth 4000 (credit effect) → crosses back to credit
        await _applyEntityBalanceChange(
          tableName: 'suppliers',
          entityId: supplierId,
          signedChange: 4000.0, // credit effect
        );

        supplier = await db
            .query('suppliers', where: 'id = ?', whereArgs: [supplierId]);
        // Was debit 3000, signed: -3000, after +4000: -3000 + 4000 = +1000 → credit 1000
        expect(
            MoneyHelper.readMoney(supplier.first['balance']), equals(1000.0));
        expect(supplier.first['balance_type'], equals('credit'));

        // Pay exactly 1000 → zero balance → defaults to credit
        await _applyEntityBalanceChange(
          tableName: 'suppliers',
          entityId: supplierId,
          signedChange: -1000.0,
        );

        supplier = await db
            .query('suppliers', where: 'id = ?', whereArgs: [supplierId]);
        expect(MoneyHelper.readMoney(supplier.first['balance']),
            closeTo(0.0, 0.01));
        expect(supplier.first['balance_type'], equals('credit'));

        // Test customer flip: start debit, cross to credit
        final customerId = await _insertCustomer(
          name: 'عميل اختبار الانقلاب',
          balance: 3000.0,
          balanceType: 'debit',
          currency: 'YER',
        );

        // Customer overpays us by 5000 (credit effect)
        await _applyEntityBalanceChange(
          tableName: 'customers',
          entityId: customerId,
          signedChange: 8000.0, // credit effect (receipt)
        );

        final customer = await db
            .query('customers', where: 'id = ?', whereArgs: [customerId]);
        // Was debit 3000, signed: -3000, after +8000: -3000 + 8000 = +5000 → credit 5000
        expect(
            MoneyHelper.readMoney(customer.first['balance']), equals(5000.0));
        expect(customer.first['balance_type'], equals('credit'));
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════
  //  Group 8: Trial Balance / ميزان المراجعة
  // ══════════════════════════════════════════════════════════════════

  group('Trial Balance / ميزان المراجعة', () {
    test(
      'Total debits across all transactions = Total credits across all transactions / '
      'إجمالي المدين عبر جميع المعاملات = إجمالي الدائن',
      () async {
        final journalId = DateTime.now().microsecondsSinceEpoch + 60;

        final cashAccount = await _findAccountByCode('1100');
        final obEquityAccount = await _findAccountByCode('2901');
        final customersAccount = await _findAccountByCode('1200');
        final salesAccount = await _findAccountByCode('4100');
        final suppliersAccount = await _findAccountByCode('2100');
        final expenseAccount = await _findAccountByCode('5100');

        // Create a series of balanced operations
        // OB: Debit Cash 100000, Credit OB Equity 100000
        final ob = MoneyHelper.toCents(100000.0);
        await _insertTransaction(
            accountId: cashAccount!['id'] as int,
            journalId: journalId,
            debit: ob,
            credit: 0,
            description: 'رصيد افتتاحي');
        await _insertTransaction(
            accountId: obEquityAccount!['id'] as int,
            journalId: journalId,
            debit: 0,
            credit: ob,
            description: 'رصيد افتتاحي');

        // Sale: Debit Customer 25000, Credit Sales 25000
        final journalId2 = journalId + 1;
        final sale = MoneyHelper.toCents(25000.0);
        await _insertTransaction(
            accountId: customersAccount!['id'] as int,
            journalId: journalId2,
            debit: sale,
            credit: 0,
            description: 'مبيعات');
        await _insertTransaction(
            accountId: salesAccount!['id'] as int,
            journalId: journalId2,
            debit: 0,
            credit: sale,
            description: 'مبيعات');

        // Purchase: Debit Expense 12000, Credit Supplier 12000
        final journalId3 = journalId + 2;
        final purchase = MoneyHelper.toCents(12000.0);
        await _insertTransaction(
            accountId: expenseAccount!['id'] as int,
            journalId: journalId3,
            debit: purchase,
            credit: 0,
            description: 'مشتريات');
        await _insertTransaction(
            accountId: suppliersAccount!['id'] as int,
            journalId: journalId3,
            debit: 0,
            credit: purchase,
            description: 'مشتريات');

        // Receipt from customer: Debit Cash 10000, Credit Customer 10000
        final journalId4 = journalId + 3;
        final receipt = MoneyHelper.toCents(10000.0);
        await _insertTransaction(
            accountId: cashAccount['id'] as int,
            journalId: journalId4,
            debit: receipt,
            credit: 0,
            description: 'قبض من عميل');
        await _insertTransaction(
            accountId: customersAccount['id'] as int,
            journalId: journalId4,
            debit: 0,
            credit: receipt,
            description: 'قبض من عميل');

        // Payment to supplier: Debit Supplier 7000, Credit Cash 7000
        final journalId5 = journalId + 4;
        final payment = MoneyHelper.toCents(7000.0);
        await _insertTransaction(
            accountId: suppliersAccount['id'] as int,
            journalId: journalId5,
            debit: payment,
            credit: 0,
            description: 'صرف للمورد');
        await _insertTransaction(
            accountId: cashAccount['id'] as int,
            journalId: journalId5,
            debit: 0,
            credit: payment,
            description: 'صرف للمورد');

        // Verify global trial balance
        await _assertGlobalTrialBalance();
      },
    );

    test(
      'Per-account debit sum and credit sum are consistent / '
      'مجموع المدين والدائن لكل حساب متسق',
      () async {
        final journalId = DateTime.now().microsecondsSinceEpoch + 70;

        final cashAccount = await _findAccountByCode('1100');
        final salesAccount = await _findAccountByCode('4100');

        // Two cash sales
        final amount1 = MoneyHelper.toCents(5000.0);
        final amount2 = MoneyHelper.toCents(3000.0);

        // Sale 1
        await _insertTransaction(
            accountId: cashAccount!['id'] as int,
            journalId: journalId,
            debit: amount1,
            credit: 0,
            description: 'نقدية 1');
        await _insertTransaction(
            accountId: salesAccount!['id'] as int,
            journalId: journalId,
            debit: 0,
            credit: amount1,
            description: 'مبيعات 1');

        // Sale 2
        final journalId2 = journalId + 1;
        await _insertTransaction(
            accountId: cashAccount['id'] as int,
            journalId: journalId2,
            debit: amount2,
            credit: 0,
            description: 'نقدية 2');
        await _insertTransaction(
            accountId: salesAccount['id'] as int,
            journalId: journalId2,
            debit: 0,
            credit: amount2,
            description: 'مبيعات 2');

        // Check per-account totals for Cash (1100)
        final cashTotals = await db.rawQuery(
          'SELECT CAST(COALESCE(SUM(debit), 0) AS INTEGER) AS total_debit, '
          'CAST(COALESCE(SUM(credit), 0) AS INTEGER) AS total_credit '
          'FROM transactions WHERE account_id = ?',
          [cashAccount['id']],
        );
        expect(cashTotals.first['total_debit'], equals(amount1 + amount2));
        expect(cashTotals.first['total_credit'], equals(0));

        // Check per-account totals for Sales (4100)
        final salesTotals = await db.rawQuery(
          'SELECT CAST(COALESCE(SUM(debit), 0) AS INTEGER) AS total_debit, '
          'CAST(COALESCE(SUM(credit), 0) AS INTEGER) AS total_credit '
          'FROM transactions WHERE account_id = ?',
          [salesAccount['id']],
        );
        expect(salesTotals.first['total_debit'], equals(0));
        expect(salesTotals.first['total_credit'], equals(amount1 + amount2));

        // Verify net across both accounts
        final netTotals = await db.rawQuery(
          'SELECT CAST(COALESCE(SUM(debit), 0) AS INTEGER) AS total_debit, '
          'CAST(COALESCE(SUM(credit), 0) AS INTEGER) AS total_credit '
          'FROM transactions WHERE account_id IN (?, ?)',
          [cashAccount['id'], salesAccount['id']],
        );
        expect(netTotals.first['total_debit'], equals(amount1 + amount2));
        expect(netTotals.first['total_credit'], equals(amount1 + amount2));
      },
    );

    test(
      'Trial balance holds after complex multi-currency operations / '
      'ميزان المراجعة متوازن بعد عمليات متعددة العملات',
      () async {
        final journalId = DateTime.now().microsecondsSinceEpoch + 80;

        final cashYerAccount = await _findAccountByCode('1100');
        final cashUsdAccount = await _findAccountByCode('1102');
        final obEquityAccount = await _findAccountByCode('2901');
        final obEquityUsdAccount = await _findAccountByCode('2903');

        expect(cashYerAccount, isNotNull);
        expect(cashUsdAccount, isNotNull);
        expect(obEquityAccount, isNotNull);
        expect(obEquityUsdAccount, isNotNull);

        // OB in YER: Debit Cash 500000, Credit OB Equity 500000
        final obYer = MoneyHelper.toCents(500000.0);
        await _insertTransaction(
            accountId: cashYerAccount!['id'] as int,
            journalId: journalId,
            debit: obYer,
            credit: 0,
            currencyCode: 'YER',
            amountBase: obYer,
            description: 'OB YER');
        await _insertTransaction(
            accountId: obEquityAccount!['id'] as int,
            journalId: journalId,
            debit: 0,
            credit: obYer,
            currencyCode: 'YER',
            amountBase: obYer,
            description: 'OB YER');

        // OB in USD: Debit Cash-USD 1000, Credit OB Equity-USD 1000
        final journalId2 = journalId + 1;
        final obUsd = MoneyHelper.toCents(1000.0);
        final obUsdBase = obUsd * 530; // 1000 USD * 530 = 530000 YER base
        await _insertTransaction(
            accountId: cashUsdAccount!['id'] as int,
            journalId: journalId2,
            debit: obUsd,
            credit: 0,
            currencyCode: 'USD',
            exchangeRate: 530.0,
            amountBase: obUsdBase,
            description: 'OB USD');
        await _insertTransaction(
            accountId: obEquityUsdAccount!['id'] as int,
            journalId: journalId2,
            debit: 0,
            credit: obUsd,
            currencyCode: 'USD',
            exchangeRate: 530.0,
            amountBase: obUsdBase,
            description: 'OB USD');

        // Verify each journal balanced
        await _assertJournalBalanced(journalId);
        await _assertJournalBalanced(journalId2);

        // Verify global trial balance
        await _assertGlobalTrialBalance();
      },
    );
  });
}
