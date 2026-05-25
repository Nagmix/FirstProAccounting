class Product {
  final int? id;
  final String? itemCode;
  final String nameAr;
  final String nameEn;
  final String? barcode;
  final int? categoryId;
  final int? unitId;
  final int? supplierId;
  final String? groupId;
  final String? description;
  final double costPrice;
  final double averageCost; // Weighted average cost for accurate COGS
  final double sellPrice;
  final double wholesalePrice;
  final double specialWholesalePrice;
  final double minimumSalePrice;
  final double taxRate;
  final int? salesAccountId;
  final int? purchaseAccountId;
  final int? inventoryAccountId;
  final double currentStock;
  final double minStock;
  final int? warehouseId;
  final DateTime? expiryDate;
  final bool expiryTracking;
  final double weight;
  final String? notes;
  final bool includeInReports;
  final bool isActive;
  final bool hasVariants;
  final String? imagePath;
  final DateTime createdAt;
  final DateTime updatedAt;

  Product({
    this.id,
    this.itemCode,
    required this.nameAr,
    this.nameEn = '',
    this.barcode,
    this.categoryId,
    this.unitId,
    this.supplierId,
    this.groupId,
    this.description,
    this.costPrice = 0.0,
    this.averageCost = 0.0,
    this.sellPrice = 0.0,
    this.wholesalePrice = 0.0,
    this.specialWholesalePrice = 0.0,
    this.minimumSalePrice = 0.0,
    this.taxRate = 0.0,
    this.salesAccountId,
    this.purchaseAccountId,
    this.inventoryAccountId,
    this.currentStock = 0.0,
    this.minStock = 0.0,
    this.warehouseId,
    this.expiryDate,
    this.expiryTracking = false,
    this.weight = 0.0,
    this.notes,
    this.includeInReports = true,
    this.isActive = true,
    this.hasVariants = false,
    this.imagePath,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_code': itemCode,
      'name_ar': nameAr,
      'name_en': nameEn,
      'barcode': barcode,
      'category_id': categoryId,
      'unit_id': unitId,
      'supplier_id': supplierId,
      'group_id': groupId,
      'description': description,
      'cost_price': costPrice,
      'average_cost': averageCost,
      'sell_price': sellPrice,
      'wholesale_price': wholesalePrice,
      'special_wholesale_price': specialWholesalePrice,
      'minimum_sale_price': minimumSalePrice,
      'tax_rate': taxRate,
      'sales_account_id': salesAccountId,
      'purchase_account_id': purchaseAccountId,
      'inventory_account_id': inventoryAccountId,
      'current_stock': currentStock,
      'min_stock': minStock,
      'warehouse_id': warehouseId,
      'expiry_date': expiryDate?.toIso8601String(),
      'expiry_tracking': expiryTracking ? 1 : 0,
      'weight': weight,
      'notes': notes,
      'include_in_reports': includeInReports ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'has_variants': hasVariants ? 1 : 0,
      'image_path': imagePath,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      itemCode: map['item_code'],
      nameAr: map['name_ar'] ?? '',
      nameEn: map['name_en'] ?? '',
      barcode: map['barcode'],
      categoryId: map['category_id'],
      unitId: map['unit_id'],
      supplierId: map['supplier_id'],
      groupId: map['group_id'],
      description: map['description'],
      costPrice: (map['cost_price'] ?? 0.0).toDouble(),
      averageCost: (map['average_cost'] ?? map['cost_price'] ?? 0.0).toDouble(),
      sellPrice: (map['sell_price'] ?? 0.0).toDouble(),
      wholesalePrice: (map['wholesale_price'] ?? 0.0).toDouble(),
      specialWholesalePrice: (map['special_wholesale_price'] ?? 0.0).toDouble(),
      minimumSalePrice: (map['minimum_sale_price'] ?? 0.0).toDouble(),
      taxRate: (map['tax_rate'] ?? 0.0).toDouble(),
      salesAccountId: map['sales_account_id'],
      purchaseAccountId: map['purchase_account_id'],
      inventoryAccountId: map['inventory_account_id'],
      currentStock: (map['current_stock'] ?? 0.0).toDouble(),
      minStock: (map['min_stock'] ?? 0.0).toDouble(),
      warehouseId: map['warehouse_id'],
      expiryDate: map['expiry_date'] != null
          ? DateTime.parse(map['expiry_date'])
          : null,
      expiryTracking: (map['expiry_tracking'] ?? 0) == 1,
      weight: (map['weight'] ?? 0.0).toDouble(),
      notes: map['notes'],
      includeInReports: (map['include_in_reports'] ?? 1) == 1,
      isActive: (map['is_active'] ?? 1) == 1,
      hasVariants: (map['has_variants'] ?? 0) == 1,
      imagePath: map['image_path'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Product copyWith({
    int? id,
    String? itemCode,
    String? nameAr,
    String? nameEn,
    String? barcode,
    int? categoryId,
    int? unitId,
    int? supplierId,
    String? groupId,
    String? description,
    double? costPrice,
    double? averageCost,
    double? sellPrice,
    double? wholesalePrice,
    double? specialWholesalePrice,
    double? minimumSalePrice,
    double? taxRate,
    int? salesAccountId,
    int? purchaseAccountId,
    int? inventoryAccountId,
    double? currentStock,
    double? minStock,
    int? warehouseId,
    DateTime? expiryDate,
    bool? expiryTracking,
    double? weight,
    String? notes,
    bool? includeInReports,
    bool? isActive,
    bool? hasVariants,
    String? imagePath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      itemCode: itemCode ?? this.itemCode,
      nameAr: nameAr ?? this.nameAr,
      nameEn: nameEn ?? this.nameEn,
      barcode: barcode ?? this.barcode,
      categoryId: categoryId ?? this.categoryId,
      unitId: unitId ?? this.unitId,
      supplierId: supplierId ?? this.supplierId,
      groupId: groupId ?? this.groupId,
      description: description ?? this.description,
      costPrice: costPrice ?? this.costPrice,
      averageCost: averageCost ?? this.averageCost,
      sellPrice: sellPrice ?? this.sellPrice,
      wholesalePrice: wholesalePrice ?? this.wholesalePrice,
      specialWholesalePrice: specialWholesalePrice ?? this.specialWholesalePrice,
      minimumSalePrice: minimumSalePrice ?? this.minimumSalePrice,
      taxRate: taxRate ?? this.taxRate,
      salesAccountId: salesAccountId ?? this.salesAccountId,
      purchaseAccountId: purchaseAccountId ?? this.purchaseAccountId,
      inventoryAccountId: inventoryAccountId ?? this.inventoryAccountId,
      currentStock: currentStock ?? this.currentStock,
      minStock: minStock ?? this.minStock,
      warehouseId: warehouseId ?? this.warehouseId,
      expiryDate: expiryDate ?? this.expiryDate,
      expiryTracking: expiryTracking ?? this.expiryTracking,
      weight: weight ?? this.weight,
      notes: notes ?? this.notes,
      includeInReports: includeInReports ?? this.includeInReports,
      isActive: isActive ?? this.isActive,
      hasVariants: hasVariants ?? this.hasVariants,
      imagePath: imagePath ?? this.imagePath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
