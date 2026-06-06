import 'package:flutter_test/flutter_test.dart';
import 'package:visual_ingredient_scanner/models/app_settings.dart';
import 'package:visual_ingredient_scanner/services/recipe_service.dart';

void main() {
  test('defaults to the configured Gemini model', () {
    expect(RecipeService(apiKey: 'key').modelName, kDefaultGeminiModel);
    expect(kDefaultGeminiModel, 'gemini-3.1-flash-lite');
  });

  group('buildPrompt', () {
    test('lists ingredients with rounded grams', () {
      final prompt = RecipeService.buildPrompt({
        'tomato': 199.6,
        'onion': 50.0,
      });
      expect(prompt, contains('- tomato: 200g'));
      expect(prompt, contains('- onion: 50g'));
      expect(prompt, contains('JSON array'));
    });
  });

  group('parseRecipes', () {
    test('parses a plain JSON array', () {
      const json =
          '[{"name":"Soup","ingredients_used":["tomato 200g"],'
          '"steps":["Boil"],"servings":2}]';
      final recipes = RecipeService.parseRecipes(json);
      expect(recipes, hasLength(1));
      expect(recipes.single.name, 'Soup');
      expect(recipes.single.servings, 2);
    });

    test('strips a ```json code fence', () {
      const fenced =
          '```json\n'
          '[{"name":"Salad","ingredients_used":[],"steps":[],"servings":1}]\n'
          '```';
      final recipes = RecipeService.parseRecipes(fenced);
      expect(recipes.single.name, 'Salad');
    });

    test('caps at 3 recipes', () {
      final json =
          '[${List.filled(5, '{"name":"R","ingredients_used":[],"steps":[],"servings":1}').join(',')}]';
      expect(RecipeService.parseRecipes(json), hasLength(3));
    });

    test('returns empty on malformed or non-array output', () {
      expect(RecipeService.parseRecipes('not json'), isEmpty);
      expect(RecipeService.parseRecipes('{"name":"x"}'), isEmpty);
    });
  });

  group('generate', () {
    test('returns no recipes without an API key', () async {
      final service = RecipeService(apiKey: '');
      expect(await service.generate({'tomato': 200}), isEmpty);
    });

    test('returns no recipes with no ingredients', () async {
      final service = RecipeService(apiKey: 'key');
      expect(await service.generate(const {}), isEmpty);
    });
  });
}
