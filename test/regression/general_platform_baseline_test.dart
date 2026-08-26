import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('current production baseline is schema version 58 before v59', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 58,
      onCreate: DatabaseSchema.onCreate,
    );

    try {
      final rows = await db.rawQuery('PRAGMA user_version');
      expect(rows, hasLength(1));
      expect((rows.single.values.single as num).toInt(), 58);
    } finally {
      await db.close();
    }
  });
}
