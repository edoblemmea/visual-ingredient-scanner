import 'package:flutter_test/flutter_test.dart';
import 'package:visual_ingredient_scanner/services/asset_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registry exposes detectors and depth models with defaults', () async {
    final registry = await AssetCatalog.loadRegistry();

    expect(
      registry.detectors.map((d) => d.id),
      containsAll(['v26m_e20', 'v26m_e30', 'v26m_e40', 'v26m_best', 'v11s_old']),
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
    expect(depthAnything.externalData, isNotNull);
  });

  test('v11s detector carries its own 83-class labels file', () async {
    final registry = await AssetCatalog.loadRegistry();
    final v11s = registry.detectors.firstWhere((d) => d.id == 'v11s_old');
    expect(v11s.labelsAsset, 'assets/data/labels_v11s.txt');

    final labels = await AssetCatalog.loadDetectorLabels(v11s.labelsAsset!);
    expect(labels.length, 83);
    expect(labels.first, 'apple');

    final densities = await AssetCatalog.loadDensityTable();
    expect(labels.where((l) => !densities.containsKey(l)), isEmpty);
  });

  test('labels.txt loads exactly the expected class count', () async {
    final labels = await AssetCatalog.loadLabels();
    expect(labels.length, kExpectedClassCount);
    expect(labels.first, 'apple');
  });

  test('density table is a non-empty class to kg/m3 map', () async {
    final labels = await AssetCatalog.loadLabels();
    final densities = await AssetCatalog.loadDensityTable();
    final missing = labels.where((label) => !densities.containsKey(label));

    expect(densities, isNotEmpty);
    expect(densities['apple'], greaterThan(0));
    expect(missing, isEmpty);
  });
}
