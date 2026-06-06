// Parsed view of `assets/model_registry.json` — the declarative list of
// selectable detector and depth models bundled with the app.

class DetectorModel {
  const DetectorModel({
    required this.id,
    required this.label,
    required this.asset,
    required this.inputSize,
    required this.isDefault,
  });

  final String id;
  final String label;
  final String asset;
  final int inputSize;
  final bool isDefault;

  factory DetectorModel.fromJson(Map<String, dynamic> json) => DetectorModel(
        id: json['id'] as String,
        label: json['label'] as String,
        asset: json['asset'] as String,
        inputSize: json['inputSize'] as int? ?? 640,
        isDefault: json['default'] as bool? ?? false,
      );
}

class DepthModel {
  const DepthModel({
    required this.id,
    required this.label,
    required this.asset,
    required this.family,
    required this.float16,
    required this.externalData,
    required this.requiresManualDownload,
    required this.isDefault,
  });

  final String id;
  final String label;
  final String asset;

  /// `metric3d` or `depthanything` — selects the pre/post-processing branch.
  final String family;

  /// True when the model has float16 I/O; DepthService feeds it via the
  /// runtime's native float16 conversion (`OrtValue.to(float16)`).
  final bool float16;

  /// ONNX external-data file this model needs alongside [asset], if any.
  final String? externalData;
  final bool requiresManualDownload;
  final bool isDefault;

  factory DepthModel.fromJson(Map<String, dynamic> json) => DepthModel(
        id: json['id'] as String,
        label: json['label'] as String,
        asset: json['asset'] as String,
        family: json['family'] as String,
        float16: json['precision'] == 'float16',
        externalData: json['externalData'] as String?,
        requiresManualDownload: json['requiresManualDownload'] as bool? ?? false,
        isDefault: json['default'] as bool? ?? false,
      );
}

class ModelRegistry {
  const ModelRegistry({required this.detectors, required this.depth});

  final List<DetectorModel> detectors;
  final List<DepthModel> depth;

  factory ModelRegistry.fromJson(Map<String, dynamic> json) => ModelRegistry(
        detectors: (json['detectors'] as List)
            .map((e) => DetectorModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        depth: (json['depth'] as List)
            .map((e) => DepthModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  DetectorModel get defaultDetector =>
      detectors.firstWhere((d) => d.isDefault, orElse: () => detectors.first);

  DepthModel get defaultDepth =>
      depth.firstWhere((d) => d.isDefault, orElse: () => depth.first);
}
