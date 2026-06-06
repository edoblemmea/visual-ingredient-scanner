import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visual_ingredient_scanner/services/asset_catalog.dart';
import 'package:visual_ingredient_scanner/services/settings_repository.dart';
import 'package:visual_ingredient_scanner/state/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh provider resolves model choice to registry defaults', () async {
    final registry = await AssetCatalog.loadRegistry();
    final provider = SettingsProvider(
      repository: await SettingsRepository.create(),
      registry: registry,
    );

    expect(provider.modelChoice.detectorId, 'v26m_e30');
    expect(provider.modelChoice.depthId, 'metric3d');
  });

  test('changes persist across provider instances (G4)', () async {
    final registry = await AssetCatalog.loadRegistry();

    final first = SettingsProvider(
      repository: await SettingsRepository.create(),
      registry: registry,
    );
    await first.setDetector('v26m_e40');
    await first.setDepth('depthanything');
    await first.setConfidenceThreshold(0.3);
    await first.setDensityOverride('tomato', 950);
    await first.setShowBoxes(true);
    await first.setGeminiApiKey('secret');

    // A new repository + provider reading the same backing store.
    final second = SettingsProvider(
      repository: await SettingsRepository.create(),
      registry: registry,
    );

    expect(second.settings.detectorId, 'v26m_e40');
    expect(second.settings.depthId, 'depthanything');
    expect(second.settings.confidenceThreshold, 0.3);
    expect(second.settings.densityOverrides['tomato'], 950);
    expect(second.settings.showBoxes, isTrue);
    expect(second.settings.geminiApiKey, 'secret');
    expect(second.modelChoice.detectorId, 'v26m_e40');
  });

  test('clearing a density override reverts that class', () async {
    final registry = await AssetCatalog.loadRegistry();
    final provider = SettingsProvider(
      repository: await SettingsRepository.create(),
      registry: registry,
    );

    await provider.setDensityOverride('onion', 600);
    await provider.setDensityOverride('tomato', 950);
    await provider.clearDensityOverride('onion');

    expect(provider.settings.densityOverrides.containsKey('onion'), isFalse);
    expect(provider.settings.densityOverrides['tomato'], 950);

    await provider.clearAllDensityOverrides();
    expect(provider.settings.densityOverrides, isEmpty);
  });

  test('notifies listeners on change', () async {
    final registry = await AssetCatalog.loadRegistry();
    final provider = SettingsProvider(
      repository: await SettingsRepository.create(),
      registry: registry,
    );

    var notified = 0;
    provider.addListener(() => notified++);
    await provider.setShowDepthMap(true);

    expect(notified, 1);
  });
}
