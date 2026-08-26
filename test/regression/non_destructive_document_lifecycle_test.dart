import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/services/cash_box_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('posted voucher cannot be deleted and remains auditable', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 59,
      onCreate: (database, version) => DatabaseSchema.onCreate(database, version),
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
    DatabaseHelper.useTestDatabase(db);
    final service = CashBoxService(DatabaseHelper());
    try {
      final voucherId = await db.insert('vouchers', {
        'voucher_number': 'V-POSTED-1',
        'voucher_type': 'receipt',
        'date': '2026-08-26',
        'currency': 'YER',
        'total_amount': 10000,
        'is_posted': 1,
        'created_at': '2026-08-26T10:00:00.000Z',
        'updated_at': '2026-08-26T10:00:00.000Z',
      });

      await expectLater(
        service.deleteVoucher(voucherId),
        throwsA(isA<StateError>()),
      );

      expect(
        await db.query('vouchers', where: 'id = ?', whereArgs: [voucherId]),
        hasLength(1),
      );
    } finally {
      DatabaseHelper.clearTestDatabase();
      await db.close();
    }
  });
}
