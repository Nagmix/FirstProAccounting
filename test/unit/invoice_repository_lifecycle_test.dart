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

  test('recordInvoicePayment rejects a cancelled invoice without mutating it', () async {
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
        'id': 'CANCELLED-PAYMENT-GUARD',
        'type': 'sale',
        'status': 'cancelled',
        'is_posted': 1,
        'total': 10000,
        'paid_amount': 0,
        'remaining': 10000,
        'currency': 'YER',
        'exchange_rate': 1.0,
        'created_at': '2026-08-27T00:00:00.000Z',
      });
      final repository = InvoiceRepository(DatabaseHelper());

      await expectLater(
        repository.recordInvoicePayment(
          invoiceId: 'CANCELLED-PAYMENT-GUARD',
          amount: 40,
          cashBoxId: 1,
        ),
        throwsA(isA<StateError>()),
      );

      final row = (await db.query(
        'invoices',
        columns: ['status', 'paid_amount', 'remaining'],
        where: 'id = ?',
        whereArgs: ['CANCELLED-PAYMENT-GUARD'],
      )).single;
      expect(row['status'], 'cancelled');
      expect(row['paid_amount'], 0);
      expect(row['remaining'], 10000);
    } finally {
      await db.close();
      DatabaseHelper.clearTestDatabase();
    }
  });

  test('deleteInvoiceWithCascade rejects a posted invoice without deleting it', () async {
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
        'id': 'POSTED-CASCADE-DELETE-GUARD',
        'type': 'sale',
        'status': 'posted',
        'is_posted': 1,
        'created_at': '2026-08-27T00:00:00.000Z',
      });
      final repository = InvoiceRepository(DatabaseHelper());

      await expectLater(
        repository.deleteInvoiceWithCascade('POSTED-CASCADE-DELETE-GUARD'),
        throwsA(isA<StateError>()),
      );

      expect(
        await db.query(
          'invoices',
          where: 'id = ?',
          whereArgs: ['POSTED-CASCADE-DELETE-GUARD'],
        ),
        hasLength(1),
      );
    } finally {
      await db.close();
      DatabaseHelper.clearTestDatabase();
    }
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

