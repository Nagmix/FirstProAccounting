/// Unit model for the comprehensive unit management system.
///
/// Each unit belongs to a type category (count, weight, liquid, packaging, pharmacy)
/// and has flags indicating whether it can be used for sales, purchases, as a base unit,
/// or as a packaging unit.
class Unit {
  final int? id;
  final String nameAr;
  final String nameEn;
  final String abbreviation;
  final String unitType; // 'count', 'weight', 'liquid', 'packaging', 'pharmacy'
  final String? description;
  final bool isActive;
  final bool isSellable;
  final bool isPurchasable;
  final bool isPackaging;
  final bool isBaseUnit;
  final int displayOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Unit({
    this.id,
    required this.nameAr,
    this.nameEn = '',
    this.abbreviation = '',
    this.unitType = 'count',
    this.description,
    this.isActive = true,
    this.isSellable = true,
    this.isPurchasable = true,
    this.isPackaging = false,
    this.isBaseUnit = false,
    this.displayOrder = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Unit type display labels (Arabic)
  static const Map<String, String> unitTypeLabels = {
    'count': 'عد',
    'weight': 'وزن',
    'liquid': 'سوائل',
    'packaging': 'تغليف',
    'pharmacy': 'صيدلية',
  };

  /// Get display label for this unit's type
  String get unitTypeLabel => unitTypeLabels[unitType] ?? unitType;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name_ar': nameAr,
      'name_en': nameEn,
      'abbreviation': abbreviation,
      'unit_type': unitType,
      'description': description,
      'is_active': isActive ? 1 : 0,
      'is_sellable': isSellable ? 1 : 0,
      'is_purchasable': isPurchasable ? 1 : 0,
      'is_packaging': isPackaging ? 1 : 0,
      'is_base_unit': isBaseUnit ? 1 : 0,
      'display_order': displayOrder,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Unit.fromMap(Map<String, dynamic> map) {
    return Unit(
      id: map['id'],
      nameAr: map['name_ar'] ?? '',
      nameEn: map['name_en'] ?? '',
      abbreviation: map['abbreviation'] ?? '',
      unitType: map['unit_type'] ?? 'count',
      description: map['description'],
      isActive: (map['is_active'] ?? 1) == 1,
      isSellable: (map['is_sellable'] ?? 1) == 1,
      isPurchasable: (map['is_purchasable'] ?? 1) == 1,
      isPackaging: (map['is_packaging'] ?? 0) == 1,
      isBaseUnit: (map['is_base_unit'] ?? 0) == 1,
      displayOrder: (map['display_order'] ?? 0) as int,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : DateTime.now(),
    );
  }

  Unit copyWith({
    int? id,
    String? nameAr,
    String? nameEn,
    String? abbreviation,
    String? unitType,
    String? description,
    bool? isActive,
    bool? isSellable,
    bool? isPurchasable,
    bool? isPackaging,
    bool? isBaseUnit,
    int? displayOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Unit(
      id: id ?? this.id,
      nameAr: nameAr ?? this.nameAr,
      nameEn: nameEn ?? this.nameEn,
      abbreviation: abbreviation ?? this.abbreviation,
      unitType: unitType ?? this.unitType,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      isSellable: isSellable ?? this.isSellable,
      isPurchasable: isPurchasable ?? this.isPurchasable,
      isPackaging: isPackaging ?? this.isPackaging,
      isBaseUnit: isBaseUnit ?? this.isBaseUnit,
      displayOrder: displayOrder ?? this.displayOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'Unit(id: $id, nameAr: $nameAr, type: $unitType)';
}
