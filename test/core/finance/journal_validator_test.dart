import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/finance/journal_validator.dart';

void main() {
  group('JournalValidator', () {
    test('accepts a balanced multi-line journal in base currency', () {
      final lines = [
        const JournalLine(
          accountId: 1,
          debitMinorUnits: 10000,
          creditMinorUnits: 0,
          currencyCode: 'USD',
          amountBaseMinorUnits: 36000,
        ),
        const JournalLine(
          accountId: 2,
          debitMinorUnits: 0,
          creditMinorUnits: 10000,
          currencyCode: 'USD',
          amountBaseMinorUnits: 36000,
        ),
      ];

      expect(() => JournalValidator.ensureBalanced(lines), returnsNormally);
    });

    test('rejects a journal whose base-currency totals do not balance', () {
      final lines = [
        const JournalLine(
          accountId: 1,
          debitMinorUnits: 10000,
          creditMinorUnits: 0,
          currencyCode: 'USD',
          amountBaseMinorUnits: 36000,
        ),
        const JournalLine(
          accountId: 2,
          debitMinorUnits: 0,
          creditMinorUnits: 10000,
          currencyCode: 'USD',
          amountBaseMinorUnits: 35999,
        ),
      ];

      expect(
        () => JournalValidator.ensureBalanced(lines),
        throwsA(isA<JournalValidationException>()),
      );
    });

    test('rejects a line that contains both debit and credit', () {
      const lines = [
        JournalLine(
          accountId: 1,
          debitMinorUnits: 100,
          creditMinorUnits: 1,
          currencyCode: 'YER',
          amountBaseMinorUnits: 100,
        ),
      ];

      expect(
        () => JournalValidator.ensureBalanced(lines),
        throwsA(isA<JournalValidationException>()),
      );
    });

    test('rejects an empty or all-zero journal', () {
      expect(
        () => JournalValidator.ensureBalanced(const <JournalLine>[]),
        throwsA(isA<JournalValidationException>()),
      );
      expect(
        () => JournalValidator.ensureBalanced([
          const JournalLine(
            accountId: 1,
            debitMinorUnits: 0,
            creditMinorUnits: 0,
            currencyCode: 'YER',
            amountBaseMinorUnits: 0,
          ),
        ]),
        throwsA(isA<JournalValidationException>()),
      );
    });
  });
}
