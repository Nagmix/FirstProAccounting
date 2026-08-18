import 'package:firstpro/core/utils/money_helper.dart';

class ProductionOutput {
  final int? id;
  final String productionOrderId;
  final int productId;
  final double quantity;
  final int totalCost;
  final DateTime createdAt;

  ProductionOutput({
    this.id,
    required this.productionOrderId,
    required this.productId,
    required this.quantity,
    required this.totalCost,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => MoneyHelper.toCentsMap(
        {
          'id': id,
          'production_order_id': productionOrderId,
          'product_id': productId,
          'quantity': quantity,
          'total_cost': MoneyHelper.fromCents(totalCost),
          'created_at': createdAt.toIso8601String(),
        },
        const ['total_cost'],
      );

  factory ProductionOutput.fromMap(Map<String, dynamic> map) => ProductionOutput(
        id: (map['id'] as num?)?.toInt(),
        productionOrderId: map['production_order_id'] as String,
        productId: (map['product_id'] as num).toInt(),
        quantity: (map['quantity'] as num).toDouble(),
        totalCost: (map['total_cost'] as num? ?? 0).toInt(),
        createdAt: _date(map['created_at']) ?? DateTime.now(),
      );

  static DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.parse(value as String);
}
