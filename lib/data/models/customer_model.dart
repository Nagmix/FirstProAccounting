class Customer {
  final int? id;
  final String name;
  final String? phone;
  final String? address;
  final String? address2;
  final String? email;
  final String? contactMethod; // was notificationMethod
  final String? notes;
  final double balance;
  final String balanceType; // 'debit' or 'credit'
  final String currency;
  final double debtCeiling; // was creditLimit (سقف المدينية)
  final DateTime createdAt;
  final DateTime updatedAt;

  Customer({
    this.id,
    required this.name,
    this.phone,
    this.address,
    this.address2,
    this.email,
    this.contactMethod,
    this.notes,
    this.balance = 0.0,
    this.balanceType = 'credit',
    this.currency = 'YER',
    this.debtCeiling = 0.0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'address2': address2,
      'email': email,
      'contact_method': contactMethod,
      'notes': notes,
      'balance': balance,
      'balance_type': balanceType,
      'currency': currency,
      'debt_ceiling': debtCeiling,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'],
      name: map['name'],
      phone: map['phone'],
      address: map['address'],
      address2: map['address2'],
      email: map['email'],
      contactMethod: map['contact_method'] ?? map['notification_method'],
      notes: map['notes'],
      balance: (map['balance'] ?? 0.0).toDouble(),
      balanceType: map['balance_type'] ?? 'credit',
      currency: map['currency'] ?? 'YER',
      debtCeiling: (map['debt_ceiling'] ?? map['credit_limit'] ?? 0.0).toDouble(),
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Customer copyWith({
    int? id, String? name, String? phone, String? address, String? address2,
    String? email, String? contactMethod, String? notes,
    double? balance, String? balanceType, String? currency,
    double? debtCeiling, DateTime? createdAt, DateTime? updatedAt,
  }) {
    return Customer(
      id: id ?? this.id, name: name ?? this.name, phone: phone ?? this.phone,
      address: address ?? this.address, address2: address2 ?? this.address2,
      email: email ?? this.email,
      contactMethod: contactMethod ?? this.contactMethod,
      notes: notes ?? this.notes, balance: balance ?? this.balance,
      balanceType: balanceType ?? this.balanceType,
      currency: currency ?? this.currency,
      debtCeiling: debtCeiling ?? this.debtCeiling,
      createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
