class Recipe {
  final int? id;
  final int outputProductId;
  final String name;
  final double outputQuantity;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Recipe({
    this.id,
    required this.outputProductId,
    required this.name,
    required this.outputQuantity,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'output_product_id': outputProductId,
        'name': name,
        'output_quantity': outputQuantity,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Recipe.fromMap(Map<String, dynamic> map) => Recipe(
        id: map['id'] as int?,
        outputProductId: map['output_product_id'] as int,
        name: map['name'] as String,
        outputQuantity: (map['output_quantity'] as num).toDouble(),
        isActive: (map['is_active'] as num? ?? 1) == 1,
        createdAt: _date(map['created_at']) ?? DateTime.now(),
        updatedAt: _date(map['updated_at']) ?? DateTime.now(),
      );

  static DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.parse(value as String);
}
