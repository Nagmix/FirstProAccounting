import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards for audit items H-03/H-04/H-05/H-07.
///
/// These source-level checks prevent reintroducing journal rows without core
/// audit metadata, ungrouped journal IDs, missing balance validation helpers,
/// or the old shift cash-in bug that credited generic expenses.
void main() {
  group('Journal integrity source guards', () {
    test('all transaction inserts include audit and currency metadata', () {
      final missing = <String>[];
      final requiredFields = [
        'journal_id',
        'amount_base',
        'reference_type',
        'reference_id',
        'currency_code',
        'exchange_rate',
      ];

      final dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in dartFiles) {
        final source = file.readAsStringSync();
        var searchFrom = 0;
        while (true) {
          final insertIndex = source.indexOf("insert('transactions'", searchFrom);
          if (insertIndex == -1) break;
          final endIndex = source.indexOf('});', insertIndex);
          final block = endIndex == -1
              ? source.substring(insertIndex)
              : source.substring(insertIndex, endIndex + 3);
          final line = '\n'.allMatches(source.substring(0, insertIndex)).length + 1;

          for (final field in requiredFields) {
            if (!block.contains("'$field'")) {
              missing.add('${file.path}:$line missing $field');
            }
          }
          searchFrom = insertIndex + 20;
        }
      }

      expect(
        missing,
        isEmpty,
        reason: 'Every journal row must be traceable and suitable for consolidated financial reporting.',
      );
    });

    test('journal validation helpers exist and are used outside invoices', () {
      final journalService = File(
        'lib/data/datasources/services/journal_service.dart',
      ).readAsStringSync();
      expect(journalService.contains('validateJournalBalanceInTransaction'), isTrue);
      expect(journalService.contains('validateJournalBaseBalanceInTransaction'), isTrue);

      final nonInvoiceFiles = Directory('lib/data')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => !file.path.endsWith('invoice_repository.dart'));
      final usages = nonInvoiceFiles
          .map((file) => file.readAsStringSync())
          .where((source) =>
              source.contains('validateJournalBalanceInTransaction') ||
              source.contains('validateJournalBaseBalanceInTransaction'))
          .length;

      expect(usages, greaterThan(1),
          reason: 'Journal validation must be applied to non-invoice financial services, not only invoices.');
    });

    test('shift cash-in no longer credits generic expenses', () {
      final source = File(
        'lib/data/datasources/services/shift_service.dart',
      ).readAsStringSync();

      expect(source.contains('shift_cash_in'), isTrue);
      expect(source.contains('shift_cash_out'), isTrue);
      expect(source.contains('4450'), isTrue,
          reason: 'Cash-in should use a dedicated cash-over revenue account.');
      expect(source.contains('5550'), isTrue,
          reason: 'Cash-out should use a dedicated cash-short expense account.');
      expect(source.contains('expenseAccountCode = 5000'), isFalse,
          reason: 'The old implementation used generic expenses as the counterpart for cash-in/out.');
      expect(source.contains('دائن (مصاريف متنوعة)'), isFalse,
          reason: 'Cash-in must not credit generic expenses and understate expenses.');
    });
  });
}
