import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visual_ingredient_scanner/models/model_registry.dart';
import 'package:visual_ingredient_scanner/services/asset_catalog.dart';
import 'package:visual_ingredient_scanner/services/settings_repository.dart';
import 'package:visual_ingredient_scanner/state/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<SettingsProvider> makeProvider(ModelRegistry registry) async {
    final repo = await SettingsRepository.create();
    return SettingsProvider(
      repository: repo,
      registry: registry,
      initial: await repo.load(),
    );
  }

  test('a fresh provider resolves model choice to registry defaults', () async {
    final registry = await AssetCatalog.loadRegistry();
    final provider = await makeProvider(registry);

    expect(provider.modelChoice.detectorId, 'v26m_e40');
    expect(provider.modelChoice.depthId, 'metric3d');
    expect(provider.settings.showBoxes, isTrue);
    expect(provider.settings.showDepthMap, isFalse);
  });

  test(
    'changes persist across provider instances, key via secure storage (G3)',
    () async {
      final registry = await AssetCatalog.loadRegistry();

      final first = await makeProvider(registry);
      await first.setDetector('v26m_e40');
      await first.setDepth('depthanything');
      await first.setConfidenceThreshold(0.3);
      await first.setDensityOverride('tomato', 950);
      await first.setShowBoxes(true);
      await first.setGeminiModel('gemini-3.1-pro');
      await first.setGeminiApiKey('secret');

      // A new repository + provider reading the same backing stores.
      final second = await makeProvider(registry);

      expect(second.settings.detectorId, 'v26m_e40');
      expect(second.settings.depthId, 'depthanything');
      expect(second.settings.confidenceThreshold, 0.3);
      expect(second.settings.densityOverrides['tomato'], 950);
      expect(second.settings.showBoxes, isTrue);
      expect(second.settings.geminiModel, 'gemini-3.1-pro');
      expect(second.settings.geminiApiKey, 'secret'); // from secure storage
      expect(second.modelChoice.detectorId, 'v26m_e40');
    },
  );

  test('the API key is not written to the shared_preferences blob', () async {
    final registry = await AssetCatalog.loadRegistry();
    final provider = await makeProvider(registry);
    await provider.setGeminiApiKey('secret');

    final prefs = await SharedPreferences.getInstance();
    final blob = prefs.getString('app_settings_v1') ?? '';
    expect(blob.contains('secret'), isFalse);
  });

  test('blank Gemini model input resets to the default model', () async {
    final registry = await AssetCatalog.loadRegistry();
    final provider = await makeProvider(registry);

    await provider.setGeminiModel('gemini-3.1-pro');
    await provider.setGeminiModel('   ');

    expect(provider.settings.geminiModel, 'gemini-3.1-flash-lite');
  });

  test('clearing a density override reverts that class', () async {
    final registry = await AssetCatalog.loadRegistry();
    final provider = await makeProvider(registry);

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
    final provider = await makeProvider(registry);

    var notified = 0;
    provider.addListener(() => notified++);
    await provider.setShowDepthMap(true);

    expect(notified, 1);
  });
}
