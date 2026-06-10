import 'package:firstpro/core/constants/app_constants.dart';

/// Utility class for formatting currency values in Arabic context.
class CurrencyFormatter {
  CurrencyFormatter._();

  /// Formats [amount] with two decimal places and the given [symbol].
  static String format(double amount, {String symbol = AppConstants.currency}) {
    final formatted = _addCommas(amount.toStringAsFixed(2));
    return '$formatted $symbol';
  }

  /// Formats [amount] with the currency symbol (alias for format).
  static String formatWithSymbol(double amount,
      {String symbol = AppConstants.currency}) {
    return format(amount, symbol: symbol);
  }

  /// Formats [amount] without the currency symbol.
  static String formatValue(double amount) {
    return _addCommas(amount.toStringAsFixed(2));
  }

  /// Formats [amount] with a compact representation for dashboards.
  static String formatCompact(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    }
    if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(0);
  }

  /// Formats [amount] as a compact string with the currency symbol.
  static String formatCompactWithSymbol(
    double amount, {
    String symbol = AppConstants.currency,
  }) {
    return '${formatCompact(amount)} $symbol';
  }

  /// Parses a formatted currency string back to a double.
  static double parse(String value) {
    final cleaned = value
        .replaceAll(',', '')
        .replaceAll(AppConstants.currency, '')
        .replaceAll(AppConstants.currencyEn, '')
        .trim();
    return double.tryParse(cleaned) ?? 0.0;
  }

  /// Returns `true` if [amount] is effectively zero (within epsilon).
  static bool isZero(double amount, {double epsilon = 0.005}) {
    return amount.abs() < epsilon;
  }

  /// Returns a signed display string.
  static String formatSigned(
    double amount, {
    String symbol = AppConstants.currency,
  }) {
    final prefix = amount >= 0 ? '+' : '';
    return '$prefix${format(amount, symbol: symbol)}';
  }

  // ── Private helpers ────────────────────────────────────────────
  static String _addCommas(String value) {
    final parts = value.split('.');
    final integerPart = parts[0];
    final decimalPart = parts.length > 1 ? '.${parts[1]}' : '';

    final buffer = StringBuffer();
    final length = integerPart.length;
    for (var i = 0; i < length; i++) {
      if (i > 0 && (length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(integerPart[i]);
    }
    return '$buffer$decimalPart';
  }
}
