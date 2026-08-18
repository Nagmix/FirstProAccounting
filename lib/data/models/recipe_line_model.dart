class RecipeLine {
  final int? id;
  final int? recipeId;
  final int componentProductId;
  final double quantity;

  const RecipeLine({
    this.id,
    this.recipeId,
    required this.componentProductId,
    required this.quantity,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'recipe_id': recipeId,
        'component_product_id': componentProductId,
        'quantity': quantity,
      };

  factory RecipeLine.fromMap(Map<String, dynamic> map) => RecipeLine(
        id: map['id'] as int?,
        recipeId: map['recipe_id'] as int?,
        componentProductId: map['component_product_id'] as int,
        quantity: (map['quantity'] as num).toDouble(),
      );
}
