import 'bbox.dart';

/// A single detected (or manually annotated) food item — mirrors the Python
/// `Detection` dataclass in `pipeline/detect.py`.
class Detection {
  const Detection({
    required this.className,
    required this.confidence,
    required this.bbox,
    this.classId,
    this.isManual = false,
  });

  final String className;
  final double confidence;
  final BBox bbox;

  /// Index into the labels list, when known (null for manual annotations).
  final int? classId;

  /// True when the user drew this box for an item the detector missed (FR7).
  final bool isManual;

  Detection copyWith({
    String? className,
    double? confidence,
    BBox? bbox,
    int? classId,
    bool? isManual,
  }) =>
      Detection(
        className: className ?? this.className,
        confidence: confidence ?? this.confidence,
        bbox: bbox ?? this.bbox,
        classId: classId ?? this.classId,
        isManual: isManual ?? this.isManual,
      );
}
