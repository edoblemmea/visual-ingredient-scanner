import 'dart:math' as math;

import '../models/depth_map.dart';
import '../models/detection.dart';
import '../models/weighted_item.dart';
import 'density_service.dart';

/// Metric depth is clamped to this range as a sanity guard before projection —
/// matches `np.clip(depth_m, 0.1, 10.0)` in weight.py.
const double kMinDepthM = 0.1;
const double kMaxDepthM = 10.0;

/// Shape heuristic class sets — ported verbatim from `_SPHERE_CLASSES` /
/// `_CYLINDER_CLASSES` in weight.py. Everything else is treated as a box.
const Set<String> _sphereClasses = {
  // fruits
  'apple', 'avocado', 'blackberries', 'blueberries', 'cantaloupe', 'coconut',
  'cherry', 'fig', 'grapes', 'grapefruit', 'kiwi', 'lemon', 'lime', 'mango',
  'orange', 'peach', 'pear', 'pomegranate', 'raspberries', 'strawberries',
  'watermelon',
  // vegetables
  'artichoke', 'beet', 'brussels_sprouts', 'cabbage', 'cauliflower', 'egg',
  'garlic', 'mushrooms', 'onion', 'peas', 'potato', 'pumpkin', 'radish',
  'sweet_potato', 'tomato', 'turnip',
};

const Set<String> _cylinderClasses = {
  // fruits & vegetables
  'banana', 'carrot', 'celery', 'chili', 'corn', 'cucumber', 'eggplant',
  'green_beans', 'okra', 'pineapple', 'zucchini',
  // dairy & packaged
  'canned_beans', 'heavy_cream', 'honey', 'hummus', 'jam', 'juice',
  'mayonnaise', 'oil', 'soda', 'tomato_sauce', 'vinegar', 'water', 'yogurt',
};

/// Stage ④ — pinhole projection + shape heuristics. Pure Dart port of
/// `estimate_weights` in `pipeline/weight.py`; no model inference, so it is
/// cheap to re-run for the distance/density/manual-box corrections (G6).
class WeightService {
  const WeightService({required this.densityService});

  final DensityService densityService;

  List<WeightedItem> estimate({
    required List<Detection> detections,
    required DepthMap depthMap,
    required double focalPx,
  }) {
    final results = <WeightedItem>[];
    for (final det in detections) {
      final rawDepth = depthMap.medianIn(det.bbox);
      if (rawDepth == null) continue; // empty ROI — skip, as weight.py does
      final depthM = rawDepth.clamp(kMinDepthM, kMaxDepthM).toDouble();

      final realW = (det.bbox.width / focalPx) * depthM;
      final realH = (det.bbox.height / focalPx) * depthM;

      final shape = shapeForClass(det.className);
      final volume = volumeM3(shape, realW, realH);
      final density = densityService.densityFor(det.className);

      results.add(
        WeightedItem(
          detection: det,
          shape: shape,
          depthM: depthM,
          realWidthM: realW,
          realHeightM: realH,
          volumeM3: volume,
          densityKgM3: density,
          weightG: volume * density * 1000.0,
        ),
      );
    }
    return results;
  }

  static Shape shapeForClass(String className) {
    final name = className.toLowerCase();
    if (_sphereClasses.contains(name)) return Shape.sphere;
    if (_cylinderClasses.contains(name)) return Shape.cylinder;
    return Shape.box;
  }

  /// Volume (m³) from real-world bbox dimensions (m). Formulas verbatim from
  /// `_volume_m3` in weight.py — note the box uses `max(w, h)` as the third
  /// dimension (not the metric depth) with a 0.5 projection factor.
  static double volumeM3(Shape shape, double w, double h) {
    switch (shape) {
      case Shape.sphere:
        final d = math.min(w, h);
        return (4 / 3) * math.pi * math.pow(d / 2, 3).toDouble();
      case Shape.cylinder:
        final r = w / 2;
        return math.pi * r * r * h;
      case Shape.box:
        return w * h * math.min(w, h) * 0.5;
    }
  }
}
