import 'package:firstpro/core/utils/money_helper.dart';

enum CostingMethod { weightedAverage, fifo, lifo }

extension CostingMethodExt on CostingMethod {
  String get value {
    switch (this) {
      case CostingMethod.weightedAverage:
        return 'weighted_average';
      case CostingMethod.fifo:
        return 'fifo';
      case CostingMethod.lifo:
        return 'lifo';
    }
  }

  String get nameAr {
    switch (this) {
      case CostingMethod.weightedAverage:
        return 'متوسط مرجح';
      case CostingMethod.fifo:
        return 'المتقدم أولاً (FIFO)';
      case CostingMethod.lifo:
        return 'المتأخر أولاً (LIFO)';
    }
  }

  static CostingMethod fromValue(String v) {
    switch (v) {
      case 'fifo':
        return CostingMethod.fifo;
      case 'lifo':
        return CostingMethod.lifo;
      default:
        return CostingMethod.weightedAverage;
    }
  }
}

class InventoryCostLayer {
  final int? id;
  final int productId;
  final int? warehouseId;
  final double quantityOriginal;
  final double quantityRemaining;
  final double unitCost;
  final DateTime acquisitionDate;
  final String? referenceType;
  final String? referenceId;
  final bool isFullyConsumed;
  final DateTime createdAt;

  InventoryCostLayer({
    this.id,
    required this.productId,
    this.warehouseId,
    required this.quantityOriginal,
    required this.quantityRemaining,
    required this.unitCost,
    required this.acquisitionDate,
    this.referenceType,
    this.referenceId,
    this.isFullyConsumed = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get remainingValue => quantityRemaining * unitCost;

  Map<String, dynamic> toMap() => {
        'id': id,
        'product_id': productId,
        'warehouse_id': warehouseId,
        'quantity_original': quantityOriginal,
        'quantity_remaining': quantityRemaining,
        'unit_cost': MoneyHelper.toCents(unitCost),
        'acquisition_date': acquisitionDate.toIso8601String(),
        'reference_type': referenceType,
        'reference_id': referenceId,
        'is_fully_consumed': isFullyConsumed ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory InventoryCostLayer.fromMap(Map<String, dynamic> map) =>
      InventoryCostLayer(
        id: map['id'],
        productId: map['product_id'],
        warehouseId: map['warehouse_id'],
        quantityOriginal: (map['quantity_original'] ?? 0.0).toDouble(),
        quantityRemaining: (map['quantity_remaining'] ?? 0.0).toDouble(),
        unitCost: MoneyHelper.readMoney(map['unit_cost']),
        acquisitionDate: DateTime.parse(map['acquisition_date']),
        referenceType: map['reference_type'],
        referenceId: map['reference_id'],
        isFullyConsumed: (map['is_fully_consumed'] ?? 0) == 1,
        createdAt: DateTime.parse(map['created_at']),
      );
}

class MovementCostAllocation {
  final int? id;
  final int productId;
  final int costLayerId;
  final String? invoiceId;
  final double quantityUsed;
  final double unitCost;
  final double totalCost;
  final DateTime createdAt;

  MovementCostAllocation({
    this.id,
    required this.productId,
    required this.costLayerId,
    this.invoiceId,
    required this.quantityUsed,
    required this.unitCost,
    required this.totalCost,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'product_id': productId,
        'cost_layer_id': costLayerId,
        'invoice_id': invoiceId,
        'quantity_used': quantityUsed,
        'unit_cost': MoneyHelper.toCents(unitCost),
        'total_cost': MoneyHelper.toCents(totalCost),
        'created_at': createdAt.toIso8601String(),
      };

  factory MovementCostAllocation.fromMap(Map<String, dynamic> map) =>
      MovementCostAllocation(
        id: map['id'],
        productId: map['product_id'],
        costLayerId: map['cost_layer_id'],
        invoiceId: map['invoice_id'],
        quantityUsed: (map['quantity_used'] ?? 0.0).toDouble(),
        unitCost: MoneyHelper.readMoney(map['unit_cost']),
        totalCost: MoneyHelper.readMoney(map['total_cost']),
        createdAt: DateTime.parse(map['created_at']),
      );
}
