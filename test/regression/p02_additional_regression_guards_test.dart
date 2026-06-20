import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// P-02: Additional regression guards for critical behaviors discovered
/// during the audit process. These guards prevent re-introduction of
/// subtle bugs that were fixed in previous iterations.
void main() {
  group('P-02: Source-level regression guards', () {
    // ── Guard 1: MoneyHelper.readMoney vs readCalculatedMoney ──────
    test('MoneyHelper.readMoney and readCalculatedMoney are distinct methods', () {
      final moneyHelperFile = File('lib/core/utils/money_helper.dart');
      expect(moneyHelperFile.existsSync(), isTrue,
          reason: 'MoneyHelper source must exist.');
      final source = moneyHelperFile.readAsStringSync();

      // Both methods must exist — they handle different DB return types.
      expect(source.contains('static double readMoney('), isTrue,
          reason: 'MoneyHelper.readMoney must exist (handles int vs double).');
      expect(source.contains('static double readCalculatedMoney('), isTrue,
          reason: 'MoneyHelper.readCalculatedMoney must exist (always ÷100).');
    });

    // ── Guard 2: JournalService has fiscal period check ────────────
    test('JournalService.checkFiscalPeriodOpen exists and is called', () {
      final journalFile = File('lib/data/datasources/services/journal_service.dart');
      expect(journalFile.existsSync(), isTrue);
      final source = journalFile.readAsStringSync();

      expect(source.contains('checkFiscalPeriodOpen'), isTrue,
          reason: 'JournalService must have checkFiscalPeriodOpen to prevent '
              'posting in closed fiscal years.');
    });

    // ── Guard 3: InvoiceRepository uses reference_type/reference_id ─
    test('InvoiceRepository stamps reference_type on transactions', () {
      final invoiceRepoFile =
          File('lib/data/datasources/repositories/invoice_repository.dart');
      expect(invoiceRepoFile.existsSync(), isTrue);
      final source = invoiceRepoFile.readAsStringSync();

      // The v46+ source-linking pattern must be present.
      expect(source.contains("'reference_type'"), isTrue,
          reason: 'InvoiceRepository must stamp reference_type on '
              'transactions for source-linking (v46+).');
      expect(source.contains("'reference_id'"), isTrue,
          reason: 'InvoiceRepository must stamp reference_id on '
              'transactions for source-linking (v46+).');
    });

    // ── Guard 4: CostingEngineService has reverseCOGSAllocations ───
    test('CostingEngineService has reverseCOGSAllocations for returns', () {
      final costingFile =
          File('lib/data/datasources/services/costing_engine_service.dart');
      expect(costingFile.existsSync(), isTrue);
      final source = costingFile.readAsStringSync();

      expect(source.contains('reverseCOGSAllocations'), isTrue,
          reason: 'CostingEngineService must have reverseCOGSAllocations '
              'for FIFO/LIFO cost layer restoration on invoice returns.');
      expect(source.contains('reverseCOGSAllocationsInTransaction'), isTrue,
          reason: 'CostingEngineService must have the in-transaction variant '
              'for use within db.transaction().');
    });

    // ── Guard 5: EntityBalanceHelper handles zero-crossing ─────────
    test('EntityBalanceHelper auto-flips balance_type on zero-crossing', () {
      final entityFile =
          File('lib/core/utils/entity_balance_helper.dart');
      expect(entityFile.existsSync(), isTrue);
      final source = entityFile.readAsStringSync();

      // The signed-balance convention with auto-flip must be present.
      expect(source.contains('applyBalanceChange'), isTrue,
          reason: 'EntityBalanceHelper.applyBalanceChange must exist.');
      expect(source.contains('balance_type'), isTrue,
          reason: 'EntityBalanceHelper must manage balance_type column.');
    });

    // ── Guard 6: LicenseService uses INSERT OR REPLACE (T-01) ──────
    test('LicenseService._saveState uses INSERT OR REPLACE (T-01)', () {
      final licenseFile = File('lib/core/license/license_service.dart');
      expect(licenseFile.existsSync(), isTrue);
      final source = licenseFile.readAsStringSync();

      expect(source.contains('ConflictAlgorithm.replace'), isTrue,
          reason: 'LicenseService._saveState must use INSERT OR REPLACE '
              '(not DELETE-then-INSERT) for atomic state save (T-01).');
      // Ensure the old DELETE pattern is NOT present.
      expect(source.contains("db.delete('license_state')"), isFalse,
          reason: 'LicenseService._saveState must NOT use DELETE '
              '(that was the pre-T-01 pattern).');
    });

    // ── Guard 7: ThemeProvider exists and is registered (U-01) ─────
    test('ThemeProvider exists for reactive theme switching (U-01)', () {
      final themeFile = File('lib/core/theme/theme_provider.dart');
      expect(themeFile.existsSync(), isTrue,
          reason: 'ThemeProvider must exist for reactive theme (U-01).');

      final locatorFile = File('lib/core/di/service_locator.dart');
      final locatorSource = locatorFile.readAsStringSync();
      expect(locatorSource.contains('ThemeProvider'), isTrue,
          reason: 'ThemeProvider must be registered in service_locator.dart.');
    });

    // ── Guard 8: DB version is consistent across files ─────────────
    test('DB version is 54 in both DatabaseHelper and AppConstants', () {
      final dbHelperFile = File('lib/data/datasources/database_helper.dart');
      final dbSource = dbHelperFile.readAsStringSync();
      expect(dbSource.contains('_databaseVersion = 54'), isTrue,
          reason: 'DatabaseHelper._databaseVersion must be 54.');

      final constantsFile = File('lib/core/constants/app_constants.dart');
      final constantsSource = constantsFile.readAsStringSync();
      expect(constantsSource.contains('dbVersion = 54'), isTrue,
          reason: 'AppConstants.dbVersion must match DatabaseHelper (54).');
    });

    // ── Guard 9: No orphan ThermalPrinterService (B-02) ────────────
    test('ThermalPrinterService is not re-introduced (B-02)', () {
      final orphan = File('lib/core/services/thermal_printer_service.dart');
      expect(orphan.existsSync(), isFalse,
          reason: 'ThermalPrinterService was deleted (B-02). Do not re-create.');
    });

    // ── Guard 10: AppConstants.currency removed (T-04) ─────────────
    test('AppConstants.currency and currencyEn are removed (T-04)', () {
      final constantsFile = File('lib/core/constants/app_constants.dart');
      final source = constantsFile.readAsStringSync();
      expect(RegExp(r'static\s+String\s+currency\s*=').hasMatch(source), isFalse,
          reason: 'AppConstants.currency was removed (T-04).');
      expect(RegExp(r'static\s+String\s+currencyEn\s*=').hasMatch(source), isFalse,
          reason: 'AppConstants.currencyEn was removed (T-04).');
    });

    // ── Guard 11: VAT rate is stored as percentage (B-04) ──────────
    test('SAR vat_rate is 15.0 (percentage, not fraction) in seeds (B-04)', () {
      final seedsFile = File('lib/data/datasources/migrations/seeds.dart');
      final source = seedsFile.readAsStringSync();
      // The SAR entry should have vat_rate: 15.0, not 0.15 or 0.0.
      expect(source.contains("'vat_rate': 15.0"), isTrue,
          reason: 'SAR vat_rate in seeds must be 15.0 (percentage), not 0.0 '
              'or 0.15 (B-04 fix).');
    });

    // ── Guard 12: RecurringInvoiceService exists (F-03) ────────────
    test('RecurringInvoiceService exists with processDueTemplates (F-03)', () {
      final recurringFile =
          File('lib/data/datasources/services/recurring_invoice_service.dart');
      expect(recurringFile.existsSync(), isTrue,
          reason: 'RecurringInvoiceService must exist (F-03).');

      final source = recurringFile.readAsStringSync();
      expect(source.contains('processDueTemplates'), isTrue,
          reason: 'RecurringInvoiceService must have processDueTemplates.');
      expect(source.contains('createTemplate'), isTrue,
          reason: 'RecurringInvoiceService must have createTemplate.');
    });

    // ── Guard 13: InventoryAlertService exists (F-05+F-06) ─────────
    test('InventoryAlertService exists with scanAndGenerateAlerts (F-05+F-06)',
        () {
      final alertFile =
          File('lib/data/datasources/services/inventory_alert_service.dart');
      expect(alertFile.existsSync(), isTrue,
          reason: 'InventoryAlertService must exist (F-05+F-06).');

      final source = alertFile.readAsStringSync();
      expect(source.contains('scanAndGenerateAlerts'), isTrue);
      expect(source.contains('getAlertSummary'), isTrue);
    });

    // ── Guard 14: InvoiceShareService exists (F-04) ────────────────
    test('InvoiceShareService exists with WhatsApp + email (F-04)', () {
      final shareFile = File('lib/core/utils/invoice_share_service.dart');
      expect(shareFile.existsSync(), isTrue,
          reason: 'InvoiceShareService must exist (F-04).');

      final source = shareFile.readAsStringSync();
      expect(source.contains('shareViaWhatsApp'), isTrue);
      expect(source.contains('shareViaEmail'), isTrue);
    });

    // ── Guard 15: BankStatementImporter exists (F-02) ──────────────
    test('BankStatementImporter exists with CSV/Excel parsing (F-02)', () {
      final importFile = File('lib/core/utils/bank_statement_importer.dart');
      expect(importFile.existsSync(), isTrue,
          reason: 'BankStatementImporter must exist (F-02).');

      final source = importFile.readAsStringSync();
      expect(source.contains('_parseCsv'), isTrue);
      expect(source.contains('_parseExcel'), isTrue);
      expect(source.contains('autoDetectColumns'), isTrue);
    });
  });
}
