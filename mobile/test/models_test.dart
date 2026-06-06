import 'package:flutter_test/flutter_test.dart';
import 'package:visual_ingredient_scanner/models/models.dart';

WeightedItem _item(String name, double grams) => WeightedItem(
      detection: Detection(
        className: name,
        confidence: 0.9,
        bbox: const BBox(0, 0, 10, 10),
      ),
      shape: Shape.sphere,
      depthM: 0.5,
      realWidthM: 0.05,
      realHeightM: 0.05,
      volumeM3: 6.5e-5,
      densityKgM3: 800,
      weightG: grams,
    );

void main() {
  group('ScanResult.fromItems', () {
    test('sums grams per class like pipeline.py', () {
      final result = ScanResult.fromItems([
        _item('tomato', 120),
        _item('tomato', 80),
        _item('onion', 50),
      ]);

      expect(result.ingredientWeights['tomato'], 200);
      expect(result.ingredientWeights['onion'], 50);
      expect(result.items.length, 3);
    });

    test('empty result reports isEmpty', () {
      expect(ScanResult.empty.isEmpty, isTrue);
      expect(ScanResult.fromItems(const []).isEmpty, isTrue);
    });
  });

  group('Recipe JSON', () {
    test('parses Gemini snake_case and round-trips', () {
      final recipe = Recipe.fromJson(const {
        'name': 'Tomato soup',
        'ingredients_used': ['tomato 200g', 'onion 50g'],
        'steps': ['Chop', 'Simmer'],
        'servings': 2,
      });

      expect(recipe.name, 'Tomato soup');
      expect(recipe.ingredientsUsed, hasLength(2));
      expect(recipe.servings, 2);
      expect(Recipe.fromJson(recipe.toJson()).steps, recipe.steps);
    });

    test('tolerates missing fields', () {
      final recipe = Recipe.fromJson(const {});
      expect(recipe.ingredientsUsed, isEmpty);
      expect(recipe.servings, 0);
    });
  });

  group('AppSettings', () {
    test('round-trips through JSON including overrides', () {
      const settings = AppSettings(
        detectorId: 'v26m_e40',
        depthId: 'depthanything',
        confidenceThreshold: 0.25,
        densityOverrides: {'tomato': 950},
        showBoxes: true,
        geminiApiKey: 'secret',
      );

      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.detectorId, 'v26m_e40');
      expect(restored.confidenceThreshold, 0.25);
      expect(restored.densityOverrides['tomato'], 950);
      expect(restored.showBoxes, isTrue);
      expect(restored.showDepthMap, isFalse);
      expect(restored.geminiApiKey, 'secret');
    });

    test('resolves model choice to registry defaults when unset', () {
      final choice = AppSettings.defaults.modelChoice('v26m_e30', 'metric3d');
      expect(choice, const ModelChoice(detectorId: 'v26m_e30', depthId: 'metric3d'));
    });
  });
}
