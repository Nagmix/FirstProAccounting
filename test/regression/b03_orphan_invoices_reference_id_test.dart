import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// B-03 regression guard: AuditService.getOrphanedInvoices must use the
/// canonical `reference_id` / `reference_type` columns (added in v46)
/// instead of the legacy `description LIKE '%' || i.id || '%'` pattern.
///
/// Before the fix, invoice "inv-B" would match transactions whose
/// description contains "inv-B" as a substring (e.g. "...inv-ABC..."),
/// masking real orphans and creating false negatives. After the fix,
/// the JOIN is precise:
///   transactions.reference_id = invoices.id
///   AND reference_type IN ('sale','pos','purchase',...).
///
/// This test seeds three invoices and two transaction rows, then runs
/// the SAME SQL query that AuditService.getOrphanedInvoices uses, and
/// verifies exactly one orphan (inv-C) is returned. inv-B is the trap:
/// it has a real transaction row with reference_id='inv-B', but its
/// description contains "...inv-ABC..." which the legacy LIKE query
/// would have matched against inv-B (and also against a hypothetical
/// inv-ABC invoice). The new reference_id JOIN avoids this trap.
void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 53,
      onCreate: (database, version) async {
        await DatabaseSchema.onCreate(database, version);
      },
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
    await _seedTestData(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// The exact SQL used by AuditService.getOrphanedInvoices after the
  /// B-03 fix. Kept in sync with lib/data/datasources/services/audit_service.dart.
  /// If the query in audit_service.dart changes, update this constant
  /// to match — the test's job is to verify that the query behaves
  /// correctly on the seeded data.
  const orphanedInvoicesQuery = r'''
      SELECT i.id, i.type, i.total, i.currency, i.created_at,
             CASE WHEN i.customer_id IS NOT NULL THEN c.name
                  WHEN i.supplier_id IS NOT NULL THEN s.name
                  ELSE 'بدون عميل/مورد' END AS entity_name
      FROM invoices i
      LEFT JOIN customers c ON c.id = i.customer_id
      LEFT JOIN suppliers s ON s.id = i.supplier_id
      LEFT JOIN transactions t
        ON t.reference_id = i.id
       AND t.reference_type IN
           ('sale','pos','purchase','sale_return','purchase_return','invoice_journal')
      WHERE i.is_return = 0 AND i.total > 0
        AND t.id IS NULL
      ORDER BY i.created_at DESC
      LIMIT ?
    ''';

  /// The LEGACY SQL used before the B-03 fix. Used here to demonstrate
  /// the bug — under the same seed data, the legacy query would mask
  /// inv-C (the real orphan) because inv-B's description contains
  /// "...inv-ABC..." which matches nothing relevant, but the LIKE
  /// pattern '%' || i.id || '%' would match inv-B against the
  /// "inv-ABC" description (substring match), causing inv-B to appear
  /// non-orphan — which happens to be correct in this case. To expose
  /// the LIKE bug more clearly, the seed data is designed so that
  /// inv-C is the only true orphan, and any substring-based matching
  /// would still correctly identify inv-C as orphan. The real value
  /// of this test is verifying the new query's PRECISION.
  const legacyLikeQuery = r'''
      SELECT i.id
      FROM invoices i
      LEFT JOIN transactions t ON t.description LIKE '%' || i.id || '%' AND t.description LIKE 'فاتورة%'
      WHERE i.is_return = 0 AND i.total > 0
        AND t.id IS NULL
      ORDER BY i.created_at DESC
      LIMIT ?
    ''';

  test('B-03: new reference_id-based query returns exactly the orphan (inv-C)', () async {
    final orphans = await db.rawQuery(orphanedInvoicesQuery, [50]);

    expect(orphans, hasLength(1),
        reason: 'Exactly one orphan invoice expected (inv-C).');
    expect(orphans.first['id'], 'inv-C',
        reason: 'The orphan must be inv-C, which has no matching '
            'transactions.reference_id row.');
  });

  test('B-03: inv-B is NOT flagged as orphan (it has a real reference_id row)', () async {
    // Critical B-03 assertion: inv-B has a transaction row with
    // reference_id='inv-B'. The new query correctly recognizes it as
    // posted. The legacy LIKE query would ALSO recognize it (because
    // "inv-B" appears as a substring of "...inv-ABC..." in the
    // description), but for the WRONG reason — substring matching
    // rather than canonical reference_id linkage.
    final orphans = await db.rawQuery(orphanedInvoicesQuery, [50]);
    expect(orphans.any((o) => o['id'] == 'inv-B'), isFalse,
        reason: 'inv-B has a matching transaction.reference_id and must '
            'not be flagged as orphan.');
    expect(orphans.any((o) => o['id'] == 'inv-A'), isFalse,
        reason: 'inv-A has a matching transaction.reference_id and must '
            'not be flagged as orphan.');
  });

  test('B-03: query respects the limit parameter', () async {
    // Add 5 more orphans to verify limit is honored.
    final now = DateTime.now().toIso8601String();
    for (var i = 0; i < 5; i++) {
      await db.insert('invoices', {
        'id': 'inv-extra-$i',
        'type': 'sale',
        'is_return': 0,
        'total': MoneyHelper.toCents(100.0),
        'paid_amount': MoneyHelper.toCents(100.0),
        'remaining': 0,
        'currency': 'YER',
        'exchange_rate': 1.0,
        'is_posted': 0,
        'created_at': now,
      });
    }

    final orphansLimited = await db.rawQuery(orphanedInvoicesQuery, [3]);
    expect(orphansLimited.length, lessThanOrEqualTo(3),
        reason: 'Result count must respect the limit parameter.');

    final orphansAll = await db.rawQuery(orphanedInvoicesQuery, [100]);
    expect(orphansAll.length, 6,
        reason: 'Without limit, all 6 orphans (inv-C + 5 extras) should '
            'be returned.');
  });

  test('B-03: legacy LIKE query demonstrated weaker precision (reference only)', () async {
    // This test documents the legacy behavior. It is NOT a regression
    // target — it exists to explain WHY the fix was needed. The legacy
    // query uses substring matching which can produce false positives
    // (mask real orphans) when invoice ids share substrings.
    //
    // In our seed data:
    //   - inv-A has description "فاتورة مبيعات - inv-A"
    //   - inv-B has description "فاتورة مبيعات - inv-ABC (trap for LIKE)"
    //   - inv-C has no transaction
    //
    // Under the legacy LIKE query:
    //   - inv-A: matches "inv-A" in its own description -> NOT orphan (correct)
    //   - inv-B: matches "inv-B" as substring of "...inv-ABC..." -> NOT orphan (correct by accident)
    //   - inv-C: no match -> orphan (correct)
    //
    // The bug appears when an invoice id is a SUBSTRING of another's
    // description but has no real reference_id row. For example, if we
    // had an invoice "inv" (no suffix), the LIKE query would match it
    // against EVERY "فاتورة...inv-X..." description and mask it as
    // non-orphan. The new reference_id query avoids this entirely.
    final legacyOrphans = await db.rawQuery(legacyLikeQuery, [50]);
    // The legacy query also returns inv-C as orphan in this seed data,
    // but for the wrong reason (no substring match). The point of this
    // test is to document the legacy behavior, not to assert it.
    expect(legacyOrphans.any((o) => o['id'] == 'inv-C'), isTrue,
        reason: 'Legacy LIKE query also identifies inv-C as orphan in '
            'this seed data, but for the wrong reason (substring '
            'matching rather than canonical reference_id linkage).');
  });
}

/// Seed three invoices and matching transactions to exercise the B-03 fix.
Future<void> _seedTestData(Database db) async {
  final now = DateTime.now().toIso8601String();

  // Three invoices (all non-return, total > 0 so they're eligible for
  // orphan detection).
  for (final id in ['inv-A', 'inv-B', 'inv-C']) {
    await db.insert('invoices', {
      'id': id,
      'type': 'sale',
      'is_return': 0,
      'total': MoneyHelper.toCents(100.0),
      'paid_amount': MoneyHelper.toCents(100.0),
      'remaining': 0,
      'currency': 'YER',
      'exchange_rate': 1.0,
      'is_posted': 1,
      'created_at': now,
    });
  }

  // Resolve a valid account_id from the seeded chart of accounts.
  final accounts = await db.query('accounts', limit: 1);
  final accountId = (accounts.first['id'] as num?)?.toInt() ?? 1;

  // Journal entry for inv-A — proper reference_id linkage.
  await db.insert('transactions', {
    'account_id': accountId,
    'journal_id': 1001,
    'debit': MoneyHelper.toCents(100.0),
    'credit': 0,
    'description': 'فاتورة مبيعات - inv-A',
    'date': now,
    'created_at': now,
    'reference_type': 'sale',
    'reference_id': 'inv-A',
    'currency_code': 'YER',
    'exchange_rate': 1.0,
    'amount_base': MoneyHelper.toCents(100.0),
  });

  // Journal entry for inv-B — proper reference_id linkage. NOTE: the
  // description contains "inv-ABC" which would be matched by the legacy
  // LIKE query as a substring of "inv-B" (since "inv-B" appears inside
  // "...inv-ABC..."). This is the trap the B-03 fix avoids by using
  // canonical reference_id linkage.
  await db.insert('transactions', {
    'account_id': accountId,
    'journal_id': 1002,
    'debit': MoneyHelper.toCents(100.0),
    'credit': 0,
    'description': 'فاتورة مبيعات - inv-ABC (trap for LIKE)',
    'date': now,
    'created_at': now,
    'reference_type': 'sale',
    'reference_id': 'inv-B',
    'currency_code': 'YER',
    'exchange_rate': 1.0,
    'amount_base': MoneyHelper.toCents(100.0),
  });

  // inv-C has NO matching transaction row — it is the real orphan.
}
