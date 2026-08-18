import 'package:firstpro/core/utils/money_helper.dart';

class ServiceOrder {
  final String id;
  final String orderNumber;
  final int? customerId;
  final String status;
  final String priority;
  final DateTime receivedAt;
  final DateTime? promisedAt;
  final DateTime? completedAt;
  final DateTime? deliveredAt;
  final String currencyCode;
  final double exchangeRate;
  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double transportCharges;
  final double total;
  final double paidAmount;
  final double remaining;
  final bool isPosted;
  final int? postedJournalId;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  ServiceOrder({
    required this.id,
    required this.orderNumber,
    this.customerId,
    this.status = 'draft',
    this.priority = 'normal',
    required this.receivedAt,
    this.promisedAt,
    this.completedAt,
    this.deliveredAt,
    this.currencyCode = 'YER',
    this.exchangeRate = 1.0,
    this.subtotal = 0.0,
    this.discountAmount = 0.0,
    this.taxAmount = 0.0,
    this.transportCharges = 0.0,
    this.total = 0.0,
    this.paidAmount = 0.0,
    this.remaining = 0.0,
    this.isPosted = false,
    this.postedJournalId,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order_number': orderNumber,
      'customer_id': customerId,
      'status': status,
      'priority': priority,
      'received_at': receivedAt.toIso8601String(),
      'promised_at': promisedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'currency_code': currencyCode,
      'exchange_rate': exchangeRate,
      'subtotal': subtotal,
      'discount_amount': discountAmount,
      'tax_amount': taxAmount,
      'transport_charges': transportCharges,
      'total': total,
      'paid_amount': paidAmount,
      'remaining': remaining,
      'is_posted': isPosted ? 1 : 0,
      'posted_journal_id': postedJournalId,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ServiceOrder.fromMap(Map<String, dynamic> map) {
    return ServiceOrder(
      id: map['id'] as String,
      orderNumber: map['order_number'] as String,
      customerId: map['customer_id'] as int?,
      status: map['status'] as String? ?? 'draft',
      priority: map['priority'] as String? ?? 'normal',
      receivedAt: DateTime.parse(map['received_at'] as String),
      promisedAt: _parseDate(map['promised_at']),
      completedAt: _parseDate(map['completed_at']),
      deliveredAt: _parseDate(map['delivered_at']),
      currencyCode: map['currency_code'] as String? ?? 'YER',
      exchangeRate: (map['exchange_rate'] as num?)?.toDouble() ?? 1.0,
      subtotal: MoneyHelper.readMoney(map['subtotal']),
      discountAmount: MoneyHelper.readMoney(map['discount_amount']),
      taxAmount: MoneyHelper.readMoney(map['tax_amount']),
      transportCharges: MoneyHelper.readMoney(map['transport_charges']),
      total: MoneyHelper.readMoney(map['total']),
      paidAmount: MoneyHelper.readMoney(map['paid_amount']),
      remaining: MoneyHelper.readMoney(map['remaining']),
      isPosted: (map['is_posted'] ?? 0) == 1,
      postedJournalId: map['posted_journal_id'] as int?,
      notes: map['notes'] as String?,
      createdAt: _parseDate(map['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(map['updated_at']) ?? DateTime.now(),
    );
  }

  ServiceOrder copyWith({
    String? id,
    String? orderNumber,
    int? customerId,
    String? status,
    String? priority,
    DateTime? receivedAt,
    DateTime? promisedAt,
    DateTime? completedAt,
    DateTime? deliveredAt,
    String? currencyCode,
    double? exchangeRate,
    double? subtotal,
    double? discountAmount,
    double? taxAmount,
    double? transportCharges,
    double? total,
    double? paidAmount,
    double? remaining,
    bool? isPosted,
    int? postedJournalId,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ServiceOrder(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      customerId: customerId ?? this.customerId,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      receivedAt: receivedAt ?? this.receivedAt,
      promisedAt: promisedAt ?? this.promisedAt,
      completedAt: completedAt ?? this.completedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      currencyCode: currencyCode ?? this.currencyCode,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      subtotal: subtotal ?? this.subtotal,
      discountAmount: discountAmount ?? this.discountAmount,
      taxAmount: taxAmount ?? this.taxAmount,
      transportCharges: transportCharges ?? this.transportCharges,
      total: total ?? this.total,
      paidAmount: paidAmount ?? this.paidAmount,
      remaining: remaining ?? this.remaining,
      isPosted: isPosted ?? this.isPosted,
      postedJournalId: postedJournalId ?? this.postedJournalId,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _parseDate(dynamic value) =>
      value == null ? null : DateTime.parse(value as String);
}
