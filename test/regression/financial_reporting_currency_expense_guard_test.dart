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
    late String schemaSource;
    late String cashBoxSource;
    late String bankReconciliationSource;

    setUpAll(() {
      reportSource = [
        'lib/data/datasources/services/report_service.dart',
        'lib/data/datasources/services/report_service_daily_inventory.dart',
        'lib/data/datasources/services/report_service_statistics.dart',
      ].map((path) => File(path).readAsStringSync()).join('\n');
      invoiceSource = File(
        'lib/data/datasources/repositories/invoice_repository.dart',
      ).readAsStringSync();
      expenseSource = File(
        'lib/data/datasources/repositories/expense_repository.dart',
      ).readAsStringSync();
      schemaSource = File(
        'lib/data/datasources/migrations/schema.dart',
      ).readAsStringSync();
      cashBoxSource = File(
        'lib/data/datasources/services/cash_box_service.dart',
      ).readAsStringSync();
      bankReconciliationSource = File(
        'lib/data/datasources/services/bank_reconciliation_service.dart',
      ).readAsStringSync();
    });

    test('monthly cash flow does not query non-existent expenses.total', () {
      final start = reportSource.indexOf('getMonthlyCashFlow');
      expect(start, greaterThan(0));
      final body = reportSource.substring(start, (start + 4500).clamp(0, reportSource.length));

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
      final body = reportSource.substring(start, (start + 2200).clamp(0, reportSource.length));

      expect(body.contains(r'LEFT JOIN transactions t ON t.account_id = a.id$dateFilter'), isTrue);
      expect(body.contains(r'WHERE a.is_active = 1$currencyFilter'), isTrue);
      expect(
        body.contains('[...dateArgs, ...currencyArgs]'),
        isTrue,
        reason: 'dateFilter placeholders appear before currencyFilter placeholders in SQL.',
      );
    });

    test('financial statements SQL args follow placeholder order', () {
      final start = reportSource.indexOf('Future<List<Map<String, dynamic>>> getFinancialStatementsData');
      expect(start, greaterThan(0));
      final body = reportSource.substring(start, (start + 2600).clamp(0, reportSource.length));

      expect(body.contains(r'LEFT JOIN transactions t ON t.account_id = a.id$dateFilter'), isTrue);
      expect(body.contains(r"a.account_type IN (${accountTypes.map((_) => '?').join(',')})$currencyFilter"), isTrue);
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


    test('fresh schema includes account code/currency unique index', () {
      expect(
        schemaSource.contains('idx_accounts_code_currency'),
        isTrue,
        reason: 'Fresh installs must enforce the same (account_code, currency) uniqueness as migrations.',
      );
      expect(
        schemaSource.contains('CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_code_currency ON accounts (account_code, currency)'),
        isTrue,
      );
    });

    test('cash box currency filtering and balances include expenses', () {
      expect(
        cashBoxSource.contains('COALESCE(a.currency, cb.currency) = ?'),
        isTrue,
        reason: 'Unlinked cash boxes must be filtered by cash_boxes.currency instead of appearing for every currency.',
      );
      expect(
        cashBoxSource.contains('(cb.linked_account_id IS NULL)'),
        isFalse,
        reason: 'linked_account_id IS NULL should not make a cash box visible in every currency.',
      );
      expect(cashBoxSource.contains("operation_type = 'صرف'"), isTrue);
      expect(cashBoxSource.contains("operation_type = 'قبض'"), isTrue);
      expect(cashBoxSource.contains("'source': 'expense'"), isTrue);
    });

    test('bank reconciliation aggregate totals use readCalculatedMoney', () {
      expect(
        bankReconciliationSource.contains('MoneyHelper.readMoney(unmatchedDeposits.first'),
        isFalse,
        reason: 'SQL SUM(amount) returns cents and must be read with readCalculatedMoney.',
      );
      expect(
        bankReconciliationSource.contains('MoneyHelper.readCalculatedMoney(unmatchedDeposits.first'),
        isTrue,
      );
      expect(
        bankReconciliationSource.contains('MoneyHelper.readCalculatedMoney(newBankDebits.first'),
        isTrue,
      );
    });

    test('manual P&L COGS uses COST/base_code and keeps NULL manual refs', () {
      expect(
        reportSource.contains("account_type = 'COGS'"),
        isFalse,
        reason: 'The chart of accounts uses account_type COST; COGS is identified by base_code/account_code.',
      );
      expect(reportSource.contains("a.account_type = 'COST'"), isTrue);
      expect(reportSource.contains('a.base_code = 3200'), isTrue);
      expect(
        reportSource.contains('t.reference_type IS NULL OR t.reference_type NOT IN'),
        isTrue,
        reason: 'Manual/legacy entries with NULL reference_type must not be excluded by SQL NOT IN semantics.',
      );
    });

  });
}
