// Parsed view of `assets/model_registry.json` — the declarative list of
// selectable detector and depth models bundled with the app.

class DetectorModel {
  const DetectorModel({
    required this.id,
    required this.label,
    required this.asset,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.inputSize,
    required this.labelsAsset,
    required this.isDefault,
  });

  final String id;
  final String label;
  final String asset;
  final String downloadUrl;
  final int sizeBytes;
  final int inputSize;

  /// Labels file for detectors whose class list differs from the shared
  /// `labels.txt` (e.g. the 83-class YOLO11s prototype). Null = shared list.
  final String? labelsAsset;
  final bool isDefault;

  String get filename => asset.split('/').last;

  factory DetectorModel.fromJson(Map<String, dynamic> json) => DetectorModel(
        id: json['id'] as String,
        label: json['label'] as String,
        asset: json['asset'] as String,
        downloadUrl: json['downloadUrl'] as String,
        sizeBytes: json['sizeBytes'] as int? ?? 0,
        inputSize: json['inputSize'] as int? ?? 640,
        labelsAsset: json['labelsAsset'] as String?,
        isDefault: json['default'] as bool? ?? false,
      );
}

class DepthModel {
  const DepthModel({
    required this.id,
    required this.label,
    required this.asset,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.family,
    required this.float16,
    required this.externalData,
    required this.externalDataUrl,
    required this.externalDataSizeBytes,
    required this.isDefault,
  });

  final String id;
  final String label;
  final String asset;
  final String downloadUrl;
  final int sizeBytes;

  /// metric3d or depthanything — selects the pre/post-processing branch.
  final String family;
  final bool float16;

  /// ONNX external-data sidecar asset path, if any.
  final String? externalData;
  final String? externalDataUrl;
  final int externalDataSizeBytes;
  final bool isDefault;

  String get filename => asset.split('/').last;
  String? get externalFilename => externalData?.split('/').last;

  /// Total download size in bytes (main file + external data if present).
  int get totalSizeBytes => sizeBytes + externalDataSizeBytes;

  factory DepthModel.fromJson(Map<String, dynamic> json) => DepthModel(
        id: json['id'] as String,
        label: json['label'] as String,
        asset: json['asset'] as String,
        downloadUrl: json['downloadUrl'] as String,
        sizeBytes: json['sizeBytes'] as int? ?? 0,
        family: json['family'] as String,
        float16: json['precision'] == 'float16',
        externalData: json['externalData'] as String?,
        externalDataUrl: json['externalDataUrl'] as String?,
        externalDataSizeBytes: json['externalDataSizeBytes'] as int? ?? 0,
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
