import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/recipe.dart';
import '../models/saved_recipe.dart';

class SavedRecipeRepository {
  SavedRecipeRepository(this._prefs);

  static const String _key = 'saved_recipes_v1';

  final SharedPreferences _prefs;

  static Future<SavedRecipeRepository> create() async =>
      SavedRecipeRepository(await SharedPreferences.getInstance());

  List<SavedRecipe> load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final recipes = decoded
          .whereType<Map>()
          .map((m) => SavedRecipe.fromJson(m.cast<String, dynamic>()))
          .where((r) => r.id.isNotEmpty)
          .toList();
      recipes.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return recipes;
    } catch (_) {
      return const [];
    }
  }

  Future<SavedRecipe> saveRecipe(
    Recipe recipe, {
    required Map<String, double> ingredientWeights,
  }) async {
    final now = DateTime.now();
    final saved = SavedRecipe(
      id: '${now.microsecondsSinceEpoch}_${recipe.name.hashCode}',
      recipe: recipe,
      savedAt: now,
      ingredientWeights: Map.unmodifiable(ingredientWeights),
    );
    final recipes = [saved, ...load()];
    await _saveAll(recipes);
    return saved;
  }

  Future<void> delete(String id) async {
    final recipes = load().where((r) => r.id != id).toList();
    await _saveAll(recipes);
  }

  Future<void> _saveAll(List<SavedRecipe> recipes) async {
    await _prefs.setString(
      _key,
      jsonEncode(recipes.map((r) => r.toJson()).toList()),
    );
  }
}
