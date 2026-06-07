import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/model_choice.dart';
import '../models/model_registry.dart';
import '../services/settings_repository.dart';

/// Holds the live [AppSettings] and persists every change. Each mutator updates
/// in-memory state, notifies listeners immediately (responsive UI), then writes
/// through to [SettingsRepository] (G3). The registry supplies the defaults used
/// to resolve an unset model selection.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider({
    required SettingsRepository repository,
    required ModelRegistry registry,
    required AppSettings initial,
  }) : _repository = repository,
       _registry = registry,
       _settings = initial;

  final SettingsRepository _repository;
  final ModelRegistry _registry;
  AppSettings _settings;

  AppSettings get settings => _settings;

  /// Selected models, resolving null choices to the registry defaults (G4).
  ModelChoice get modelChoice => _settings.modelChoice(
    _registry.defaultDetector.id,
    _registry.defaultDepth.id,
  );

  Future<void> _update(AppSettings next) async {
    _settings = next;
    notifyListeners();
    await _repository.save(next);
  }

  Future<void> setDetector(String id) =>
      _update(_settings.copyWith(detectorId: id));

  Future<void> setDepth(String id) => _update(_settings.copyWith(depthId: id));

  Future<void> setConfidenceThreshold(double value) =>
      _update(_settings.copyWith(confidenceThreshold: value));

  Future<void> setShowBoxes(bool value) =>
      _update(_settings.copyWith(showBoxes: value));

  Future<void> setShowDepthMap(bool value) =>
      _update(_settings.copyWith(showDepthMap: value));

  Future<void> setGeminiModel(String value) {
    final trimmed = value.trim();
    return _update(
      _settings.copyWith(
        geminiModel: trimmed.isEmpty ? kDefaultGeminiModel : trimmed,
      ),
    );
  }

  Future<void> setGeminiApiKey(String value) =>
      _update(_settings.copyWith(geminiApiKey: value));

  Future<void> setDensityOverride(String className, double density) {
    final next = Map<String, double>.from(_settings.densityOverrides)
      ..[className] = density;
    return _update(_settings.copyWith(densityOverrides: next));
  }

  Future<void> clearDensityOverride(String className) {
    final next = Map<String, double>.from(_settings.densityOverrides)
      ..remove(className);
    return _update(_settings.copyWith(densityOverrides: next));
  }

  Future<void> clearAllDensityOverrides() =>
      _update(_settings.copyWith(densityOverrides: const {}));
}
