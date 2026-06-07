import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visual_ingredient_scanner/models/recipe.dart';
import 'package:visual_ingredient_scanner/services/saved_recipe_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves, loads, and deletes recipes', () async {
    final repo = await SavedRecipeRepository.create();
    const recipe = Recipe(
      name: 'Tomato soup',
      ingredientsUsed: ['tomato 200g'],
      steps: ['Simmer'],
      servings: 2,
    );

    final saved = await repo.saveRecipe(
      recipe,
      ingredientWeights: const {'tomato': 200},
    );

    final loaded = repo.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.id, saved.id);
    expect(loaded.single.recipe.name, 'Tomato soup');
    expect(loaded.single.ingredientWeights['tomato'], 200);

    await repo.delete(saved.id);
    expect(repo.load(), isEmpty);
  });
}
