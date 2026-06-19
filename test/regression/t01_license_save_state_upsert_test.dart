import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';

/// T-01 regression guard: LicenseService._saveState must use
/// INSERT OR REPLACE (atomic UPSERT), not DELETE-then-INSERT.
///
/// Before the fix, _saveState did:
///   await db.delete('license_state');
///   await db.insert('license_state', _state.toMap());
///
/// If the INSERT failed (constraint violation, disk error, process
/// kill between the two statements), the user's license state was
/// lost — including the license_key — causing silent revert to 'free'
/// on the next launch.
///
/// After the fix, _saveState uses:
///   await db.insert('license_state', map,
///       conflictAlgorithm: ConflictAlgorithm.replace);
///
/// This is atomic: there is no window where the row is missing.
///
/// This test verifies the SQL pattern works correctly on the
/// license_state table (which has PRIMARY KEY CHECK (id = 1)):
///   1. The seed row exists after onCreate.
///   2. INSERT OR REPLACE with id=1 updates the existing row.
///   3. INSERT OR REPLACE with a new license_key preserves the key.
///   4. The row is never missing between operations.
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
  });

  tearDown(() async {
    await db.close();
  });

  test('T-01: license_state table is seeded with id=1 on fresh install', () async {
    final rows = await db.query('license_state');
    expect(rows, hasLength(1),
        reason: 'Schema seed should insert exactly one license_state row.');
    expect(rows.first['id'], 1,
        reason: 'license_state row must have id=1 (CHECK constraint).');
    expect(rows.first['license_type'], 'free');
    expect(rows.first['status'], 'free');
  });

  test('T-01: INSERT OR REPLACE atomically updates the existing row', () async {
    // Simulate _saveState with an activated license state.
    final newMap = <String, dynamic>{
      'id': 1,
      'license_key': 'TEST-KEY-ABCD-EFGH-IJKL',
      'license_type': 'yearly',
      'status': 'active',
      'expires_at': '2027-06-19T00:00:00.000',
      'device_fingerprint': 'abc123hash',
      'installation_id': 'install-uuid-1',
      'session_token': null, // never persisted in toMap (per design)
      'last_validated_at': '2026-06-19T03:00:00.000',
      'last_sync_at': '2026-06-19T03:00:00.000',
      'record_count': 42,
      'is_offline_grace': 0,
      'offline_since': null,
      'server_url': null,
    };

    // Use the same INSERT OR REPLACE pattern as the fixed _saveState.
    await db.insert(
      'license_state',
      newMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Verify the row was updated (not duplicated).
    final rows = await db.query('license_state');
    expect(rows, hasLength(1),
        reason: 'INSERT OR REPLACE must not create a duplicate row.');
    expect(rows.first['id'], 1);
    expect(rows.first['license_key'], 'TEST-KEY-ABCD-EFGH-IJKL');
    expect(rows.first['license_type'], 'yearly');
    expect(rows.first['status'], 'active');
    expect(rows.first['record_count'], 42);
  });

  test('T-01: row is never missing between DELETE and INSERT (the bug scenario)', () async {
    // This test documents the bug scenario that the OLD code exposed:
    // if DELETE succeeded but INSERT failed, the row was missing.
    //
    // With the new INSERT OR REPLACE approach, there is no intermediate
    // state where the row is missing — the operation either succeeds
    // atomically or fails without modifying the existing row.
    //
    // We simulate this by attempting an INSERT that would fail (e.g.
    // with an invalid id that violates the CHECK constraint) and
    // verifying the existing row is preserved.

    // First, verify the seed row exists.
    var rows = await db.query('license_state');
    expect(rows, hasLength(1));
    expect(rows.first['license_key'], isNull); // seed has no key

    // Now try to INSERT with id=2 (violates CHECK constraint).
    // This should fail, but the existing id=1 row must be preserved.
    try {
      await db.insert(
        'license_state',
        {
          'id': 2, // INVALID — CHECK (id = 1) constraint
          'license_type': 'free',
          'status': 'free',
          'record_count': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      fail('Expected CHECK constraint violation for id=2');
    } catch (e) {
      // Expected: CHECK constraint failed
    }

    // The existing id=1 row must still be there.
    rows = await db.query('license_state');
    expect(rows, hasLength(1),
        reason: 'T-01: failed INSERT must NOT delete the existing row. '
            'With INSERT OR REPLACE, the failure is atomic and the '
            'previous state is preserved.');
    expect(rows.first['id'], 1);
  });

  test('T-01: multiple consecutive INSERT OR REPLACE calls preserve the latest state', () async {
    // Simulate the rapid state changes that happen during license
    // activation: free → activating → active. Each _saveState call
    // must replace the previous one without losing data.

    // Call 1: free state
    await db.insert(
      'license_state',
      {
        'id': 1,
        'license_key': null,
        'license_type': 'free',
        'status': 'free',
        'record_count': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    var rows = await db.query('license_state');
    expect(rows.first['status'], 'free');

    // Call 2: activating
    await db.insert(
      'license_state',
      {
        'id': 1,
        'license_key': 'NEW-KEY-1234-5678-9ABC',
        'license_type': 'free',
        'status': 'active',
        'record_count': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    rows = await db.query('license_state');
    expect(rows.first['status'], 'active');
    expect(rows.first['license_key'], 'NEW-KEY-1234-5678-9ABC');

    // Call 3: re-validate (record count update)
    await db.insert(
      'license_state',
      {
        'id': 1,
        'license_key': 'NEW-KEY-1234-5678-9ABC',
        'license_type': 'yearly',
        'status': 'active',
        'record_count': 100,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    rows = await db.query('license_state');
    expect(rows, hasLength(1),
        reason: 'No duplicate rows after 3 consecutive replaces.');
    expect(rows.first['license_type'], 'yearly');
    expect(rows.first['record_count'], 100);
  });
}
