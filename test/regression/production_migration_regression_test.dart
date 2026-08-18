import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;

  String read(String relativePath) =>
      File('$root/$relativePath').readAsStringSync();

  test('v58 production migration is additive and wired after v57', () {
    final migration = read('lib/data/datasources/migrations/migration_v58.dart');
    final runner = read('lib/data/datasources/migrations/migration_runner.dart');
    final schema = read('lib/data/datasources/migrations/schema.dart');
    final helper = read('lib/data/datasources/database_helper.dart');

    for (final table in [
      'recipes',
      'recipe_lines',
      'production_orders',
      'production_consumptions',
      'production_outputs',
      'production_status_history',
    ]) {
      expect(migration, contains('CREATE TABLE IF NOT EXISTS $table'));
      expect(schema, contains('CREATE TABLE IF NOT EXISTS $table'));
    }

    expect(migration, contains('CREATE INDEX IF NOT EXISTS'));
    expect(runner, contains("migration_v58.dart"));
    expect(runner, contains('MigrationV58.migrate(db)'));
    expect(runner.indexOf('MigrationV57.migrate(db)'), lessThan(runner.indexOf('MigrationV58.migrate(db)')));
    expect(helper, contains('static const int _databaseVersion = 58;'));
  });
}
