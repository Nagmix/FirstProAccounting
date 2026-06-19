import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T-02 regression guard: LicenseService must cache the record count
/// for 60 seconds to avoid running 4 COUNT(*) queries on every
/// canAddRecord() call.
///
/// This is a source-level guard (not a behavioral test) because
/// LicenseService is a singleton that depends on DatabaseHelper +
/// FlutterSecureStorage, which are hard to mock without a full
/// integration test harness. The guard verifies that the caching
/// fields and methods exist in the source code, and that the four
/// add-screens call invalidateRecordCountCache() after a successful
/// save.
void main() {
  group('T-02: LicenseService record count cache (source guard)', () {
    test('license_service.dart contains the cache fields and methods', () {
      // Read the source file and verify the T-02 fix is present.
      // If a future refactor removes the cache, this test fails.
      final source = File('lib/core/license/license_service.dart')
          .readAsStringSync();

      // Cache fields.
      expect(
        source.contains('int? _cachedRecordCount;'),
        isTrue,
        reason: 'T-02: _cachedRecordCount field must exist for the cache.',
      );
      expect(
        source.contains('DateTime? _cachedRecordCountAt;'),
        isTrue,
        reason: 'T-02: _cachedRecordCountAt field must exist for the cache '
            'TTL check.',
      );
      expect(
        source.contains('_recordCountCacheTtl'),
        isTrue,
        reason: 'T-02: _recordCountCacheTtl constant must exist.',
      );

      // Cache invalidation method.
      expect(
        source.contains('void invalidateRecordCountCache()'),
        isTrue,
        reason: 'T-02: invalidateRecordCountCache() method must exist so '
            'callers can force a refresh after a record insert.',
      );

      // _getTotalRecordCount must accept forceRefresh parameter.
      expect(
        source.contains(
            'Future<int> _getTotalRecordCount({bool forceRefresh = false})'),
        isTrue,
        reason: 'T-02: _getTotalRecordCount must accept a forceRefresh '
            'parameter so syncWithServer can bypass the cache.',
      );

      // syncWithServer must call with forceRefresh: true.
      expect(
        source.contains('_getTotalRecordCount(forceRefresh: true)'),
        isTrue,
        reason: 'T-02: syncWithServer must bypass the cache to report the '
            'exact current count to the server.',
      );

      // The cache TTL check must be present.
      expect(
        source.contains('age < _recordCountCacheTtl'),
        isTrue,
        reason: 'T-02: the cache must check the age against the TTL before '
            'returning the cached value.',
      );
    });

    test('LicenseProvider exposes invalidateRecordCountCache to the UI', () {
      final source = File('lib/core/license/license_provider.dart')
          .readAsStringSync();
      expect(
        source.contains('void invalidateRecordCountCache()'),
        isTrue,
        reason: 'T-02: LicenseProvider must expose '
            'invalidateRecordCountCache() so UI screens can call it after '
            'a successful record insert.',
      );
    });

    test('add screens call invalidateRecordCountCache after successful save', () {
      // The four screens that check canAddRecord before saving must
      // also invalidate the cache after a successful save, so the next
      // canAddRecord check reflects the new count.
      final screens = [
        'lib/ui/screens/customers/add_customer_sheet.dart',
        'lib/ui/screens/products/add_product_sheet.dart',
        'lib/ui/screens/expenses/add_expense_screen.dart',
        'lib/ui/screens/invoices/create_invoice_screen.dart',
      ];
      for (final path in screens) {
        final source = File(path).readAsStringSync();
        expect(
          source.contains('invalidateRecordCountCache()'),
          isTrue,
          reason: 'T-02: $path must call invalidateRecordCountCache() after '
              'a successful save so the next canAddRecord check reflects '
              'the new count immediately.',
        );
      }
    });
  });
}
