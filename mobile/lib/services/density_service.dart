/// Last-resort density (kg/m³) for a class absent from the table — matches
/// `_DEFAULT_DENSITY` in `pipeline/density.py` and the 800 fallback in
/// `pipeline/weight.py`.
const double kDefaultDensity = 800.0;

/// Static density lookup (stage ③) — mirrors `pipeline/density.py`, extended
/// with the user override layer (FR3).
///
/// Immutable so it can be rebuilt per scan/recompute and sent across the scan
/// isolate. Resolution order: user override → bundled baseline → [kDefaultDensity].
class DensityService {
  const DensityService({required this.baseline, this.overrides = const {}});

  /// Bundled `food_densities.json` table (class → kg/m³).
  final Map<String, double> baseline;

  /// User edits applied on top of the baseline (FR3).
  final Map<String, double> overrides;

  double densityFor(String className) =>
      overrides[className] ?? baseline[className] ?? kDefaultDensity;

  /// Baseline value ignoring any override — used by the density editor to show
  /// and reset to the shipped default.
  double baselineFor(String className) =>
      baseline[className] ?? kDefaultDensity;

  bool isOverridden(String className) => overrides.containsKey(className);

  Map<String, double> densitiesFor(Iterable<String> classNames) => {
        for (final c in classNames) c: densityFor(c),
      };
}
