import 'package:flutter_test/flutter_test.dart';
import 'package:visual_ingredient_scanner/services/asset_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registry exposes detectors and depth models with defaults', () async {
    final registry = await AssetCatalog.loadRegistry();

    expect(
      registry.detectors.map((d) => d.id),
      containsAll(['v26m_e30', 'v26m_e40', 'v26m_best']),
    );
    expect(
      registry.depth.map((d) => d.id),
      containsAll(['metric3d', 'depthanything']),
    );
    expect(registry.defaultDetector.id, 'v26m_e40');
    expect(registry.defaultDepth.id, 'metric3d');

    final depthAnything = registry.depth.firstWhere(
      (d) => d.id == 'depthanything',
    );
    expect(depthAnything.requiresManualDownload, isFalse);
    expect(depthAnything.externalData, isNotNull);
  });

  test('labels.txt loads exactly the expected class count', () async {
    final labels = await AssetCatalog.loadLabels();
    expect(labels.length, kExpectedClassCount);
    expect(labels.first, 'apple');
  });

  test('density table is a non-empty class to kg/m3 map', () async {
    final densities = await AssetCatalog.loadDensityTable();
    expect(densities, isNotEmpty);
    expect(densities['apple'], greaterThan(0));
  });
}
