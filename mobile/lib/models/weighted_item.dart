import 'detection.dart';

/// Volume model used for an item — mirrors the shape heuristics in
/// `pipeline/weight.py` (sphere / cylinder / box).
enum Shape { sphere, cylinder, box }

/// A detection enriched with the depth/shape/density-derived weight — mirrors
/// the Python `WeightedDetection` dataclass in `pipeline/weight.py`.
class WeightedItem {
  const WeightedItem({
    required this.detection,
    required this.shape,
    required this.depthM,
    required this.realWidthM,
    required this.realHeightM,
    required this.volumeM3,
    required this.densityKgM3,
    required this.weightG,
  });

  final Detection detection;
  final Shape shape;
  final double depthM;
  final double realWidthM;
  final double realHeightM;
  final double volumeM3;
  final double densityKgM3;
  final double weightG;

  String get className => detection.className;
}
