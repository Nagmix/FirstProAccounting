import 'package:firstpro/core/utils/money_helper.dart';

class ServicePayment {
  final int? id;
  final String serviceOrderId;
  final String paymentMethod;
  final double amount;
  final String currencyCode;
  final double exchangeRate;
  final double amountBase;
  final int? cashBoxId;
  final String? referenceNumber;
  final bool isPosted;
  final int? journalId;
  final DateTime paymentDate;
  final DateTime? createdAt;

  ServicePayment({
    this.id,
    required this.serviceOrderId,
    this.paymentMethod = 'cash',
    required this.amount,
    this.currencyCode = 'YER',
    this.exchangeRate = 1.0,
    this.amountBase = 0.0,
    this.cashBoxId,
    this.referenceNumber,
    this.isPosted = false,
    this.journalId,
    required this.paymentDate,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'service_order_id': serviceOrderId,
      'payment_method': paymentMethod,
      'amount': amount,
      'currency_code': currencyCode,
      'exchange_rate': exchangeRate,
      'amount_base': amountBase,
      'cash_box_id': cashBoxId,
      'reference_number': referenceNumber,
      'is_posted': isPosted ? 1 : 0,
      'journal_id': journalId,
      'payment_date': paymentDate.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory ServicePayment.fromMap(Map<String, dynamic> map) {
    return ServicePayment(
      id: map['id'] as int?,
      serviceOrderId: map['service_order_id'] as String,
      paymentMethod: map['payment_method'] as String? ?? 'cash',
      amount: MoneyHelper.readMoney(map['amount']),
      currencyCode: map['currency_code'] as String? ?? 'YER',
      exchangeRate: (map['exchange_rate'] as num?)?.toDouble() ?? 1.0,
      amountBase: MoneyHelper.readMoney(map['amount_base']),
      cashBoxId: map['cash_box_id'] as int?,
      referenceNumber: map['reference_number'] as String?,
      isPosted: (map['is_posted'] ?? 0) == 1,
      journalId: map['journal_id'] as int?,
      paymentDate: DateTime.parse(map['payment_date'] as String),
      createdAt: map['created_at'] == null
          ? null
          : DateTime.parse(map['created_at'] as String),
    );
  }
}
