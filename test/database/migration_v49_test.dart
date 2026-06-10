import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// ══════════════════════════════════════════════════════════════════
/// اختبارات ترحيل v49 — سلامة العملات وتتبع المبلغ الأساسي
/// Tests for v49 migration: Currency integrity and base-amount tracking
///
/// Verifies:
///   1. `amount_base` column is added to transactions table
///   2. `exchange_rate` column is added to vouchers table
///   3. NULL `currency_code` values are backfilled to 'YER'
///   4. `amount_base` is computed correctly for existing transactions
/// ══════════════════════════════════════════════════════════════════

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// Create a pre-v49 schema (without amount_base, without exchange_rate
  /// on vouchers, with nullable currency_code) so we can test the migration.
  Future<Database> createPreV49Database() async {
    final database = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (database, version) async {
        await database.execute('PRAGMA foreign_keys = ON');

        // Accounts — needed as FK target
        await database.execute('''
          CREATE TABLE accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name_ar TEXT NOT NULL,
            name_en TEXT NOT NULL DEFAULT '',
            parent_id INTEGER,
            account_code TEXT NOT NULL,
            account_type TEXT NOT NULL DEFAULT 'ASSET',
            balance INTEGER NOT NULL DEFAULT 0,
            currency TEXT NOT NULL DEFAULT 'YER',
            linked_cash_box_id INTEGER,
            is_active INTEGER NOT NULL DEFAULT 1,
            is_system INTEGER NOT NULL DEFAULT 0,
            debt_ceiling INTEGER NOT NULL DEFAULT 0,
            balance_type TEXT NOT NULL DEFAULT 'debit',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');

        // Transactions — pre-v49: NO amount_base, NO currency_code default,
        // NO exchange_rate.  These are what v49 adds/backfills.
        await database.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_id INTEGER NOT NULL,
            journal_id INTEGER,
            debit INTEGER NOT NULL DEFAULT 0,
            credit INTEGER NOT NULL DEFAULT 0,
            description TEXT,
            date TEXT NOT NULL,
            created_at TEXT NOT NULL,
            balance_type TEXT,
            currency_code TEXT,
            exchange_rate REAL NOT NULL DEFAULT 1.0,
            reference_type TEXT,
            reference_id TEXT,
            FOREIGN KEY (account_id) REFERENCES accounts (id)
          )
        ''');

        // Vouchers — pre-v49: NO exchange_rate column
        await database.execute('''
          CREATE TABLE vouchers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            voucher_number TEXT NOT NULL,
            voucher_type TEXT NOT NULL,
            date TEXT NOT NULL,
            description TEXT,
            currency TEXT NOT NULL DEFAULT 'YER',
            total_amount INTEGER NOT NULL DEFAULT 0,
            cash_box_id INTEGER,
            customer_id INTEGER,
            supplier_id INTEGER,
            employee_id INTEGER,
            is_posted INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');

        // Currencies — needed by v49 backfill step 5
        await database.execute('''
          CREATE TABLE currencies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT NOT NULL UNIQUE,
            name_ar TEXT NOT NULL,
            name_en TEXT NOT NULL,
            symbol TEXT NOT NULL,
            exchange_rate REAL NOT NULL DEFAULT 1.0,
            is_default INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL
          )
        ''');

        // Seed currencies so the backfill can look up exchange rates
        final now = DateTime.now().toIso8601String();
        await database.insert('currencies', {
          'code': 'YER',
          'name_ar': 'ريال يمني',
          'name_en': 'Yemeni Rial',
          'symbol': 'ر.ي',
          'exchange_rate': 1.0,
          'is_default': 1,
          'is_active': 1,
          'created_at': now,
        });
        await database.insert('currencies', {
          'code': 'SAR',
          'name_ar': 'ريال سعودي',
          'name_en': 'Saudi Riyal',
          'symbol': 'ر.س',
          'exchange_rate': 140.0,
          'is_default': 0,
          'is_active': 1,
          'created_at': now,
        });
        await database.insert('currencies', {
          'code': 'USD',
          'name_ar': 'دولار أمريكي',
          'name_en': 'US Dollar',
          'symbol': '\$',
          'exchange_rate': 530.0,
          'is_default': 0,
          'is_active': 1,
          'created_at': now,
        });
      },
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
    return database;
  }

  /// Apply the v49 migration logic (reproduced from migration_v49.dart).
  /// We reproduce the SQL here rather than importing the migration class,
  /// because the migration class uses sqflite_sqlcipher's Database type
  /// which is incompatible with sqflite_common_ffi.
  Future<void> applyV49Migration(Database db) async {
    // 1. Add amount_base column to transactions
    final txColumns = await db.rawQuery('PRAGMA table_info(transactions)');
    final hasAmountBase = txColumns.any((col) => col['name'] == 'amount_base');
    if (!hasAmountBase) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN amount_base INTEGER NOT NULL DEFAULT 0',
      );
    }

    // 2. Add exchange_rate column to vouchers (if missing)
    final vColumns = await db.rawQuery('PRAGMA table_info(vouchers)');
    final hasVoucherExchangeRate =
        vColumns.any((col) => col['name'] == 'exchange_rate');
    if (!hasVoucherExchangeRate) {
      await db.execute(
        'ALTER TABLE vouchers ADD COLUMN exchange_rate REAL NOT NULL DEFAULT 1.0',
      );
    }

    // 3. Backfill NULL currency_code in transactions to 'YER'
    await db.execute(
      "UPDATE transactions SET currency_code = 'YER' WHERE currency_code IS NULL",
    );

    // 4. Backfill amount_base for existing transactions
    await db.execute('''
      UPDATE transactions
      SET amount_base = CASE
        WHEN currency_code = 'YER' OR currency_code IS NULL THEN
          CASE WHEN debit > 0 THEN debit ELSE credit END
        ELSE
          CAST(ROUND(
            CASE WHEN debit > 0 THEN debit ELSE credit END
            * exchange_rate
          ) AS INTEGER)
      END
      WHERE amount_base = 0
        AND (debit > 0 OR credit > 0)
    ''');

    // 5. Backfill exchange_rate for vouchers based on their currency
    await db.execute('''
      UPDATE vouchers
      SET exchange_rate = COALESCE(
        (SELECT c.exchange_rate FROM currencies c WHERE c.code = vouchers.currency),
        1.0
      )
      WHERE exchange_rate = 1.0
        AND currency != 'YER'
    ''');

    // 6. Create index on amount_base
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transactions_amount_base ON transactions (amount_base)',
      );
    } catch (_) {
      // Index may already exist, ignore
    }
  }

  tearDown(() async {
    await db.close();
  });

  // ══════════════════════════════════════════════════════════════
  //  Test: amount_base column is added to transactions
  // ══════════════════════════════════════════════════════════════

  group('V49 Migration — amount_base column on transactions', () {
    test(
        'amount_base column is added after migration / يتم إضافة عمود amount_base بعد الترحيل',
        () async {
      db = await createPreV49Database();
      final now = DateTime.now().toIso8601String();

      // Verify amount_base does NOT exist before migration
      var columns = await db.rawQuery('PRAGMA table_info(transactions)');
      expect(columns.any((col) => col['name'] == 'amount_base'), isFalse,
          reason: 'amount_base should not exist before v49 migration');

      // Insert a test account
      final accountId = await db.insert('accounts', {
        'name_ar': 'حساب اختبار',
        'name_en': 'Test Account',
        'account_code': '1000',
        'account_type': 'ASSET',
        'balance': 0,
        'currency': 'YER',
        'balance_type': 'debit',
        'is_active': 1,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });

      // Insert a transaction before migration (without amount_base)
      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': 1001,
        'debit': MoneyHelper.toCents(5000.0),
        'credit': 0,
        'description': 'معاملة قبل الترحيل',
        'date': now,
        'created_at': now,
        'currency_code': 'YER',
        'exchange_rate': 1.0,
      });

      // Apply migration
      await applyV49Migration(db);

      // Verify amount_base column now exists
      columns = await db.rawQuery('PRAGMA table_info(transactions)');
      expect(columns.any((col) => col['name'] == 'amount_base'), isTrue,
          reason: 'amount_base should exist after v49 migration');
    });

    test(
        'amount_base defaults to 0 for new columns / القيمة الافتراضية لـ amount_base هي 0',
        () async {
      db = await createPreV49Database();
      final now = DateTime.now().toIso8601String();

      final accountId = await db.insert('accounts', {
        'name_ar': 'حساب',
        'name_en': 'Account',
        'account_code': '1001',
        'account_type': 'ASSET',
        'balance': 0,
        'currency': 'YER',
        'balance_type': 'debit',
        'is_active': 1,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });

      // Apply migration first, then insert a transaction with explicit amount_base = 0
      await applyV49Migration(db);

      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': 1002,
        'debit': MoneyHelper.toCents(1000.0),
        'credit': 0,
        'description': 'معاملة جديدة',
        'date': now,
        'created_at': now,
        'currency_code': 'YER',
        'exchange_rate': 1.0,
        'amount_base': 0,
      });

      final txn = await db
          .query('transactions', where: 'journal_id = ?', whereArgs: [1002]);
      expect(txn.isNotEmpty, isTrue);
      expect(txn.first['amount_base'], 0);
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Test: exchange_rate column is added to vouchers
  // ══════════════════════════════════════════════════════════════

  group('V49 Migration — exchange_rate column on vouchers', () {
    test(
        'exchange_rate column is added after migration / يتم إضافة عمود exchange_rate بعد الترحيل',
        () async {
      db = await createPreV49Database();
      final now = DateTime.now().toIso8601String();

      // Verify exchange_rate does NOT exist before migration
      var columns = await db.rawQuery('PRAGMA table_info(vouchers)');
      expect(columns.any((col) => col['name'] == 'exchange_rate'), isFalse,
          reason: 'exchange_rate should not exist before v49 migration');

      // Insert a voucher before migration (without exchange_rate)
      await db.insert('vouchers', {
        'voucher_number': 'VCH-001',
        'voucher_type': 'receipt',
        'date': now,
        'description': 'سند قبض',
        'currency': 'YER',
        'total_amount': MoneyHelper.toCents(5000.0),
        'is_posted': 1,
        'created_at': now,
        'updated_at': now,
      });

      // Apply migration
      await applyV49Migration(db);

      // Verify exchange_rate column now exists
      columns = await db.rawQuery('PRAGMA table_info(vouchers)');
      expect(columns.any((col) => col['name'] == 'exchange_rate'), isTrue,
          reason: 'exchange_rate should exist after v49 migration');
    });

    test(
        'exchange_rate defaults to 1.0 for YER vouchers / القيمة الافتراضية لسعر الصرف هي 1.0 لسندات الريال',
        () async {
      db = await createPreV49Database();
      final now = DateTime.now().toIso8601String();

      await db.insert('vouchers', {
        'voucher_number': 'VCH-002',
        'voucher_type': 'payment',
        'date': now,
        'currency': 'YER',
        'total_amount': MoneyHelper.toCents(3000.0),
        'is_posted': 1,
        'created_at': now,
        'updated_at': now,
      });

      await applyV49Migration(db);

      final voucher = await db.query('vouchers',
          where: 'voucher_number = ?', whereArgs: ['VCH-002']);
      expect(voucher.isNotEmpty, isTrue);
      expect(voucher.first['exchange_rate'], 1.0);
    });

    test(
        'exchange_rate is backfilled for foreign currency vouchers / يتم تعبئة سعر الصرف للسندات بعملة أجنبية',
        () async {
      db = await createPreV49Database();
      final now = DateTime.now().toIso8601String();

      // Insert a USD voucher before migration
      await db.insert('vouchers', {
        'voucher_number': 'VCH-003',
        'voucher_type': 'receipt',
        'date': now,
        'currency': 'USD',
        'total_amount': MoneyHelper.toCents(100.0),
        'is_posted': 1,
        'created_at': now,
        'updated_at': now,
      });

      // Insert a SAR voucher
      await db.insert('vouchers', {
        'voucher_number': 'VCH-004',
        'voucher_type': 'payment',
        'date': now,
        'currency': 'SAR',
        'total_amount': MoneyHelper.toCents(500.0),
        'is_posted': 1,
        'created_at': now,
        'updated_at': now,
      });

      await applyV49Migration(db);

      final usdVoucher = await db.query('vouchers',
          where: 'voucher_number = ?', whereArgs: ['VCH-003']);
      expect(usdVoucher.isNotEmpty, isTrue);
      expect(usdVoucher.first['exchange_rate'], 530.0,
          reason: 'USD exchange_rate should be backfilled to 530.0');

      final sarVoucher = await db.query('vouchers',
          where: 'voucher_number = ?', whereArgs: ['VCH-004']);
      expect(sarVoucher.isNotEmpty, isTrue);
      expect(sarVoucher.first['exchange_rate'], 140.0,
          reason: 'SAR exchange_rate should be backfilled to 140.0');
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Test: NULL currency_code values backfilled to 'YER'
  // ══════════════════════════════════════════════════════════════

  group('V49 Migration — NULL currency_code backfilled', () {
    test(
        'NULL currency_code values are updated to YER / تحديث قيم currency_code الفارغة إلى ريال يمني',
        () async {
      db = await createPreV49Database();
      final now = DateTime.now().toIso8601String();

      final accountId = await db.insert('accounts', {
        'name_ar': 'حساب اختبار',
        'name_en': 'Test Account',
        'account_code': '1002',
        'account_type': 'ASSET',
        'balance': 0,
        'currency': 'YER',
        'balance_type': 'debit',
        'is_active': 1,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });

      // Insert transactions with NULL currency_code
      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': 2001,
        'debit': MoneyHelper.toCents(10000.0),
        'credit': 0,
        'description': 'معاملة بدون عملة',
        'date': now,
        'created_at': now,
        'currency_code': null, // NULL — should be backfilled
        'exchange_rate': 1.0,
      });

      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': 2002,
        'debit': 0,
        'credit': MoneyHelper.toCents(7500.0),
        'description': 'معاملة أخرى بدون عملة',
        'date': now,
        'created_at': now,
        'currency_code': null, // NULL — should be backfilled
        'exchange_rate': 1.0,
      });

      // Verify NULL before migration
      var nullCount = await db.rawQuery(
        "SELECT COUNT(*) AS cnt FROM transactions WHERE currency_code IS NULL",
      );
      expect((nullCount.first['cnt'] as num?)?.toInt(), 2);

      // Apply migration
      await applyV49Migration(db);

      // Verify no NULL currency_code after migration
      nullCount = await db.rawQuery(
        "SELECT COUNT(*) AS cnt FROM transactions WHERE currency_code IS NULL",
      );
      expect((nullCount.first['cnt'] as num?)?.toInt(), 0,
          reason: 'No NULL currency_code should remain after v49 migration');

      // Verify all are 'YER'
      final backfilled = await db.query('transactions',
          where: 'journal_id IN (?, ?)', whereArgs: [2001, 2002]);
      for (final txn in backfilled) {
        expect(txn['currency_code'], 'YER',
            reason: 'Backfilled currency_code should be YER');
      }
    });

    test(
        'Non-NULL currency_code values are preserved / الحفاظ على قيم currency_code غير الفارغة',
        () async {
      db = await createPreV49Database();
      final now = DateTime.now().toIso8601String();

      final accountId = await db.insert('accounts', {
        'name_ar': 'حساب',
        'name_en': 'Account',
        'account_code': '1003',
        'account_type': 'ASSET',
        'balance': 0,
        'currency': 'YER',
        'balance_type': 'debit',
        'is_active': 1,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });

      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': 2003,
        'debit': MoneyHelper.toCents(200.0),
        'credit': 0,
        'description': 'معاملة بالدولار',
        'date': now,
        'created_at': now,
        'currency_code': 'USD',
        'exchange_rate': 530.0,
      });

      await applyV49Migration(db);

      final txn = await db
          .query('transactions', where: 'journal_id = ?', whereArgs: [2003]);
      expect(txn.isNotEmpty, isTrue);
      expect(txn.first['currency_code'], 'USD',
          reason: 'Existing USD currency_code should be preserved');
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Test: amount_base computed correctly for existing transactions
  // ══════════════════════════════════════════════════════════════

  group('V49 Migration — amount_base backfill computation', () {
    test(
        'YER transactions: amount_base = debit or credit / معاملات الريال: amount_base = المدين أو الدائن',
        () async {
      db = await createPreV49Database();
      final now = DateTime.now().toIso8601String();

      final accountId = await db.insert('accounts', {
        'name_ar': 'حساب',
        'name_en': 'Account',
        'account_code': '1004',
        'account_type': 'ASSET',
        'balance': 0,
        'currency': 'YER',
        'balance_type': 'debit',
        'is_active': 1,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });

      // YER debit transaction
      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': 3001,
        'debit': MoneyHelper.toCents(5000.0),
        'credit': 0,
        'description': 'مدين بالريال',
        'date': now,
        'created_at': now,
        'currency_code': 'YER',
        'exchange_rate': 1.0,
      });

      // YER credit transaction
      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': 3002,
        'debit': 0,
        'credit': MoneyHelper.toCents(3000.0),
        'description': 'دائن بالريال',
        'date': now,
        'created_at': now,
        'currency_code': 'YER',
        'exchange_rate': 1.0,
      });

      await applyV49Migration(db);

      // Check debit transaction
      final debitTxn = await db
          .query('transactions', where: 'journal_id = ?', whereArgs: [3001]);
      expect(debitTxn.isNotEmpty, isTrue);
      expect(debitTxn.first['amount_base'], MoneyHelper.toCents(5000.0),
          reason: 'YER debit: amount_base should equal debit (500000 cents)');

      // Check credit transaction
      final creditTxn = await db
          .query('transactions', where: 'journal_id = ?', whereArgs: [3002]);
      expect(creditTxn.isNotEmpty, isTrue);
      expect(creditTxn.first['amount_base'], MoneyHelper.toCents(3000.0),
          reason: 'YER credit: amount_base should equal credit (300000 cents)');
    });

    test(
        'Foreign currency transactions: amount_base = amount * exchange_rate / معاملات العملة الأجنبية: amount_base = المبلغ × سعر الصرف',
        () async {
      db = await createPreV49Database();
      final now = DateTime.now().toIso8601String();

      final accountId = await db.insert('accounts', {
        'name_ar': 'حساب',
        'name_en': 'Account',
        'account_code': '1005',
        'account_type': 'ASSET',
        'balance': 0,
        'currency': 'YER',
        'balance_type': 'debit',
        'is_active': 1,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });

      // USD debit: 100 USD * 530 = 53000 YER
      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': 3003,
        'debit': MoneyHelper.toCents(100.0),
        'credit': 0,
        'description': 'مدين بالدولار',
        'date': now,
        'created_at': now,
        'currency_code': 'USD',
        'exchange_rate': 530.0,
      });

      // SAR credit: 500 SAR * 140 = 70000 YER
      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': 3004,
        'debit': 0,
        'credit': MoneyHelper.toCents(500.0),
        'description': 'دائن بالريال السعودي',
        'date': now,
        'created_at': now,
        'currency_code': 'SAR',
        'exchange_rate': 140.0,
      });

      await applyV49Migration(db);

      // Check USD transaction: 10000 cents * 530 = 5300000 → MoneyHelper.fromCents = 53000.0
      final usdTxn = await db
          .query('transactions', where: 'journal_id = ?', whereArgs: [3003]);
      expect(usdTxn.isNotEmpty, isTrue);
      final usdAmountBase = usdTxn.first['amount_base'] as int;
      // amount_base = ROUND(debit * exchange_rate) = ROUND(10000 * 530) = 5300000
      expect(usdAmountBase, 5300000,
          reason:
              'USD 100 @ 530: amount_base should be 5300000 cents (= 53000 YER)');

      // Check SAR transaction: 50000 cents * 140 = 7000000
      final sarTxn = await db
          .query('transactions', where: 'journal_id = ?', whereArgs: [3004]);
      expect(sarTxn.isNotEmpty, isTrue);
      final sarAmountBase = sarTxn.first['amount_base'] as int;
      // amount_base = ROUND(credit * exchange_rate) = ROUND(50000 * 140) = 7000000
      expect(sarAmountBase, 7000000,
          reason:
              'SAR 500 @ 140: amount_base should be 7000000 cents (= 70000 YER)');
    });

    test(
        'Mixed NULL and non-NULL currency_code backfill / تعبئة مختلطة لـ currency_code',
        () async {
      db = await createPreV49Database();
      final now = DateTime.now().toIso8601String();

      final accountId = await db.insert('accounts', {
        'name_ar': 'حساب',
        'name_en': 'Account',
        'account_code': '1006',
        'account_type': 'ASSET',
        'balance': 0,
        'currency': 'YER',
        'balance_type': 'debit',
        'is_active': 1,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });

      // NULL currency_code — should become YER and amount_base = debit
      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': 3005,
        'debit': MoneyHelper.toCents(8000.0),
        'credit': 0,
        'description': 'بدون عملة',
        'date': now,
        'created_at': now,
        'currency_code': null,
        'exchange_rate': 1.0,
      });

      // YER currency_code — amount_base = debit
      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': 3006,
        'debit': MoneyHelper.toCents(2000.0),
        'credit': 0,
        'description': 'بالريال',
        'date': now,
        'created_at': now,
        'currency_code': 'YER',
        'exchange_rate': 1.0,
      });

      await applyV49Migration(db);

      final nullTxn = await db
          .query('transactions', where: 'journal_id = ?', whereArgs: [3005]);
      expect(nullTxn.first['currency_code'], 'YER');
      expect(nullTxn.first['amount_base'], MoneyHelper.toCents(8000.0));

      final yerTxn = await db
          .query('transactions', where: 'journal_id = ?', whereArgs: [3006]);
      expect(yerTxn.first['currency_code'], 'YER');
      expect(yerTxn.first['amount_base'], MoneyHelper.toCents(2000.0));
    });

    test(
        'Idempotent: running migration twice does not corrupt data / تشغيل الترحيل مرتين لا يفسد البيانات',
        () async {
      db = await createPreV49Database();
      final now = DateTime.now().toIso8601String();

      final accountId = await db.insert('accounts', {
        'name_ar': 'حساب',
        'name_en': 'Account',
        'account_code': '1007',
        'account_type': 'ASSET',
        'balance': 0,
        'currency': 'YER',
        'balance_type': 'debit',
        'is_active': 1,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });

      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': 3007,
        'debit': MoneyHelper.toCents(6000.0),
        'credit': 0,
        'description': 'اختبار التكرار',
        'date': now,
        'created_at': now,
        'currency_code': 'YER',
        'exchange_rate': 1.0,
      });

      // Apply migration twice
      await applyV49Migration(db);
      await applyV49Migration(db);

      final txn = await db
          .query('transactions', where: 'journal_id = ?', whereArgs: [3007]);
      expect(txn.isNotEmpty, isTrue);
      expect(txn.first['amount_base'], MoneyHelper.toCents(6000.0),
          reason: 'amount_base should remain correct after double migration');

      // Verify only one amount_base column exists
      final columns = await db.rawQuery('PRAGMA table_info(transactions)');
      final amountBaseCols =
          columns.where((col) => col['name'] == 'amount_base');
      expect(amountBaseCols.length, 1,
          reason: 'amount_base column should exist exactly once');
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Test: Index creation on amount_base
  // ══════════════════════════════════════════════════════════════

  group('V49 Migration — Index on amount_base', () {
    test(
        'Index idx_transactions_amount_base is created / يتم إنشاء فهرس على amount_base',
        () async {
      db = await createPreV49Database();
      final now = DateTime.now().toIso8601String();

      final accountId = await db.insert('accounts', {
        'name_ar': 'حساب',
        'name_en': 'Account',
        'account_code': '1008',
        'account_type': 'ASSET',
        'balance': 0,
        'currency': 'YER',
        'balance_type': 'debit',
        'is_active': 1,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });

      await db.insert('transactions', {
        'account_id': accountId,
        'journal_id': 3008,
        'debit': MoneyHelper.toCents(1000.0),
        'credit': 0,
        'description': 'اختبار',
        'date': now,
        'created_at': now,
        'currency_code': 'YER',
        'exchange_rate': 1.0,
      });

      await applyV49Migration(db);

      // Verify index exists
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_transactions_amount_base'",
      );
      expect(indexes.isNotEmpty, isTrue,
          reason:
              'Index idx_transactions_amount_base should exist after migration');
    });
  });
}
