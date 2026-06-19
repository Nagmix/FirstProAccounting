import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:firstpro/core/security/db_encryption.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/services/journal_service.dart';
import 'package:firstpro/data/datasources/repositories/account_repository.dart';
import 'package:firstpro/data/datasources/repositories/customer_repository.dart';
import 'package:firstpro/data/datasources/repositories/invoice_repository.dart';
import 'package:firstpro/data/datasources/repositories/product_repository.dart';
import 'package:firstpro/data/datasources/repositories/supplier_repository.dart';
import 'package:firstpro/data/datasources/repositories/expense_repository.dart';
import 'package:firstpro/data/datasources/repositories/expense_sub_account_repository.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';
import 'package:firstpro/data/datasources/services/cash_box_service.dart';
import 'package:firstpro/data/datasources/services/stock_service.dart';
import 'package:firstpro/data/datasources/services/shift_service.dart';
import 'package:firstpro/data/datasources/repositories/order_repository.dart';
import 'package:firstpro/data/datasources/services/report_service.dart';
import 'package:firstpro/data/datasources/services/audit_service.dart';
import 'package:firstpro/data/datasources/services/costing_engine_service.dart';
import 'package:firstpro/data/datasources/services/bank_reconciliation_service.dart';
import 'package:firstpro/data/datasources/services/base_currency_service.dart';
import 'package:firstpro/data/datasources/services/voucher_auto_mapping_service.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/migrations/migration_runner.dart';
import 'package:firstpro/data/datasources/migrations/migration_helpers.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  // ══════════════════════════════════════════════════════════════
  //  C-08 + Architecture Fix: Sub-services accessed via service locator
  //
  //  Instead of creating new instances of repositories/services (which
  //  bypasses DI and creates duplicate objects), we now resolve them
  //  through the service locator. This ensures:
  //  1. Single instance per repository/service (singleton guarantee)
  //  2. Screens can use either `locator<XRepository>()` or `DatabaseHelper().xRepository`
  //  3. Both paths resolve to the SAME object — no more duplicate instances
  //  4. Future migration (e.g., PowerSync) only requires changing repository
  //     implementations, not DatabaseHelper or screens
  //
  //  The late resolution via locator is safe because setupLocator() runs
  //  in main() before any screen is loaded. These getters are only called
  //  after the app is fully initialized.
  // ══════════════════════════════════════════════════════════════

  /// Whether to use the service locator for resolving sub-services.
  /// Set to true after setupLocator() completes. Falls back to direct
  /// instantiation during migration/setup phase when locator isn't ready.
  static bool _locatorReady = false;

  /// Called by setupLocator() after all registrations are complete.
  static void markLocatorReady() => _locatorReady = true;

  // Sub-service getters — resolve via locator when available, else create locally
  JournalService get journal =>
      _locatorReady ? locator<JournalService>() : JournalService(this);
  AccountRepository get accounts =>
      _locatorReady ? locator<AccountRepository>() : AccountRepository(this);
  CustomerRepository get customers =>
      _locatorReady ? locator<CustomerRepository>() : CustomerRepository(this);
  InvoiceRepository get invoices =>
      _locatorReady ? locator<InvoiceRepository>() : InvoiceRepository(this);
  ProductRepository get products =>
      _locatorReady ? locator<ProductRepository>() : ProductRepository(this);
  SupplierRepository get suppliers =>
      _locatorReady ? locator<SupplierRepository>() : SupplierRepository(this);
  ExpenseRepository get expenses =>
      _locatorReady ? locator<ExpenseRepository>() : ExpenseRepository(this);
  CashBoxService get cashBoxes =>
      _locatorReady ? locator<CashBoxService>() : CashBoxService(this);
  ReferenceDataRepository get refData => _locatorReady
      ? locator<ReferenceDataRepository>()
      : ReferenceDataRepository(this);
  StockService get stock =>
      _locatorReady ? locator<StockService>() : StockService(this);
  ShiftService get shifts =>
      _locatorReady ? locator<ShiftService>() : ShiftService(this);
  OrderRepository get orders =>
      _locatorReady ? locator<OrderRepository>() : OrderRepository(this);
  ReportService get reports =>
      _locatorReady ? locator<ReportService>() : ReportService(this);
  AuditService get audit =>
      _locatorReady ? locator<AuditService>() : AuditService(this);
  CostingEngineService get costingEngine => _locatorReady
      ? locator<CostingEngineService>()
      : CostingEngineService(this);
  BankReconciliationService get bankReconciliation => _locatorReady
      ? locator<BankReconciliationService>()
      : BankReconciliationService(this);
  ExpenseSubAccountRepository get expenseSubAccounts => _locatorReady
      ? locator<ExpenseSubAccountRepository>()
      : ExpenseSubAccountRepository(this);
  VoucherAutoMappingService get voucherAutoMapping => _locatorReady
      ? locator<VoucherAutoMappingService>()
      : VoucherAutoMappingService(this);
  BaseCurrencyService get baseCurrency =>
      _locatorReady ? locator<BaseCurrencyService>() : BaseCurrencyService(this);

  static Database? _database;
  static Future<Database>? _databaseFuture;

  static const int _databaseVersion = 54;
  static const String _databaseName = 'firstpro.db';

  Future<Database> get database async {
    if (_database != null) return _database!;
    try {
      _databaseFuture ??= initDatabase();
      _database = await _databaseFuture!;
      return _database!;
    } catch (e) {
      // If init failed, clear the cached future so the next call retries.
      // Without this, a single failed open would permanently break all DB access.
      _databaseFuture = null;
      rethrow;
    }
  }

  /// Close the current database connection and reset the singleton instance.
  /// Call this before replacing the DB file during a restore operation.
  Future<void> resetInstance() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _databaseFuture = null;
    }
  }

  /// Test-only: inject an in-memory database for integration tests.
  ///
  /// F-05 + F-06 regression tests (and any future test that needs to
  /// exercise the real DatabaseHelper singleton with an in-memory db)
  /// call this BEFORE constructing the services under test. The
  /// injected db is returned by the `database` getter until
  /// [clearTestDatabase] is called.
  ///
  /// This is intentionally a static method (not a constructor parameter)
  /// because the production code uses `DatabaseHelper()` (factory →
  /// singleton) everywhere, and we want tests to override that singleton
  /// without changing every call site.
  @visibleForTesting
  static void useTestDatabase(Database db) {
    _database = db;
    _databaseFuture = null;
  }

  /// Test-only: clear the injected test database so the next `database`
  /// getter call re-initializes from the real initDatabase() path.
  /// Call this in tearDown() to avoid leaking the in-memory db between
  /// tests.
  @visibleForTesting
  static void clearTestDatabase() {
    // Do NOT close the db here — the test's own tearDown closes it.
    // We only clear the cached reference so the singleton is reset.
    _database = null;
    _databaseFuture = null;
  }

  /// Get the database file path (useful for backup/restore).
  Future<String> getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, _databaseName);
  }

  Future<Database> initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    final encryptionKey = await DbEncryption.getOrGenerateKey();
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      password: encryptionKey,
      onConfigure: (db) async {
        // C-06: Enable foreign key enforcement early (before onCreate/onUpgrade)
        try {
          await db.execute('PRAGMA foreign_keys = ON');
        } catch (e) {
          if (kDebugMode) debugPrint('PRAGMA foreign_keys = ON failed: $e');
        }
        // NOTE: WAL mode and PRAGMA synchronous = NORMAL were removed because
        // they can conflict with SQLCipher encryption on some devices/Android
        // versions, causing ALL database queries to fail after app startup.
        // WAL mode can be re-enabled after thorough testing with SQLCipher
        // by using: await db.execute('PRAGMA journal_mode = WAL');
      },
      onOpen: (db) async {
        // Enable foreign key enforcement (M-06)
        // SQLite doesn't enforce FK constraints by default
        try {
          await db.execute('PRAGMA foreign_keys = ON');
        } catch (e) {
          if (kDebugMode) {
            debugPrint('PRAGMA foreign_keys = ON (onOpen) failed: $e');
          }
        }
        // B-15: VERIFY enforcement is actually active instead of trusting
        // the execute call. If foreign keys are silently off in production,
        // orphan journal/stock rows can accumulate without anyone noticing.
        try {
          final rows = await db.rawQuery('PRAGMA foreign_keys');
          final enabled = rows.isNotEmpty &&
              (rows.first.values.first == 1 || rows.first.values.first == '1');
          if (!enabled) {
            // Loudly record the integrity risk (debug console + release log).
            debugPrint(
              'CRITICAL: SQLite foreign_keys enforcement is OFF — '
              'referential integrity is NOT guaranteed on this device.',
            );
            assert(
              false,
              'PRAGMA foreign_keys could not be enabled — fix before shipping.',
            );
          }
        } catch (e) {
          debugPrint('B-15: PRAGMA foreign_keys verification failed: $e');
        }
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await DatabaseSchema.onCreate(db, version);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await MigrationRunner.onUpgrade(db, oldVersion, newVersion);
  }

  // ── Pass-through helper methods ──
  // These delegate to MigrationHelpers for backward compatibility with
  // code that references DatabaseHelper for these operations.

  /// Log a migration error (delegates to MigrationHelpers).
  static void logMigrationError(String operation, dynamic error) =>
      MigrationHelpers.logMigrationError(operation, error);

  /// Delegates to [JournalService.updateAccountBalance].
  Future<void> updateAccountBalance(int accountId, double amount,
          {required bool isDebit}) =>
      journal.updateAccountBalance(accountId, amount, isDebit: isDebit);

  /// Get a setting value by key. Returns null if not found.
  Future<String?> getSetting(String key) async {
    final db = await database;
    final results = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return results.first['value'] as String?;
  }

  /// Delete a setting by key.
  Future<void> deleteSetting(String key) async {
    final db = await database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }
}
