import 'dart:math' as math;

import '../models/bbox.dart';
import '../models/depth_map.dart';

/// Smart manual-annotation helper (S16, FR7): from a single tap on the centre of
/// an object, estimate its bounding box from the depth map alone — no size
/// priors.
///
/// **Why a radial scan, not a flood fill.** In a top-down fridge/counter shot
/// the item and the surface it rests on are at almost the same distance — on a
/// real Metric3D map ~20 % of the whole frame is within 6 % depth of any given
/// point. A connected-component flood fill therefore leaks across the surface
/// and the neighbouring items and returns a huge box. What actually separates an
/// item from its surroundings is that the item pokes *toward* the camera: its
/// nearest point is a local depth minimum, and depth rises as you move off it.
///
/// So we:
///   1. take the **local depth minimum** in a small window at the tap as the
///      object's near-point reference (robust to the tap missing the true peak);
///   2. cast rays outward in all directions, each stopping where depth has risen
///      past `ref + threshold` (an absolute step, adaptive to distance);
///   3. take the **75th-percentile** extent on each side (left/right/up/down)
///      so a few rays that escape along a same-depth seam don't inflate the box,
///      while the box still adapts its aspect ratio per object.
///
/// Validated against test_image3 depth: smart boxes land within ~1 cm of the
/// detector's boxes for oranges, lemon and garlic.
///
/// Pure and static so it is unit-testable and cheap (the box is only a first
/// guess the user can still drag to adjust).
class SmartBoxService {
  SmartBoxService._();

  /// Half-size (px) of the window used to find the object's near-point depth.
  static const int _refWindow = 24;

  /// Depth step (as a fraction of the reference depth) at which a ray is
  /// considered to have left the object onto the receding surface behind it.
  static const double _stepFrac = 0.10;

  /// Absolute floor for that step (m), so very-close objects (small absolute
  /// depth) still get a usable band.
  static const double _stepFloorM = 0.015;

  /// Per-side percentile of ray extents kept as the half-extent — below the max
  /// so a handful of escaping rays are trimmed.
  static const double _extentPercentile = 0.75;

  /// Hard cap on a ray's reach, as a fraction of the smaller image side.
  static const double _maxReachFrac = 0.40;

  /// Number of rays cast around the tap.
  static const int _rayCount = 72;

  /// Minimum half-extent (px) so a tap always yields a usable box.
  static const double _minHalfExtent = 6.0;

  /// Estimate a bbox in original-image pixels around [cx], [cy] using [depth].
  /// Returns null if the tap is outside the depth map or has no valid depth.
  static BBox? boxAround(DepthMap depth, double cx, double cy) {
    final w = depth.width;
    final h = depth.height;
    final sx = cx.round();
    final sy = cy.round();
    if (sx < 0 || sy < 0 || sx >= w || sy >= h) return null;

    final ref = _localMin(depth, sx, sy);
    if (ref == null) return null;

    final threshold = ref + math.max(_stepFloorM, ref * _stepFrac);
    final maxReach = (math.min(w, h) * _maxReachFrac);

    // Ray extents projected onto each side. Index by sign of the projection.
    final right = <double>[];
    final left = <double>[];
    final down = <double>[];
    final up = <double>[];

    for (var i = 0; i < _rayCount; i++) {
      final angle = 2 * math.pi * i / _rayCount;
      final dx = math.cos(angle);
      final dy = math.sin(angle);
      final reach = _rayReach(depth, sx, sy, dx, dy, threshold, maxReach);
      final px = dx * reach;
      final py = dy * reach;
      if (px >= 0) {
        right.add(px);
      } else {
        left.add(-px);
      }
      if (py >= 0) {
        down.add(py);
      } else {
        up.add(-py);
      }
    }

    final hl = _percentile(left, _extentPercentile);
    final hr = _percentile(right, _extentPercentile);
    final hu = _percentile(up, _extentPercentile);
    final hd = _percentile(down, _extentPercentile);

    final x1 = cx - math.max(_minHalfExtent, hl);
    final x2 = cx + math.max(_minHalfExtent, hr);
    final y1 = cy - math.max(_minHalfExtent, hu);
    final y2 = cy + math.max(_minHalfExtent, hd);

    return BBox(x1, y1, x2, y2).clampTo(w, h);
  }

  /// Nearest depth in a small window around the tap — the object's near point.
  /// Null if the window holds no valid (finite, positive) depth.
  static double? _localMin(DepthMap depth, int cx, int cy) {
    final x0 = math.max(0, cx - _refWindow);
    final x1 = math.min(depth.width - 1, cx + _refWindow);
    final y0 = math.max(0, cy - _refWindow);
    final y1 = math.min(depth.height - 1, cy + _refWindow);
    var best = double.infinity;
    for (var y = y0; y <= y1; y++) {
      final row = y * depth.width;
      for (var x = x0; x <= x1; x++) {
        final d = depth.data[row + x];
        if (d.isFinite && d > 0 && d < best) best = d;
      }
    }
    return best.isFinite ? best : null;
  }

  /// Distance (px) a ray travels from ([cx],[cy]) along ([dx],[dy]) before depth
  /// exceeds [threshold] (the object→surface step) or it leaves the image / the
  /// [maxReach] cap. A short run of over-threshold pixels is tolerated so a
  /// single noisy pixel doesn't cut the ray short.
  static double _rayReach(
    DepthMap depth,
    int cx,
    int cy,
    double dx,
    double dy,
    double threshold,
    double maxReach,
  ) {
    const tolerateRun = 2; // consecutive over-threshold pixels allowed
    var over = 0;
    var lastGood = 0;
    final limit = maxReach.floor();
    for (var r = 1; r <= limit; r++) {
      final x = (cx + dx * r).round();
      final y = (cy + dy * r).round();
      if (x < 0 || y < 0 || x >= depth.width || y >= depth.height) {
        return r.toDouble();
      }
      final d = depth.data[y * depth.width + x];
      if (!d.isFinite || d > threshold) {
        over++;
        if (over > tolerateRun) return lastGood.toDouble();
      } else {
        over = 0;
        lastGood = r;
      }
    }
    return maxReach;
  }

  /// Value at fractional [p] of [values] (not pre-sorted). Empty → 0.
  static double _percentile(List<double> values, double p) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final i = (p * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
    return sorted[i];
  }
}
