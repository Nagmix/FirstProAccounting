import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/models/service_order_line_model.dart';

class ServiceOrderTotalsResult {
  const ServiceOrderTotalsResult({
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.transportCharges,
    required this.total,
  });

  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double transportCharges;
  final double total;
}

class ServiceOrderTotals {
  ServiceOrderTotals._();

  static ServiceOrderTotalsResult calculate({
    required List<ServiceOrderLine> lines,
    required double discountAmount,
    required double transportCharges,
  }) {
    final subtotalMinorUnits = lines.fold<int>(
      0,
      (sum, line) => sum + MoneyHelper.toCents(line.lineTotal),
    );
    final taxMinorUnits = lines.fold<int>(
      0,
      (sum, line) => sum + MoneyHelper.toCents(line.taxAmount),
    );
    final discountMinorUnits = MoneyHelper.toCents(discountAmount);
    final transportMinorUnits = MoneyHelper.toCents(transportCharges);

    if (discountMinorUnits < 0) {
      throw ArgumentError.value(
        discountAmount,
        'discountAmount',
        'cannot be negative',
      );
    }
    if (discountMinorUnits > subtotalMinorUnits) {
      throw ArgumentError.value(
        discountAmount,
        'discountAmount',
        'cannot exceed the subtotal',
      );
    }
    if (transportMinorUnits < 0) {
      throw ArgumentError.value(
        transportCharges,
        'transportCharges',
        'cannot be negative',
      );
    }

    final totalMinorUnits = subtotalMinorUnits +
        taxMinorUnits -
        discountMinorUnits +
        transportMinorUnits;

    return ServiceOrderTotalsResult(
      subtotal: subtotalMinorUnits / 100,
      discountAmount: discountMinorUnits / 100,
      taxAmount: taxMinorUnits / 100,
      transportCharges: transportMinorUnits / 100,
      total: totalMinorUnits / 100,
    );
  }
}
