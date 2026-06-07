import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/core/constants/app_constants.dart';

/// CurrencyFormatter Unit Tests
/// Tests all formatting, parsing, and display functions
void main() {
  group('CurrencyFormatter', () {
    group('format', () {
      test('formats amount with two decimal places and symbol', () {
        final result = CurrencyFormatter.format(1500.75, symbol: 'ر.ي');
        expect(result, contains('1,500.75'));
        expect(result, contains('ر.ي'));
      });

      test('formats zero amount', () {
        final result = CurrencyFormatter.format(0.0, symbol: 'ر.ي');
        expect(result, contains('0.00'));
      });

      test('formats large amount with commas', () {
        final result = CurrencyFormatter.format(1500000.50, symbol: 'ر.ي');
        expect(result, contains('1,500,000.50'));
      });

      test('formats small amount correctly', () {
        final result = CurrencyFormatter.format(0.01, symbol: 'ر.ي');
        expect(result, contains('0.01'));
      });
    });

    group('formatValue', () {
      test('formats amount without symbol', () {
        final result = CurrencyFormatter.formatValue(1500.75);
        expect(result, contains('1,500.75'));
        expect(result, isNot(contains('ر.ي')));
      });
    });

    group('formatCompact', () {
      test('formats millions with M suffix', () {
        expect(CurrencyFormatter.formatCompact(1500000), contains('1.5M'));
      });

      test('formats thousands with K suffix', () {
        expect(CurrencyFormatter.formatCompact(1500), contains('1.5K'));
      });

      test('formats small numbers without suffix', () {
        expect(CurrencyFormatter.formatCompact(500), equals('500'));
      });

      test('formats exactly 1000 with K', () {
        expect(CurrencyFormatter.formatCompact(1000), contains('1.0K'));
      });
    });

    group('parse', () {
      test('parses formatted string to double', () {
        expect(CurrencyFormatter.parse('1,500.75'), closeTo(1500.75, 0.01));
      });

      test('parses string without commas', () {
        expect(CurrencyFormatter.parse('1500.75'), closeTo(1500.75, 0.01));
      });

      test('parses string with currency symbol', () {
        // The parse method removes the default currency symbol
        expect(CurrencyFormatter.parse('1,500.75 ر.ي'), closeTo(1500.75, 0.01));
      });

      test('returns 0.0 for unparseable string', () {
        expect(CurrencyFormatter.parse('abc'), equals(0.0));
      });

      test('parses zero', () {
        expect(CurrencyFormatter.parse('0.00'), equals(0.0));
      });
    });

    group('isZero', () {
      test('returns true for zero', () {
        expect(CurrencyFormatter.isZero(0.0), isTrue);
      });

      test('returns true for near-zero within epsilon', () {
        expect(CurrencyFormatter.isZero(0.004), isTrue);
      });

      test('returns false for non-zero', () {
        expect(CurrencyFormatter.isZero(0.01), isFalse);
        expect(CurrencyFormatter.isZero(100.0), isFalse);
      });
    });

    group('formatSigned', () {
      test('adds + prefix for positive amounts', () {
        final result = CurrencyFormatter.formatSigned(100.0, symbol: 'ر.ي');
        expect(result, contains('+'));
      });

      test('no + prefix for negative amounts', () {
        final result = CurrencyFormatter.formatSigned(-100.0, symbol: 'ر.ي');
        expect(result, isNot(contains('+')));
      });

      test('zero has + prefix (0 >= 0 is true in formatSigned)', () {
        // formatSigned adds '+' for amount >= 0, and 0 >= 0 is true
        final result = CurrencyFormatter.formatSigned(0.0, symbol: 'ر.ي');
        expect(result, contains('+'));
      });
    });
  });
}
