import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/utils/money_helper.dart';

void main() {
  group('Repair regressions: deterministic money boundaries', () {
    test('integer money values are treated as persisted cents', () {
      final result = MoneyHelper.toCentsMap(
        {'amount': 125},
        ['amount'],
      );
      expect(result['amount'], 125);
      expect(MoneyHelper.readMoney(result['amount']), closeTo(1.25, 0.0001));
    });

    test('large integer money values are not converted by a magnitude heuristic', () {
      final result = MoneyHelper.toCentsMap(
        {'amount': 125000000},
        ['amount'],
      );
      expect(result['amount'], 125000000);
      expect(MoneyHelper.readMoney(result['amount']), closeTo(1250000, 0.01));
    });

    test('decimal UI money values are converted exactly once', () {
      final result = MoneyHelper.toCentsMap(
        {'amount': 125.75},
        ['amount'],
      );
      expect(result['amount'], 12575);
      expect(MoneyHelper.readMoney(result['amount']), closeTo(125.75, 0.0001));
    });

    test('calculated SQL money values are divided from cents regardless of runtime type', () {
      expect(MoneyHelper.readCalculatedMoney(67500), closeTo(675.0, 0.0001));
      expect(MoneyHelper.readCalculatedMoney(67500.0), closeTo(675.0, 0.0001));
    });
  });
}
