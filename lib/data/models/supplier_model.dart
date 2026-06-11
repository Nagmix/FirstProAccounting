import 'package:firstpro/core/utils/money_helper.dart';

class Supplier {
  final int? id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final double balance;
  final String balanceType; // 'debit' (عليه) or 'credit' (له)
  final String currency;
  final String? notes;
  final double debtCeiling; // سقف المدينية
  final String? contactMethod; // 'whatsapp' or 'phone'
  final DateTime createdAt;
  final DateTime updatedAt;

  Supplier({
    this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.balance = 0.0,
    this.balanceType = 'credit',
    this.currency = 'YER',
    this.notes,
    this.debtCeiling = 0.0,
    this.contactMethod = 'whatsapp',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'balance': balance,
      'balance_type': balanceType,
      'currency': currency,
      'notes': notes,
      'debt_ceiling': debtCeiling,
      'contact_method': contactMethod,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: map['id'],
      name: map['name'],
      phone: map['phone'],
      email: map['email'],
      address: map['address'],
      balance: MoneyHelper.readMoney(map['balance']),
      balanceType: map['balance_type'] ?? 'credit',
      currency: map['currency'] ?? 'YER',
      notes: map['notes'],
      debtCeiling: MoneyHelper.readMoney(map['debt_ceiling']),
      contactMethod: map['contact_method'] ?? 'whatsapp',
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Supplier copyWith({
    int? id,
    String? name,
    String? phone,
    String? email,
    String? address,
    double? balance,
    String? balanceType,
    String? currency,
    String? notes,
    double? debtCeiling,
    String? contactMethod,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Supplier(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      balance: balance ?? this.balance,
      balanceType: balanceType ?? this.balanceType,
      currency: currency ?? this.currency,
      notes: notes ?? this.notes,
      debtCeiling: debtCeiling ?? this.debtCeiling,
      contactMethod: contactMethod ?? this.contactMethod,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Computes the dynamic balance direction label based on actual financial position.
  /// Returns 'له', 'عليه', or 'متساوي' based on the net position.
  static String getDynamicBalanceLabel(double netBalance, String balanceType) {
    if (netBalance.abs() < 0.005) return 'متساوي';
    if (netBalance > 0) {
      return balanceType == 'credit' ? 'له' : 'عليه';
    } else {
      // Negative net balance flips the direction
      return balanceType == 'credit' ? 'عليه' : 'له';
    }
  }
}
