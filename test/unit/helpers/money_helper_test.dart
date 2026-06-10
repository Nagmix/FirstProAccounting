import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// MoneyHelper Unit Tests
/// Tests all fixed-point arithmetic operations for accounting precision.
/// This is the foundation of the financial system — any error here
/// would corrupt all monetary calculations.
void main() {
  group('MoneyHelper', () {
    // ═══════════════════════════════════════════════════════════
    //  toCents / fromCents — Core conversion
    // ═══════════════════════════════════════════════════════════
    group('toCents', () {
      test('converts zero to zero', () {
        expect(MoneyHelper.toCents(0.0), equals(0));
      });

      test('converts simple whole amount correctly', () {
        expect(MoneyHelper.toCents(100.0), equals(10000));
      });

      test('converts amount with two decimal places correctly', () {
        expect(MoneyHelper.toCents(150.75), equals(15075));
      });

      test('converts small decimal amounts correctly', () {
        expect(MoneyHelper.toCents(0.01), equals(1));
        expect(MoneyHelper.toCents(0.50), equals(50));
        expect(MoneyHelper.toCents(0.99), equals(99));
      });

      test('handles large amounts correctly', () {
        expect(MoneyHelper.toCents(999999.99), equals(99999999));
      });

      test('rounds floating-point drift correctly (0.1 + 0.2)', () {
        // 0.1 + 0.2 = 0.30000000000000004 in floating point
        // After toCents → round() → 30, which is correct
        final result = MoneyHelper.toCents(0.1 + 0.2);
        expect(result, equals(30));
      });

      test('rounds 0.005 correctly (boundary)', () {
        // 0.005 * 100 = 0.5 → rounds to 0 (banker's rounding in round())
        // Actually Dart's round() rounds 0.5 away from zero → 1
        final result = MoneyHelper.toCents(0.005);
        expect(result, equals(1)); // 0.005 rounds up to 0.01 = 1 cent
      });

      test('handles negative amounts', () {
        expect(MoneyHelper.toCents(-100.50), equals(-10050));
      });
    });

    group('fromCents', () {
      test('converts zero cents to zero', () {
        expect(MoneyHelper.fromCents(0), equals(0.0));
      });

      test('converts cents to human-readable amount', () {
        expect(MoneyHelper.fromCents(15075), closeTo(150.75, 0.001));
      });

      test('converts 1 cent to 0.01', () {
        expect(MoneyHelper.fromCents(1), closeTo(0.01, 0.001));
      });

      test('converts large cents correctly', () {
        expect(MoneyHelper.fromCents(99999999), closeTo(999999.99, 0.001));
      });
    });

    group('toCents / fromCents round-trip', () {
      test('round-trip preserves value for typical amounts', () {
        final amounts = [0.0, 0.01, 1.0, 99.99, 100.0, 150.75, 999999.99];
        for (final amount in amounts) {
          final cents = MoneyHelper.toCents(amount);
          final restored = MoneyHelper.fromCents(cents);
          expect(restored, closeTo(amount, 0.001),
              reason: 'Round-trip failed for $amount');
        }
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  readMoney — Safe database read
    // ═══════════════════════════════════════════════════════════
    group('readMoney', () {
      test('returns fallback for null', () {
        expect(MoneyHelper.readMoney(null), equals(0.0));
        expect(MoneyHelper.readMoney(null, fallback: 5.0), equals(5.0));
      });

      test('reads int as cents (new INTEGER columns)', () {
        // 15075 cents → 150.75
        expect(MoneyHelper.readMoney(15075), closeTo(150.75, 0.001));
      });

      test('reads double as legacy (already divided)', () {
        // Legacy REAL column: value already in human-readable form
        expect(MoneyHelper.readMoney(150.75), equals(150.75));
      });

      test('reads zero int correctly', () {
        expect(MoneyHelper.readMoney(0), equals(0.0));
      });

      test('reads zero double correctly', () {
        expect(MoneyHelper.readMoney(0.0), equals(0.0));
      });

      test('handles num type with integer value', () {
        // num that is actually an int → treat as cents
        expect(MoneyHelper.readMoney(15075 as num), closeTo(150.75, 0.001));
      });
    });

    group('readCalculatedMoney', () {
      test('reads int as cents', () {
        expect(MoneyHelper.readCalculatedMoney(15075), closeTo(150.75, 0.001));
      });

      test('reads double as cents (unlike readMoney which treats as legacy)', () {
        // readCalculatedMoney ALWAYS divides by 100, even for doubles
        // This is for SQL-calculated values like SUM(base_quantity * unit_cost)
        expect(MoneyHelper.readCalculatedMoney(67500.0), closeTo(675.0, 0.01));
      });

      test('returns fallback for null', () {
        expect(MoneyHelper.readCalculatedMoney(null), equals(0.0));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  Arithmetic operations with fixed-point precision
    // ═══════════════════════════════════════════════════════════
    group('add', () {
      test('adds two monetary values correctly', () {
        expect(MoneyHelper.add(100.50, 50.25), closeTo(150.75, 0.001));
      });

      test('avoids floating-point drift (0.1 + 0.2)', () {
        // Regular double: 0.1 + 0.2 = 0.30000000000000004
        // MoneyHelper.add: should be exactly 0.30
        expect(MoneyHelper.add(0.1, 0.2), closeTo(0.30, 0.001));
      });

      test('adds zero correctly', () {
        expect(MoneyHelper.add(100.0, 0.0), closeTo(100.0, 0.001));
      });
    });

    group('subtract', () {
      test('subtracts two monetary values correctly', () {
        expect(MoneyHelper.subtract(150.75, 50.25), closeTo(100.50, 0.001));
      });

      test('handles negative result', () {
        expect(MoneyHelper.subtract(50.0, 100.0), closeTo(-50.0, 0.001));
      });
    });

    group('multiply', () {
      test('multiplies amount by factor correctly', () {
        expect(MoneyHelper.multiply(100.0, 3.0), closeTo(300.0, 0.01));
      });

      test('multiplies by fractional factor', () {
        expect(MoneyHelper.multiply(100.0, 0.15), closeTo(15.0, 0.01));
      });

      test('multiplies by zero', () {
        expect(MoneyHelper.multiply(100.0, 0.0), closeTo(0.0, 0.001));
      });

      test('multiplies by negative factor', () {
        expect(MoneyHelper.multiply(100.0, -1.0), closeTo(-100.0, 0.01));
      });
    });

    group('divide', () {
      test('divides amount by factor correctly', () {
        expect(MoneyHelper.divide(300.0, 3.0), closeTo(100.0, 0.01));
      });

      test('returns zero when dividing by zero', () {
        expect(MoneyHelper.divide(100.0, 0.0), equals(0.0));
      });

      test('handles non-integer quotient', () {
        expect(MoneyHelper.divide(100.0, 3.0), closeTo(33.33, 0.01));
      });
    });

    group('compare', () {
      test('returns negative when a < b', () {
        expect(MoneyHelper.compare(50.0, 100.0), lessThan(0));
      });

      test('returns zero when a == b', () {
        expect(MoneyHelper.compare(100.0, 100.0), equals(0));
      });

      test('returns positive when a > b', () {
        expect(MoneyHelper.compare(100.0, 50.0), greaterThan(0));
      });

      test('compares values that differ by floating-point drift', () {
        // 0.1 + 0.2 should equal 0.3 in accounting terms
        expect(MoneyHelper.compare(0.1 + 0.2, 0.3), equals(0));
      });
    });

    group('round2', () {
      test('rounds to 2 decimal places', () {
        expect(MoneyHelper.round2(150.756), closeTo(150.76, 0.001));
        expect(MoneyHelper.round2(150.754), closeTo(150.75, 0.001));
      });

      test('handles values already at 2 decimal places', () {
        expect(MoneyHelper.round2(150.75), closeTo(150.75, 0.001));
      });
    });

    group('isZero', () {
      test('returns true for zero', () {
        expect(MoneyHelper.isZero(0.0), isTrue);
      });

      test('returns true for near-zero values within precision', () {
        expect(MoneyHelper.isZero(0.004), isTrue); // Below half-cent
      });

      test('returns false for non-zero values', () {
        expect(MoneyHelper.isZero(0.01), isFalse);
        expect(MoneyHelper.isZero(100.0), isFalse);
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  toCentsMap — Batch conversion for database storage
    // ═══════════════════════════════════════════════════════════
    group('toCentsMap', () {
      test('converts specified double fields to cents', () {
        final map = {
          'name': 'Test',
          'balance': 150.75,
          'amount': 200.50,
        };
        final result = MoneyHelper.toCentsMap(map, ['balance', 'amount']);
        expect(result['name'], equals('Test')); // Non-money field unchanged
        expect(result['balance'], equals(15075)); // Converted
        expect(result['amount'], equals(20050)); // Converted
      });

      test('skips non-existent fields silently', () {
        final map = {'name': 'Test'};
        final result = MoneyHelper.toCentsMap(map, ['balance']);
        expect(result.containsKey('balance'), isFalse);
      });

      test('converts int fields to cents (fixes the 5.00 bug)', () {
        // int values from UI forms must be converted to cents too.
        // Previously, ints were skipped, causing 500 → stored as 500 cents
        // → readMoney(500) = 5.00 riyals (should be 500 riyals).
        final map = {'balance': 500}; // Human-readable 500 riyals
        final result = MoneyHelper.toCentsMap(map, ['balance']);
        expect(result['balance'], equals(50000)); // 500 * 100 = 50000 cents
      });

      test('preserves original map', () {
        final map = {'balance': 150.75};
        final result = MoneyHelper.toCentsMap(map, ['balance']);
        expect(map['balance'], equals(150.75)); // Original not modified
        expect(result['balance'], equals(15075)); // Result is converted
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  Money field constants
    // ═══════════════════════════════════════════════════════════
    group('Money field constants', () {
      test('invoiceMoneyFields contains expected fields', () {
        expect(MoneyHelper.invoiceMoneyFields, containsAll([
          'subtotal', 'discount_amount', 'tax_amount', 'total',
          'paid_amount', 'remaining', 'transport_charges',
        ]));
      });

      test('productMoneyFields contains expected fields', () {
        expect(MoneyHelper.productMoneyFields, containsAll([
          'sell_price', 'cost_price', 'average_cost',
          'wholesale_price', 'special_wholesale_price', 'minimum_sale_price',
        ]));
      });

      test('accountMoneyFields contains expected fields', () {
        expect(MoneyHelper.accountMoneyFields,
            containsAll(['balance', 'debt_ceiling']));
      });

      test('transactionMoneyFields contains debit and credit', () {
        expect(MoneyHelper.transactionMoneyFields,
            containsAll(['debit', 'credit']));
      });

      test('voucherMoneyFields includes total_amount (Fix #4)', () {
        // Fix #4: total_amount must be included for vouchers
        expect(MoneyHelper.voucherMoneyFields, contains('total_amount'));
      });
    });
  });
}
