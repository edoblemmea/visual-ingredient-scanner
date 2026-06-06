import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/model_registry.dart';

/// Number of food classes the detectors emit. Must match `labels.txt` and
/// `data/classes.yaml`; an out-of-step labels file would silently mislabel every
/// detection, so we fail loudly at load.
const int kExpectedClassCount = 86;

/// Loads the bundled model registry, class labels, and density table from
/// assets. Pure I/O — no model inference here.
class AssetCatalog {
  const AssetCatalog._();

  static Future<ModelRegistry> loadRegistry() async {
    final raw = await rootBundle.loadString('assets/model_registry.json');
    return ModelRegistry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  static Future<List<String>> loadLabels() async {
    final raw = await rootBundle.loadString('assets/data/labels.txt');
    final labels = const LineSplitter()
        .convert(raw)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList(growable: false);
    if (labels.length != kExpectedClassCount) {
      throw StateError(
        'labels.txt has ${labels.length} classes, expected $kExpectedClassCount',
      );
    }
    return labels;
  }

  static Future<Map<String, double>> loadDensityTable() async {
    final raw = await rootBundle.loadString('assets/data/food_densities.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }
}

/// Everything resolved from assets at startup, passed down to the app.
class AppCatalog {
  const AppCatalog({
    required this.registry,
    required this.labels,
    required this.densities,
  });

  final ModelRegistry registry;
  final List<String> labels;
  final Map<String, double> densities;

  static Future<AppCatalog> load() async {
    final registry = await AssetCatalog.loadRegistry();
    final labels = await AssetCatalog.loadLabels();
    final densities = await AssetCatalog.loadDensityTable();
    return AppCatalog(registry: registry, labels: labels, densities: densities);
  }
}
