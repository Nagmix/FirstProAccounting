import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/utils/currency_exchange_calculator.dart';

/// U-03 unit tests for CurrencyExchangeCalculator.
///
/// These tests verify the pure calculation logic extracted from
/// CurrencyExchangeScreen. They run without DB access or widget
/// setup, making the math regression-testable in isolation.
void main() {
  group('CurrencyExchangeCalculator.getCurrencyRate', () {
    test('returns the exchange_rate for a known currency', () {
      final currencies = <Map<String, dynamic>>[
        {'code': 'YER', 'exchange_rate': 1.0},
        {'code': 'SAR', 'exchange_rate': 140.0},
        {'code': 'USD', 'exchange_rate': 530.0},
      ];
      expect(CurrencyExchangeCalculator.getCurrencyRate(currencies, 'YER'), 1.0);
      expect(CurrencyExchangeCalculator.getCurrencyRate(currencies, 'SAR'), 140.0);
      expect(CurrencyExchangeCalculator.getCurrencyRate(currencies, 'USD'), 530.0);
    });

    test('returns 1.0 as fallback for an unknown currency', () {
      final currencies = <Map<String, dynamic>>[
        {'code': 'YER', 'exchange_rate': 1.0},
      ];
      expect(CurrencyExchangeCalculator.getCurrencyRate(currencies, 'EUR'), 1.0,
          reason: 'Unknown currency should fall back to 1.0 (no conversion).');
    });

    test('returns 1.0 for an empty currencies list', () {
      expect(CurrencyExchangeCalculator.getCurrencyRate([], 'YER'), 1.0);
    });

    test('handles num exchange_rate values (int, double)', () {
      final currencies = <Map<String, dynamic>>[
        {'code': 'A', 'exchange_rate': 100}, // int
        {'code': 'B', 'exchange_rate': 530.0}, // double
      ];
      expect(CurrencyExchangeCalculator.getCurrencyRate(currencies, 'A'), 100.0);
      expect(CurrencyExchangeCalculator.getCurrencyRate(currencies, 'B'), 530.0);
    });

    test('falls back to 1.0 when exchange_rate is null', () {
      final currencies = <Map<String, dynamic>>[
        {'code': 'X', 'exchange_rate': null},
      ];
      expect(CurrencyExchangeCalculator.getCurrencyRate(currencies, 'X'), 1.0);
    });
  });

  group('CurrencyExchangeCalculator.calculateCrossRate', () {
    test('returns fromRate / toRate', () {
      expect(CurrencyExchangeCalculator.calculateCrossRate(fromRate: 1.0, toRate: 140.0), closeTo(1.0 / 140.0, 0.0001));
      expect(CurrencyExchangeCalculator.calculateCrossRate(fromRate: 530.0, toRate: 1.0), 530.0);
      expect(CurrencyExchangeCalculator.calculateCrossRate(fromRate: 140.0, toRate: 530.0), closeTo(140.0 / 530.0, 0.0001));
    });

    test('returns 0 when toRate is 0 (division by zero guard)', () {
      expect(CurrencyExchangeCalculator.calculateCrossRate(fromRate: 100.0, toRate: 0.0), 0,
          reason: 'Division by zero must return 0, not throw or inf.');
    });

    test('returns 0 when both rates are 0', () {
      expect(CurrencyExchangeCalculator.calculateCrossRate(fromRate: 0.0, toRate: 0.0), 0);
    });
  });

  group('CurrencyExchangeCalculator.calculateCrossRateFromCurrencies', () {
    test('looks up rates and computes the cross rate', () {
      final currencies = <Map<String, dynamic>>[
        {'code': 'YER', 'exchange_rate': 1.0},
        {'code': 'SAR', 'exchange_rate': 140.0},
      ];
      final rate = CurrencyExchangeCalculator.calculateCrossRateFromCurrencies(
          currencies: currencies, fromCurrency: 'YER', toCurrency: 'SAR');
      expect(rate, closeTo(1.0 / 140.0, 0.0001));
    });

    test('falls back to 1.0 for unknown currencies (gives rate = 1.0)', () {
      final currencies = <Map<String, dynamic>>[
        {'code': 'YER', 'exchange_rate': 1.0},
      ];
      // EUR is unknown → rate 1.0; YER is known → rate 1.0 → cross = 1.0/1.0 = 1.0
      final rate = CurrencyExchangeCalculator.calculateCrossRateFromCurrencies(
          currencies: currencies, fromCurrency: 'EUR', toCurrency: 'YER');
      expect(rate, 1.0);
    });
  });

  group('CurrencyExchangeCalculator.calculateGainLoss', () {
    test('returns none when fromAmount is 0', () {
      final r = CurrencyExchangeCalculator.calculateGainLoss(
          fromAmount: 0, manualRate: 140, systemRate: 140, toCurrencyRateToBase: 1.0);
      expect(r.isNone, isTrue);
      expect(r.amount, 0);
    });

    test('returns none when systemRate is 0', () {
      final r = CurrencyExchangeCalculator.calculateGainLoss(
          fromAmount: 100, manualRate: 140, systemRate: 0, toCurrencyRateToBase: 1.0);
      expect(r.isNone, isTrue);
    });

    test('returns none when diff is 0', () {
      final r = CurrencyExchangeCalculator.calculateGainLoss(
          fromAmount: 100, manualRate: 140.0, systemRate: 140.0, toCurrencyRateToBase: 1.0);
      expect(r.isNone, isTrue);
    });

    test('returns gain when manualRate > systemRate', () {
      // fromAmount=100 SAR, manualRate=141, systemRate=140
      // actualTo = 100*141 = 14100; systemTo = 100*140 = 14000
      // diff = +100 SAR → in base (YER) = 100 * 140 (SAR rate) = 14000 YER
      final r = CurrencyExchangeCalculator.calculateGainLoss(
          fromAmount: 100, manualRate: 141, systemRate: 140, toCurrencyRateToBase: 140.0);
      expect(r.isGain, isTrue);
      expect(r.amount, 14000.0);
    });

    test('returns loss when manualRate < systemRate', () {
      // fromAmount=100 SAR, manualRate=139, systemRate=140
      // actualTo = 13900; systemTo = 14000; diff = -100 SAR
      // in base = 100 * 140 = 14000 YER (absolute value)
      final r = CurrencyExchangeCalculator.calculateGainLoss(
          fromAmount: 100, manualRate: 139, systemRate: 140, toCurrencyRateToBase: 140.0);
      expect(r.isLoss, isTrue);
      expect(r.amount, 14000.0);
    });

    test('amount is always non-negative (absolute value)', () {
      final r = CurrencyExchangeCalculator.calculateGainLoss(
          fromAmount: 100, manualRate: 130, systemRate: 140, toCurrencyRateToBase: 1.0);
      expect(r.amount, greaterThanOrEqualTo(0));
      expect(r.isLoss, isTrue);
      // diff = 100*(130-140) = -1000 → |diff| * 1.0 = 1000
      expect(r.amount, 1000.0);
    });
  });

  group('CurrencyExchangeCalculator.formatRate', () {
    test('formats whole numbers without decimals', () {
      expect(CurrencyExchangeCalculator.formatRate(140), '140');
      expect(CurrencyExchangeCalculator.formatRate(140.0), '140');
      expect(CurrencyExchangeCalculator.formatRate(1), '1');
    });

    test('formats fractional rates with up to 4 decimal places', () {
      // 1/140 = 0.007142857... → 4 decimals = 0.0071
      expect(CurrencyExchangeCalculator.formatRate(1 / 140), '0.0071');
      // 1/530 = 0.001886... → 4 decimals = 0.0019
      expect(CurrencyExchangeCalculator.formatRate(1 / 530), '0.0019');
    });

    test('strips trailing zeros from fractional rates', () {
      // 0.5 → "0.5000" → strip zeros → "0.5"
      expect(CurrencyExchangeCalculator.formatRate(0.5), '0.5');
      // 0.25 → "0.2500" → strip zeros → "0.25"
      expect(CurrencyExchangeCalculator.formatRate(0.25), '0.25');
    });
  });

  group('CurrencyExchangeCalculator.formatAmount', () {
    test('formats whole numbers without decimals', () {
      expect(CurrencyExchangeCalculator.formatAmount(1000), '1000');
      expect(CurrencyExchangeCalculator.formatAmount(1000.0), '1000');
    });

    test('formats fractional amounts with up to 2 decimal places', () {
      expect(CurrencyExchangeCalculator.formatAmount(99.99), '99.99');
      expect(CurrencyExchangeCalculator.formatAmount(99.5), '99.5');
      expect(CurrencyExchangeCalculator.formatAmount(99.25), '99.25');
    });
  });

  group('CurrencyExchangeCalculator.calculateToAmount', () {
    test('returns fromAmount * rate', () {
      expect(CurrencyExchangeCalculator.calculateToAmount(100, 140), 14000);
      expect(CurrencyExchangeCalculator.calculateToAmount(0, 140), 0);
      expect(CurrencyExchangeCalculator.calculateToAmount(100, 0), 0);
    });
  });

  group('GainLossResult equality', () {
    test('two identical results are equal', () {
      const a = GainLossResult(amount: 100, type: GainLossType.gain);
      const b = GainLossResult(amount: 100, type: GainLossType.gain);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different amounts are not equal', () {
      const a = GainLossResult(amount: 100, type: GainLossType.gain);
      const b = GainLossResult(amount: 200, type: GainLossType.gain);
      expect(a, isNot(equals(b)));
    });

    test('different types are not equal', () {
      const a = GainLossResult(amount: 100, type: GainLossType.gain);
      const b = GainLossResult(amount: 100, type: GainLossType.loss);
      expect(a, isNot(equals(b)));
    });

    test('isGain/isLoss/isNone getters work', () {
      const gain = GainLossResult(amount: 100, type: GainLossType.gain);
      const loss = GainLossResult(amount: 100, type: GainLossType.loss);
      const none = GainLossResult(amount: 0, type: GainLossType.none);
      expect(gain.isGain, isTrue);
      expect(gain.isLoss, isFalse);
      expect(gain.isNone, isFalse);
      expect(loss.isLoss, isTrue);
      expect(none.isNone, isTrue);
    });
  });
}
