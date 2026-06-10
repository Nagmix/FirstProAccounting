class Currency {
  final int? id;
  final String code;
  final String nameAr;
  final String nameEn;
  final String symbol;
  final double exchangeRate;
  final bool isDefault;
  final bool isActive;
  final int codeOffset;
  final DateTime createdAt;

  Currency({
    this.id,
    required this.code,
    required this.nameAr,
    required this.nameEn,
    required this.symbol,
    this.exchangeRate = 1.0,
    this.isDefault = false,
    this.isActive = true,
    this.codeOffset = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name_ar': nameAr,
      'name_en': nameEn,
      'symbol': symbol,
      'exchange_rate': exchangeRate,
      'is_default': isDefault ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'code_offset': codeOffset,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Currency.fromMap(Map<String, dynamic> map) {
    return Currency(
      id: map['id'],
      code: map['code'] ?? '',
      nameAr: map['name_ar'] ?? '',
      nameEn: map['name_en'] ?? '',
      symbol: map['symbol'] ?? '',
      exchangeRate: (map['exchange_rate'] ?? 1.0).toDouble(),
      isDefault: (map['is_default'] ?? 0) == 1,
      isActive: (map['is_active'] ?? 1) == 1,
      codeOffset: map['code_offset'] ?? 0,
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  Currency copyWith({
    int? id,
    String? code,
    String? nameAr,
    String? nameEn,
    String? symbol,
    double? exchangeRate,
    bool? isDefault,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Currency(
      id: id ?? this.id,
      code: code ?? this.code,
      nameAr: nameAr ?? this.nameAr,
      nameEn: nameEn ?? this.nameEn,
      symbol: symbol ?? this.symbol,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
