import 'recipe.dart';

class SavedRecipe {
  const SavedRecipe({
    required this.id,
    required this.recipe,
    required this.savedAt,
    required this.ingredientWeights,
  });

  final String id;
  final Recipe recipe;
  final DateTime savedAt;
  final Map<String, double> ingredientWeights;

  factory SavedRecipe.fromJson(Map<String, dynamic> json) => SavedRecipe(
    id: json['id'] as String? ?? '',
    recipe: Recipe.fromJson(
      (json['recipe'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    savedAt:
        DateTime.tryParse(json['saved_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    ingredientWeights:
        (json['ingredient_weights'] as Map?)?.map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ) ??
        const {},
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'recipe': recipe.toJson(),
    'saved_at': savedAt.toIso8601String(),
    'ingredient_weights': ingredientWeights,
  };
}
