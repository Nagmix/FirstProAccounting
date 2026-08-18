import 'package:firstpro/data/models/product_model.dart';
import 'package:firstpro/data/models/recipe_line_model.dart';
import 'package:firstpro/data/models/recipe_model.dart';

class RecipePolicy {
  const RecipePolicy._();

  static void validateRecipe({
    required Recipe recipe,
    required List<RecipeLine> lines,
    required Map<int, ProductKind> productKinds,
  }) {
    if (recipe.outputQuantity <= 0) {
      throw ArgumentError.value(
        recipe.outputQuantity,
        'outputQuantity',
        'Recipe output quantity must be positive',
      );
    }

    final outputKind = productKinds[recipe.outputProductId];
    if (outputKind == null || !outputKind.createsStockMovement) {
      throw ArgumentError('Recipe output must be a stock product');
    }

    if (lines.isEmpty) {
      throw ArgumentError('Recipe must contain at least one component');
    }

    final seenComponents = <int>{};
    for (final line in lines) {
      if (line.quantity <= 0) {
        throw ArgumentError.value(
          line.quantity,
          'quantity',
          'Recipe component quantity must be positive',
        );
      }
      if (line.componentProductId == recipe.outputProductId) {
        throw StateError('Recipe cannot consume its own output product');
      }
      if (!seenComponents.add(line.componentProductId)) {
        throw ArgumentError(
          'Recipe cannot contain duplicate component products',
        );
      }
      final componentKind = productKinds[line.componentProductId];
      if (componentKind == null || !componentKind.createsStockMovement) {
        throw ArgumentError('Recipe components must be stock products');
      }
    }
  }
}
