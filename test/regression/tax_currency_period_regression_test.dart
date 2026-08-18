import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/core/finance/currency_engine.dart';
import 'package:firstpro/core/finance/tax_engine.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/services/journal_service.dart';

void main() {
  late Database db;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 58,
      onCreate: (database, version) async {
        await DatabaseSchema.onCreate(database, version);
      },
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
    DatabaseHelper.useTestDatabase(db);
  });

  tearDown(() async {
    DatabaseHelper.clearTestDatabase();
    await db.close();
  });

  group('tax, currency and fiscal-period regression guards', () {
    test('rejects a zero exchange rate before conversion', () {
      expect(
        () => const CurrencyEngine().convertMinorUnits(
          amountMinorUnits: 100,
          exchangeRateMicros: 0,
        ),
        throwsArgumentError,
      );
    });

    test('rounds inclusive tax at the minor-unit boundary', () {
      final result = const TaxEngine().calculate(
        taxableMinorUnits: 101,
        rateBasisPoints: 1500,
        isInclusive: true,
      );

      expect(result.netMinorUnits, 88);
      expect(result.taxMinorUnits, 13);
      expect(result.grossMinorUnits, 101);
    });

    test('rejects postings dated in a closed fiscal year', () async {
      final now = DateTime.utc(2099, 8, 1).toIso8601String();
      await db.insert('fiscal_years', {
        'year': 2099,
        'name': 'FY 2099',
        'start_date': '2099-01-01',
        'end_date': '2099-12-31',
        'status': 'closed',
        'closed_at': now,
        'closed_by': 'test',
        'created_at': now,
        'updated_at': now,
      });

      await expectLater(
        JournalService(DatabaseHelper()).checkFiscalPeriodOpen('2099-08-19'),
        throwsException,
      );
    });
  });
}

