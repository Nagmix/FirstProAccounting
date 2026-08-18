import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Service maintenance migration v57 guards', () {
    test('MigrationV57 defines all service tables and indexes', () {
      final migrationFile =
          File('lib/data/datasources/migrations/migration_v57.dart');
      expect(migrationFile.existsSync(), isTrue);
      final source = migrationFile.readAsStringSync();

      for (final table in [
        'service_orders',
        'service_order_devices',
        'service_order_lines',
        'service_status_history',
        'service_payments',
        'service_warranties',
      ]) {
        expect(
          source.contains('CREATE TABLE IF NOT EXISTS $table'),
          isTrue,
          reason: 'MigrationV57 must create $table idempotently.',
        );
      }

      expect(source.contains('idx_service_orders_status'), isTrue);
      expect(source.contains('idx_service_order_lines_order'), isTrue);
      expect(source.contains('idx_service_payments_order'), isTrue);
      expect(source.contains('idx_service_warranties_order'), isTrue);
    });

    test('MigrationRunner invokes v57 after v56', () {
      final runnerFile =
          File('lib/data/datasources/migrations/migration_runner.dart');
      expect(runnerFile.existsSync(), isTrue);
      final source = runnerFile.readAsStringSync();

      expect(source.contains("migration_v57.dart"), isTrue);
      expect(source.contains('if (oldVersion < 57)'), isTrue);
      expect(source.contains('MigrationV57.migrate(db)'), isTrue);

      final v56Position = source.indexOf('MigrationV56.migrate(db)');
      final v57Position = source.indexOf('MigrationV57.migrate(db)');
      expect(v56Position, greaterThanOrEqualTo(0));
      expect(v57Position, greaterThan(v56Position));
    });

    test('database version is 58 in both sources after v58', () {
      final dbSource =
          File('lib/data/datasources/database_helper.dart').readAsStringSync();
      final constantsSource =
          File('lib/core/constants/app_constants.dart').readAsStringSync();

      expect(dbSource.contains('_databaseVersion = 58'), isTrue);
      expect(constantsSource.contains('dbVersion = 58'), isTrue);
    });

    test('fresh schema contains service maintenance tables', () {
      final schemaSource =
          File('lib/data/datasources/migrations/schema.dart').readAsStringSync();

      for (final table in [
        'service_orders',
        'service_order_devices',
        'service_order_lines',
        'service_status_history',
        'service_payments',
        'service_warranties',
      ]) {
        expect(
          schemaSource.contains('CREATE TABLE IF NOT EXISTS $table') ||
              schemaSource.contains('CREATE TABLE $table'),
          isTrue,
          reason: 'Fresh databases must include $table.',
        );
      }
    });
  });
}
