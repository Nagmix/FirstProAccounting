/// MoneyHelper — Fixed-point arithmetic for accounting precision.
///
/// All monetary values are stored in the database as INTEGER (cents/fils),
/// i.e. multiplied by [scaleFactor]. Dart models continue using `double`
/// for UI compatibility, and this helper converts at the data boundary.
///
/// Example:
///   - User sees: 150.75  (YER / USD / SAR)
///   - DB stores: 15075   (integer cents)
///   - toCents(150.75)  → 15075
///   - fromCents(15075) → 150.75
class MoneyHelper {
  MoneyHelper._();

  /// Scale factor: 100 means 2 decimal places (cents/fils).
  static const int scaleFactor = 100;

  /// Convert a human-readable double (e.g. 150.75) to integer cents (15075).
  ///
  /// Uses [round()] after scaling to avoid floating-point drift.
  /// This is safe for values up to ~9 × 10¹³ in the original currency,
  /// well beyond any practical accounting need.
  static int toCents(double value) {
    return (value * scaleFactor).round();
  }

  /// Convert integer cents (15075) back to a double (150.75).
  static double fromCents(int cents) {
    return cents / scaleFactor;
  }

  /// Safe read from a database map: handles both int (new) and double (legacy).
  ///
  /// After migration v34, all monetary columns are INTEGER, so [value] will
  /// be an `int`. During migration or for legacy databases, it may be `double`.
  /// This method handles both cases gracefully.
  static double readMoney(dynamic value, {double fallback = 0.0}) {
    if (value == null) return fallback;
    if (value is int) return fromCents(value);
    if (value is double) return value; // legacy REAL column
    if (value is num) {
      // num could be int or double at runtime
      if (value.toInt() == value) return fromCents(value.toInt());
      return value.toDouble();
    }
    return fallback;
  }

  /// Round a double to 2 decimal places — useful for intermediate calcs.
  static double round2(double value) {
    return (value * scaleFactor).roundToDouble() / scaleFactor;
  }

  /// Check if a monetary double is effectively zero.
  static bool isZero(double amount) {
    return toCents(amount) == 0;
  }

  /// Add two monetary doubles with fixed-point precision.
  static double add(double a, double b) {
    return fromCents(toCents(a) + toCents(b));
  }

  /// Subtract two monetary doubles with fixed-point precision.
  static double subtract(double a, double b) {
    return fromCents(toCents(a) - toCents(b));
  }

  /// Multiply a monetary double by a factor with fixed-point precision.
  static double multiply(double amount, double factor) {
    return fromCents((toCents(amount) * factor).round());
  }

  /// Divide a monetary double by a factor with fixed-point precision.
  static double divide(double amount, double factor) {
    if (factor == 0) return 0.0;
    return fromCents((toCents(amount) / factor).round());
  }

  /// Compare two monetary doubles. Returns:
  /// - negative if a < b
  /// - zero if a == b
  /// - positive if a > b
  static int compare(double a, double b) {
    return toCents(a).compareTo(toCents(b));
  }
}
