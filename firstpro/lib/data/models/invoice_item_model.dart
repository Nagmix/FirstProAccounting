class InvoiceItem {
  final int? id;
  final String invoiceId;
  final int productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double totalPrice;
  final String? notes;

  InvoiceItem({
    this.id,
    required this.invoiceId,
    required this.productId,
    required this.productName,
    this.quantity = 1.0,
    this.unitPrice = 0.0,
    this.totalPrice = 0.0,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'product_id': productId,
      'product_name': productName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'notes': notes,
    };
  }

  factory InvoiceItem.fromMap(Map<String, dynamic> map) {
    return InvoiceItem(
      id: map['id'],
      invoiceId: map['invoice_id'],
      productId: map['product_id'],
      productName: map['product_name'],
      quantity: (map['quantity'] ?? 1.0).toDouble(),
      unitPrice: (map['unit_price'] ?? 0.0).toDouble(),
      totalPrice: (map['total_price'] ?? 0.0).toDouble(),
      notes: map['notes'],
    );
  }

  InvoiceItem copyWith({
    int? id,
    String? invoiceId,
    int? productId,
    String? productName,
    double? quantity,
    double? unitPrice,
    double? totalPrice,
    String? notes,
  }) {
    return InvoiceItem(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalPrice: totalPrice ?? this.totalPrice,
      notes: notes ?? this.notes,
    );
  }
}
