import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import '../../core/security/db_encryption.dart';
import '../../core/utils/money_helper.dart';
import '../../core/di/service_locator.dart';
import 'services/journal_service.dart';
import 'repositories/account_repository.dart';
import 'repositories/customer_repository.dart';
import 'repositories/invoice_repository.dart';
import 'repositories/product_repository.dart';
import 'repositories/supplier_repository.dart';
import 'repositories/expense_repository.dart';
import 'repositories/reference_data_repository.dart';
import 'services/cash_box_service.dart';
import 'services/stock_service.dart';
import 'services/shift_service.dart';
import 'repositories/order_repository.dart';
import 'services/report_service.dart';
import 'services/audit_service.dart';
import 'services/costing_engine_service.dart';
import 'services/bank_reconciliation_service.dart';
import '../models/account_model.dart';
import '../models/customer_model.dart';
import '../models/product_model.dart';
import '../models/invoice_model.dart';
import 'migrations/schema.dart';
import 'migrations/seeds.dart';
import 'migrations/migration_runner.dart';
import 'migrations/migration_helpers.dart';

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
  JournalService get journal => _locatorReady ? locator<JournalService>() : JournalService(this);
  AccountRepository get accounts => _locatorReady ? locator<AccountRepository>() : AccountRepository(this);
  CustomerRepository get customers => _locatorReady ? locator<CustomerRepository>() : CustomerRepository(this);
  InvoiceRepository get invoices => _locatorReady ? locator<InvoiceRepository>() : InvoiceRepository(this);
  ProductRepository get products => _locatorReady ? locator<ProductRepository>() : ProductRepository(this);
  SupplierRepository get suppliers => _locatorReady ? locator<SupplierRepository>() : SupplierRepository(this);
  ExpenseRepository get expenses => _locatorReady ? locator<ExpenseRepository>() : ExpenseRepository(this);
  CashBoxService get cashBoxes => _locatorReady ? locator<CashBoxService>() : CashBoxService(this);
  ReferenceDataRepository get refData => _locatorReady ? locator<ReferenceDataRepository>() : ReferenceDataRepository(this);
  StockService get stock => _locatorReady ? locator<StockService>() : StockService(this);
  ShiftService get shifts => _locatorReady ? locator<ShiftService>() : ShiftService(this);
  OrderRepository get orders => _locatorReady ? locator<OrderRepository>() : OrderRepository(this);
  ReportService get reports => _locatorReady ? locator<ReportService>() : ReportService(this);
  AuditService get audit => _locatorReady ? locator<AuditService>() : AuditService(this);
  CostingEngineService get costingEngine => _locatorReady ? locator<CostingEngineService>() : CostingEngineService(this);
  BankReconciliationService get bankReconciliation => _locatorReady ? locator<BankReconciliationService>() : BankReconciliationService(this);

  static Database? _database;
  static Future<Database>? _databaseFuture;

  static const int _databaseVersion = 43;
  static const String _databaseName = 'firstpro.db';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _databaseFuture ??= initDatabase();
    _database = await _databaseFuture!;
    return _database!;
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
        await db.execute('PRAGMA foreign_keys = ON');
        // Enable WAL mode for better concurrent read/write performance
        await db.execute('PRAGMA journal_mode = WAL');
        // Reduce sync frequency (safe with WAL; much faster writes)
        await db.execute('PRAGMA synchronous = NORMAL');
      },
      onOpen: (db) async {
        // Enable foreign key enforcement (M-06)
        // SQLite doesn't enforce FK constraints by default
        await db.execute('PRAGMA foreign_keys = ON');
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
  Future<void> updateAccountBalance(int accountId, double amount, {required bool isDebit}) =>
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
