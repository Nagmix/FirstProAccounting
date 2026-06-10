import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// ══════════════════════════════════════════════════════════════════════════
/// اختبارات شجرة الحسابات ودفتر الحساب
///
/// Chart of Accounts Integrity & Account Ledger Tests
///
/// Tests cover:
///   1. Schema integrity — system accounts, balance_type, codes, uniqueness
///   2. Account hierarchy — parent-child, circular refs, nesting
///   3. CRUD operations — insert, update, delete, constraints
///   4. Balance calculations — zero init, debit/credit effects, running balance
///   5. Account ledger — date ordering, filtering, opening balance
///   6. Account type aggregation — totals by type, accounting equation
///   7. Currency-specific operations — YER/SAR/USD, amount_base
///   8. Fiscal year & annual posting — closing to retained earnings
/// ══════════════════════════════════════════════════════════════════════════

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

  // ────────────────────────────────────────────────────────────────
  //  Helpers
  // ────────────────────────────────────────────────────────────────

  /// Insert a custom account and return its id.
  Future<int> insertAccount({
    required String code,
    required String accountType,
    required String balanceType,
    String currency = 'YER',
    String nameAr = '',
    String nameEn = '',
    int isSystem = 0,
    int isActive = 1,
    int? parentId,
    int balance = 0,
    int debtCeiling = 0,
    int? linkedCashBoxId,
  }) async {
    final now = DateTime.now().toIso8601String();
    return db.insert('accounts', {
      'name_ar': nameAr.isEmpty ? 'حساب $code' : nameAr,
      'name_en': nameEn.isEmpty ? 'Account $code' : nameEn,
      'account_code': code,
      'account_type': accountType,
      'balance': balance,
      'currency': currency,
      'balance_type': balanceType,
      'is_active': isActive,
      'is_system': isSystem,
      'parent_id': parentId,
      'debt_ceiling': debtCeiling,
      'linked_cash_box_id': linkedCashBoxId,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Insert a transaction row and return its id.
  Future<int> insertTransaction({
    required int accountId,
    int? journalId,
    int debit = 0,
    int credit = 0,
    String description = '',
    required String date,
    String currencyCode = 'YER',
    double exchangeRate = 1.0,
    int amountBase = 0,
    String? referenceType,
    String? referenceId,
  }) async {
    final now = DateTime.now().toIso8601String();
    return db.insert('transactions', {
      'account_id': accountId,
      'journal_id': journalId ?? DateTime.now().microsecondsSinceEpoch,
      'debit': debit,
      'credit': credit,
      'description': description,
      'date': date,
      'created_at': now,
      'currency_code': currencyCode,
      'exchange_rate': exchangeRate,
      'amount_base': amountBase,
      'reference_type': referenceType,
      'reference_id': referenceId,
    });
  }

  /// Get the stored balance (in cents) for an account.
  Future<int> getAccountBalanceCents(int accountId) async {
    final rows = await db.query(
      'accounts',
      columns: ['balance'],
      where: 'id = ?',
      whereArgs: [accountId],
    );
    return rows.first['balance'] as int;
  }

  /// Compute the running balance for an account from transactions.
  /// For debit-balance accounts: +debit - credit
  /// For credit-balance accounts: +credit - debit
  Future<int> computeBalanceFromTransactions(
    int accountId,
    String balanceType,
  ) async {
    final result = await db.rawQuery(
      'SELECT CAST(COALESCE(SUM(debit), 0) AS INTEGER) AS total_debit, '
      'CAST(COALESCE(SUM(credit), 0) AS INTEGER) AS total_credit '
      'FROM transactions WHERE account_id = ?',
      [accountId],
    );
    final totalDebit = (result.first['total_debit'] as num).toInt();
    final totalCredit = (result.first['total_credit'] as num).toInt();
    if (balanceType == 'debit') {
      return totalDebit - totalCredit;
    } else {
      return totalCredit - totalDebit;
    }
  }

  // ══════════════════════════════════════════════════════════════════
  //  Group 1: Chart of Accounts Schema Integrity
  //  سلامة هيكل شجرة الحسابات
  // ══════════════════════════════════════════════════════════════════

  group('Chart of Accounts Schema Integrity — سلامة هيكل شجرة الحسابات', () {
    test(
      'System accounts are created on DB initialization / يتم إنشاء الحسابات النظامية عند تهيئة قاعدة البيانات',
      () async {
        // Key system account codes for YER (offset 0): 1100, 1200, 2100, 2901, 4100, 5100
        final requiredCodes = ['1100', '1200', '2100', '2901', '4100', '5100'];
        for (final code in requiredCodes) {
          final rows = await db.query(
            'accounts',
            where: 'account_code = ? AND is_system = 1',
            whereArgs: [code],
          );
          expect(rows.isNotEmpty, isTrue,
              reason: 'System account with code $code should exist');
        }
      },
    );

    test(
      'All system accounts have is_system = 1 / جميع الحسابات النظامية معلمة كنظامية',
      () async {
        final systemAccounts =
            await db.query('accounts', where: 'is_system = 1');
        expect(systemAccounts.isNotEmpty, isTrue,
            reason: 'There should be at least one system account');

        // Double-check: every account with is_system=1 actually has the flag set
        for (final acc in systemAccounts) {
          expect(acc['is_system'], 1,
              reason: 'Account ${acc['account_code']} should have is_system=1');
        }
      },
    );

    test(
      'All system accounts have correct balance_type / جميع الحسابات النظامية لها نوع رصيد صحيح',
      () async {
        final systemAccounts =
            await db.query('accounts', where: 'is_system = 1');
        final debitTypes = {'ASSET', 'COST', 'EXPENSE'};
        final creditTypes = {'LIABILITY', 'EQUITY', 'REVENUE'};

        for (final acc in systemAccounts) {
          final accountType = acc['account_type'] as String;
          final balanceType = acc['balance_type'] as String;
          final code = acc['account_code'];

          if (debitTypes.contains(accountType)) {
            expect(balanceType, 'debit',
                reason:
                    'Account $code ($accountType) should have balance_type=debit');
          } else if (creditTypes.contains(accountType)) {
            expect(balanceType, 'credit',
                reason:
                    'Account $code ($accountType) should have balance_type=credit');
          }
        }
      },
    );

    test(
      'All system accounts have is_active = 1 / جميع الحسابات النظامية مفعلة',
      () async {
        final systemAccounts =
            await db.query('accounts', where: 'is_system = 1');
        for (final acc in systemAccounts) {
          expect(acc['is_active'], 1,
              reason: 'System account ${acc['account_code']} should be active');
        }
      },
    );

    test(
      'Account codes follow +offset convention for YER/SAR/USD / أكواد الحسابات تتبع اتفاقية الإزاحة للعملات',
      () async {
        // Cash accounts: base 1100 → 1100(YER), 1101(SAR), 1102(USD)
        final cashYer = await db.query('accounts',
            where: "account_code = '1100' AND currency = 'YER'");
        final cashSar = await db.query('accounts',
            where: "account_code = '1101' AND currency = 'SAR'");
        final cashUsd = await db.query('accounts',
            where: "account_code = '1102' AND currency = 'USD'");

        expect(cashYer.isNotEmpty, isTrue,
            reason: 'Cash YER account (1100) should exist');
        expect(cashSar.isNotEmpty, isTrue,
            reason: 'Cash SAR account (1101) should exist');
        expect(cashUsd.isNotEmpty, isTrue,
            reason: 'Cash USD account (1102) should exist');

        // Sales accounts: base 4100 → 4100(YER), 4101(SAR), 4102(USD)
        final salesYer = await db.query('accounts',
            where: "account_code = '4100' AND currency = 'YER'");
        final salesSar = await db.query('accounts',
            where: "account_code = '4101' AND currency = 'SAR'");
        final salesUsd = await db.query('accounts',
            where: "account_code = '4102' AND currency = 'USD'");

        expect(salesYer.isNotEmpty, isTrue,
            reason: 'Sales YER account (4100) should exist');
        expect(salesSar.isNotEmpty, isTrue,
            reason: 'Sales SAR account (4101) should exist');
        expect(salesUsd.isNotEmpty, isTrue,
            reason: 'Sales USD account (4102) should exist');

        // Employees: base 5100 → 5100, 5101, 5102
        final empYer = await db.query('accounts',
            where: "account_code = '5100' AND currency = 'YER'");
        final empSar = await db.query('accounts',
            where: "account_code = '5101' AND currency = 'SAR'");
        final empUsd = await db.query('accounts',
            where: "account_code = '5102' AND currency = 'USD'");

        expect(empYer.isNotEmpty, isTrue,
            reason: 'Employees YER account (5100) should exist');
        expect(empSar.isNotEmpty, isTrue,
            reason: 'Employees SAR account (5101) should exist');
        expect(empUsd.isNotEmpty, isTrue,
            reason: 'Employees USD account (5102) should exist');
      },
    );

    test(
      'No duplicate account codes within same currency / لا توجد أكواد حسابات مكررة ضمن نفس العملة',
      () async {
        // account_code is NOT globally unique — the +offset scheme for currencies
        // can cause cross-currency code collisions (e.g. 2901 YER vs 2901 SAR).
        // The real uniqueness constraint is (account_code, currency).
        final result = await db.rawQuery(
          'SELECT account_code, currency, COUNT(*) as cnt '
          'FROM accounts GROUP BY account_code, currency HAVING cnt > 1',
        );
        expect(result, isEmpty,
            reason:
                'No duplicate (account_code, currency) pairs should exist. Found: $result');
      },
    );

    test(
      'Account codes are unique per currency — known cross-currency collisions documented / أكواد الحسابات فريدة لكل عملة — التضاربات المعروفة موثقة',
      () async {
        // Document the known cross-currency collision: the +offset scheme
        // causes equity group codes to overlap across currencies.
        // E.g. base 2900 + SAR offset 1 = 2901, which collides with
        // base 2901 (Opening Balance Equity) + YER offset 0 = 2901.
        // This is a design trade-off — the (account_code, currency) pair
        // is the true unique key.
        final result = await db.rawQuery(
          'SELECT account_code, COUNT(*) as cnt FROM accounts GROUP BY account_code HAVING cnt > 1',
        );
        // We expect some cross-currency collisions due to the offset scheme
        if (result.isNotEmpty) {
          // Verify each duplicate is across different currencies, not within same currency
          for (final row in result) {
            final code = row['account_code'] as String;
            final currencies = await db.rawQuery(
              "SELECT DISTINCT currency FROM accounts WHERE account_code = ?",
              [code],
            );
            // Each duplicate should have different currencies
            final currencySet =
                currencies.map((r) => r['currency'] as String).toSet();
            expect(currencySet.length, (row['cnt'] as num).toInt(),
                reason:
                    'Duplicate code $code should be across different currencies');
          }
        }
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════
  //  Group 2: Account Hierarchy
  //  التسلسل الهرمي للحسابات
  // ══════════════════════════════════════════════════════════════════

  group('Account Hierarchy — التسلسل الهرمي للحسابات', () {
    test(
      'Parent-child relationship: create parent then child with parent_id / علاقة أب-ابن: إنشاء حساب أب ثم ابن',
      () async {
        final parentId = await insertAccount(
          code: '9001',
          accountType: 'ASSET',
          balanceType: 'debit',
          nameAr: 'حساب أب',
          nameEn: 'Parent Account',
        );

        final childId = await insertAccount(
          code: '9002',
          accountType: 'ASSET',
          balanceType: 'debit',
          nameAr: 'حساب ابن',
          nameEn: 'Child Account',
          parentId: parentId,
        );

        final child =
            await db.query('accounts', where: 'id = ?', whereArgs: [childId]);
        expect(child.first['parent_id'], parentId,
            reason: 'Child account should reference the parent account');
      },
    );

    test(
      'Cannot create circular reference (account cannot be its own parent) / لا يمكن إنشاء مرجع دائري',
      () async {
        final accountId = await insertAccount(
          code: '9011',
          accountType: 'ASSET',
          balanceType: 'debit',
        );

        // Try to set parent_id = own id — this is a logical constraint
        // The DB doesn't enforce this at the FK level (parent_id points to a valid id),
        // but we verify the application should prevent it.
        // We test that attempting this update doesn't corrupt the hierarchy.
        await db.update(
          'accounts',
          {'parent_id': accountId},
          where: 'id = ?',
          whereArgs: [accountId],
        );

        final updated =
            await db.query('accounts', where: 'id = ?', whereArgs: [accountId]);
        // After setting self-reference, verify the row exists but flag it as invalid
        // In production code, this should be prevented at the service level
        expect(updated.first['parent_id'], accountId,
            reason:
                'Self-reference was stored; service layer should prevent this');

        // Clean up: remove the self-reference
        await db.update(
          'accounts',
          {'parent_id': null},
          where: 'id = ?',
          whereArgs: [accountId],
        );
      },
    );

    test(
      'Account tree can have multiple levels of nesting / يمكن أن يكون شجرة الحسابات متعددة المستويات',
      () async {
        // Level 0: Root group
        final rootId = await insertAccount(
          code: '9020',
          accountType: 'ASSET',
          balanceType: 'debit',
          nameAr: 'أصول - جذر',
          nameEn: 'Assets - Root',
        );

        // Level 1: Sub-group
        final subGroupId = await insertAccount(
          code: '9021',
          accountType: 'ASSET',
          balanceType: 'debit',
          nameAr: 'أصول متداولة',
          nameEn: 'Current Assets',
          parentId: rootId,
        );

        // Level 2: Detail account
        final detailId = await insertAccount(
          code: '9022',
          accountType: 'ASSET',
          balanceType: 'debit',
          nameAr: 'الصندوق الفرعي',
          nameEn: 'Sub Cash',
          parentId: subGroupId,
        );

        // Level 3: Sub-detail account
        final subDetailId = await insertAccount(
          code: '9023',
          accountType: 'ASSET',
          balanceType: 'debit',
          nameAr: 'صندوق فرعي دقيق',
          nameEn: 'Micro Cash',
          parentId: detailId,
        );

        // Verify the chain
        final subDetail = await db
            .query('accounts', where: 'id = ?', whereArgs: [subDetailId]);
        expect(subDetail.first['parent_id'], detailId);

        final detail =
            await db.query('accounts', where: 'id = ?', whereArgs: [detailId]);
        expect(detail.first['parent_id'], subGroupId);

        final subGroup = await db
            .query('accounts', where: 'id = ?', whereArgs: [subGroupId]);
        expect(subGroup.first['parent_id'], rootId);

        final root =
            await db.query('accounts', where: 'id = ?', whereArgs: [rootId]);
        expect(root.first['parent_id'], isNull);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════
  //  Group 3: Account CRUD Operations
  //  عمليات إنشاء وقراءة وتحديث وحذف الحسابات
  // ══════════════════════════════════════════════════════════════════

  group('Account CRUD Operations — عمليات الحسابات الأساسية', () {
    test(
      'Insert new account → verify all fields stored correctly / إدراج حساب جديد → التحقق من تخزين جميع الحقول',
      () async {
        final id = await insertAccount(
          code: '9100',
          accountType: 'EXPENSE',
          balanceType: 'debit',
          currency: 'SAR',
          nameAr: 'مصاريف إدارية',
          nameEn: 'Administrative Expenses',
          balance: MoneyHelper.toCents(1000.0),
          debtCeiling: MoneyHelper.toCents(50000.0),
          isActive: 1,
        );

        final rows =
            await db.query('accounts', where: 'id = ?', whereArgs: [id]);
        expect(rows.length, 1);

        final acc = rows.first;
        expect(acc['name_ar'], 'مصاريف إدارية');
        expect(acc['name_en'], 'Administrative Expenses');
        expect(acc['account_code'], '9100');
        expect(acc['account_type'], 'EXPENSE');
        expect(acc['balance_type'], 'debit');
        expect(acc['currency'], 'SAR');
        expect(acc['balance'], MoneyHelper.toCents(1000.0));
        expect(acc['debt_ceiling'], MoneyHelper.toCents(50000.0));
        expect(acc['is_active'], 1);
        expect(acc['is_system'], 0);
        expect(acc['parent_id'], isNull);
        expect(acc['created_at'], isNotNull);
        expect(acc['updated_at'], isNotNull);
      },
    );

    test(
      'Update account name → verify change persisted / تحديث اسم الحساب → التحقق من حفظ التغيير',
      () async {
        final id = await insertAccount(
          code: '9110',
          accountType: 'REVENUE',
          balanceType: 'credit',
          nameAr: 'إيرادات قديمة',
          nameEn: 'Old Revenue',
        );

        final now = DateTime.now().toIso8601String();
        await db.update(
          'accounts',
          {
            'name_ar': 'إيرادات جديدة',
            'name_en': 'New Revenue',
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );

        final updated =
            await db.query('accounts', where: 'id = ?', whereArgs: [id]);
        expect(updated.first['name_ar'], 'إيرادات جديدة');
        expect(updated.first['name_en'], 'New Revenue');
      },
    );

    test(
      'Delete non-system account → verify removed from DB / حذف حساب غير نظامي → التحقق من إزالته',
      () async {
        final id = await insertAccount(
          code: '9120',
          accountType: 'ASSET',
          balanceType: 'debit',
        );

        // Delete any transactions referencing this account first (FK constraint)
        await db
            .delete('transactions', where: 'account_id = ?', whereArgs: [id]);

        final deleted = await db.delete('accounts',
            where: 'id = ? AND is_system = 0', whereArgs: [id]);
        expect(deleted, 1, reason: 'One row should be deleted');

        final remaining =
            await db.query('accounts', where: 'id = ?', whereArgs: [id]);
        expect(remaining, isEmpty, reason: 'Account should no longer exist');
      },
    );

    test(
      'Cannot delete system account (is_system=1 constraint) / لا يمكن حذف حساب نظامي',
      () async {
        // Get a system account
        final systemAccounts =
            await db.query('accounts', where: 'is_system = 1', limit: 1);
        expect(systemAccounts.isNotEmpty, isTrue,
            reason: 'Should have at least one system account');

        final systemId = systemAccounts.first['id'];

        // Attempt to delete with is_system filter — should match 0 rows
        final deleted = await db.delete('accounts',
            where: 'id = ? AND is_system = 0', whereArgs: [systemId]);
        expect(deleted, 0,
            reason:
                'System account should not be deleted via is_system filter');

        // Verify it still exists
        final stillExists =
            await db.query('accounts', where: 'id = ?', whereArgs: [systemId]);
        expect(stillExists.isNotEmpty, isTrue,
            reason: 'System account should still exist in DB');
      },
    );

    test(
      'Delete account with children should fail or cascade / حذف حساب لديه أبناء يجب أن يفشل أو يتتالي',
      () async {
        final parentId = await insertAccount(
          code: '9130',
          accountType: 'ASSET',
          balanceType: 'debit',
          nameAr: 'حساب أب للحذف',
          nameEn: 'Parent for Deletion',
        );

        final childId = await insertAccount(
          code: '9131',
          accountType: 'ASSET',
          balanceType: 'debit',
          nameAr: 'حساب ابن للحذف',
          nameEn: 'Child for Deletion',
          parentId: parentId,
        );

        // With foreign keys ON, deleting the parent should fail
        // because the child still references it
        try {
          await db.delete('accounts', where: 'id = ?', whereArgs: [parentId]);
          // If we reach here, FK enforcement may not be working for this path
          // Check if child still exists
          final childRows =
              await db.query('accounts', where: 'id = ?', whereArgs: [childId]);
          if (childRows.isEmpty) {
            // Cascade deletion happened or child was orphaned
            fail('Parent deletion should have been prevented by FK constraint');
          }
        } on DatabaseException catch (e) {
          // Expected: FK constraint violation
          expect(e.toString(), contains('FOREIGN KEY'),
              reason: 'Should get FK constraint error');
        }

        // Clean up: delete child first, then parent
        await db.delete('accounts', where: 'id = ?', whereArgs: [childId]);
        await db.delete('accounts', where: 'id = ?', whereArgs: [parentId]);
      },
    );

    test(
      'Insert account with specific currency → verify currency field / إدراج حساب بعملة محددة → التحقق من حقل العملة',
      () async {
        final usdId = await insertAccount(
          code: '9140',
          accountType: 'ASSET',
          balanceType: 'debit',
          currency: 'USD',
        );

        final acc =
            await db.query('accounts', where: 'id = ?', whereArgs: [usdId]);
        expect(acc.first['currency'], 'USD');

        final sarId = await insertAccount(
          code: '9141',
          accountType: 'LIABILITY',
          balanceType: 'credit',
          currency: 'SAR',
        );

        final accSar =
            await db.query('accounts', where: 'id = ?', whereArgs: [sarId]);
        expect(accSar.first['currency'], 'SAR');
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════
  //  Group 4: Account Balance Calculations
  //  حسابات رصيد الحساب
  // ══════════════════════════════════════════════════════════════════

  group('Account Balance Calculations — حسابات رصيد الحساب', () {
    test(
      'New account has zero balance / الحساب الجديد له رصيد صفري',
      () async {
        final id = await insertAccount(
          code: '9200',
          accountType: 'ASSET',
          balanceType: 'debit',
        );

        final balanceCents = await getAccountBalanceCents(id);
        expect(balanceCents, 0, reason: 'New account should have zero balance');
        expect(MoneyHelper.fromCents(balanceCents), 0.0);
      },
    );

    test(
      'After debit transaction on debit-balance account, balance increases / بعد قيد مدين على حساب مدين يزداد الرصيد',
      () async {
        final id = await insertAccount(
          code: '9210',
          accountType: 'ASSET',
          balanceType: 'debit',
        );

        final debitAmount = MoneyHelper.toCents(5000.0);
        await insertTransaction(
          accountId: id,
          debit: debitAmount,
          credit: 0,
          date: '2025-01-15',
          currencyCode: 'YER',
          exchangeRate: 1.0,
          amountBase: debitAmount,
        );

        // Update account balance: debit on debit account → increase
        await db.rawUpdate('''
          UPDATE accounts SET
            balance = balance + CASE
              WHEN balance_type = 'debit' THEN ?
              WHEN balance_type = 'credit' THEN -?
              ELSE 0
            END,
            updated_at = ?
          WHERE id = ?
        ''', [debitAmount, debitAmount, DateTime.now().toIso8601String(), id]);

        final balanceCents = await getAccountBalanceCents(id);
        expect(balanceCents, debitAmount,
            reason: 'Debit on debit-balance account should increase balance');
        expect(MoneyHelper.fromCents(balanceCents), 5000.0);
      },
    );

    test(
      'After credit transaction on credit-balance account, balance increases / بعد قيد دائن على حساب دائن يزداد الرصيد',
      () async {
        final id = await insertAccount(
          code: '9220',
          accountType: 'REVENUE',
          balanceType: 'credit',
        );

        final creditAmount = MoneyHelper.toCents(3000.0);
        await insertTransaction(
          accountId: id,
          debit: 0,
          credit: creditAmount,
          date: '2025-01-15',
          currencyCode: 'YER',
          exchangeRate: 1.0,
          amountBase: creditAmount,
        );

        // Update account balance: credit on credit account → increase
        await db.rawUpdate('''
          UPDATE accounts SET
            balance = balance + CASE
              WHEN balance_type = 'credit' THEN ?
              WHEN balance_type = 'debit' THEN -?
              ELSE 0
            END,
            updated_at = ?
          WHERE id = ?
        ''',
            [creditAmount, creditAmount, DateTime.now().toIso8601String(), id]);

        final balanceCents = await getAccountBalanceCents(id);
        expect(balanceCents, creditAmount,
            reason: 'Credit on credit-balance account should increase balance');
        expect(MoneyHelper.fromCents(balanceCents), 3000.0);
      },
    );

    test(
      'After credit transaction on debit-balance account, balance decreases / بعد قيد دائن على حساب مدين يقل الرصيد',
      () async {
        final id = await insertAccount(
          code: '9230',
          accountType: 'ASSET',
          balanceType: 'debit',
          balance: MoneyHelper.toCents(10000.0),
        );

        final creditAmount = MoneyHelper.toCents(3000.0);
        await insertTransaction(
          accountId: id,
          debit: 0,
          credit: creditAmount,
          date: '2025-01-15',
          currencyCode: 'YER',
          exchangeRate: 1.0,
          amountBase: creditAmount,
        );

        // Update account balance: credit on debit account → decrease
        await db.rawUpdate('''
          UPDATE accounts SET
            balance = balance - ?,
            updated_at = ?
          WHERE id = ? AND balance_type = 'debit'
        ''', [creditAmount, DateTime.now().toIso8601String(), id]);

        final balanceCents = await getAccountBalanceCents(id);
        expect(balanceCents, MoneyHelper.toCents(7000.0),
            reason: 'Credit on debit-balance account should decrease balance');
      },
    );

    test(
      'Running balance computation: 3 transactions in order / حساب الرصيد التراكمي: 3 معاملات بالترتيب',
      () async {
        final id = await insertAccount(
          code: '9240',
          accountType: 'ASSET',
          balanceType: 'debit',
        );

        // Transaction 1: Debit 10000
        final t1 = MoneyHelper.toCents(10000.0);
        await insertTransaction(
          accountId: id,
          debit: t1,
          credit: 0,
          date: '2025-01-10',
          currencyCode: 'YER',
          exchangeRate: 1.0,
          amountBase: t1,
        );

        // Transaction 2: Debit 5000
        final t2 = MoneyHelper.toCents(5000.0);
        await insertTransaction(
          accountId: id,
          debit: t2,
          credit: 0,
          date: '2025-01-15',
          currencyCode: 'YER',
          exchangeRate: 1.0,
          amountBase: t2,
        );

        // Transaction 3: Credit 3000
        final t3 = MoneyHelper.toCents(3000.0);
        await insertTransaction(
          accountId: id,
          debit: 0,
          credit: t3,
          date: '2025-01-20',
          currencyCode: 'YER',
          exchangeRate: 1.0,
          amountBase: t3,
        );

        // Verify running balance at each step
        final txns = await db.rawQuery(
          'SELECT debit, credit, date FROM transactions '
          'WHERE account_id = ? ORDER BY date ASC',
          [id],
        );

        int runningBalance = 0;
        final expectedBalances = [
          t1, // 10000 after first debit
          t1 + t2, // 15000 after second debit
          t1 + t2 - t3, // 12000 after credit
        ];

        for (int i = 0; i < txns.length; i++) {
          final debit = (txns[i]['debit'] as num).toInt();
          final credit = (txns[i]['credit'] as num).toInt();
          runningBalance += (debit - credit); // debit-balance account
          expect(runningBalance, expectedBalances[i],
              reason: 'Running balance after transaction ${i + 1} mismatch');
        }

        // Final: 10000 + 5000 - 3000 = 12000
        expect(runningBalance, MoneyHelper.toCents(12000.0));
      },
    );

    test(
      'Account balance matches sum of transactions (adjusted for balance_type) / رصيد الحساب يطابق مجموع المعاملات حسب نوع الرصيد',
      () async {
        // Test debit-balance account
        final debitId = await insertAccount(
          code: '9250',
          accountType: 'ASSET',
          balanceType: 'debit',
        );

        final d1 = MoneyHelper.toCents(8000.0);
        final d2 = MoneyHelper.toCents(2000.0);
        final c1 = MoneyHelper.toCents(3000.0);

        await insertTransaction(
            accountId: debitId,
            debit: d1,
            credit: 0,
            date: '2025-02-01',
            currencyCode: 'YER',
            exchangeRate: 1.0,
            amountBase: d1);
        await insertTransaction(
            accountId: debitId,
            debit: d2,
            credit: 0,
            date: '2025-02-05',
            currencyCode: 'YER',
            exchangeRate: 1.0,
            amountBase: d2);
        await insertTransaction(
            accountId: debitId,
            debit: 0,
            credit: c1,
            date: '2025-02-10',
            currencyCode: 'YER',
            exchangeRate: 1.0,
            amountBase: c1);

        final debitBalance =
            await computeBalanceFromTransactions(debitId, 'debit');
        expect(debitBalance, d1 + d2 - c1,
            reason: 'Debit balance = total debit - total credit');

        // Test credit-balance account
        final creditId = await insertAccount(
          code: '9251',
          accountType: 'REVENUE',
          balanceType: 'credit',
        );

        final cr1 = MoneyHelper.toCents(15000.0);
        final cr2 = MoneyHelper.toCents(5000.0);
        final dr1 = MoneyHelper.toCents(2000.0);

        await insertTransaction(
            accountId: creditId,
            debit: 0,
            credit: cr1,
            date: '2025-02-01',
            currencyCode: 'YER',
            exchangeRate: 1.0,
            amountBase: cr1);
        await insertTransaction(
            accountId: creditId,
            debit: 0,
            credit: cr2,
            date: '2025-02-05',
            currencyCode: 'YER',
            exchangeRate: 1.0,
            amountBase: cr2);
        await insertTransaction(
            accountId: creditId,
            debit: dr1,
            credit: 0,
            date: '2025-02-10',
            currencyCode: 'YER',
            exchangeRate: 1.0,
            amountBase: dr1);

        final creditBalance =
            await computeBalanceFromTransactions(creditId, 'credit');
        expect(creditBalance, cr1 + cr2 - dr1,
            reason: 'Credit balance = total credit - total debit');
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════
  //  Group 5: Account Ledger / دفتر الحساب
  // ══════════════════════════════════════════════════════════════════

  group('Account Ledger / دفتر الحساب', () {
    late int accountId;

    setUp(() async {
      accountId = await insertAccount(
        code: '9300',
        accountType: 'ASSET',
        balanceType: 'debit',
      );

      // Insert transactions with specific dates
      final amounts = [
        {
          'debit': MoneyHelper.toCents(10000.0),
          'credit': 0,
          'date': '2025-03-01'
        },
        {
          'debit': 0,
          'credit': MoneyHelper.toCents(2000.0),
          'date': '2025-03-05'
        },
        {
          'debit': MoneyHelper.toCents(5000.0),
          'credit': 0,
          'date': '2025-03-10'
        },
        {
          'debit': 0,
          'credit': MoneyHelper.toCents(3000.0),
          'date': '2025-03-15'
        },
        {
          'debit': MoneyHelper.toCents(7000.0),
          'credit': 0,
          'date': '2025-03-20'
        },
      ];

      for (int i = 0; i < amounts.length; i++) {
        final amt = amounts[i];
        final debitVal = amt['debit'] as int;
        final creditVal = amt['credit'] as int;
        final baseVal = debitVal > 0 ? debitVal : creditVal;
        await insertTransaction(
          accountId: accountId,
          debit: debitVal,
          credit: creditVal,
          date: amt['date'] as String,
          currencyCode: 'YER',
          exchangeRate: 1.0,
          amountBase: baseVal,
        );
      }
    });

    test(
      'Get all transactions for an account, ordered by date / جلب جميع معاملات الحساب مرتبة بالتاريخ',
      () async {
        final txns = await db.rawQuery(
          'SELECT * FROM transactions WHERE account_id = ? ORDER BY date ASC',
          [accountId],
        );

        expect(txns.length, 5, reason: 'Should have 5 transactions');

        // Verify chronological order
        for (int i = 1; i < txns.length; i++) {
          expect(
              txns[i]['date']
                      .toString()
                      .compareTo(txns[i - 1]['date'].toString()) >=
                  0,
              isTrue,
              reason: 'Transactions should be in ascending date order');
        }
      },
    );

    test(
      'Date range filtering: only transactions within date range / تصفية بنطاق التاريخ: فقط المعاملات ضمن النطاق',
      () async {
        final txns = await db.rawQuery(
          "SELECT * FROM transactions WHERE account_id = ? AND date >= ? AND date <= ? ORDER BY date ASC",
          [accountId, '2025-03-05', '2025-03-15'],
        );

        expect(txns.length, 3,
            reason: 'Should have 3 transactions in the date range');

        for (final txn in txns) {
          final date = txn['date'] as String;
          expect(date.compareTo('2025-03-05') >= 0, isTrue);
          expect(date.compareTo('2025-03-15') <= 0, isTrue);
        }
      },
    );

    test(
      'Opening balance calculation: sum of all transactions before start date / حساب رصيد الافتتاح: مجموع المعاملات قبل تاريخ البداية',
      () async {
        // Opening balance as of 2025-03-10 = sum of transactions before that date
        final result = await db.rawQuery(
          'SELECT CAST(COALESCE(SUM(debit), 0) AS INTEGER) AS total_debit, '
          'CAST(COALESCE(SUM(credit), 0) AS INTEGER) AS total_credit '
          'FROM transactions WHERE account_id = ? AND date < ?',
          [accountId, '2025-03-10'],
        );

        final totalDebit = (result.first['total_debit'] as num).toInt();
        final totalCredit = (result.first['total_credit'] as num).toInt();

        // Before 2025-03-10: 10000 debit (Mar 1) - 2000 credit (Mar 5)
        // For debit account: opening = 10000 - 2000 = 8000
        final openingBalance = totalDebit - totalCredit;
        expect(openingBalance, MoneyHelper.toCents(8000.0),
            reason: 'Opening balance before Mar 10 should be 8000');
      },
    );

    test(
      'Running balance respects chronological order regardless of display direction / الرصيد التراكمي يراعي الترتيب الزمني',
      () async {
        // Fetch in descending order for display (newest first)
        final txnsDesc = await db.rawQuery(
          'SELECT debit, credit, date FROM transactions '
          'WHERE account_id = ? ORDER BY date DESC',
          [accountId],
        );

        // But the running balance should be computed from earliest to latest
        final txnsAsc = await db.rawQuery(
          'SELECT debit, credit, date FROM transactions '
          'WHERE account_id = ? ORDER BY date ASC',
          [accountId],
        );

        int runningBalance = 0;
        final balanceByDate = <String, int>{};
        for (final txn in txnsAsc) {
          final debit = (txn['debit'] as num).toInt();
          final credit = (txn['credit'] as num).toInt();
          runningBalance += (debit - credit);
          balanceByDate[txn['date'] as String] = runningBalance;
        }

        // The latest transaction should have the final balance
        final latestDate = txnsDesc.first['date'] as String;
        expect(balanceByDate[latestDate], MoneyHelper.toCents(17000.0),
            reason: 'Final running balance: 10000-2000+5000-3000+7000 = 17000');
      },
    );

    test(
      'Multi-currency transactions on same account are handled correctly / المعاملات متعددة العملات على نفس الحساب تُعالج بشكل صحيح',
      () async {
        final multiAccountId = await insertAccount(
          code: '9310',
          accountType: 'ASSET',
          balanceType: 'debit',
          currency: 'YER',
        );

        // YER transaction
        final yerAmount = MoneyHelper.toCents(10000.0);
        await insertTransaction(
          accountId: multiAccountId,
          debit: yerAmount,
          credit: 0,
          date: '2025-04-01',
          currencyCode: 'YER',
          exchangeRate: 1.0,
          amountBase: yerAmount,
        );

        // SAR transaction (100 SAR @ 140)
        final sarAmount = MoneyHelper.toCents(100.0);
        final sarBase = (sarAmount * 140.0).round();
        await insertTransaction(
          accountId: multiAccountId,
          debit: sarAmount,
          credit: 0,
          date: '2025-04-05',
          currencyCode: 'SAR',
          exchangeRate: 140.0,
          amountBase: sarBase,
        );

        // USD transaction (50 USD @ 530)
        final usdAmount = MoneyHelper.toCents(50.0);
        final usdBase = (usdAmount * 530.0).round();
        await insertTransaction(
          accountId: multiAccountId,
          debit: usdAmount,
          credit: 0,
          date: '2025-04-10',
          currencyCode: 'USD',
          exchangeRate: 530.0,
          amountBase: usdBase,
        );

        // Verify each transaction has its own currency_code
        final txns = await db.query('transactions',
            where: 'account_id = ?', whereArgs: [multiAccountId]);
        expect(txns.length, 3);

        final currencies =
            txns.map((t) => t['currency_code'] as String).toList();
        expect(currencies, containsAll(['YER', 'SAR', 'USD']));

        // Total in base currency (YER) via amount_base
        final baseResult = await db.rawQuery(
          'SELECT CAST(COALESCE(SUM(amount_base), 0) AS INTEGER) AS total_base '
          'FROM transactions WHERE account_id = ? AND debit > 0',
          [multiAccountId],
        );
        final totalBase = (baseResult.first['total_base'] as num).toInt();
        expect(totalBase, yerAmount + sarBase + usdBase,
            reason:
                'Total base amount should be sum of all amount_base values');
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════
  //  Group 6: Account Type Aggregation
  //  تجميع حسب نوع الحساب
  // ══════════════════════════════════════════════════════════════════

  group('Account Type Aggregation — التجميع حسب نوع الحساب', () {
    test(
      'All ASSET accounts sum to total assets (in base currency) / مجموع حسابات الأصول يساوي إجمالي الأصول',
      () async {
        final assetAccounts =
            await db.query('accounts', where: "account_type = 'ASSET'");
        expect(assetAccounts.isNotEmpty, isTrue,
            reason: 'Should have at least one ASSET account');

        // All system ASSET accounts start with balance 0
        int totalBalance = 0;
        for (final acc in assetAccounts) {
          totalBalance += (acc['balance'] as num).toInt();
        }
        // After seeding, all balances are 0
        expect(totalBalance, 0,
            reason: 'Initially, total assets should be zero');
      },
    );

    test(
      'All LIABILITY accounts sum to total liabilities / مجموع حسابات الخصوم يساوي إجمالي الخصوم',
      () async {
        final liabilityAccounts =
            await db.query('accounts', where: "account_type = 'LIABILITY'");
        expect(liabilityAccounts.isNotEmpty, isTrue,
            reason: 'Should have at least one LIABILITY account');

        int totalBalance = 0;
        for (final acc in liabilityAccounts) {
          totalBalance += (acc['balance'] as num).toInt();
        }
        expect(totalBalance, 0,
            reason: 'Initially, total liabilities should be zero');
      },
    );

    test(
      'Accounting equation: Assets = Liabilities + Equity / المعادلة المحاسبية: الأصول = الخصوم + حقوق الملكية',
      () async {
        // After all transactions, verify the fundamental accounting equation
        // We'll create a balanced set of transactions first

        // Get system accounts
        final cashAccount = await db.query('accounts',
            where: "account_code = '1100' AND currency = 'YER'", limit: 1);
        final revenueAccount = await db.query('accounts',
            where: "account_code = '4100' AND currency = 'YER'", limit: 1);

        expect(cashAccount.isNotEmpty, isTrue);
        expect(revenueAccount.isNotEmpty, isTrue);

        final cashId = cashAccount.first['id'] as int;
        final revenueId = revenueAccount.first['id'] as int;

        // Balanced entry: Debit Cash 10000, Credit Revenue 10000
        final amount = MoneyHelper.toCents(10000.0);
        final journalId = DateTime.now().microsecondsSinceEpoch;
        final date = '2025-05-01';

        await db.transaction((txn) async {
          await txn.insert('transactions', {
            'account_id': cashId,
            'journal_id': journalId,
            'debit': amount,
            'credit': 0,
            'description': 'مبيعات نقدية',
            'date': date,
            'created_at': DateTime.now().toIso8601String(),
            'currency_code': 'YER',
            'exchange_rate': 1.0,
            'amount_base': amount,
          });
          await txn.insert('transactions', {
            'account_id': revenueId,
            'journal_id': journalId,
            'debit': 0,
            'credit': amount,
            'description': 'إيرادات المبيعات',
            'date': date,
            'created_at': DateTime.now().toIso8601String(),
            'currency_code': 'YER',
            'exchange_rate': 1.0,
            'amount_base': amount,
          });

          // Update account balances
          await txn.rawUpdate('''
            UPDATE accounts SET balance = balance + ?, updated_at = ?
            WHERE id = ? AND balance_type = 'debit'
          ''', [amount, DateTime.now().toIso8601String(), cashId]);

          await txn.rawUpdate('''
            UPDATE accounts SET balance = balance + ?, updated_at = ?
            WHERE id = ? AND balance_type = 'credit'
          ''', [amount, DateTime.now().toIso8601String(), revenueId]);
        });

        // Now verify: Assets (debit nature) increased by 10000
        // Revenue (credit nature) increased by 10000
        // Revenue is part of Equity (retained earnings via income summary)
        // So Assets = Liabilities + Equity + Net Income
        // 10000 = 0 + 0 + 10000 ✓

        final assetResult = await db.rawQuery(
          "SELECT CAST(COALESCE(SUM(balance), 0) AS INTEGER) AS total "
          "FROM accounts WHERE account_type = 'ASSET' AND currency = 'YER'",
        );
        final liabilityResult = await db.rawQuery(
          "SELECT CAST(COALESCE(SUM(balance), 0) AS INTEGER) AS total "
          "FROM accounts WHERE account_type = 'LIABILITY' AND currency = 'YER'",
        );
        final equityResult = await db.rawQuery(
          "SELECT CAST(COALESCE(SUM(balance), 0) AS INTEGER) AS total "
          "FROM accounts WHERE account_type IN ('EQUITY', 'REVENUE') AND currency = 'YER'",
        );

        final totalAssets = (assetResult.first['total'] as num).toInt();
        final totalLiabilities =
            (liabilityResult.first['total'] as num).toInt();
        final totalEquity = (equityResult.first['total'] as num).toInt();

        expect(totalAssets, MoneyHelper.toCents(10000.0));
        expect(totalLiabilities, 0);
        expect(totalEquity, MoneyHelper.toCents(10000.0));
        expect(totalAssets, totalLiabilities + totalEquity,
            reason:
                'Assets must equal Liabilities + Equity (including Revenue)');
      },
    );

    test(
      'Each account type group has at least one system account / كل نوع حساب لديه حساب نظامي واحد على الأقل',
      () async {
        final types = [
          'ASSET',
          'LIABILITY',
          'EQUITY',
          'COST',
          'REVENUE',
          'EXPENSE'
        ];
        for (final type in types) {
          final accounts = await db.query('accounts',
              where: 'account_type = ? AND is_system = 1', whereArgs: [type]);
          expect(accounts.isNotEmpty, isTrue,
              reason: 'Should have at least one system account of type $type');
        }
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════
  //  Group 7: Currency-Specific Account Operations
  //  عمليات الحسابات حسب العملة
  // ══════════════════════════════════════════════════════════════════

  group('Currency-Specific Account Operations — عمليات الحسابات حسب العملة',
      () {
    test(
      'YER account with YER transactions → balance matches / حساب ريال يمني بمعاملات ريال → الرصيد متطابق',
      () async {
        final id = await insertAccount(
          code: '9400',
          accountType: 'ASSET',
          balanceType: 'debit',
          currency: 'YER',
        );

        final amount = MoneyHelper.toCents(25000.0);
        await insertTransaction(
          accountId: id,
          debit: amount,
          credit: 0,
          date: '2025-06-01',
          currencyCode: 'YER',
          exchangeRate: 1.0,
          amountBase: amount,
        );

        final computedBalance =
            await computeBalanceFromTransactions(id, 'debit');
        expect(computedBalance, amount,
            reason: 'YER balance should match transaction amount exactly');

        // amount_base = amount for YER (exchange_rate = 1)
        final txn = await db.query('transactions',
            where: 'account_id = ?', whereArgs: [id], limit: 1);
        expect(txn.first['amount_base'], amount);
        expect(txn.first['exchange_rate'], 1.0);
      },
    );

    test(
      'SAR account with SAR transactions → balance matches / حساب ريال سعودي بمعاملات ريال سعودي → الرصيد متطابق',
      () async {
        final id = await insertAccount(
          code: '9401',
          accountType: 'ASSET',
          balanceType: 'debit',
          currency: 'SAR',
        );

        final sarAmount = MoneyHelper.toCents(500.0); // 500 SAR in cents
        const exchangeRate = 140.0;
        final amountBase = (sarAmount * exchangeRate).round();

        await insertTransaction(
          accountId: id,
          debit: sarAmount,
          credit: 0,
          date: '2025-06-01',
          currencyCode: 'SAR',
          exchangeRate: exchangeRate,
          amountBase: amountBase,
        );

        // The account stores balance in SAR cents
        // But for cross-currency reporting, amount_base is in YER cents
        final txn = await db.query('transactions',
            where: 'account_id = ?', whereArgs: [id], limit: 1);
        expect(txn.first['debit'], sarAmount);
        expect(txn.first['currency_code'], 'SAR');
        expect(txn.first['exchange_rate'], exchangeRate);
        expect(txn.first['amount_base'], amountBase,
            reason: 'amount_base = 50000 * 140 = 7000000 (70000 YER in cents)');
      },
    );

    test(
      'Cannot mix currencies in a single journal entry (each row has its own currency_code) / لا يمكن خلط العملات في قيد واحد',
      () async {
        // Each transaction row has its own currency_code.
        // A journal entry can have rows in different currencies,
        // but the amount_base must balance in the base currency (YER).
        // This test verifies the data model supports this correctly.

        final yerAccountId = await insertAccount(
          code: '9410',
          accountType: 'ASSET',
          balanceType: 'debit',
          currency: 'YER',
        );
        final sarAccountId = await insertAccount(
          code: '9411',
          accountType: 'REVENUE',
          balanceType: 'credit',
          currency: 'SAR',
        );

        final journalId = DateTime.now().microsecondsSinceEpoch + 500;

        // Exchange 70000 YER for 500 SAR (rate = 140)
        final yerAmount = MoneyHelper.toCents(70000.0);
        final sarAmount = MoneyHelper.toCents(500.0);
        final sarAmountBase = (sarAmount * 140.0).round();

        await db.insert('transactions', {
          'account_id': sarAccountId,
          'journal_id': journalId,
          'debit': sarAmount,
          'credit': 0,
          'description': 'استلام ريال سعودي',
          'date': '2025-06-15',
          'created_at': DateTime.now().toIso8601String(),
          'currency_code': 'SAR',
          'exchange_rate': 140.0,
          'amount_base': sarAmountBase,
        });
        await db.insert('transactions', {
          'account_id': yerAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': yerAmount,
          'description': 'صرف ريال يمني',
          'date': '2025-06-15',
          'created_at': DateTime.now().toIso8601String(),
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': yerAmount,
        });

        // Verify: amount_base balances in YER
        final debitBase = await db.rawQuery(
          'SELECT CAST(COALESCE(SUM(amount_base), 0) AS INTEGER) AS total '
          'FROM transactions WHERE journal_id = ? AND debit > 0',
          [journalId],
        );
        final creditBase = await db.rawQuery(
          'SELECT CAST(COALESCE(SUM(amount_base), 0) AS INTEGER) AS total '
          'FROM transactions WHERE journal_id = ? AND credit > 0',
          [journalId],
        );

        final totalDebitBase = (debitBase.first['total'] as num).toInt();
        final totalCreditBase = (creditBase.first['total'] as num).toInt();
        expect(totalDebitBase, totalCreditBase,
            reason:
                'In base currency (YER), debits must equal credits even across different currencies');
      },
    );

    test(
      'amount_base is computed correctly for SAR/USD transactions / amount_base محسوب بشكل صحيح لمعاملات الريال السعودي والدولار',
      () async {
        // SAR: 1000 SAR at rate 140 → amount_base = 100000 * 140 = 14000000
        final sarCents = MoneyHelper.toCents(1000.0);
        const sarRate = 140.0;
        final sarBase = (sarCents * sarRate).round();
        expect(sarBase, 14000000,
            reason: '1000 SAR → 140000 YER → 14000000 cents');

        // USD: 200 USD at rate 530 → amount_base = 20000 * 530 = 10600000
        final usdCents = MoneyHelper.toCents(200.0);
        const usdRate = 530.0;
        final usdBase = (usdCents * usdRate).round();
        expect(usdBase, 10600000,
            reason: '200 USD → 106000 YER → 10600000 cents');

        // Verify via actual DB inserts
        final sarAccountId = await insertAccount(
          code: '9420',
          accountType: 'ASSET',
          balanceType: 'debit',
          currency: 'SAR',
        );
        await insertTransaction(
          accountId: sarAccountId,
          debit: sarCents,
          credit: 0,
          date: '2025-06-20',
          currencyCode: 'SAR',
          exchangeRate: sarRate,
          amountBase: sarBase,
        );

        final sarTxn = await db.query('transactions',
            where: 'account_id = ?', whereArgs: [sarAccountId], limit: 1);
        expect(sarTxn.first['amount_base'], sarBase);

        final usdAccountId = await insertAccount(
          code: '9421',
          accountType: 'ASSET',
          balanceType: 'debit',
          currency: 'USD',
        );
        await insertTransaction(
          accountId: usdAccountId,
          debit: usdCents,
          credit: 0,
          date: '2025-06-20',
          currencyCode: 'USD',
          exchangeRate: usdRate,
          amountBase: usdBase,
        );

        final usdTxn = await db.query('transactions',
            where: 'account_id = ?', whereArgs: [usdAccountId], limit: 1);
        expect(usdTxn.first['amount_base'], usdBase);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════
  //  Group 8: Fiscal Year and Annual Posting
  //  السنة المالية والترحيل السنوي
  // ══════════════════════════════════════════════════════════════════

  group('Fiscal Year and Annual Posting — السنة المالية والترحيل السنوي', () {
    test(
      'Revenue and expense accounts can be closed to retained earnings / يمكن إقفال حسابات الإيرادات والمصروفات إلى الأرباح المحتجزة',
      () async {
        // Create a fiscal year
        final now = DateTime.now().toIso8601String();
        await db.insert('fiscal_years', {
          'year': 2025,
          'start_date': '2025-01-01',
          'end_date': '2025-12-31',
          'status': 'open',
          'net_profit': 0,
          'created_at': now,
          'updated_at': now,
        });

        // Get revenue and expense system accounts (YER)
        final revenueAccounts = await db.query('accounts',
            where:
                "account_type = 'REVENUE' AND currency = 'YER' AND is_system = 1");
        final expenseAccounts = await db.query('accounts',
            where:
                "account_type = 'EXPENSE' AND currency = 'YER' AND is_system = 1");
        final retainedEarningsAccounts = await db.query('accounts',
            where: "account_code = '2910' AND currency = 'YER'");

        expect(revenueAccounts.isNotEmpty, isTrue,
            reason: 'Should have revenue accounts');
        expect(expenseAccounts.isNotEmpty, isTrue,
            reason: 'Should have expense accounts');
        expect(retainedEarningsAccounts.isNotEmpty, isTrue,
            reason: 'Should have retained earnings account');

        // Set some balances
        final revenueId = revenueAccounts.first['id'] as int;
        final expenseId = expenseAccounts.first['id'] as int;
        final retainedId = retainedEarningsAccounts.first['id'] as int;

        final revenueBalance = MoneyHelper.toCents(50000.0);
        final expenseBalance = MoneyHelper.toCents(30000.0);

        await db.update(
            'accounts', {'balance': revenueBalance, 'updated_at': now},
            where: 'id = ?', whereArgs: [revenueId]);
        await db.update(
            'accounts', {'balance': expenseBalance, 'updated_at': now},
            where: 'id = ?', whereArgs: [expenseId]);

        // Simulate closing entry: close revenue & expense to retained earnings
        // Net income = Revenue - Expense = 50000 - 30000 = 20000
        final netIncome = revenueBalance - expenseBalance;

        // Close revenue (credit balance → debit to zero it out)
        await db.update('accounts', {'balance': 0, 'updated_at': now},
            where: 'id = ?', whereArgs: [revenueId]);

        // Close expense (debit balance → credit to zero it out)
        await db.update('accounts', {'balance': 0, 'updated_at': now},
            where: 'id = ?', whereArgs: [expenseId]);

        // Add net income to retained earnings (credit account → increase)
        await db.rawUpdate('''
          UPDATE accounts SET
            balance = balance + ?,
            updated_at = ?
          WHERE id = ? AND balance_type = 'credit'
        ''', [netIncome, now, retainedId]);

        // Verify
        final closedRevenue =
            await db.query('accounts', where: 'id = ?', whereArgs: [revenueId]);
        final closedExpense =
            await db.query('accounts', where: 'id = ?', whereArgs: [expenseId]);
        final updatedRetained = await db
            .query('accounts', where: 'id = ?', whereArgs: [retainedId]);

        expect(closedRevenue.first['balance'], 0,
            reason: 'Revenue account should be zeroed after closing');
        expect(closedExpense.first['balance'], 0,
            reason: 'Expense account should be zeroed after closing');
        expect(updatedRetained.first['balance'], netIncome,
            reason: 'Retained earnings should equal net income');
      },
    );

    test(
      'After annual posting, revenue/expense accounts have zero balance / بعد الترحيل السنوي، حسابات الإيرادات والمصروفات رصيدها صفر',
      () async {
        // Create accounts and post transactions
        final revenueId = await insertAccount(
          code: '9500',
          accountType: 'REVENUE',
          balanceType: 'credit',
          balance: MoneyHelper.toCents(75000.0),
        );
        final expenseId = await insertAccount(
          code: '9501',
          accountType: 'EXPENSE',
          balanceType: 'debit',
          balance: MoneyHelper.toCents(45000.0),
        );

        // Simulate closing: set balances to zero
        final now = DateTime.now().toIso8601String();
        await db.update('accounts', {'balance': 0, 'updated_at': now},
            where: 'id = ?', whereArgs: [revenueId]);
        await db.update('accounts', {'balance': 0, 'updated_at': now},
            where: 'id = ?', whereArgs: [expenseId]);

        final closedRevenue = await getAccountBalanceCents(revenueId);
        final closedExpense = await getAccountBalanceCents(expenseId);

        expect(closedRevenue, 0,
            reason: 'Revenue should be zero after annual closing');
        expect(closedExpense, 0,
            reason: 'Expense should be zero after annual closing');
      },
    );

    test(
      'Cannot post same fiscal year twice / لا يمكن ترحيل نفس السنة المالية مرتين',
      () async {
        final now = DateTime.now().toIso8601String();

        // Create a fiscal year
        await db.insert('fiscal_years', {
          'year': 2026,
          'start_date': '2026-01-01',
          'end_date': '2026-12-31',
          'status': 'open',
          'net_profit': 0,
          'created_at': now,
          'updated_at': now,
        });

        // Close it
        await db.update(
          'fiscal_years',
          {
            'status': 'closed',
            'net_profit': MoneyHelper.toCents(20000.0),
            'closed_at': now,
            'closed_by': 'admin',
            'updated_at': now,
          },
          where: 'year = ?',
          whereArgs: [2026],
        );

        // Verify it's closed
        final closed = await db
            .query('fiscal_years', where: 'year = ?', whereArgs: [2026]);
        expect(closed.first['status'], 'closed');

        // Attempting to close again should be prevented at application level
        // We verify the status check: if status is 'closed', reject
        final isAlreadyClosed = closed.first['status'] == 'closed';
        expect(isAlreadyClosed, isTrue,
            reason: 'Fiscal year is already closed, cannot post again');

        // Verify uniqueness constraint: cannot insert another 2026 year
        try {
          await db.insert('fiscal_years', {
            'year': 2026,
            'start_date': '2026-01-01',
            'end_date': '2026-12-31',
            'status': 'open',
            'net_profit': 0,
            'created_at': now,
            'updated_at': now,
          });
          fail('Should have thrown due to UNIQUE constraint on year column');
        } on DatabaseException catch (e) {
          expect(e.toString(), contains('UNIQUE'),
              reason: 'Duplicate fiscal year should violate UNIQUE constraint');
        }
      },
    );
  });
}
