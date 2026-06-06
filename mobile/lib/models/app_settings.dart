import 'model_choice.dart';

/// Default confidence threshold — matches `conf_threshold` in
/// `pipeline/detect.py`.
const double kDefaultConfidence = 0.10;

/// Default Gemini recipe-generation model.
const String kDefaultGeminiModel = 'gemini-3.1-flash-lite';

String _geminiModelFromJson(Object? value) {
  final model = value is String ? value.trim() : '';
  return model.isEmpty ? kDefaultGeminiModel : model;
}

/// All user-controlled, persisted settings (S4 stores/restores this).
///
/// [detectorId]/[depthId] are nullable: a fresh install has no choice yet and
/// resolves to the registry defaults. Visualisation toggles default off (FR5).
class AppSettings {
  const AppSettings({
    this.detectorId,
    this.depthId,
    this.confidenceThreshold = kDefaultConfidence,
    this.densityOverrides = const {},
    this.showBoxes = false,
    this.showDepthMap = false,
    this.geminiModel = kDefaultGeminiModel,
    this.geminiApiKey = '',
  });

  final String? detectorId;
  final String? depthId;
  final double confidenceThreshold;

  /// class name → user-overridden density (kg/m³); merged over the bundled
  /// table by DensityService.
  final Map<String, double> densityOverrides;

  final bool showBoxes;
  final bool showDepthMap;

  /// Gemini model used for recipe generation.
  final String geminiModel;

  /// Per-user Gemini key. **Never serialised into the shared_preferences blob**
  /// — it is stored separately in flutter_secure_storage (Keychain/Keystore) by
  /// SettingsRepository, so no secret lands in plaintext prefs.
  final String geminiApiKey;

  static const AppSettings defaults = AppSettings();

  /// Resolved model selection, falling back to registry defaults when unset.
  ModelChoice modelChoice(String defaultDetectorId, String defaultDepthId) =>
      ModelChoice(
        detectorId: detectorId ?? defaultDetectorId,
        depthId: depthId ?? defaultDepthId,
      );

  AppSettings copyWith({
    String? detectorId,
    String? depthId,
    double? confidenceThreshold,
    Map<String, double>? densityOverrides,
    bool? showBoxes,
    bool? showDepthMap,
    String? geminiModel,
    String? geminiApiKey,
  }) => AppSettings(
    detectorId: detectorId ?? this.detectorId,
    depthId: depthId ?? this.depthId,
    confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
    densityOverrides: densityOverrides ?? this.densityOverrides,
    showBoxes: showBoxes ?? this.showBoxes,
    showDepthMap: showDepthMap ?? this.showDepthMap,
    geminiModel: geminiModel ?? this.geminiModel,
    geminiApiKey: geminiApiKey ?? this.geminiApiKey,
  );

  /// Excludes [geminiApiKey] by design — it is persisted in secure storage.
  Map<String, dynamic> toJson() => {
    'detectorId': detectorId,
    'depthId': depthId,
    'confidenceThreshold': confidenceThreshold,
    'densityOverrides': densityOverrides,
    'showBoxes': showBoxes,
    'showDepthMap': showDepthMap,
    'geminiModel': geminiModel,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    detectorId: json['detectorId'] as String?,
    depthId: json['depthId'] as String?,
    confidenceThreshold:
        (json['confidenceThreshold'] as num?)?.toDouble() ?? kDefaultConfidence,
    densityOverrides:
        (json['densityOverrides'] as Map?)?.map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ) ??
        const {},
    showBoxes: json['showBoxes'] as bool? ?? false,
    showDepthMap: json['showDepthMap'] as bool? ?? false,
    geminiModel: _geminiModelFromJson(json['geminiModel']),
  );
}
