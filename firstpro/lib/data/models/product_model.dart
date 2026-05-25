class Product {
  final int? id;
  final String? itemCode;
  final String nameAr;
  final String nameEn;
  final String? barcode;
  final int? categoryId;
  final int? unitId; // Kept for backward compat, maps to base_unit_id
  final int? baseUnitId; // The base unit (smallest) - all stock stored in this unit
  final int? purchaseUnitId; // Default purchase unit
  final int? saleUnitId; // Default sale unit
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
  final bool taxInclusive; // Is price tax-inclusive?
  final int? salesAccountId;
  final int? purchaseAccountId;
  final int? inventoryAccountId;
  final double currentStock;
  final double minStock;
  final int? warehouseId;
  final DateTime? expiryDate;
  final bool expiryTracking;
  final bool trackStock; // Whether to track inventory for this product
  final double weight;
  final String? notes;
  final bool includeInReports;
  final bool isActive;
  final bool hasVariants;
  final bool isSellable; // Can this product be sold?
  final bool isPurchasable; // Can this product be purchased?
  final bool allowNegative; // Allow selling below zero stock?
  final bool sellRetail; // Can be sold in retail (base unit)?
  final bool showInPos; // Show in POS screen?
  final String? imagePath;
  final String? supplierCode; // Supplier's code for this product
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
    this.baseUnitId,
    this.purchaseUnitId,
    this.saleUnitId,
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
    this.taxInclusive = false,
    this.salesAccountId,
    this.purchaseAccountId,
    this.inventoryAccountId,
    this.currentStock = 0.0,
    this.minStock = 0.0,
    this.warehouseId,
    this.expiryDate,
    this.expiryTracking = false,
    this.trackStock = true,
    this.weight = 0.0,
    this.notes,
    this.includeInReports = true,
    this.isActive = true,
    this.hasVariants = false,
    this.isSellable = true,
    this.isPurchasable = true,
    this.allowNegative = false,
    this.sellRetail = true,
    this.showInPos = true,
    this.imagePath,
    this.supplierCode,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// The effective base unit ID - uses baseUnitId if set, falls back to unitId
  int? get effectiveBaseUnitId => baseUnitId ?? unitId;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_code': itemCode,
      'name_ar': nameAr,
      'name_en': nameEn,
      'barcode': barcode,
      'category_id': categoryId,
      'unit_id': unitId,
      'base_unit_id': baseUnitId,
      'purchase_unit_id': purchaseUnitId,
      'sale_unit_id': saleUnitId,
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
      'tax_inclusive': taxInclusive ? 1 : 0,
      'sales_account_id': salesAccountId,
      'purchase_account_id': purchaseAccountId,
      'inventory_account_id': inventoryAccountId,
      'current_stock': currentStock,
      'min_stock': minStock,
      'warehouse_id': warehouseId,
      'expiry_date': expiryDate?.toIso8601String(),
      'expiry_tracking': expiryTracking ? 1 : 0,
      'track_stock': trackStock ? 1 : 0,
      'weight': weight,
      'notes': notes,
      'include_in_reports': includeInReports ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'has_variants': hasVariants ? 1 : 0,
      'is_sellable': isSellable ? 1 : 0,
      'is_purchasable': isPurchasable ? 1 : 0,
      'allow_negative': allowNegative ? 1 : 0,
      'sell_retail': sellRetail ? 1 : 0,
      'show_in_pos': showInPos ? 1 : 0,
      'image_path': imagePath,
      'supplier_code': supplierCode,
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
      baseUnitId: map['base_unit_id'],
      purchaseUnitId: map['purchase_unit_id'],
      saleUnitId: map['sale_unit_id'],
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
      taxInclusive: (map['tax_inclusive'] ?? 0) == 1,
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
      trackStock: (map['track_stock'] ?? 1) == 1,
      weight: (map['weight'] ?? 0.0).toDouble(),
      notes: map['notes'],
      includeInReports: (map['include_in_reports'] ?? 1) == 1,
      isActive: (map['is_active'] ?? 1) == 1,
      hasVariants: (map['has_variants'] ?? 0) == 1,
      isSellable: (map['is_sellable'] ?? 1) == 1,
      isPurchasable: (map['is_purchasable'] ?? 1) == 1,
      allowNegative: (map['allow_negative'] ?? 0) == 1,
      sellRetail: (map['sell_retail'] ?? 1) == 1,
      showInPos: (map['show_in_pos'] ?? 1) == 1,
      imagePath: map['image_path'],
      supplierCode: map['supplier_code'],
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
    int? baseUnitId,
    int? purchaseUnitId,
    int? saleUnitId,
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
    bool? taxInclusive,
    int? salesAccountId,
    int? purchaseAccountId,
    int? inventoryAccountId,
    double? currentStock,
    double? minStock,
    int? warehouseId,
    DateTime? expiryDate,
    bool? expiryTracking,
    bool? trackStock,
    double? weight,
    String? notes,
    bool? includeInReports,
    bool? isActive,
    bool? hasVariants,
    bool? isSellable,
    bool? isPurchasable,
    bool? allowNegative,
    bool? sellRetail,
    bool? showInPos,
    String? imagePath,
    String? supplierCode,
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
      baseUnitId: baseUnitId ?? this.baseUnitId,
      purchaseUnitId: purchaseUnitId ?? this.purchaseUnitId,
      saleUnitId: saleUnitId ?? this.saleUnitId,
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
      taxInclusive: taxInclusive ?? this.taxInclusive,
      salesAccountId: salesAccountId ?? this.salesAccountId,
      purchaseAccountId: purchaseAccountId ?? this.purchaseAccountId,
      inventoryAccountId: inventoryAccountId ?? this.inventoryAccountId,
      currentStock: currentStock ?? this.currentStock,
      minStock: minStock ?? this.minStock,
      warehouseId: warehouseId ?? this.warehouseId,
      expiryDate: expiryDate ?? this.expiryDate,
      expiryTracking: expiryTracking ?? this.expiryTracking,
      trackStock: trackStock ?? this.trackStock,
      weight: weight ?? this.weight,
      notes: notes ?? this.notes,
      includeInReports: includeInReports ?? this.includeInReports,
      isActive: isActive ?? this.isActive,
      hasVariants: hasVariants ?? this.hasVariants,
      isSellable: isSellable ?? this.isSellable,
      isPurchasable: isPurchasable ?? this.isPurchasable,
      allowNegative: allowNegative ?? this.allowNegative,
      sellRetail: sellRetail ?? this.sellRetail,
      showInPos: showInPos ?? this.showInPos,
      imagePath: imagePath ?? this.imagePath,
      supplierCode: supplierCode ?? this.supplierCode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
