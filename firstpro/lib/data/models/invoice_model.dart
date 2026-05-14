class Invoice {
  final String id; // UUID
  final String type; // sale, purchase, return
  final String paymentType; // cash, credit, partial, card
  final int? customerId;
  final int? supplierId;
  final double subtotal;
  final double discountRate;
  final double discountAmount;
  final double taxAmount;
  final double total;
  final double paidAmount;
  final double remaining;
  final String status; // paid, unpaid, pending
  final int? cashierId;
  final int? warehouseId;
  final String? notes;
  final DateTime createdAt;

  Invoice({
    required this.id,
    required this.type,
    this.paymentType = 'cash',
    this.customerId,
    this.supplierId,
    this.subtotal = 0.0,
    this.discountRate = 0.0,
    this.discountAmount = 0.0,
    this.taxAmount = 0.0,
    this.total = 0.0,
    this.paidAmount = 0.0,
    this.remaining = 0.0,
    this.status = 'pending',
    this.cashierId,
    this.warehouseId,
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'payment_type': paymentType,
      'customer_id': customerId,
      'supplier_id': supplierId,
      'subtotal': subtotal,
      'discount_rate': discountRate,
      'discount_amount': discountAmount,
      'tax_amount': taxAmount,
      'total': total,
      'paid_amount': paidAmount,
      'remaining': remaining,
      'status': status,
      'cashier_id': cashierId,
      'warehouse_id': warehouseId,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Invoice.fromMap(Map<String, dynamic> map) {
    return Invoice(
      id: map['id'],
      type: map['type'],
      paymentType: map['payment_type'] ?? 'cash',
      customerId: map['customer_id'],
      supplierId: map['supplier_id'],
      subtotal: (map['subtotal'] ?? 0.0).toDouble(),
      discountRate: (map['discount_rate'] ?? 0.0).toDouble(),
      discountAmount: (map['discount_amount'] ?? 0.0).toDouble(),
      taxAmount: (map['tax_amount'] ?? 0.0).toDouble(),
      total: (map['total'] ?? 0.0).toDouble(),
      paidAmount: (map['paid_amount'] ?? 0.0).toDouble(),
      remaining: (map['remaining'] ?? 0.0).toDouble(),
      status: map['status'] ?? 'pending',
      cashierId: map['cashier_id'],
      warehouseId: map['warehouse_id'],
      notes: map['notes'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  Invoice copyWith({
    String? id,
    String? type,
    String? paymentType,
    int? customerId,
    int? supplierId,
    double? subtotal,
    double? discountRate,
    double? discountAmount,
    double? taxAmount,
    double? total,
    double? paidAmount,
    double? remaining,
    String? status,
    int? cashierId,
    int? warehouseId,
    String? notes,
    DateTime? createdAt,
  }) {
    return Invoice(
      id: id ?? this.id,
      type: type ?? this.type,
      paymentType: paymentType ?? this.paymentType,
      customerId: customerId ?? this.customerId,
      supplierId: supplierId ?? this.supplierId,
      subtotal: subtotal ?? this.subtotal,
      discountRate: discountRate ?? this.discountRate,
      discountAmount: discountAmount ?? this.discountAmount,
      taxAmount: taxAmount ?? this.taxAmount,
      total: total ?? this.total,
      paidAmount: paidAmount ?? this.paidAmount,
      remaining: remaining ?? this.remaining,
      status: status ?? this.status,
      cashierId: cashierId ?? this.cashierId,
      warehouseId: warehouseId ?? this.warehouseId,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
