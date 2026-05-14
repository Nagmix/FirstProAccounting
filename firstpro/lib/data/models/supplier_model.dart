class Supplier {
  final int? id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final double balance;
  final String currency;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Supplier({
    this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.balance = 0.0,
    this.currency = 'SAR',
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'balance': balance,
      'currency': currency,
      'notes': notes,
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
      balance: (map['balance'] ?? 0.0).toDouble(),
      currency: map['currency'] ?? 'SAR',
      notes: map['notes'],
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
    String? currency,
    String? notes,
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
      currency: currency ?? this.currency,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
