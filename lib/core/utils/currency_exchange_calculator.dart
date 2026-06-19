import 'package:flutter/foundation.dart';

/// Pure calculation logic for currency exchange operations.
///
/// U-03 refactor (2026-06-19): extracted from the
/// `_CurrencyExchangeScreenState` class so the math is testable in
/// isolation without DB access or widget setup.
///
/// This class is stateless and pure — all methods take their inputs as
/// parameters and return computed values. The widget layer remains
/// responsible for TextEditingController plumbing and setState calls.
///
/// The previous in-widget implementation duplicated the calculation
/// across `_calculateCrossRate`, `_calculateGainLoss`, `_getCurrencyRate`,
/// `_formatRate`, and `_formatAmount`. The same logic now lives here.
class CurrencyExchangeCalculator {
  CurrencyExchangeCalculator._();

  /// Look up the exchange_rate value from a currencies list.
  ///
  /// [currencies] is the raw DB rows from `ReferenceDataRepository
  /// .getAllCurrencies()` — each row has at least `code` (String) and
  /// `exchange_rate` (num).
  ///
  /// Returns 1.0 as a defensive fallback if the currency is not found
  /// (matches the previous in-widget behavior).
  static double getCurrencyRate(
    List<Map<String, dynamic>> currencies,
    String code,
  ) {
    for (final c in currencies) {
      if (c['code'] == code) {
        return (c['exchange_rate'] as num?)?.toDouble() ?? 1.0;
      }
    }
    return 1.0;
  }

  /// Calculate the cross rate between two currencies.
  ///
  /// Formula: `crossRate = fromRate / toRate`
  ///
  /// This gives the number of TO-currency units per 1 FROM-currency
  /// unit. Example: from=YER (rate 1.0), to=SAR (rate 140.0) →
  /// crossRate = 1.0 / 140.0 = 0.00714 SAR per YER.
  ///
  /// Returns 0 if [toRate] is 0 (division by zero guard).
  static double calculateCrossRate({
    required double fromRate,
    required double toRate,
  }) {
    if (toRate == 0) return 0;
    return fromRate / toRate;
  }

  /// Convenience: look up rates from [currencies] and compute the cross rate.
  static double calculateCrossRateFromCurrencies({
    required List<Map<String, dynamic>> currencies,
    required String fromCurrency,
    required String toCurrency,
  }) {
    final fromRate = getCurrencyRate(currencies, fromCurrency);
    final toRate = getCurrencyRate(currencies, toCurrency);
    return calculateCrossRate(fromRate: fromRate, toRate: toRate);
  }

  /// Calculate the gain/loss from a manual exchange rate vs the system
  /// cross rate.
  ///
  /// Gain/loss is the difference between:
  ///   - actualToAmount = fromAmount * manualRate (what the user gets)
  ///   - systemToAmount = fromAmount * systemRate (what they'd get at system rate)
  ///
  /// The difference is computed in the TO currency, then converted to
  /// the BASE currency (YER) for accounting purposes (the gain/loss
  /// journal entry is posted to account 4700/5300 in YER per IAS 21).
  ///
  /// Returns a [GainLossResult] with:
  ///   - amount: the absolute gain/loss in BASE currency (YER), ≥ 0.
  ///   - type: 'gain', 'loss', or 'none' (when |diff| < 0.01).
  static GainLossResult calculateGainLoss({
    required double fromAmount,
    required double manualRate,
    required double systemRate,
    required double toCurrencyRateToBase,
  }) {
    if (fromAmount == 0 || systemRate == 0) {
      return const GainLossResult(amount: 0, type: GainLossType.none);
    }

    final systemToAmount = fromAmount * systemRate;
    final actualToAmount = fromAmount * manualRate;
    final diff = actualToAmount - systemToAmount;

    if (diff.abs() < 0.01) {
      return const GainLossResult(amount: 0, type: GainLossType.none);
    }

    // Convert diff to base currency (YER) for gain/loss accounting.
    final diffInBase = diff * toCurrencyRateToBase;

    if (diff > 0) {
      return GainLossResult(amount: diffInBase, type: GainLossType.gain);
    } else {
      return GainLossResult(amount: diffInBase.abs(), type: GainLossType.loss);
    }
  }

  /// Format a rate value for display.
  ///
  /// Whole numbers are shown without decimals (e.g. `140`).
  /// Fractional rates are shown with up to 4 decimal places, with
  /// trailing zeros stripped (e.g. `0.0071` not `0.007100`).
  static String formatRate(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value
        .toStringAsFixed(4)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  /// Format an amount value for display in a text field.
  ///
  /// Whole numbers are shown without decimals (e.g. `1000`).
  /// Fractional amounts are shown with up to 2 decimal places, with
  /// trailing zeros stripped.
  static String formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  /// Calculate the TO amount from FROM amount and exchange rate.
  ///
  /// Returns 0 if either input is 0 or unparseable.
  static double calculateToAmount(double fromAmount, double rate) {
    return fromAmount * rate;
  }
}

/// Type of gain/loss result from an exchange.
enum GainLossType { gain, loss, none }

/// Immutable result of a gain/loss calculation.
@immutable
class GainLossResult {
  final double amount;
  final GainLossType type;

  const GainLossResult({required this.amount, required this.type});

  bool get isGain => type == GainLossType.gain;
  bool get isLoss => type == GainLossType.loss;
  bool get isNone => type == GainLossType.none;

  @override
  String toString() => 'GainLossResult(amount: $amount, type: $type)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GainLossResult &&
          runtimeType == other.runtimeType &&
          amount == other.amount &&
          type == other.type;

  @override
  int get hashCode => amount.hashCode ^ type.hashCode;
}
