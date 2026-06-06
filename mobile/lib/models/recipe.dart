/// One recipe suggestion — mirrors the JSON object returned by Gemini in
/// `pipeline/recipe.py` (snake_case keys preserved for round-tripping).
class Recipe {
  const Recipe({
    required this.name,
    required this.ingredientsUsed,
    required this.steps,
    required this.servings,
  });

  final String name;
  final List<String> ingredientsUsed;
  final List<String> steps;
  final int servings;

  factory Recipe.fromJson(Map<String, dynamic> json) => Recipe(
        name: json['name'] as String? ?? 'Untitled recipe',
        ingredientsUsed: _stringList(json['ingredients_used']),
        steps: _stringList(json['steps']),
        servings: (json['servings'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'ingredients_used': ingredientsUsed,
        'steps': steps,
        'servings': servings,
      };

  static List<String> _stringList(Object? raw) =>
      (raw as List?)?.map((e) => e.toString()).toList(growable: false) ??
      const [];
}
