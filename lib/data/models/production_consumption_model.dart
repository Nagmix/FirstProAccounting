import 'package:firstpro/core/utils/money_helper.dart';

class ProductionConsumption {
  final int? id;
  final String productionOrderId;
  final int componentProductId;
  final double quantity;
  final int unitCost;
  final int totalCost;
  final DateTime createdAt;

  ProductionConsumption({
    this.id,
    required this.productionOrderId,
    required this.componentProductId,
    required this.quantity,
    required this.unitCost,
    required this.totalCost,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => MoneyHelper.toCentsMap(
        {
          'id': id,
          'production_order_id': productionOrderId,
          'component_product_id': componentProductId,
          'quantity': quantity,
          'unit_cost': MoneyHelper.fromCents(unitCost),
          'total_cost': MoneyHelper.fromCents(totalCost),
          'created_at': createdAt.toIso8601String(),
        },
        const ['unit_cost', 'total_cost'],
      );

  factory ProductionConsumption.fromMap(Map<String, dynamic> map) =>
      ProductionConsumption(
        id: (map['id'] as num?)?.toInt(),
        productionOrderId: map['production_order_id'] as String,
        componentProductId: (map['component_product_id'] as num).toInt(),
        quantity: (map['quantity'] as num).toDouble(),
        unitCost: (map['unit_cost'] as num? ?? 0).toInt(),
        totalCost: (map['total_cost'] as num? ?? 0).toInt(),
        createdAt: _date(map['created_at']) ?? DateTime.now(),
      );

  static DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.parse(value as String);
}
