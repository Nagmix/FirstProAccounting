class Product {
  final int? id;
  final String nameAr;
  final String nameEn;
  final String? barcode;
  final int? categoryId;
  final int? unitId;
  final double costPrice;
  final double sellPrice;
  final double wholesalePrice;
  final double currentStock;
  final double minStock;
  final double taxRate;
  final bool isActive;
  final bool expiryTracking;
  final bool hasVariants;
  final DateTime? expiryDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  Product({
    this.id,
    required this.nameAr,
    required this.nameEn,
    this.barcode,
    this.categoryId,
    this.unitId,
    this.costPrice = 0.0,
    this.sellPrice = 0.0,
    this.wholesalePrice = 0.0,
    this.currentStock = 0.0,
    this.minStock = 0.0,
    this.taxRate = 0.0,
    this.isActive = true,
    this.expiryTracking = false,
    this.hasVariants = false,
    this.expiryDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name_ar': nameAr,
      'name_en': nameEn,
      'barcode': barcode,
      'category_id': categoryId,
      'unit_id': unitId,
      'cost_price': costPrice,
      'sell_price': sellPrice,
      'wholesale_price': wholesalePrice,
      'current_stock': currentStock,
      'min_stock': minStock,
      'tax_rate': taxRate,
      'is_active': isActive ? 1 : 0,
      'expiry_tracking': expiryTracking ? 1 : 0,
      'has_variants': hasVariants ? 1 : 0,
      'expiry_date': expiryDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      nameAr: map['name_ar'],
      nameEn: map['name_en'],
      barcode: map['barcode'],
      categoryId: map['category_id'],
      unitId: map['unit_id'],
      costPrice: (map['cost_price'] ?? 0.0).toDouble(),
      sellPrice: (map['sell_price'] ?? 0.0).toDouble(),
      wholesalePrice: (map['wholesale_price'] ?? 0.0).toDouble(),
      currentStock: (map['current_stock'] ?? 0.0).toDouble(),
      minStock: (map['min_stock'] ?? 0.0).toDouble(),
      taxRate: (map['tax_rate'] ?? 0.0).toDouble(),
      isActive: (map['is_active'] ?? 1) == 1,
      expiryTracking: (map['expiry_tracking'] ?? 0) == 1,
      hasVariants: (map['has_variants'] ?? 0) == 1,
      expiryDate: map['expiry_date'] != null
          ? DateTime.parse(map['expiry_date'])
          : null,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Product copyWith({
    int? id,
    String? nameAr,
    String? nameEn,
    String? barcode,
    int? categoryId,
    int? unitId,
    double? costPrice,
    double? sellPrice,
    double? wholesalePrice,
    double? currentStock,
    double? minStock,
    double? taxRate,
    bool? isActive,
    bool? expiryTracking,
    bool? hasVariants,
    DateTime? expiryDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      nameAr: nameAr ?? this.nameAr,
      nameEn: nameEn ?? this.nameEn,
      barcode: barcode ?? this.barcode,
      categoryId: categoryId ?? this.categoryId,
      unitId: unitId ?? this.unitId,
      costPrice: costPrice ?? this.costPrice,
      sellPrice: sellPrice ?? this.sellPrice,
      wholesalePrice: wholesalePrice ?? this.wholesalePrice,
      currentStock: currentStock ?? this.currentStock,
      minStock: minStock ?? this.minStock,
      taxRate: taxRate ?? this.taxRate,
      isActive: isActive ?? this.isActive,
      expiryTracking: expiryTracking ?? this.expiryTracking,
      hasVariants: hasVariants ?? this.hasVariants,
      expiryDate: expiryDate ?? this.expiryDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
