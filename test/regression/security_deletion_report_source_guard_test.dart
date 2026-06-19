import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards for the second full rescan critical/high findings:
/// C-01, H-01, H-02, H-03, H-04, M-02, M-03, M-04, L-01.
///
/// Note: The historical "repository audit report is marked as historical"
/// guard was removed when docs/audit_report.md was deleted per project owner
/// request (archived audit reports are no longer kept in the repo). The
/// active audit reference now lives at agent-ctx/AUDIT.md (gitignored).
void main() {
  group('Security, deletion, and report source guards', () {
    late String appLockSource;
    late String licenseApiSource;
    late String licenseModelSource;
    late String referenceDataSource;
    late String productRepositorySource;
    late String accountRepositorySource;
    late String reportServiceSource;
    late String supportSource;

    setUpAll(() {
      appLockSource = File('lib/ui/screens/app_lock/app_lock_screen.dart')
          .readAsStringSync();
      licenseApiSource = File('lib/core/license/license_api_client.dart')
          .readAsStringSync();
      licenseModelSource = File('lib/core/license/license_models.dart')
          .readAsStringSync();
      referenceDataSource = File(
        'lib/data/datasources/repositories/reference_data_repository.dart',
      ).readAsStringSync();
      productRepositorySource = File(
        'lib/data/datasources/repositories/product_repository.dart',
      ).readAsStringSync();
      accountRepositorySource = File(
        'lib/data/datasources/repositories/account_repository.dart',
      ).readAsStringSync();
      reportServiceSource =
          File('lib/data/datasources/services/report_service.dart')
              .readAsStringSync();
      supportSource = File('lib/ui/screens/support/support_screen.dart')
          .readAsStringSync();
    });

    test('app lock does not bypass security on initialization errors', () {
      expect(appLockSource.contains('SECURITY ERROR'), isTrue);
      expect(appLockSource.contains('_buildSecurityErrorScreen'), isTrue);
      expect(appLockSource.contains('F1r5tPr0_Fallback_2024_Salt'), isFalse,
          reason: 'Static fallback PIN salts are not allowed.');

      final catchIdx = appLockSource.indexOf(
          'AppLockScreen._initializeScreen: SECURITY ERROR');
      expect(catchIdx, greaterThanOrEqualTo(0));
      final catchBlock = appLockSource.substring(catchIdx, catchIdx + 500);
      expect(catchBlock.contains('_navigateToApp'), isFalse,
          reason: 'Initialization failures must not navigate into the app.');
    });

    test('license logging and storage redacts sensitive values', () {
      expect(licenseApiSource.contains('LogInterceptor'), isFalse);
      expect(licenseApiSource.contains('requestBody: true'), isFalse);
      expect(licenseApiSource.contains('responseBody: true'), isFalse);
      expect(licenseApiSource.contains('License API request'), isTrue);
      expect(licenseModelSource.contains("'session_token': null"), isTrue,
          reason:
              'session_token must not be persisted to license_state DB rows.');
      expect(licenseModelSource.contains('sessionToken: null'), isTrue,
          reason: 'session_token should be loaded from secure storage only.');
    });

    test('currency deletion is blocked when currency is used', () {
      expect(referenceDataSource.contains('getCurrencyUsageSummary'), isTrue);
      for (final token in [
        'accounts',
        'transactions',
        'invoices',
        'expenses',
        'cash_boxes',
        'vouchers',
        'products',
      ]) {
        expect(referenceDataSource.contains(token), isTrue);
      }
      expect(referenceDataSource.contains('لا يمكن حذف العملة'), isTrue);
    });

    test('product deletion considers inventory and costing history', () {
      expect(productRepositorySource.contains('dependencyTables'), isTrue);
      for (final table in [
        'invoice_items',
        'stock_movements',
        'inventory_cost_layers',
        'movement_cost_allocations',
        'stock_transfers',
        'inventory_voucher_items',
        'stocktaking_items',
      ]) {
        expect(productRepositorySource.contains(table), isTrue);
      }
      expect(productRepositorySource.contains("'is_active': 0"), isTrue,
          reason: 'Products with history should be soft-deleted.');
    });

    test('account deletion checks critical dependencies before hard delete',
        () {
      expect(accountRepositorySource.contains('blockingChecks'), isTrue);
      expect(
          accountRepositorySource.contains('لا يمكن حذف حساب نظامي'), isTrue);
      expect(
          accountRepositorySource.contains('لا يمكن حذف حساب يحتوي على حسابات فرعية'),
          isTrue);
      for (final table in [
        'transactions',
        'voucher_items',
        'cash_boxes',
        'expenses',
        'products',
      ]) {
        expect(accountRepositorySource.contains(table), isTrue);
      }
    });

    test('sales report type filter is whitelisted', () {
      expect(
          reportServiceSource.contains('_salesReportTypeFilterWhitelist'),
          isTrue);
      expect(
          reportServiceSource.contains('String whereClause = typeFilter'),
          isFalse);
      expect(reportServiceSource.contains('ArgumentError.value'), isTrue);
    });

    test('support attachments are copied to persistent app storage', () {
      expect(supportSource.contains('getApplicationDocumentsDirectory'), isTrue);
      expect(supportSource.contains('support_attachments'), isTrue);
      expect(supportSource.contains('io.File(picked.path).copy'), isTrue);
      expect(supportSource.contains('_ComplaintSearchDelegate'), isTrue);
    });

    test(
        'account code generation is currency-aware in repository and UI', () {
      expect(
          accountRepositorySource.contains(
              'getNextAccountCode(String accountType, {String? currency})'),
          isTrue);
      expect(accountRepositorySource.contains('AND currency = ?'), isTrue);
      final addAccountSource =
          File('lib/ui/screens/accounts/add_account_sheet.dart')
              .readAsStringSync();
      expect(addAccountSource.contains('currency: _currency'), isTrue);
      expect(addAccountSource.contains('_generateCode();'), isTrue);
    });
  });
}
