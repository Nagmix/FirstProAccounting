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

  /// Read a calculated SQL result that is always in cents.
  ///
  /// Use this for SQL-calculated values like `SUM(base_quantity * unit_cost)`
  /// or `current_stock * cost_price`. SQLite may return these as REAL (double)
  /// because one operand is REAL, but the value is still in cents.
  /// Unlike [readMoney] which treats doubles as "legacy" (already divided),
  /// this method ALWAYS divides by 100 regardless of type.
  ///
  /// Example: `SUM(base_quantity * unit_cost)` returns 67500.0 (REAL in cents)
  /// → readCalculatedMoney(67500.0) = 675.0 (correct)
  /// → readMoney(67500.0) = 67500.0 (WRONG - treats as legacy)
  static double readCalculatedMoney(dynamic value, {double fallback = 0.0}) {
    if (value == null) return fallback;
    if (value is int) return fromCents(value);
    if (value is double) return fromCents(value.round());
    if (value is num) return fromCents(value.round());
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

  /// Convert specified money fields in a map from human-readable doubles
  /// to integer cents for database storage.
  ///
  /// This is the central conversion point: screens work with doubles
  /// (e.g. 2000.00), but the DB stores integers (200000 cents).
  /// Call this before any `db.insert()` or `db.update()` on maps
  /// that come from the UI layer.
  ///
  /// Non-existent keys are silently skipped, so it's safe to pass
  /// a superset of field names.
  static Map<String, dynamic> toCentsMap(
    Map<String, dynamic> map,
    List<String> moneyFields,
  ) {
    final result = Map<String, dynamic>.from(map);
    for (final field in moneyFields) {
      final value = result[field];
      if (value is double) {
        result[field] = toCents(value);
      } else if (value is int) {
        // FIX: Convert int values to cents too.
        // Previously, ints were assumed to already be in cents, but this caused
        // a critical bug: when a UI form passes an integer-valued amount (e.g., 500
        // instead of 500.0), the value would be stored as 500 (human-readable)
        // instead of 50000 (cents). Then readMoney(500) would divide by 100 = 5.00,
        // making 500 riyals display as 5.00 riyals.
        // Since readMoney() always returns a double, legitimate cents-as-int values
        // should never appear in a UI-originated map.
        result[field] = toCents(value.toDouble());
      } else if (value is num && value.toDouble() != value.toInt()) {
        // num with decimal part — convert
        result[field] = toCents(value.toDouble());
      }
    }
    return result;
  }

  /// Common money field names for each table.
  /// Use these constants to avoid typos and keep field lists centralized.
  static const invoiceMoneyFields = [
    'subtotal', 'discount_amount', 'tax_amount', 'transport_charges',
    'total', 'paid_amount', 'remaining',
  ];

  static const invoiceItemMoneyFields = [
    'unit_price', 'total_price', 'unit_cost',
  ];

  static const productMoneyFields = [
    'sell_price', 'cost_price', 'average_cost',
    'wholesale_price', 'special_wholesale_price', 'minimum_sale_price',
  ];

  static const accountMoneyFields = [
    'balance', 'debt_ceiling',
  ];

  static const expenseMoneyFields = [
    'amount',
  ];

  // Note: 'opening_balance' removed (not a column in customers table).
  static const customerMoneyFields = [
    'balance', 'debt_ceiling',
  ];

  // Fix: 'opening_balance' removed (not a column in suppliers table).
  // Fix: 'debt_ceiling' added (it IS a money column stored in cents).
  static const supplierMoneyFields = [
    'balance', 'debt_ceiling',
  ];

  static const cashBoxMoneyFields = [
    'balance', 'opening_balance',
  ];

  // Fix #4: Include 'total_amount' — the vouchers table stores the amount
  // in a column named 'total_amount', not 'amount'. Without this, the
  // toCentsMap conversion would skip the field entirely, causing a ×100 error.
  static const voucherMoneyFields = [
    'total_amount', 'amount',
  ];

  static const shiftMoneyFields = [
    'opening_amount', 'total_sales', 'total_returns', 'total_discounts', 'closing_amount',
    'expected_amount', 'difference',
  ];

  static const transactionMoneyFields = [
    'debit', 'credit',
  ];

  static const stockMovementMoneyFields = [
    'unit_cost',
  ];

  static const currencyMoneyFields = [
    'exchange_rate',
  ];

  static const orderMoneyFields = [
    'subtotal', 'discount_amount', 'tax_amount', 'total', 'paid_amount', 'remaining',
  ];

  static const orderItemMoneyFields = [
    'unit_price', 'total_price',
  ];

  static const bankReconciliationMoneyFields = [
    'statement_balance', 'book_balance', 'deposits_in_transit',
    'outstanding_checks', 'bank_charges', 'interest_earned',
    'nsf_checks', 'other_adjustments', 'adjusted_bank_balance',
    'adjusted_book_balance', 'difference',
  ];

  static const bankStatementLineMoneyFields = [
    'amount',
  ];
}
