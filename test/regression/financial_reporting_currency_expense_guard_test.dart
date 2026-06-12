import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guards for the 2026-06-12 audit fixes:
/// - C-01: report SQL placeholder argument order.
/// - C-02: monthly cash flow must not reference a non-existent expenses.total.
/// - C-04: invoice journal transaction inserts must populate amount_base.
/// - C-05/H-06: expenses post in native currency and use expense_date as
///   transaction date, not DateTime.now() as the accounting date.
void main() {
  group('Financial reporting and multi-currency expense source guards', () {
    late String reportSource;
    late String invoiceSource;
    late String expenseSource;

    setUpAll(() {
      reportSource = File(
        'lib/data/datasources/services/report_service.dart',
      ).readAsStringSync();
      invoiceSource = File(
        'lib/data/datasources/repositories/invoice_repository.dart',
      ).readAsStringSync();
      expenseSource = File(
        'lib/data/datasources/repositories/expense_repository.dart',
      ).readAsStringSync();
    });

    test('monthly cash flow does not query non-existent expenses.total', () {
      final start = reportSource.indexOf('getMonthlyCashFlow');
      expect(start, greaterThan(0));
      final body = reportSource.substring(start, start + 4500);

      expect(
        body.contains('SUM(total) AS outflow'),
        isFalse,
        reason: 'expenses table has amount/amount_base, not total.',
      );
      expect(
        body.contains("final expenseAmountExpr = hasCurrencyFilter ? 'amount' : 'amount_base'"),
        isTrue,
        reason: 'Currency-specific cash flow uses native amount; consolidated cash flow uses amount_base.',
      );
    });

    test('trial balance SQL args follow placeholder order', () {
      final start = reportSource.indexOf('Future<List<Map<String, dynamic>>> getTrialBalanceData');
      expect(start, greaterThan(0));
      final body = reportSource.substring(start, start + 2200);

      expect(body.contains('LEFT JOIN transactions t ON t.account_id = a.id\$dateFilter'), isTrue);
      expect(body.contains('WHERE a.is_active = 1\$currencyFilter'), isTrue);
      expect(
        body.contains('[...dateArgs, ...currencyArgs]'),
        isTrue,
        reason: 'dateFilter placeholders appear before currencyFilter placeholders in SQL.',
      );
    });

    test('financial statements SQL args follow placeholder order', () {
      final start = reportSource.indexOf('Future<List<Map<String, dynamic>>> getFinancialStatementsData');
      expect(start, greaterThan(0));
      final body = reportSource.substring(start, start + 2600);

      expect(body.contains('LEFT JOIN transactions t ON t.account_id = a.id\$dateFilter'), isTrue);
      expect(body.contains('a.account_type IN (\${accountTypes.map((_) => \'?\').join(\',\')})\$currencyFilter'), isTrue);
      expect(
        body.contains('[...dateArgs, ...accountTypes, ...currencyArgs]'),
        isTrue,
        reason: 'SQL placeholders are date filters, then account types, then currency filter.',
      );
    });

    test('all invoice journal transaction inserts populate amount_base', () {
      final missingLines = <int>[];
      var index = 0;
      while (true) {
        final insertIndex = invoiceSource.indexOf("insert('transactions'", index);
        if (insertIndex == -1) break;
        final endIndex = invoiceSource.indexOf('});', insertIndex);
        final block = invoiceSource.substring(insertIndex, endIndex + 3);
        if (!block.contains('amount_base')) {
          final line = '\n'.allMatches(invoiceSource.substring(0, insertIndex)).length + 1;
          missingLines.add(line);
        }
        index = insertIndex + 20;
      }

      expect(
        missingLines,
        isEmpty,
        reason: 'Every invoice journal row must include amount_base for consolidated reporting.',
      );
    });

    test('expenses use native-currency posting policy and expense_date', () {
      expect(
        expenseSource.contains('needsYerConversion'),
        isFalse,
        reason: 'Expenses should no longer silently convert journal debit/credit to YER while keeping foreign currency_code.',
      );
      expect(
        expenseSource.contains('final transactionDate = expenseDate;'),
        isTrue,
        reason: 'New expense journal entries must use expense_date as accounting date.',
      );
      expect(
        expenseSource.contains('final newTransactionDate = expenseDate;'),
        isTrue,
        reason: 'Updated expense journal entries must use the selected expense date.',
      );
      expect(
        expenseSource.contains("'reference_type': 'expense'"),
        isTrue,
        reason: 'New expense transactions should be reference-linked for exact future reversals.',
      );
    });
  });
}
