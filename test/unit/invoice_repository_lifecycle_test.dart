import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/repositories/invoice_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('deleteInvoice rejects a posted invoice without mutating it', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 59,
      onCreate: (database, version) => DatabaseSchema.onCreate(database, version),
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
    DatabaseHelper.useTestDatabase(db);
    try {
      await db.insert('invoices', {
        'id': 'POSTED-DELETE-GUARD',
        'type': 'sale',
        'status': 'posted',
        'is_posted': 1,
        'created_at': '2026-08-27T00:00:00.000Z',
      });
      final repository = InvoiceRepository(DatabaseHelper());

      await expectLater(
        repository.deleteInvoice('POSTED-DELETE-GUARD'),
        throwsA(isA<StateError>()),
      );

      final row = (await db.query(
        'invoices',
        columns: ['status', 'is_posted'],
        where: 'id = ?',
        whereArgs: ['POSTED-DELETE-GUARD'],
      )).single;
      expect(row['status'], 'posted');
      expect(row['is_posted'], 1);
    } finally {
      await db.close();
      DatabaseHelper.clearTestDatabase();
    }
  });
}

