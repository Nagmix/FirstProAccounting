import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/data/datasources/migrations/migration_v50.dart';

/// ══════════════════════════════════════════════════════════════════
/// اختبارات ترحيل v50 — تصحيح balance_type='auto' في الحسابات
/// (B-14: الترحيل أُضيف في 5d749ea بدون اختبار — هذا يسد الفجوة)
///
/// Verifies:
///   1. 'auto' + LIABILITY/EQUITY/REVENUE → 'credit'
///   2. 'auto' + ASSET/COST/EXPENSE       → 'debit'
///   3. 'auto' + نوع غير معروف            → 'debit' (الخيار المحافظ)
///   4. الحسابات السليمة (credit/debit) لا تُمس
/// ══════════════════════════════════════════════════════════════════

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1,
        onCreate: (database, version) async {
      // مخطط مصغّر يكفي للترحيل (أعمدة accounts المعنية فقط)
      await database.execute('''
        CREATE TABLE accounts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name_ar TEXT NOT NULL,
          account_code TEXT NOT NULL,
          account_type TEXT NOT NULL,
          balance_type TEXT NOT NULL DEFAULT 'debit',
          balance INTEGER NOT NULL DEFAULT 0
        )
      ''');
    });
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertAccount(String code, String type, String balanceType) =>
      db.insert('accounts', {
        'name_ar': 'حساب $code',
        'account_code': code,
        'account_type': type,
        'balance_type': balanceType,
      });

  Future<String> balanceTypeOf(int id) async =>
      (await db.query('accounts', where: 'id = ?', whereArgs: [id], limit: 1))
          .first['balance_type'] as String;

  test('auto + credit-nature types resolve to credit', () async {
    final liability = await insertAccount('2100', 'LIABILITY', 'auto');
    final equity = await insertAccount('2900', 'EQUITY', 'auto');
    final revenue = await insertAccount('4100', 'REVENUE', 'auto');

    await MigrationV50.migrate(db);

    expect(await balanceTypeOf(liability), 'credit');
    expect(await balanceTypeOf(equity), 'credit');
    expect(await balanceTypeOf(revenue), 'credit');
  });

  test('auto + debit-nature types resolve to debit', () async {
    final asset = await insertAccount('1100', 'ASSET', 'auto');
    final cost = await insertAccount('3200', 'COST', 'auto');
    final expense = await insertAccount('5100', 'EXPENSE', 'auto');

    await MigrationV50.migrate(db);

    expect(await balanceTypeOf(asset), 'debit');
    expect(await balanceTypeOf(cost), 'debit');
    expect(await balanceTypeOf(expense), 'debit');
  });

  test('auto + unknown type falls back to debit (conservative)', () async {
    final weird = await insertAccount('9999', 'SOMETHING_ELSE', 'auto');

    await MigrationV50.migrate(db);

    expect(await balanceTypeOf(weird), 'debit');
  });

  test('already-correct rows are untouched', () async {
    final okCredit = await insertAccount('2101', 'LIABILITY', 'credit');
    final okDebit = await insertAccount('1101', 'ASSET', 'debit');
    // حساب "خاطئ النوع" لكنه ليس auto — يجب ألا يُعدَّل
    final mismatch = await insertAccount('4101', 'REVENUE', 'debit');

    await MigrationV50.migrate(db);

    expect(await balanceTypeOf(okCredit), 'credit');
    expect(await balanceTypeOf(okDebit), 'debit');
    expect(await balanceTypeOf(mismatch), 'debit',
        reason: 'الترحيل يصحح auto فقط ولا يلمس القيم الصريحة');
  });

  test('migration is idempotent (safe to run twice)', () async {
    final acc = await insertAccount('2100', 'LIABILITY', 'auto');

    await MigrationV50.migrate(db);
    await MigrationV50.migrate(db);

    expect(await balanceTypeOf(acc), 'credit');
    final autoCount = (await db.rawQuery(
            "SELECT COUNT(*) AS n FROM accounts WHERE balance_type = 'auto'"))
        .first['n'] as int;
    expect(autoCount, 0, reason: 'لا يتبقى أي auto بعد الترحيل');
  });
}
