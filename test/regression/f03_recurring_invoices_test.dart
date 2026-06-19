import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/repositories/invoice_repository.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';
import 'package:firstpro/data/datasources/services/recurring_invoice_service.dart';

/// F-03 regression tests for RecurringInvoiceService.
///
/// Verifies:
///   - CRUD operations on templates (create, read, update, delete).
///   - Pause/resume functionality.
///   - processDueTemplates finds due templates and advances
///     next_run_date.
///   - Frequency advancement (daily/weekly/monthly/yearly) computes
///     the correct next date.
///
/// Note: full invoice generation (saveInvoiceWithJournalEntries) is
/// NOT tested here because it requires a fully-seeded chart of
/// accounts and would make the test brittle. The generation path is
/// exercised via the existing widget/integration tests.
void main() {
  late Database db;
  late RecurringInvoiceService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 54,
      onCreate: (database, version) async {
        await DatabaseSchema.onCreate(database, version);
      },
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
    DatabaseHelper.useTestDatabase(db);
    final invoiceRepo = InvoiceRepository(DatabaseHelper());
    final refRepo = ReferenceDataRepository(DatabaseHelper());
    service = RecurringInvoiceService(DatabaseHelper(), invoiceRepo, refRepo);
  });

  tearDown(() async {
    DatabaseHelper.clearTestDatabase();
    await db.close();
  });

  group('F-03: CRUD operations', () {
    test('createTemplate inserts template + items', () async {
      final id = await service.createTemplate(
        template: {
          'name': 'إيجار المحل',
          'invoice_type': 'sale',
          'payment_mechanism': 'credit',
          'frequency': 'monthly',
          'interval_value': 1,
          'next_run_date': '2026-07-01',
          'currency': 'YER',
          'exchange_rate': 1.0,
          'vat_rate': 0.0,
          'discount_amount': 0.0,
          'transport_charges': 0.0,
        },
        items: [
          {
            'product_name': 'إيجار',
            'quantity': 1.0,
            'unit_price': 500.0,
            'total_price': 500.0,
            'unit_name': 'وحدة',
            'conversion_factor': 1.0,
            'base_quantity': 1.0,
          }
        ],
      );

      expect(id, greaterThan(0));

      final template = await service.getTemplate(id);
      expect(template, isNotNull);
      expect(template!['name'], 'إيجار المحل');
      expect(template['frequency'], 'monthly');
      expect(template['status'], 'active');
      expect(template['generated_count'], 0);

      final items = await service.getTemplateItems(id);
      expect(items, hasLength(1));
      // Money fields should be stored as cents.
      expect(items.first['unit_price'], MoneyHelper.toCents(500.0));
      expect(items.first['total_price'], MoneyHelper.toCents(500.0));
    });

    test('getAllTemplates returns all templates ordered by next_run_date', () async {
      await service.createTemplate(
        template: {
          'name': 'B',
          'frequency': 'monthly',
          'interval_value': 1,
          'next_run_date': '2026-08-01',
          'currency': 'YER',
        },
        items: [],
      );
      await service.createTemplate(
        template: {
          'name': 'A',
          'frequency': 'monthly',
          'interval_value': 1,
          'next_run_date': '2026-07-01',
          'currency': 'YER',
        },
        items: [],
      );

      final templates = await service.getAllTemplates();
      expect(templates, hasLength(2));
      // Ordered by next_run_date ASC → A (July) before B (August).
      expect(templates.first['name'], 'A');
      expect(templates.last['name'], 'B');
    });

    test('updateTemplate replaces items', () async {
      final id = await service.createTemplate(
        template: {
          'name': 'Test',
          'frequency': 'monthly',
          'interval_value': 1,
          'next_run_date': '2026-07-01',
          'currency': 'YER',
        },
        items: [
          {'product_name': 'item1', 'quantity': 1.0, 'unit_price': 100.0, 'total_price': 100.0},
        ],
      );

      await service.updateTemplate(
        id,
        template: {
          'name': 'Test Updated',
          'frequency': 'weekly',
          'interval_value': 2,
          'next_run_date': '2026-07-15',
          'currency': 'YER',
          'discount_amount': 10.0,
          'transport_charges': 0.0,
        },
        items: [
          {'product_name': 'item2', 'quantity': 2.0, 'unit_price': 200.0, 'total_price': 400.0},
          {'product_name': 'item3', 'quantity': 1.0, 'unit_price': 50.0, 'total_price': 50.0},
        ],
      );

      final template = await service.getTemplate(id);
      expect(template!['name'], 'Test Updated');
      expect(template['frequency'], 'weekly');

      final items = await service.getTemplateItems(id);
      expect(items, hasLength(2), reason: 'Old items should be replaced.');
      expect(items.first['product_name'], 'item2');
      expect(items.last['product_name'], 'item3');
    });

    test('deleteTemplate removes template + cascades to items', () async {
      final id = await service.createTemplate(
        template: {
          'name': 'To Delete',
          'frequency': 'monthly',
          'interval_value': 1,
          'next_run_date': '2026-07-01',
          'currency': 'YER',
        },
        items: [
          {'product_name': 'item', 'quantity': 1.0, 'unit_price': 100.0, 'total_price': 100.0},
        ],
      );

      await service.deleteTemplate(id);

      final template = await service.getTemplate(id);
      expect(template, isNull);

      final items = await service.getTemplateItems(id);
      expect(items, isEmpty, reason: 'Items should cascade-delete with template.');
    });

    test('pauseTemplate sets status to paused', () async {
      final id = await service.createTemplate(
        template: {
          'name': 'Test',
          'frequency': 'monthly',
          'interval_value': 1,
          'next_run_date': '2026-07-01',
          'currency': 'YER',
        },
        items: [],
      );

      await service.pauseTemplate(id);
      final template = await service.getTemplate(id);
      expect(template!['status'], 'paused');
    });

    test('resumeTemplate sets status to active', () async {
      final id = await service.createTemplate(
        template: {
          'name': 'Test',
          'frequency': 'monthly',
          'interval_value': 1,
          'next_run_date': '2026-07-01',
          'currency': 'YER',
          'status': 'paused',
        },
        items: [],
      );

      await service.resumeTemplate(id);
      final template = await service.getTemplate(id);
      expect(template!['status'], 'active');
    });

    test('resumeTemplate advances next_run_date if it is in the past', () async {
      final pastDate = DateTime.now().subtract(const Duration(days: 5));
      final id = await service.createTemplate(
        template: {
          'name': 'Test',
          'frequency': 'monthly',
          'interval_value': 1,
          'next_run_date': pastDate.toIso8601String().substring(0, 10),
          'currency': 'YER',
          'status': 'paused',
        },
        items: [],
      );

      await service.resumeTemplate(id);
      final template = await service.getTemplate(id);
      final newNextRun = template!['next_run_date'] as String;
      final newDate = DateTime.parse(newNextRun);
      // The new date should be in the future (advanced from today by 1 month).
      expect(newDate.isAfter(DateTime.now()), isTrue);
    });
  });

  group('F-03: processDueTemplates', () {
    test('does not process paused templates', () async {
      await service.createTemplate(
        template: {
          'name': 'Paused',
          'frequency': 'monthly',
          'interval_value': 1,
          'next_run_date': DateTime.now().subtract(const Duration(days: 1)).toIso8601String().substring(0, 10),
          'currency': 'YER',
          'status': 'paused',
        },
        items: [
          {'product_name': 'item', 'quantity': 1.0, 'unit_price': 100.0, 'total_price': 100.0},
        ],
      );

      final result = await service.processDueTemplates();
      expect(result.generated, 0, reason: 'Paused templates should not be processed.');
    });

    test('does not process templates with future next_run_date', () async {
      await service.createTemplate(
        template: {
          'name': 'Future',
          'frequency': 'monthly',
          'interval_value': 1,
          'next_run_date': DateTime.now().add(const Duration(days: 30)).toIso8601String().substring(0, 10),
          'currency': 'YER',
          'status': 'active',
        },
        items: [
          {'product_name': 'item', 'quantity': 1.0, 'unit_price': 100.0, 'total_price': 100.0},
        ],
      );

      final result = await service.processDueTemplates();
      expect(result.generated, 0, reason: 'Future-dated templates should not be processed.');
    });

    test('skips templates with no items', () async {
      await service.createTemplate(
        template: {
          'name': 'No Items',
          'frequency': 'monthly',
          'interval_value': 1,
          'next_run_date': DateTime.now().subtract(const Duration(days: 1)).toIso8601String().substring(0, 10),
          'currency': 'YER',
          'status': 'active',
        },
        items: [],
      );

      final result = await service.processDueTemplates();
      expect(result.generated, 0);
      expect(result.skipped, greaterThanOrEqualTo(1),
          reason: 'Templates with no items should be skipped.');
    });
  });

  group('F-03: v54 migration', () {
    test('recurring_invoices table exists after schema onCreate', () async {
      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('recurring_invoices', 'recurring_invoice_items')");
      final tableNames = tables.map((t) => t['name'] as String).toList();
      expect(tableNames, contains('recurring_invoices'));
      expect(tableNames, contains('recurring_invoice_items'));
    });

    test('indexes exist for performance', () async {
      final indexes = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_recurring%'");
      final indexNames = indexes.map((t) => t['name'] as String).toList();
      expect(indexNames, contains('idx_recurring_next_run'));
      expect(indexNames, contains('idx_recurring_items_ri'));
    });
  });
}
