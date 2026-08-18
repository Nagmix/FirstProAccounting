import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/finance/currency_engine.dart';

void main() {
  test('converts minor units using a fixed-point exchange rate', () {
    final result = const CurrencyEngine().convertMinorUnits(
      amountMinorUnits: 10000,
      exchangeRateMicros: 140000000,
    );

    expect(result, 1400000);
  });

  test('rounds negative conversions symmetrically', () {
    final result = const CurrencyEngine().convertMinorUnits(
      amountMinorUnits: -10001,
      exchangeRateMicros: 140000000,
    );

    expect(result, -140014);
  });

  test('converts major units without floating-point base arithmetic', () {
    final result = const CurrencyEngine().convertMajorUnits(
      amount: 10.01,
      exchangeRate: 140,
    );

    expect(result, 140140);
  });
}
