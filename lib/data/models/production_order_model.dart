class ProductionOrder {
  final String id;
  final String orderNumber;
  final int recipeId;
  final int outputProductId;
  final double plannedQuantity;
  final double actualQuantity;
  final String status;
  final String currencyCode;
  final double exchangeRate;
  final int totalCost;
  final int wasteCost;
  final bool isPosted;
  final int? postedJournalId;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProductionOrder({
    required this.id,
    required this.orderNumber,
    required this.recipeId,
    required this.outputProductId,
    required this.plannedQuantity,
    this.actualQuantity = 0,
    this.status = 'draft',
    this.currencyCode = 'YER',
    this.exchangeRate = 1.0,
    this.totalCost = 0,
    this.wasteCost = 0,
    this.isPosted = false,
    this.postedJournalId,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'order_number': orderNumber,
        'recipe_id': recipeId,
        'output_product_id': outputProductId,
        'planned_quantity': plannedQuantity,
        'actual_quantity': actualQuantity,
        'status': status,
        'currency_code': currencyCode,
        'exchange_rate': exchangeRate,
        'total_cost': totalCost,
        'waste_cost': wasteCost,
        'is_posted': isPosted ? 1 : 0,
        'posted_journal_id': postedJournalId,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ProductionOrder.fromMap(Map<String, dynamic> map) => ProductionOrder(
        id: map['id'] as String,
        orderNumber: map['order_number'] as String,
        recipeId: (map['recipe_id'] as num).toInt(),
        outputProductId: (map['output_product_id'] as num).toInt(),
        plannedQuantity: (map['planned_quantity'] as num).toDouble(),
        actualQuantity: (map['actual_quantity'] as num? ?? 0).toDouble(),
        status: map['status'] as String? ?? 'draft',
        currencyCode: map['currency_code'] as String? ?? 'YER',
        exchangeRate: (map['exchange_rate'] as num? ?? 1.0).toDouble(),
        totalCost: (map['total_cost'] as num? ?? 0).toInt(),
        wasteCost: (map['waste_cost'] as num? ?? 0).toInt(),
        isPosted: (map['is_posted'] as num? ?? 0) == 1,
        postedJournalId: (map['posted_journal_id'] as num?)?.toInt(),
        notes: map['notes'] as String?,
        createdAt: _date(map['created_at']) ?? DateTime.now(),
        updatedAt: _date(map['updated_at']) ?? DateTime.now(),
      );

  static DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.parse(value as String);
}
