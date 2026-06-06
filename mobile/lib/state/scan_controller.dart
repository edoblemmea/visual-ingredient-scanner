import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/app_settings.dart';
import '../models/depth_map.dart';
import '../models/detection.dart';
import '../models/model_choice.dart';
import '../models/recipe.dart';
import '../models/scan_result.dart';
import '../services/asset_catalog.dart';
import '../services/density_service.dart';
import '../services/depth_service.dart';
import '../services/detector_service.dart';
import '../services/recipe_service.dart';
import '../services/weight_service.dart';

enum ScanStatus { idle, running, success, error }

/// Orchestrates a scan (detect → depth → density → weight) using the selected
/// models, and caches the detections + raw depth map + focal so corrections
/// (density edits, distance anchor, manual boxes) recompute weights **without
/// re-running the models** (G7).
///
/// Model inference runs off the UI thread via the services' `runAsync` (ORT
/// isolate). The weight recompute is pure Dart.
class ScanController extends ChangeNotifier {
  ScanController({required this.catalog});

  final AppCatalog catalog;

  ScanStatus status = ScanStatus.idle;
  String? error;
  ScanResult result = ScanResult.empty;

  // Cached scan state for the recompute path (G7).
  img.Image? _image;
  // Original encoded capture, for the debug overlay (S14).
  Uint8List? _imageBytes;
  DepthMap? _depthMap; // raw model depth, before any distance correction
  double _focalPx = 0;
  List<Detection> _detections = const [];
  AppSettings _settings = AppSettings.defaults;
  double _depthScale = 1.0; // distance-correction multiplier (S15)
  final List<Detection> _manualDetections = []; // S16

  img.Image? get image => _image;

  /// Original captured image bytes (jpeg/png) for display in the bbox overlay.
  Uint8List? get imageBytes => _imageBytes;

  bool get hasScan => _depthMap != null;
  double get depthScale => _depthScale;
  List<Detection> get manualDetections => List.unmodifiable(_manualDetections);

  /// The depth map as currently used for weights (raw × distance correction),
  /// for the depth-map debug view (S14).
  DepthMap? get depthMap => _depthMap == null
      ? null
      : (_depthScale == 1.0
            ? _depthMap
            : _rescaleDepth(_depthMap!, _depthScale));

  bool _recipesLoading = false;
  bool get recipesLoading => _recipesLoading;

  // Lazily-loaded inference services; rebuilt when the model selection changes.
  DetectorService? _detector;
  DepthService? _depth;
  ModelChoice? _loadedChoice;

  Future<void> scan(
    img.Image image, {
    required double focalPx,
    required AppSettings settings,
    Uint8List? imageBytes,
  }) async {
    status = ScanStatus.running;
    error = null;
    notifyListeners();
    try {
      await _ensureServices(settings);
      final detections = await _detector!.detect(
        image,
        confThreshold: settings.confidenceThreshold,
      );
      final depthMap = await _depth!.estimate(image, focalPx: focalPx);

      _image = image;
      _imageBytes = imageBytes;
      _focalPx = focalPx;
      _detections = detections;
      _depthMap = depthMap;
      _settings = settings;
      _depthScale = 1.0;
      _manualDetections.clear();

      _rebuild();
      status = ScanStatus.success;
    } catch (e) {
      error = e.toString();
      status = ScanStatus.error;
      notifyListeners();
      return;
    }
    notifyListeners(); // ingredients + weights ready; recipes load after
    await _generateRecipes();
  }

  /// Stage ⑤ — fetch recipes for the current ingredients (non-blocking for the
  /// weight display). Degrades silently to no recipes on any failure.
  Future<void> _generateRecipes() async {
    if (result.isEmpty) return;
    _recipesLoading = true;
    notifyListeners();
    final recipes = await RecipeService(
      apiKey: _settings.geminiApiKey,
      modelName: _settings.geminiModel,
    ).generate(result.ingredientWeights);
    result = result.copyWith(recipes: recipes);
    _recipesLoading = false;
    notifyListeners();
  }

  /// Re-runs recipe generation on demand (e.g. after corrections change weights).
  Future<void> regenerateRecipes() => _generateRecipes();

  Future<void> _ensureServices(AppSettings settings) async {
    final choice = settings.modelChoice(
      catalog.registry.defaultDetector.id,
      catalog.registry.defaultDepth.id,
    );
    if (choice == _loadedChoice && _detector != null && _depth != null) return;

    _detector?.dispose();
    _depth?.dispose();

    final det = catalog.registry.detectors.firstWhere(
      (d) => d.id == choice.detectorId,
    );
    final dep = catalog.registry.depth.firstWhere(
      (d) => d.id == choice.depthId,
    );

    _detector = await DetectorService.fromAsset(
      assetPath: det.asset,
      labels: catalog.labels,
      inputSize: det.inputSize,
    );
    _depth = await DepthService.fromAsset(
      assetPath: dep.asset,
      family: depthFamilyFromString(dep.family),
      float16: dep.float16,
      externalData: dep.externalData,
    );
    _loadedChoice = choice;
  }

  /// Re-applies the weight pipeline to the cached depth + detections under the
  /// current settings/correction state (G7). Used by S13/S15/S16.
  void recompute() {
    if (_depthMap == null) return;
    _rebuild();
    notifyListeners();
  }

  /// S13 — density edits: swap settings (overrides) and recompute weights live.
  void updateSettings(AppSettings settings) {
    _settings = settings;
    recompute();
  }

  /// S15 — distance correction: scale the cached depth so [item]'s sampled depth
  /// equals [realDistanceM], then recompute everything.
  void applyDistanceCorrection(WeightedReference item, double realDistanceM) {
    if (item.measuredDepthM <= 0) return;
    _depthScale = realDistanceM / item.measuredDepthM;
    recompute();
  }

  void resetDistanceCorrection() {
    _depthScale = 1.0;
    recompute();
  }

  /// S16 — add a user-drawn box for a missed item, then recompute.
  void addManualDetection(Detection detection) {
    _manualDetections.add(detection.copyWith(isManual: true));
    recompute();
  }

  void removeManualDetection(Detection detection) {
    _manualDetections.remove(detection);
    recompute();
  }

  void attachRecipes(List<Recipe> recipes) {
    result = result.copyWith(recipes: recipes);
    notifyListeners();
  }

  void _rebuild() {
    result = computeResult(
      detections: [..._detections, ..._manualDetections],
      depthMap: _depthMap!,
      focalPx: _focalPx,
      baselineDensities: catalog.densities,
      densityOverrides: _settings.densityOverrides,
      depthScale: _depthScale,
      recipes: result.recipes,
    );
  }

  @override
  void dispose() {
    _detector?.dispose();
    _depth?.dispose();
    super.dispose();
  }

  /// Pure recompute: depth scaling → density → weight → aggregation. Free of
  /// any model inference, so it is unit-testable and cheap to call repeatedly.
  static ScanResult computeResult({
    required List<Detection> detections,
    required DepthMap depthMap,
    required double focalPx,
    required Map<String, double> baselineDensities,
    Map<String, double> densityOverrides = const {},
    double depthScale = 1.0,
    List<Recipe> recipes = const [],
  }) {
    final depth = depthScale == 1.0
        ? depthMap
        : _rescaleDepth(depthMap, depthScale);
    final density = DensityService(
      baseline: baselineDensities,
      overrides: densityOverrides,
    );
    final items = WeightService(
      densityService: density,
    ).estimate(detections: detections, depthMap: depth, focalPx: focalPx);
    return ScanResult.fromItems(items, recipes: recipes);
  }

  static DepthMap _rescaleDepth(DepthMap source, double scale) {
    final scaled = Float32List(source.data.length);
    for (var i = 0; i < scaled.length; i++) {
      scaled[i] = source.data[i] * scale;
    }
    return DepthMap(width: source.width, height: source.height, data: scaled);
  }
}

/// Minimal reference to an item the user picked for distance correction (S15) —
/// just the measured depth, so the controller can compute the rescale factor.
class WeightedReference {
  const WeightedReference(this.measuredDepthM);
  final double measuredDepthM;
}
