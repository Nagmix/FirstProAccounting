import '../../core/utils/money_helper.dart';

class CashBox {
  final int? id;
  final String name;
  final String type; // 'cash_box' or 'bank'
  final String? bankAccountNumber;
  final String? bankName;
  final String? bankBranch;
  final String currency;
  final double balance;
  final String balanceType; // 'debit' or 'credit'
  final int? linkedAccountId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  CashBox({
    this.id,
    required this.name,
    this.type = 'cash_box',
    this.bankAccountNumber,
    this.bankName,
    this.bankBranch,
    this.currency = 'YER',
    this.balance = 0.0,
    this.balanceType = 'credit',
    this.linkedAccountId,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  bool get isBank => type == 'bank';
  bool get isCashBox => type == 'cash_box';

  String get typeAr => isBank ? 'بنك' : 'صندوق';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'bank_account_number': bankAccountNumber,
      'bank_name': bankName,
      'bank_branch': bankBranch,
      'currency': currency,
      'balance': MoneyHelper.toCents(balance),
      'balance_type': balanceType,
      'linked_account_id': linkedAccountId,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory CashBox.fromMap(Map<String, dynamic> map) {
    return CashBox(
      id: map['id'],
      name: map['name'],
      type: map['type'] ?? 'cash_box',
      bankAccountNumber: map['bank_account_number'],
      bankName: map['bank_name'],
      bankBranch: map['bank_branch'],
      currency: map['currency'] ?? 'YER',
      balance: MoneyHelper.readMoney(map['balance']),
      balanceType: map['balance_type'] ?? 'credit',
      linkedAccountId: map['linked_account_id'],
      isActive: (map['is_active'] ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  CashBox copyWith({
    int? id, String? name, String? type, String? bankAccountNumber,
    String? bankName, String? bankBranch, String? currency, double? balance, String? balanceType,
    int? linkedAccountId, bool? isActive, DateTime? createdAt, DateTime? updatedAt,
  }) {
    return CashBox(
      id: id ?? this.id, name: name ?? this.name, type: type ?? this.type,
      bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
      bankName: bankName ?? this.bankName, bankBranch: bankBranch ?? this.bankBranch,
      currency: currency ?? this.currency, balance: balance ?? this.balance, balanceType: balanceType ?? this.balanceType,
      linkedAccountId: linkedAccountId ?? this.linkedAccountId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
