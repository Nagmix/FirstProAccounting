import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/production/recipe_policy.dart';
import 'package:firstpro/data/models/product_model.dart';
import 'package:firstpro/data/models/recipe_line_model.dart';
import 'package:firstpro/data/models/recipe_model.dart';

void main() {
  group('RecipePolicy', () {
    final validRecipe = Recipe(
      outputProductId: 10,
      name: 'خبز أبيض',
      outputQuantity: 20,
    );

    test('accepts a linear recipe with stock components', () {
      expect(
        () => RecipePolicy.validateRecipe(
          recipe: validRecipe,
          lines: [
            RecipeLine(
              recipeId: validRecipe.id,
              componentProductId: 1,
              quantity: 5,
            ),
          ],
          productKinds: {
            10: ProductKind.stock,
            1: ProductKind.stock,
          },
        ),
        returnsNormally,
      );
    });

    test('rejects a non-stock output or component', () {
      expect(
        () => RecipePolicy.validateRecipe(
          recipe: validRecipe,
          lines: [
            RecipeLine(
              recipeId: validRecipe.id,
              componentProductId: 1,
              quantity: 1,
            ),
          ],
          productKinds: {
            10: ProductKind.service,
            1: ProductKind.stock,
          },
        ),
        throwsArgumentError,
      );

      expect(
        () => RecipePolicy.validateRecipe(
          recipe: validRecipe,
          lines: [
            RecipeLine(
              recipeId: validRecipe.id,
              componentProductId: 1,
              quantity: 1,
            ),
          ],
          productKinds: {
            10: ProductKind.stock,
            1: ProductKind.service,
          },
        ),
        throwsArgumentError,
      );
    });

    test('rejects non-positive quantities and output cycles', () {
      expect(
        () => RecipePolicy.validateRecipe(
          recipe: Recipe(
            outputProductId: 10,
            name: 'وصفة غير صحيحة',
            outputQuantity: 0,
          ),
          lines: const [],
          productKinds: const {
            10: ProductKind.stock,
          },
        ),
        throwsArgumentError,
      );

      expect(
        () => RecipePolicy.validateRecipe(
          recipe: validRecipe,
          lines: [
            RecipeLine(
              recipeId: validRecipe.id,
              componentProductId: 10,
              quantity: 1,
            ),
          ],
          productKinds: const {
            10: ProductKind.stock,
          },
        ),
        throwsStateError,
      );
    });
  });
}
