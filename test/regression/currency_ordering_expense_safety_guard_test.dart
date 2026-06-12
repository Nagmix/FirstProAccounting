import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards for audit items M-01..M-04.
void main() {
  group('Currency, ordering, and expense safety source guards', () {
    late String referenceDataSource;
    late String currencyConstantsSource;
    late String expenseRepositorySource;
    late List<File> dataSourceFiles;

    setUpAll(() {
      referenceDataSource = File(
        'lib/data/datasources/repositories/reference_data_repository.dart',
      ).readAsStringSync();
      currencyConstantsSource = File(
        'lib/core/helpers/currency_constants.dart',
      ).readAsStringSync();
      expenseRepositorySource = File(
        'lib/data/datasources/repositories/expense_repository.dart',
      ).readAsStringSync();
      dataSourceFiles = Directory('lib/data/datasources')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();
    });

    test('currency mutations clear BaseCurrencyService cache', () {
      expect(referenceDataSource.contains('_clearBaseCurrencyCache'), isTrue);
      expect(referenceDataSource.contains('locator<BaseCurrencyService>().clearCache()'), isTrue);
      expect(referenceDataSource.contains("'key': 'default_currency'"), isTrue,
          reason: 'Changing default currency should keep settings.default_currency in sync.');

      for (final method in [
        'insertCurrency',
        'updateCurrency',
        'deleteCurrency',
        'setDefaultCurrency',
      ]) {
        final idx = referenceDataSource.indexOf(method);
        expect(idx, greaterThanOrEqualTo(0), reason: '$method must exist');
        final nextMethod = referenceDataSource.indexOf('\n  Future<', idx + method.length);
        final body = referenceDataSource.substring(
          idx,
          nextMethod == -1 ? referenceDataSource.length : nextMethod,
        );
        expect(body.contains('_clearBaseCurrencyCache();'), isTrue,
            reason: '$method must invalidate base currency/offset cache.');
      }
    });

    test('CurrencyConstants default code and symbol are dynamic', () {
      expect(currencyConstantsSource.contains("static String get defaultCode => 'YER'"), isFalse);
      expect(currencyConstantsSource.contains("_defaultCurrencyCode = 'YER'"), isTrue);
      expect(currencyConstantsSource.contains('getBaseCurrencyCode()'), isTrue);
      expect(currencyConstantsSource.contains("_currencyInfo[_defaultCurrencyCode]?['symbol']"), isTrue);
    });

    test('dynamic raw ORDER BY never interpolates unvalidated orderBy', () {
      final violations = <String>[];
      final dangerous = RegExp(r'ORDER BY[^\n]*(\$orderBy|\.\$)');

      for (final file in dataSourceFiles) {
        final source = file.readAsStringSync();
        for (final match in dangerous.allMatches(source)) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
          violations.add('${file.path}:$line ${match.group(0)}');
        }
      }

      expect(violations, isEmpty,
          reason: 'ORDER BY clauses must use whitelisted values before interpolation.');
      expect(referenceDataSource.contains('_currencyOrderByWhitelist'), isTrue);
      expect(referenceDataSource.contains('_notificationOrderByWhitelist'), isTrue);
      expect(File('lib/data/datasources/repositories/customer_repository.dart')
          .readAsStringSync()
          .contains('_customerOrderByWhitelist'), isTrue);
      expect(File('lib/data/datasources/repositories/product_repository.dart')
          .readAsStringSync()
          .contains('_productOrderByWhitelist'), isTrue);
      expect(File('lib/data/datasources/repositories/invoice_repository.dart')
          .readAsStringSync()
          .contains('_invoiceOrderByWhitelist'), isTrue);
      expect(File('lib/data/datasources/services/cash_box_service.dart')
          .readAsStringSync()
          .contains('_cashBoxOrderByWhitelist'), isTrue);
      expect(File('lib/data/datasources/services/shift_service.dart')
          .readAsStringSync()
          .contains('_shiftOrderByWhitelist'), isTrue);
    });



    test('legacy foreign-currency expense audit is available and read-only', () {
      expect(
        expenseRepositorySource.contains('auditLegacyForeignCurrencyExpenseJournals'),
        isTrue,
        reason: 'Historical foreign-currency expense inconsistencies need an explicit audit path.',
      );
      final idx = expenseRepositorySource.indexOf('auditLegacyForeignCurrencyExpenseJournals');
      final nextMethod = expenseRepositorySource.indexOf('Future<int> updateExpense', idx);
      final body = expenseRepositorySource.substring(idx, nextMethod);
      expect(body.contains('SELECT'), isTrue);
      expect(body.contains('UPDATE '), isFalse,
          reason: 'Historical audit must not rewrite accounting history silently.');
      expect(body.contains('DELETE '), isFalse,
          reason: 'Historical audit must be read-only.');
    });

    test('unsafe expense CRUD paths are journal-aware or blocked', () {
      final insertIdx = expenseRepositorySource.indexOf('Future<int> insertExpense');
      final updateIdx = expenseRepositorySource.indexOf('Future<int> updateExpense');
      final deleteIdx = expenseRepositorySource.indexOf('Future<int> deleteExpense');
      expect(insertIdx, greaterThanOrEqualTo(0));
      expect(updateIdx, greaterThanOrEqualTo(0));
      expect(deleteIdx, greaterThanOrEqualTo(0));

      final insertBody = expenseRepositorySource.substring(insertIdx, updateIdx);
      final updateBody = expenseRepositorySource.substring(updateIdx, deleteIdx);
      final deleteBody = expenseRepositorySource.substring(deleteIdx,
          expenseRepositorySource.indexOf('Future<double> getTotalExpensesThisMonth'));

      expect(insertBody.contains('saveExpenseWithJournalEntry'), isTrue,
          reason: 'insertExpense must not bypass journal posting.');
      expect(updateBody.contains('updateExpenseWithJournalEntry'), isTrue,
          reason: 'updateExpense must not update financial records without reversals.');
      expect(deleteBody.contains('UnsupportedError'), isTrue,
          reason: 'deleteExpense must be blocked until a journal-aware cancellation flow is used.');
      expect(expenseRepositorySource.contains('Future<int> saveExpenseWithJournalEntry'), isTrue,
          reason: 'saveExpenseWithJournalEntry returns the inserted id for safe delegation.');
    });
  });
}
