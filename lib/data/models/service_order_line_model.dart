import 'package:firstpro/core/utils/money_helper.dart';

class ServiceOrderLine {
  final int? id;
  final String serviceOrderId;
  final String lineType;
  final int? productId;
  final String description;
  final double quantity;
  final double unitPrice;
  final double unitCost;
  final double taxRate;
  final double taxAmount;
  final double lineTotal;
  final String currencyCode;
  final bool isPosted;
  final DateTime? createdAt;

  ServiceOrderLine({
    this.id,
    required this.serviceOrderId,
    required this.lineType,
    this.productId,
    required this.description,
    required this.quantity,
    this.unitPrice = 0.0,
    this.unitCost = 0.0,
    this.taxRate = 0.0,
    this.taxAmount = 0.0,
    this.lineTotal = 0.0,
    this.currencyCode = 'YER',
    this.isPosted = false,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'service_order_id': serviceOrderId,
      'line_type': lineType,
      'product_id': productId,
      'description': description,
      'quantity': quantity,
      'unit_price': unitPrice,
      'unit_cost': unitCost,
      'tax_rate': taxRate,
      'tax_amount': taxAmount,
      'line_total': lineTotal,
      'currency_code': currencyCode,
      'is_posted': isPosted ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory ServiceOrderLine.fromMap(Map<String, dynamic> map) {
    return ServiceOrderLine(
      id: map['id'] as int?,
      serviceOrderId: map['service_order_id'] as String,
      lineType: map['line_type'] as String,
      productId: map['product_id'] as int?,
      description: map['description'] as String,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      unitPrice: MoneyHelper.readMoney(map['unit_price']),
      unitCost: MoneyHelper.readMoney(map['unit_cost']),
      taxRate: (map['tax_rate'] as num?)?.toDouble() ?? 0.0,
      taxAmount: MoneyHelper.readMoney(map['tax_amount']),
      lineTotal: MoneyHelper.readMoney(map['line_total']),
      currencyCode: map['currency_code'] as String? ?? 'YER',
      isPosted: (map['is_posted'] ?? 0) == 1,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.parse(map['created_at'] as String),
    );
  }

  ServiceOrderLine copyWith({
    int? id,
    String? serviceOrderId,
    String? lineType,
    int? productId,
    String? description,
    double? quantity,
    double? unitPrice,
    double? unitCost,
    double? taxRate,
    double? taxAmount,
    double? lineTotal,
    String? currencyCode,
    bool? isPosted,
    DateTime? createdAt,
  }) {
    return ServiceOrderLine(
      id: id ?? this.id,
      serviceOrderId: serviceOrderId ?? this.serviceOrderId,
      lineType: lineType ?? this.lineType,
      productId: productId ?? this.productId,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      unitCost: unitCost ?? this.unitCost,
      taxRate: taxRate ?? this.taxRate,
      taxAmount: taxAmount ?? this.taxAmount,
      lineTotal: lineTotal ?? this.lineTotal,
      currencyCode: currencyCode ?? this.currencyCode,
      isPosted: isPosted ?? this.isPosted,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
