// ═══════════════════════════════════════════════════════════════════════════════
//  POS DATA MODELS – Extracted from pos_screen.dart
// ═══════════════════════════════════════════════════════════════════════════════

/// Discount type for order-level discounts.
enum DiscountType { fixed, percentage }

/// Checkout phase enum – controls which overlay is shown.
/// Using a single enum guarantees only ONE phase is active at a time,
/// making it impossible for multiple dialogs to stack up.
enum CheckoutPhase {
  idle,        // Normal state – no overlay
  confirming,  // Showing confirmation overlay
  saving,      // Saving invoice (no overlay, brief processing)
  completed,   // Showing sale complete overlay
}

class CartItem {
  final int productId;
  final String name;
  final double unitPrice;
  final int quantity;
  final String unitName;           // e.g., 'كرتون' or 'قطعة'
  final double conversionFactor;   // 1.0 for base unit, 24.0 for carton
  final String? unitBarcode;       // barcode for this specific unit

  CartItem({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.unitName = 'قطعة',
    this.conversionFactor = 1.0,
    this.unitBarcode,
  });

  double get total => unitPrice * quantity;
  /// Equivalent quantity in base units (for stock deduction)
  double get baseQuantity => quantity * conversionFactor;

  CartItem copyWith({int? quantity}) {
    return CartItem(
      productId: productId,
      name: name,
      unitPrice: unitPrice,
      quantity: quantity ?? this.quantity,
      unitName: unitName,
      conversionFactor: conversionFactor,
      unitBarcode: unitBarcode,
    );
  }
}

class PaymentEntry {
  final String method;
  final double amount;
  final String? providerName;
  final String? referenceNumber;
  final String? imagePath;

  PaymentEntry({
    required this.method,
    required this.amount,
    this.providerName,
    this.referenceNumber,
    this.imagePath,
  });

  PaymentEntry copyWith({
    double? amount,
    String? providerName,
    String? referenceNumber,
    String? imagePath,
  }) {
    return PaymentEntry(
      method: method,
      amount: amount ?? this.amount,
      providerName: providerName ?? this.providerName,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      imagePath: imagePath ?? this.imagePath,
    );
  }
}

class HeldOrder {
  final List<CartItem> items;
  final String paymentMethod;
  final List<PaymentEntry> payments;
  final double discount;
  final DiscountType discountType;
  final int? customerId;
  final String customerName;
  final DateTime createdAt;
  final int? dbId; // Database row ID for persistence

  HeldOrder({
    required this.items,
    required this.paymentMethod,
    required this.payments,
    required this.discount,
    required this.discountType,
    required this.customerId,
    required this.customerName,
    required this.createdAt,
    this.dbId,
  });
}
