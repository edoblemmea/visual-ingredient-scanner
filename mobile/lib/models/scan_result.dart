import 'recipe.dart';
import 'weighted_item.dart';

/// The end-to-end output of a scan — mirrors the dict returned by
/// `pipeline/pipeline.py`: per-item weights, per-class totals, and recipes.
///
/// The cached depth map + focal needed for the no-re-inference recompute path
/// (FR6/FR7, G6) are held by the scan controller (S9), not here, so this stays a
/// pure value object.
class ScanResult {
  const ScanResult({
    required this.items,
    required this.ingredientWeights,
    required this.recipes,
  });

  final List<WeightedItem> items;

  /// class name → total grams across all items of that class.
  final Map<String, double> ingredientWeights;

  final List<Recipe> recipes;

  bool get isEmpty => items.isEmpty;

  static const ScanResult empty = ScanResult(
    items: [],
    ingredientWeights: {},
    recipes: [],
  );

  /// Builds a result from weighted items, summing grams per class exactly as
  /// `pipeline.py` does. Recipes are attached later via [copyWith].
  factory ScanResult.fromItems(
    List<WeightedItem> items, {
    List<Recipe> recipes = const [],
  }) {
    final totals = <String, double>{};
    for (final item in items) {
      totals[item.className] = (totals[item.className] ?? 0) + item.weightG;
    }
    return ScanResult(
      items: items,
      ingredientWeights: totals,
      recipes: recipes,
    );
  }

  ScanResult copyWith({
    List<WeightedItem>? items,
    Map<String, double>? ingredientWeights,
    List<Recipe>? recipes,
  }) => ScanResult(
    items: items ?? this.items,
    ingredientWeights: ingredientWeights ?? this.ingredientWeights,
    recipes: recipes ?? this.recipes,
  );
}
