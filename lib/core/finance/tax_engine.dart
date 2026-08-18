enum TaxMode {
  exclusive,
  inclusive,
}

class TaxResult {
  const TaxResult({
    required this.netMinorUnits,
    required this.taxMinorUnits,
    required this.grossMinorUnits,
  });

  final int netMinorUnits;
  final int taxMinorUnits;
  final int grossMinorUnits;
}

/// Calculates tax at the minor-unit boundary.
///
/// [rateBasisPoints] stores a percentage with two decimal places: 15% is
/// 1500, 7.5% is 750. This avoids binary floating-point tax drift.
class TaxEngine {
  const TaxEngine();

  TaxResult calculate({
    required int taxableMinorUnits,
    required int rateBasisPoints,
    required bool isInclusive,
  }) {
    if (rateBasisPoints < 0 || rateBasisPoints > 100000) {
      throw ArgumentError.value(
        rateBasisPoints,
        'rateBasisPoints',
        'must be between 0% and 1000%',
      );
    }

    const denominator = 10000;
    if (isInclusive) {
      final net = _roundDivision(
        taxableMinorUnits * denominator,
        denominator + rateBasisPoints,
      );
      final tax = taxableMinorUnits - net;
      return TaxResult(
        netMinorUnits: net,
        taxMinorUnits: tax,
        grossMinorUnits: taxableMinorUnits,
      );
    }

    final tax = _roundDivision(
      taxableMinorUnits * rateBasisPoints,
      denominator,
    );
    return TaxResult(
      netMinorUnits: taxableMinorUnits,
      taxMinorUnits: tax,
      grossMinorUnits: taxableMinorUnits + tax,
    );
  }

  int _roundDivision(int numerator, int denominator) {
    final quotient = numerator ~/ denominator;
    final remainder = numerator.remainder(denominator).abs();
    if (remainder * 2 >= denominator) {
      return quotient + (numerator.isNegative ? -1 : 1);
    }
    return quotient;
  }
}
