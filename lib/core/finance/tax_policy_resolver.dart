import 'package:firstpro/core/finance/invoice_totals_engine.dart';
import 'package:firstpro/data/datasources/repositories/tax_policy_repository.dart';
import 'package:firstpro/data/models/tax_profile_model.dart';

class TaxPolicyResolver {
  final TaxPolicyRepository _repository;
  final InvoiceTotalsEngine _totalsEngine;

  const TaxPolicyResolver(
    this._repository, {
    InvoiceTotalsEngine totalsEngine = const InvoiceTotalsEngine(),
  }) : _totalsEngine = totalsEngine;

  Future<TaxProfile?> resolveFor({
    required DateTime date,
    required String countryCode,
  }) {
    return _repository.resolveActive(countryCode: countryCode, date: date);
  }

  InvoiceTotals calculateTotals({
    required TaxProfile? profile,
    required int subtotalMinorUnits,
    required int discountMinorUnits,
    required int transportMinorUnits,
    required bool taxInclusive,
  }) {
    final effectiveInclusive = profile == null
        ? taxInclusive
        : profile.calculationMethod == 'inclusive';
    return _totalsEngine.calculate(
      subtotalMinorUnits: subtotalMinorUnits,
      discountMinorUnits: discountMinorUnits,
      transportMinorUnits: transportMinorUnits,
      taxRateBasisPoints: profile?.rateBasisPoints ?? 0,
      taxInclusive: effectiveInclusive,
      transportTaxable: profile?.transportTaxable ?? false,
    );
  }
}
