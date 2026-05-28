import '../../core/utils/money_helper.dart';

class InvoiceItem {
  final int? id;
  final String invoiceId;
  final int productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double totalPrice;
  final String? unitName; // Name of the unit used in this line (e.g., 'كرتون')
  final double conversionFactor; // How many base units = 1 of this unit (e.g., 24 for carton)
  final double baseQuantity; // quantity * conversionFactor (always in base unit for stock deduction)
  final String? notes;

  InvoiceItem({
    this.id,
    required this.invoiceId,
    required this.productId,
    required this.productName,
    this.quantity = 1.0,
    this.unitPrice = 0.0,
    this.totalPrice = 0.0,
    this.unitName,
    this.conversionFactor = 1.0,
    this.baseQuantity = 1.0,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'product_id': productId,
      'product_name': productName,
      'quantity': quantity,
      'unit_price': MoneyHelper.toCents(unitPrice),
      'total_price': MoneyHelper.toCents(totalPrice),
      'unit_name': unitName,
      'conversion_factor': conversionFactor,
      'base_quantity': baseQuantity,
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
      unitPrice: MoneyHelper.readMoney(map['unit_price']),
      totalPrice: MoneyHelper.readMoney(map['total_price']),
      unitName: map['unit_name'],
      conversionFactor: (map['conversion_factor'] ?? 1.0).toDouble(),
      baseQuantity: (map['base_quantity'] ?? map['quantity'] ?? 1.0).toDouble(),
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
    String? unitName,
    double? conversionFactor,
    double? baseQuantity,
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
      unitName: unitName ?? this.unitName,
      conversionFactor: conversionFactor ?? this.conversionFactor,
      baseQuantity: baseQuantity ?? this.baseQuantity,
      notes: notes ?? this.notes,
    );
  }
}
