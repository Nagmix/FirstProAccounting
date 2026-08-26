import 'tax_engine.dart';

class InvoiceTotals {
  const InvoiceTotals({
    required this.subtotalMinorUnits,
    required this.discountMinorUnits,
    required this.taxableMinorUnits,
    required this.taxMinorUnits,
    required this.transportMinorUnits,
    required this.totalMinorUnits,
  });

  final int subtotalMinorUnits;
  final int discountMinorUnits;
  final int taxableMinorUnits;
  final int taxMinorUnits;
  final int transportMinorUnits;
  final int totalMinorUnits;
}

/// Single source of truth for invoice totals.
///
/// Transport is intentionally added after VAT. Whether transport is taxable is
/// a jurisdiction/configuration rule and must be made explicit before changing
/// this behavior; it must not vary between the UI and posting layer.
class InvoiceTotalsEngine {
  const InvoiceTotalsEngine();

  InvoiceTotals calculate({
    required int subtotalMinorUnits,
    required int discountMinorUnits,
    required int transportMinorUnits,
    required int taxRateBasisPoints,
    required bool taxInclusive,
    bool transportTaxable = false,
  }) {
    if (subtotalMinorUnits >= 0 && discountMinorUnits < 0) {
      throw ArgumentError.value(
        discountMinorUnits,
        'discountMinorUnits',
        'cannot be negative for a positive invoice',
      );
    }
    if (subtotalMinorUnits >= 0 && discountMinorUnits > subtotalMinorUnits) {
      throw ArgumentError.value(
        discountMinorUnits,
        'discountMinorUnits',
        'cannot exceed the positive subtotal',
      );
    }

    final taxableSubtotalMinorUnits = subtotalMinorUnits - discountMinorUnits;
    final taxBaseMinorUnits = taxableSubtotalMinorUnits +
        (transportTaxable ? transportMinorUnits : 0);
    final tax = const TaxEngine().calculate(
      taxableMinorUnits: taxBaseMinorUnits,
      rateBasisPoints: taxRateBasisPoints,
      isInclusive: taxInclusive,
    );

    return InvoiceTotals(
      subtotalMinorUnits: subtotalMinorUnits,
      discountMinorUnits: discountMinorUnits,
      taxableMinorUnits: tax.netMinorUnits,
      taxMinorUnits: tax.taxMinorUnits,
      transportMinorUnits: transportMinorUnits,
      totalMinorUnits: tax.grossMinorUnits +
          (transportTaxable ? 0 : transportMinorUnits),
    );
  }
}
