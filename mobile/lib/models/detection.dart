import 'bbox.dart';

enum DetectionOrigin { model, smart, manual }

/// A single detected (or manually annotated) food item — mirrors the Python
/// `Detection` dataclass in `pipeline/detect.py`.
class Detection {
  const Detection({
    required this.className,
    required this.confidence,
    required this.bbox,
    this.classId,
    DetectionOrigin? origin,
    bool isManual = false,
    this.isRelabeled = false,
    this.source,
  }) : origin =
           origin ??
           (isManual ? DetectionOrigin.manual : DetectionOrigin.model);

  final String className;
  final double confidence;
  final BBox bbox;

  /// Index into the labels list, when known (null for manual annotations).
  final int? classId;

  final DetectionOrigin origin;

  /// True when a detector-produced box has had its class changed by the user.
  final bool isRelabeled;

  /// Original detector object this edited display copy came from.
  final Detection? source;

  /// True when the user added this box for an item the detector missed (FR7).
  bool get isManual => origin != DetectionOrigin.model;

  Detection copyWith({
    String? className,
    double? confidence,
    BBox? bbox,
    int? classId,
    bool clearClassId = false,
    bool? isManual,
    DetectionOrigin? origin,
    bool? isRelabeled,
    Detection? source,
  }) => Detection(
    className: className ?? this.className,
    confidence: confidence ?? this.confidence,
    bbox: bbox ?? this.bbox,
    classId: clearClassId ? null : classId ?? this.classId,
    origin:
        origin ??
        (isManual == null
            ? this.origin
            : isManual
            ? DetectionOrigin.manual
            : DetectionOrigin.model),
    isRelabeled: isRelabeled ?? this.isRelabeled,
    source: source ?? this.source,
  );
}
