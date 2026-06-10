import '../../core/utils/money_helper.dart';

enum AccountType { ASSET, LIABILITY, EQUITY, COST, REVENUE, EXPENSE }

class Account {
  final int? id;
  final String nameAr;
  final String nameEn;
  final int? parentId;
  final String accountCode;
  final AccountType accountType;
  final double balance;
  final String currency;
  final int? linkedCashBoxId;
  final double debtCeiling;
  final String balanceType; // 'credit' or 'debit'
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
    this.currency = 'YER',
    this.linkedCashBoxId,
    this.isActive = true,
    this.debtCeiling = 0.0,
    this.balanceType = 'auto',  // Will be derived from accountType if 'auto'
    this.isSystem = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now() {
    // Auto-derive balanceType from accountType if not explicitly set
    // ASSET, COST, and EXPENSE accounts have debit nature; others have credit nature
  }

  /// Get the display symbol for this account's currency.
  /// Maps currency codes to their Arabic display symbols.
  /// This ensures balances are shown with the correct symbol
  /// (ر.س for SAR, $ for USD, ر.ي for YER) instead of always
  /// using the default YER symbol.
  String get currencySymbol {
    switch (currency) {
      case 'SAR': return 'ر.س';
      case 'USD': return r'$';
      case 'YER': default: return 'ر.ي';
    }
  }

  /// Get the effective balance type, deriving from accountType if set to 'auto'
  /// Accounting convention:
  /// - ASSET (أصول): debit nature (increase with debit)
  /// - COST (تكاليف): debit nature (increase with debit)
  /// - EXPENSE (مصاريف): debit nature (increase with debit)
  /// - LIABILITY (خصوم): credit nature (increase with credit)
  /// - EQUITY (حقوق ملكية): credit nature (increase with credit)
  /// - REVENUE (إيرادات): credit nature (increase with credit)
  String get effectiveBalanceType {
    if (balanceType != 'auto') return balanceType;
    return (accountType == AccountType.ASSET ||
            accountType == AccountType.COST ||
            accountType == AccountType.EXPENSE)
        ? 'debit'
        : 'credit'; // LIABILITY, EQUITY, REVENUE are credit-nature
  }

  String get _accountTypeString {
    switch (accountType) {
      case AccountType.ASSET: return 'ASSET';
      case AccountType.LIABILITY: return 'LIABILITY';
      case AccountType.EQUITY: return 'EQUITY';
      case AccountType.COST: return 'COST';
      case AccountType.REVENUE: return 'REVENUE';
      case AccountType.EXPENSE: return 'EXPENSE';
    }
  }

  static AccountType _accountTypeFromString(String value) {
    switch (value) {
      case 'LIABILITY': return AccountType.LIABILITY;
      case 'EQUITY': return AccountType.EQUITY;
      case 'COST': return AccountType.COST;
      case 'REVENUE': return AccountType.REVENUE;
      case 'EXPENSE': return AccountType.EXPENSE;
      case 'ASSET': default: return AccountType.ASSET;
    }
  }

  static String accountTypeAr(AccountType type) {
    switch (type) {
      case AccountType.ASSET: return 'الأصول';
      case AccountType.LIABILITY: return 'الخصوم';
      case AccountType.EQUITY: return 'حقوق الملكية';
      case AccountType.COST: return 'التكاليف';
      case AccountType.REVENUE: return 'الإيرادات';
      case AccountType.EXPENSE: return 'المصاريف';
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
      'balance': MoneyHelper.toCents(balance),
      'currency': currency,
      'linked_cash_box_id': linkedCashBoxId,
      'is_active': isActive ? 1 : 0,
      'debt_ceiling': MoneyHelper.toCents(debtCeiling),
      'balance_type': effectiveBalanceType,  // Always save derived value
      'is_system': isSystem ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'],
      nameAr: (map['name_ar'] ?? '') as String,
      nameEn: map['name_en'] ?? '',
      parentId: map['parent_id'],
      accountCode: (map['account_code'] ?? '') as String,
      accountType: _accountTypeFromString(map['account_type'] ?? 'ASSET'),
      balance: MoneyHelper.readMoney(map['balance']),
      currency: map['currency'] ?? 'YER',
      linkedCashBoxId: map['linked_cash_box_id'],
      isActive: (map['is_active'] ?? 1) == 1,
      debtCeiling: MoneyHelper.readMoney(map['debt_ceiling']),
      balanceType: map['balance_type'] ?? (
        (_accountTypeFromString(map['account_type'] ?? 'ASSET') == AccountType.LIABILITY ||
         _accountTypeFromString(map['account_type'] ?? 'ASSET') == AccountType.EQUITY ||
         _accountTypeFromString(map['account_type'] ?? 'ASSET') == AccountType.REVENUE) ? 'credit' : 'debit'
      ),
      isSystem: (map['is_system'] ?? 0) == 1,
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  Account copyWith({
    int? id, String? nameAr, String? nameEn, int? parentId, String? accountCode,
    AccountType? accountType, double? balance, String? currency, int? linkedCashBoxId,
    double? debtCeiling, String? balanceType,
    bool? isActive, bool? isSystem, DateTime? createdAt, DateTime? updatedAt,
  }) {
    return Account(
      id: id ?? this.id, nameAr: nameAr ?? this.nameAr, nameEn: nameEn ?? this.nameEn,
      parentId: parentId ?? this.parentId, accountCode: accountCode ?? this.accountCode,
      accountType: accountType ?? this.accountType, balance: balance ?? this.balance,
      currency: currency ?? this.currency, linkedCashBoxId: linkedCashBoxId ?? this.linkedCashBoxId,
      debtCeiling: debtCeiling ?? this.debtCeiling, balanceType: balanceType ?? this.balanceType,
      isActive: isActive ?? this.isActive, isSystem: isSystem ?? this.isSystem,
      createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
