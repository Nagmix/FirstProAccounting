import 'package:firstpro/core/utils/money_helper.dart';

class Invoice {
  final String id;
  final String type;
  final String paymentMechanism; // 'cash' or 'credit'
  final String
      paymentMethod; // 'cash', 'check', 'transfer', 'bank', 'ewallet', 'bank_transfer'
  final bool isReturn;
  final int? cashBoxId;
  final int? customerId;
  final int? supplierId;
  final double subtotal;
  final double discountRate;
  final double discountAmount;
  final double taxAmount;
  final double total;
  final double paidAmount;
  final double remaining;
  final String status;
  final int? cashierId;
  final int? warehouseId;
  final String? notes;
  final String currency;
  final double exchangeRate;
  final double transportCharges;
  final String? ewalletProvider;
  final String? bankTransferProvider;
  final String? transferNumber;
  final String? attachmentPath;
  final int? shiftId;
  final String? cashierName;
  final bool isPosted;
  final String? originalInvoiceId;
  final DateTime createdAt;

  Invoice({
    required this.id,
    required this.type,
    this.paymentMechanism = 'cash',
    this.paymentMethod = 'cash',
    this.isReturn = false,
    this.cashBoxId,
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
    this.currency = 'YER',
    this.exchangeRate = 1.0,
    this.transportCharges = 0.0,
    this.ewalletProvider,
    this.bankTransferProvider,
    this.transferNumber,
    this.attachmentPath,
    this.shiftId,
    this.cashierName,
    this.isPosted = false,
    this.originalInvoiceId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get effectiveType {
    if (isReturn) {
      if (type == 'sale' || type == 'pos') return 'sale_return';
      if (type == 'purchase') return 'purchase_return';
    }
    return type;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'payment_mechanism': paymentMechanism,
      'payment_method': paymentMethod,
      'is_return': isReturn ? 1 : 0,
      'cash_box_id': cashBoxId,
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
      'currency': currency,
      'exchange_rate': exchangeRate,
      'transport_charges': transportCharges,
      'ewallet_provider': ewalletProvider,
      'bank_transfer_provider': bankTransferProvider,
      'transfer_number': transferNumber,
      'attachment_path': attachmentPath,
      'shift_id': shiftId,
      'cashier_name': cashierName,
      'is_posted': isPosted ? 1 : 0,
      'original_invoice_id': originalInvoiceId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Invoice.fromMap(Map<String, dynamic> map) {
    return Invoice(
      id: map['id'],
      type: map['type'],
      paymentMechanism: map['payment_mechanism'] ?? 'cash',
      paymentMethod: map['payment_method'] ?? 'cash',
      isReturn: (map['is_return'] ?? 0) == 1,
      cashBoxId: map['cash_box_id'],
      customerId: map['customer_id'],
      supplierId: map['supplier_id'],
      subtotal: MoneyHelper.readMoney(map['subtotal']),
      discountRate: (map['discount_rate'] ?? 0.0).toDouble(),
      discountAmount: MoneyHelper.readMoney(map['discount_amount']),
      taxAmount: MoneyHelper.readMoney(map['tax_amount']),
      total: MoneyHelper.readMoney(map['total']),
      paidAmount: MoneyHelper.readMoney(map['paid_amount']),
      remaining: MoneyHelper.readMoney(map['remaining']),
      status: map['status'] ?? 'pending',
      cashierId: map['cashier_id'],
      warehouseId: map['warehouse_id'],
      notes: map['notes'],
      currency: map['currency'] ?? 'YER',
      exchangeRate: (map['exchange_rate'] ?? 1.0).toDouble(),
      transportCharges: MoneyHelper.readMoney(map['transport_charges']),
      ewalletProvider: map['ewallet_provider'],
      bankTransferProvider: map['bank_transfer_provider'],
      transferNumber: map['transfer_number'],
      attachmentPath: map['attachment_path'],
      shiftId: map['shift_id'],
      cashierName: map['cashier_name'],
      isPosted: (map['is_posted'] ?? 0) == 1,
      originalInvoiceId: map['original_invoice_id'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  Invoice copyWith({
    String? id,
    String? type,
    String? paymentMechanism,
    String? paymentMethod,
    bool? isReturn,
    int? cashBoxId,
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
    String? currency,
    double? exchangeRate,
    double? transportCharges,
    String? ewalletProvider,
    String? bankTransferProvider,
    String? transferNumber,
    String? attachmentPath,
    int? shiftId,
    String? cashierName,
    bool? isPosted,
    String? originalInvoiceId,
    DateTime? createdAt,
  }) {
    return Invoice(
      id: id ?? this.id,
      type: type ?? this.type,
      paymentMechanism: paymentMechanism ?? this.paymentMechanism,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isReturn: isReturn ?? this.isReturn,
      cashBoxId: cashBoxId ?? this.cashBoxId,
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
      currency: currency ?? this.currency,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      transportCharges: transportCharges ?? this.transportCharges,
      ewalletProvider: ewalletProvider ?? this.ewalletProvider,
      bankTransferProvider: bankTransferProvider ?? this.bankTransferProvider,
      transferNumber: transferNumber ?? this.transferNumber,
      attachmentPath: attachmentPath ?? this.attachmentPath,
      shiftId: shiftId ?? this.shiftId,
      cashierName: cashierName ?? this.cashierName,
      isPosted: isPosted ?? this.isPosted,
      originalInvoiceId: originalInvoiceId ?? this.originalInvoiceId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
