import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/services/portable_backup_database_validator.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqflite;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('accepts a valid staged SQLite database', () async {
    final directory = await Directory.systemTemp.createTemp('fpb-validator-');
    final path = '${directory.path}/staged.db';
    final database = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) => DatabaseSchema.onCreate(db, version),
      ),
    );
    await database.close();

    try {
      await PortableBackupDatabaseValidator.validate(
        path: path,
        key: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        openDatabase: _openWithFfi,
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('rejects a staged file that is not a database', () async {
    final directory = await Directory.systemTemp.createTemp('fpb-validator-');
    final path = '${directory.path}/staged.db';
    await File(path).writeAsString('not a sqlite database');

    try {
      await expectLater(
        PortableBackupDatabaseValidator.validate(
          path: path,
          key: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
          openDatabase: _openWithFfi,
        ),
        throwsA(isA<FormatException>()),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

Future<sqflite.Database> _openWithFfi(String path, String key) {
  return databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(readOnly: true),
  );
}

