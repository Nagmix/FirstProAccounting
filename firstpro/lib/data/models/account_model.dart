enum AccountType { ASSET, LIABILITY, EQUITY, REVENUE, EXPENSE }

class Account {
  final int? id;
  final String nameAr;
  final String nameEn;
  final int? parentId;
  final String accountCode;
  final AccountType accountType;
  final double balance;
  final String currency;
  final bool isActive;
  final bool isSystem;
  final DateTime createdAt;
  final DateTime updatedAt;

  Account({
    this.id,
    required this.nameAr,
    required this.nameEn,
    this.parentId,
    required this.accountCode,
    this.accountType = AccountType.ASSET,
    this.balance = 0.0,
    this.currency = 'SAR',
    this.isActive = true,
    this.isSystem = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  String get _accountTypeString {
    switch (accountType) {
      case AccountType.ASSET:
        return 'ASSET';
      case AccountType.LIABILITY:
        return 'LIABILITY';
      case AccountType.EQUITY:
        return 'EQUITY';
      case AccountType.REVENUE:
        return 'REVENUE';
      case AccountType.EXPENSE:
        return 'EXPENSE';
    }
  }

  static AccountType _accountTypeFromString(String value) {
    switch (value) {
      case 'LIABILITY':
        return AccountType.LIABILITY;
      case 'EQUITY':
        return AccountType.EQUITY;
      case 'REVENUE':
        return AccountType.REVENUE;
      case 'EXPENSE':
        return AccountType.EXPENSE;
      case 'ASSET':
      default:
        return AccountType.ASSET;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name_ar': nameAr,
      'name_en': nameEn,
      'parent_id': parentId,
      'account_code': accountCode,
      'account_type': _accountTypeString,
      'balance': balance,
      'currency': currency,
      'is_active': isActive ? 1 : 0,
      'is_system': isSystem ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'],
      nameAr: map['name_ar'],
      nameEn: map['name_en'],
      parentId: map['parent_id'],
      accountCode: map['account_code'],
      accountType: _accountTypeFromString(map['account_type']),
      balance: (map['balance'] ?? 0.0).toDouble(),
      currency: map['currency'] ?? 'SAR',
      isActive: (map['is_active'] ?? 1) == 1,
      isSystem: (map['is_system'] ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Account copyWith({
    int? id,
    String? nameAr,
    String? nameEn,
    int? parentId,
    String? accountCode,
    AccountType? accountType,
    double? balance,
    String? currency,
    bool? isActive,
    bool? isSystem,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Account(
      id: id ?? this.id,
      nameAr: nameAr ?? this.nameAr,
      nameEn: nameEn ?? this.nameEn,
      parentId: parentId ?? this.parentId,
      accountCode: accountCode ?? this.accountCode,
      accountType: accountType ?? this.accountType,
      balance: balance ?? this.balance,
      currency: currency ?? this.currency,
      isActive: isActive ?? this.isActive,
      isSystem: isSystem ?? this.isSystem,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
