import 'package:firstpro/core/utils/money_helper.dart';

class Expense {
  final int? id;
  final String title;
  final String? description;
  final double amount;
  final String currency;
  final double exchangeRate;
  final double amountBase;
  final String expenseDate;
  final String? category;
  final String paymentMethod;
  final int? cashBoxId;
  final int? accountId;
  final String? beneficiary;
  final String? referenceNumber;
  final String? notes;
  final bool isRecurring;
  final String? recurringPeriod;
  final String? attachmentPath;
  final String operationType; // 'قبض' or 'صرف'
  final int? expenseAccountId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Expense({
    this.id,
    required this.title,
    this.description,
    this.amount = 0.0,
    this.currency = 'YER',
    this.exchangeRate = 1.0,
    this.amountBase = 0.0,
    required this.expenseDate,
    this.category,
    this.paymentMethod = 'cash',
    this.cashBoxId,
    this.accountId,
    this.beneficiary,
    this.referenceNumber,
    this.notes,
    this.isRecurring = false,
    this.recurringPeriod,
    this.attachmentPath,
    this.operationType = 'صرف',
    this.expenseAccountId,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Static map of expense categories with Arabic names.
  static const Map<String, String> categoriesAr = {
    'rent': 'إيجار',
    'salary': 'رواتب',
    'utility': 'مرافق',
    'transport': 'نقل ومواصلات',
    'office': 'مستلزمات مكتبية',
    'maintenance': 'صيانة',
    'marketing': 'تسويق وإعلان',
    'insurance': 'تأمين',
    'tax': 'ضرائب',
    'other': 'أخرى',
  };

  /// Get Arabic name for a category code.
  static String getCategoryAr(String? code) {
    if (code == null) return 'أخرى';
    return categoriesAr[code] ?? code;
  }

  /// List of category entries (code, Arabic name).
  static List<MapEntry<String, String>> get categoryList =>
      categoriesAr.entries.toList();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'amount': MoneyHelper.toCents(amount),
      'currency': currency,
      'exchange_rate': exchangeRate,
      'amount_base': MoneyHelper.toCents(amountBase),
      'expense_date': expenseDate,
      'category': category,
      'payment_method': paymentMethod,
      'cash_box_id': cashBoxId,
      'account_id': accountId,
      'beneficiary': beneficiary,
      'reference_number': referenceNumber,
      'notes': notes,
      'is_recurring': isRecurring ? 1 : 0,
      'recurring_period': recurringPeriod,
      'attachment_path': attachmentPath,
      'operation_type': operationType,
      'expense_account_id': expenseAccountId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'],
      title: map['title'] ?? '',
      description: map['description'],
      amount: MoneyHelper.readMoney(map['amount']),
      currency: map['currency'] ?? 'YER',
      exchangeRate: (map['exchange_rate'] ?? 1.0).toDouble(),
      amountBase: MoneyHelper.readMoney(map['amount_base']),
      expenseDate: map['expense_date'] ?? DateTime.now().toIso8601String(),
      category: map['category'],
      paymentMethod: map['payment_method'] ?? 'cash',
      cashBoxId: map['cash_box_id'],
      accountId: map['account_id'],
      beneficiary: map['beneficiary'],
      referenceNumber: map['reference_number'],
      notes: map['notes'],
      isRecurring: (map['is_recurring'] ?? 0) == 1,
      recurringPeriod: map['recurring_period'],
      attachmentPath: map['attachment_path'],
      operationType: map['operation_type'] ?? 'صرف',
      expenseAccountId: map['expense_account_id'],
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : DateTime.now(),
    );
  }

  Expense copyWith({
    int? id,
    String? title,
    String? description,
    double? amount,
    String? currency,
    double? exchangeRate,
    double? amountBase,
    String? expenseDate,
    String? category,
    String? paymentMethod,
    int? cashBoxId,
    int? accountId,
    String? beneficiary,
    String? referenceNumber,
    String? notes,
    bool? isRecurring,
    String? recurringPeriod,
    String? attachmentPath,
    String? operationType,
    int? expenseAccountId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Expense(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      amountBase: amountBase ?? this.amountBase,
      expenseDate: expenseDate ?? this.expenseDate,
      category: category ?? this.category,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      cashBoxId: cashBoxId ?? this.cashBoxId,
      accountId: accountId ?? this.accountId,
      beneficiary: beneficiary ?? this.beneficiary,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      notes: notes ?? this.notes,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringPeriod: recurringPeriod ?? this.recurringPeriod,
      attachmentPath: attachmentPath ?? this.attachmentPath,
      operationType: operationType ?? this.operationType,
      expenseAccountId: expenseAccountId ?? this.expenseAccountId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
