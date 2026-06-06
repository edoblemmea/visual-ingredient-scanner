import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../models/app_settings.dart' show kDefaultGeminiModel;
import '../models/recipe.dart';

/// Stage ⑤ — recipe generation. Pure Dart port of `pipeline/recipe.py`: one
/// Gemini call per scan, JSON array of 3 recipes, graceful degradation (returns
/// an empty list when there is no API key, no ingredients, or the call fails —
/// so a recipe outage never breaks the detection/weight results).
class RecipeService {
  RecipeService({required this.apiKey, this.modelName = kDefaultGeminiModel});

  final String apiKey;
  final String modelName;

  Future<List<Recipe>> generate(Map<String, double> ingredientWeights) async {
    if (apiKey.isEmpty || ingredientWeights.isEmpty) return const [];
    try {
      final model = GenerativeModel(
        model: modelName,
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
        ),
      );
      final response = await model.generateContent([
        Content.text(buildPrompt(ingredientWeights)),
      ]);
      final text = response.text;
      if (text == null) return const [];
      return parseRecipes(text);
    } catch (_) {
      return const []; // offline / quota / parse failure -> no recipes
    }
  }

  /// Builds the prompt, mirroring `_PROMPT_TEMPLATE` in recipe.py.
  static String buildPrompt(Map<String, double> ingredientWeights) {
    final lines = ingredientWeights.entries
        .map((e) => '- ${e.key}: ${e.value.round()}g')
        .join('\n');
    return 'You are a helpful recipe assistant. Given the following detected '
        'ingredients and their estimated weights, suggest exactly 3 ranked '
        'recipes that make good use of the available quantities. Adapt '
        'suggestions to the amounts. Return ONLY a JSON array with this '
        'structure, no explanation:\n'
        '[\n'
        '  {\n'
        '    "name": "Recipe name",\n'
        '    "ingredients_used": ["ingredient amount", ...],\n'
        '    "steps": ["Step 1", "Step 2", ...],\n'
        '    "servings": 2\n'
        '  }\n'
        ']\n\n'
        'Available ingredients:\n$lines';
  }

  /// Parses the model's response into at most 3 recipes. Strips a ```json code
  /// fence if present (as recipe.py does) and tolerates malformed output.
  static List<Recipe> parseRecipes(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      final lines = text.split('\n');
      text = lines.sublist(1, lines.length - 1).join('\n');
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Recipe.fromJson)
          .take(3)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
