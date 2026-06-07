import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/app_settings.dart';
import '../models/bbox.dart';
import '../models/depth_map.dart';
import '../models/detection.dart';
import '../models/model_choice.dart';
import '../models/scan_result.dart';
import '../services/asset_catalog.dart';
import '../services/density_service.dart';
import '../services/depth_service.dart';
import '../services/detector_service.dart';
import '../services/smart_box_service.dart';
import '../services/weight_service.dart';

enum ScanStatus { idle, running, success, error }

class ScanEditSnapshot {
  const ScanEditSnapshot({
    required this.manualDetections,
    required this.relabels,
    required this.removed,
  });

  final List<Detection> manualDetections;
  final Map<Detection, String> relabels;
  final Set<Detection> removed;
}

/// Orchestrates a scan (detect → depth → density → weight) using the selected
/// models, and caches the detections + raw depth map + focal so corrections
/// (density edits, distance anchor, manual boxes) recompute weights **without
/// re-running the models** (G6).
///
/// Model inference runs off the UI thread via the services' `runAsync` (ORT
/// isolate). The weight recompute is pure Dart.
class ScanController extends ChangeNotifier {
  ScanController({required this.catalog, required this.modelsDir});

  final AppCatalog catalog;
  final String modelsDir;

  ScanStatus status = ScanStatus.idle;
  String? error;
  ScanResult result = ScanResult.empty;
  Duration? scanDuration;
  String scanPhase = '';
  double scanProgress = 0.0;

  // Cached scan state for the recompute path (G6).
  img.Image? _image;
  // Original encoded capture, for the debug overlay (S14).
  Uint8List? _imageBytes;
  DepthMap? _depthMap; // raw model depth, before any distance correction
  double _focalPx = 0;
  List<Detection> _detections = const [];
  AppSettings _settings = AppSettings.defaults;
  double _depthScale = 1.0; // distance-correction multiplier (S15)
  final List<Detection> _manualDetections = []; // S16 — user-drawn boxes
  // S16 edits applied to detector detections during recompute, keyed by the
  // detector Detection instance: relabels (new class) and removals.
  final Map<Detection, String> _relabels = {};
  final Set<Detection> _removed = {};

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
    final stopwatch = Stopwatch()..start();
    status = ScanStatus.running;
    error = null;
    scanDuration = null;
    scanPhase = 'Loading models…';
    scanProgress = 0.1;
    notifyListeners();
    try {
      await _ensureServices(settings);
      final List<dynamic> results;
      if (settings.parallelInference) {
        scanPhase = 'Detecting ingredients & estimating depth…';
        scanProgress = 0.2;
        notifyListeners();
        Future<void>.delayed(const Duration(seconds: 2)).then((_) {
          if (status == ScanStatus.running) {
            scanPhase = 'Detecting ingredients & estimating depth…';
            scanProgress = 0.4;
            notifyListeners();
          }
        });
        Future<void>.delayed(const Duration(seconds: 4)).then((_) {
          if (status == ScanStatus.running) {
            scanPhase = 'Detecting ingredients & estimating depth…';
            scanProgress = 0.6;
            notifyListeners();
          }
        });
        Future<void>.delayed(const Duration(seconds: 6)).then((_) {
          if (status == ScanStatus.running) {
            scanPhase = 'Detecting ingredients & estimating depth…';
            scanProgress = 0.75;
            notifyListeners();
          }
        });
        results = await Future.wait([
          _detector!.detect(image, confThreshold: settings.confidenceThreshold),
          _depth!.estimate(image, focalPx: focalPx),
        ]);
      } else {
        scanPhase = 'Detecting ingredients…';
        scanProgress = 0.3;
        notifyListeners();
        final detections = await _detector!.detect(
          image,
          confThreshold: settings.confidenceThreshold,
        );
        scanPhase = 'Estimating depth…';
        scanProgress = 0.5;
        notifyListeners();
        // Midpoint update after 2 s — fires concurrently, does not block inference.
        Future<void>.delayed(const Duration(seconds: 2)).then((_) {
          if (status == ScanStatus.running) {
            scanPhase = 'Estimating depth…';
            scanProgress = 0.6;
            notifyListeners();
          }
        });
        Future<void>.delayed(const Duration(seconds: 4)).then((_) {
          if (status == ScanStatus.running) {
            scanPhase = 'Estimating depth…';
            scanProgress = 0.75;
            notifyListeners();
          }
        });
        final depthMap = await _depth!.estimate(image, focalPx: focalPx);
        results = [detections, depthMap];
      }
      scanPhase = 'Computing weights…';
      scanProgress = 0.9;
      notifyListeners();
      await Future<void>.delayed(Duration.zero); // let the frame render
      final detections = results[0] as List<Detection>;
      final depthMap = results[1] as DepthMap;

      _image = image;
      _imageBytes = imageBytes;
      _focalPx = focalPx;
      _detections = detections;
      _depthMap = depthMap;
      _settings = settings;
      _depthScale = 1.0;
      _manualDetections.clear();
      _relabels.clear();
      _removed.clear();

      _rebuild();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      scanDuration = stopwatch.elapsed;
      status = ScanStatus.success;
    } catch (e) {
      scanDuration = stopwatch.elapsed;
      error = e.toString();
      status = ScanStatus.error;
      notifyListeners();
      return;
    }
    notifyListeners();
  }

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

    _detector = await DetectorService.fromFile(
      filePath: '$modelsDir/${det.filename}',
      labels: catalog.labels,
      inputSize: det.inputSize,
    );
    _depth = await DepthService.fromFile(
      filePath: '$modelsDir/${dep.filename}',
      family: depthFamilyFromString(dep.family),
      float16: dep.float16,
    );
    _loadedChoice = choice;
  }

  /// Re-applies the weight pipeline to the cached depth + detections under the
  /// current settings/correction state (G6). Used by S13/S15/S16.
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

  /// S15 — distance correction: rescale the cached depth so [detection]'s
  /// sampled depth equals [realDistanceM], then recompute everything. The factor
  /// is derived from the **raw** model depth (absolute), so repeated corrections
  /// don't compound.
  void applyDistanceCorrection(Detection detection, double realDistanceM) {
    final depth = _depthMap;
    if (depth == null || realDistanceM <= 0) return;
    final rawMedian = depth.medianIn(detection.bbox);
    if (rawMedian == null || rawMedian <= 0) return;
    _depthScale = realDistanceM / rawMedian;
    recompute();
  }

  void resetDistanceCorrection() {
    _depthScale = 1.0;
    recompute();
  }

  /// S16 — smart-tap box: estimate an object's bbox from the **raw** depth map
  /// around a tapped centre (px in original-image space). Null if there is no
  /// scan or the point has no valid depth.
  BBox? smartBoxAt(double cx, double cy) {
    final depth = _depthMap;
    if (depth == null) return null;
    return SmartBoxService.boxAround(depth, cx, cy);
  }

  /// S16 — circled box: the user encircled an item; the box is the bounds of the
  /// drawn loop, trimmed inward to the near-depth pixels (px in original-image
  /// space). Null if there is no scan or the loop is degenerate.
  BBox? boxFromLoop(List<(double, double)> loop) {
    final depth = _depthMap;
    if (depth == null) return null;
    return SmartBoxService.boxFromLoop(depth, loop);
  }

  /// Original capture dimensions (px) the bbox coordinates live in.
  int get imageWidth => _depthMap?.width ?? 0;
  int get imageHeight => _depthMap?.height ?? 0;

  /// S16 — add a user-drawn box for a missed item, then recompute.
  void addManualDetection(Detection detection) {
    final origin = detection.origin == DetectionOrigin.model
        ? DetectionOrigin.manual
        : detection.origin;
    _manualDetections.add(detection.copyWith(origin: origin));
    recompute();
  }

  /// S16 — remove an item, whether it was user-drawn or detector-produced. A
  /// detector detection is hidden (kept so the model output stays intact for a
  /// later re-scan); a manual one is dropped outright.
  void removeDetection(Detection detection) {
    if (_manualDetections.remove(detection)) {
      recompute();
      return;
    }
    _removed.add(detection.source ?? detection);
    recompute();
  }

  /// S16 — change the class of an item (a mislabelled or user-drawn box). Manual
  /// detections are edited in place; detector ones get a relabel overlay applied
  /// at recompute (the raw model output is left untouched).
  void relabelDetection(Detection detection, String newClass) {
    final manualIndex = _manualDetections.indexOf(detection);
    if (manualIndex >= 0) {
      _manualDetections[manualIndex] = detection.copyWith(
        className: newClass,
        clearClassId: true,
      );
      recompute();
      return;
    }
    final source = detection.source ?? detection;
    if (source.className == newClass) {
      _relabels.remove(source);
    } else {
      _relabels[source] = newClass;
    }
    recompute();
  }

  ScanEditSnapshot captureEditState() => ScanEditSnapshot(
    manualDetections: List<Detection>.from(_manualDetections),
    relabels: Map<Detection, String>.from(_relabels),
    removed: Set<Detection>.from(_removed),
  );

  void restoreEditState(ScanEditSnapshot snapshot) {
    _manualDetections
      ..clear()
      ..addAll(snapshot.manualDetections);
    _relabels
      ..clear()
      ..addAll(snapshot.relabels);
    _removed
      ..clear()
      ..addAll(snapshot.removed);
    recompute();
  }

  /// Detector detections with the S16 edits applied (removals dropped, relabels
  /// swapped) followed by the manual boxes — the set actually weighed.
  List<Detection> get effectiveDetections {
    final out = <Detection>[];
    for (final det in _detections) {
      if (_removed.contains(det)) continue;
      final relabel = _relabels[det];
      out.add(
        relabel == null
            ? det
            : det.copyWith(
                className: relabel,
                clearClassId: true,
                isRelabeled: true,
                source: det,
              ),
      );
    }
    out.addAll(_manualDetections);
    return out;
  }

  void _rebuild() {
    result = computeResult(
      detections: effectiveDetections,
      depthMap: _depthMap!,
      focalPx: _focalPx,
      baselineDensities: catalog.densities,
      densityOverrides: _settings.densityOverrides,
      depthScale: _depthScale,
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
    return ScanResult.fromItems(items);
  }

  static DepthMap _rescaleDepth(DepthMap source, double scale) {
    final scaled = Float32List(source.data.length);
    for (var i = 0; i < scaled.length; i++) {
      scaled[i] = source.data[i] * scale;
    }
    return DepthMap(width: source.width, height: source.height, data: scaled);
  }
}
