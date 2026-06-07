import 'dart:math' as math;

import '../models/bbox.dart';
import '../models/depth_map.dart';

/// Smart manual-annotation helper (S16, FR7). Two entry points, both depth-based
/// and free of size priors:
///   • [boxFromLoop] — the user **circles** an item; the box is the bounds of
///     the drawn loop (a direct, reliable extent), trimmed inward to the
///     near-depth pixels. This is the primary smart-mode gesture.
///   • [boxAround] — from a single **tap**, infer the box from depth alone (used
///     by callers that only have a point). Less reliable than a circle because
///     the extent is guessed rather than supplied.
///
/// [boxAround] details:
///
/// **Approach (validated against the real Metric3D depth of the three sample
/// images).** The item pokes toward the camera, so:
///   1. Reference depth = the **20th percentile** of a small window at the tap —
///      the object's near surface, robust to a single noisy pixel or a closer
///      neighbour clipping the window (the strict minimum collapsed the box when
///      such a dip was present).
///   2. Cast 72 rays outward; a ray stays on the object while depth tracks its
///      running-minimum plateau, and ends at the first **depth jump** back to the
///      surface behind it (a discontinuity, not a fixed band — so it follows an
///      object whose own surface depth varies or sits on a slope), with an
///      absolute-drift backstop. A short jump run is tolerated for noise.
///   3. Radius = the **55th percentile** of the ray reaches. Leaks are
///      *directional* — when the item rests against an adjacent same-depth
///      surface a whole contiguous arc of rays runs away — so a per-side
///      percentile fails (an entire side can leak) but a near-median rejects
///      ~45 % runaway rays. The box is the square of that radius around the tap;
///      the user drags it to fine-tune the aspect.
///
/// On the sample images this lands within ~10 % of the detector's box for the
/// isolated items (apple, oranges, lemon, garlic, bread); tight clusters (a pile
/// of figs) are sized to a single item, which is the sensible default.
///
/// Pure and static so it is unit-testable and cheap (the box is only a first
/// guess the user can still drag to adjust).
class SmartBoxService {
  SmartBoxService._();

  /// Half-size (px) of the window used to read the object's near-surface depth.
  /// Small (real food items span hundreds of px, so this stays well inside them)
  /// while still averaging out a single noisy pixel at the tap.
  static const int _refWindow = 8;

  /// Percentile of the reference window used as the near-surface depth — low
  /// (near the front) but not the strict minimum, so a single closer pixel
  /// doesn't drag the reference in front of the object.
  static const double _refPercentile = 0.20;

  /// A depth **jump** of more than this fraction of the object's plateau depth,
  /// between adjacent samples along a ray, marks the object→surface edge. Keying
  /// the edge to a *discontinuity* (rather than an absolute band off `ref`) makes
  /// it robust to an object whose own surface depth varies or sits on a slope:
  /// the ray follows the surface and stops only where depth actually steps back.
  static const double _jumpFrac = 0.10;

  /// Absolute floor for that jump (m), for very-close (small-depth) objects.
  static const double _jumpFloorM = 0.02;

  /// Backstop: even without a single sharp jump, a ray stops once depth has
  /// drifted this far past the reference — guards against a smooth ramp onto the
  /// background with no clean step.
  static const double _maxDriftFrac = 0.20;

  /// Hard cap on a ray's reach, as a fraction of the smaller image side.
  static const double _maxReachFrac = 0.40;

  /// Number of rays cast around the tap.
  static const int _rayCount = 72;

  /// Consecutive jump pixels a ray tolerates (noise) before stopping.
  static const int _tolerateRun = 2;

  /// Percentile of the ray reaches taken as the radius. Slightly above the
  /// median — leaks are directional so the median is the floor of robustness,
  /// and 55 % recovers the rounded-object rim the strict median clips, while
  /// staying well below the point where a leaked arc would inflate the box.
  static const double _reachPercentile = 0.55;

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

    final ref = _refDepth(depth, sx, sy);
    if (ref == null) return null;

    final maxReach = math.min(w, h) * _maxReachFrac;

    final reaches = <double>[];
    for (var i = 0; i < _rayCount; i++) {
      final angle = 2 * math.pi * i / _rayCount;
      reaches.add(_rayReach(
        depth,
        sx,
        sy,
        math.cos(angle),
        math.sin(angle),
        ref,
        maxReach,
      ));
    }

    final radius =
        math.max(_minHalfExtent, _percentile(reaches, _reachPercentile));
    return BBox(cx - radius, cy - radius, cx + radius, cy + radius)
        .clampTo(w, h);
  }

  /// Fraction of pixels inside the loop that must be farther than the trim
  /// threshold before the box is trimmed inward at all — so a tight loop that is
  /// all object is left exactly as drawn.
  static const double _minBackgroundFracToTrim = 0.10;

  /// Depth (fraction over the loop's near reference) past which a pixel inside
  /// the loop is considered background to be trimmed away.
  static const double _trimDepthFrac = 0.15;

  /// Percentile of the in-loop depths taken as the near (object) reference.
  /// Lower than the tap path's: a loose circle can be mostly background, so a
  /// higher percentile would pick the surface instead of the encircled item.
  static const double _loopRefPercentile = 0.10;

  /// Box from a **circled** region (FR7): the user loosely encircles an item and
  /// the box is the bounds of what they drew — a direct, reliable signal, no
  /// depth guessing for the extent. Depth is used only to **trim inward**: if a
  /// meaningful share of the loop is clearly-farther background, the box shrinks
  /// to the near-depth (object) pixels inside the loop. It never expands past the
  /// drawn loop, so the result can only be tighter than what was circled.
  ///
  /// [points] are in original-image pixels. Returns null for a degenerate loop.
  static BBox? boxFromLoop(DepthMap depth, List<(double, double)> points) {
    if (points.length < 3) return null;
    final w = depth.width;
    final h = depth.height;

    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final (px, py) in points) {
      if (px < minX) minX = px;
      if (py < minY) minY = py;
      if (px > maxX) maxX = px;
      if (py > maxY) maxY = py;
    }
    final loopBox = BBox(minX, minY, maxX, maxY).clampTo(w, h);
    if (loopBox.width < 2 * _minHalfExtent ||
        loopBox.height < 2 * _minHalfExtent) {
      return loopBox; // too small to refine — take it as drawn
    }

    // Near-surface reference: 20th percentile of valid depths inside the loop.
    final ix0 = loopBox.x1.floor().clamp(0, w - 1);
    final iy0 = loopBox.y1.floor().clamp(0, h - 1);
    final ix1 = loopBox.x2.ceil().clamp(0, w - 1);
    final iy1 = loopBox.y2.ceil().clamp(0, h - 1);

    final inside = <double>[];
    for (var y = iy0; y <= iy1; y++) {
      for (var x = ix0; x <= ix1; x++) {
        if (!_pointInPolygon(x.toDouble(), y.toDouble(), points)) continue;
        final d = depth.data[y * w + x];
        if (d.isFinite && d > 0) inside.add(d);
      }
    }
    if (inside.isEmpty) return loopBox;
    inside.sort();
    final ref = inside[(_loopRefPercentile * (inside.length - 1)).round()];
    final trimAt = ref * (1 + _trimDepthFrac);

    final background = inside.where((d) => d > trimAt).length;
    if (background / inside.length < _minBackgroundFracToTrim) {
      return loopBox; // loop is essentially all object — keep it as drawn
    }

    // Trim to the near-depth (object) pixels inside the loop.
    var tx0 = double.infinity, ty0 = double.infinity;
    var tx1 = -double.infinity, ty1 = -double.infinity;
    for (var y = iy0; y <= iy1; y++) {
      for (var x = ix0; x <= ix1; x++) {
        final d = depth.data[y * w + x];
        if (!d.isFinite || d <= 0 || d > trimAt) continue;
        if (!_pointInPolygon(x.toDouble(), y.toDouble(), points)) continue;
        if (x < tx0) tx0 = x.toDouble();
        if (y < ty0) ty0 = y.toDouble();
        if (x > tx1) tx1 = x.toDouble();
        if (y > ty1) ty1 = y.toDouble();
      }
    }
    if (tx1 < tx0 || ty1 < ty0) return loopBox;
    return BBox(tx0, ty0, tx1 + 1, ty1 + 1).clampTo(w, h);
  }

  /// Ray-casting point-in-polygon test (the loop is treated as closed).
  static bool _pointInPolygon(double x, double y, List<(double, double)> poly) {
    var inside = false;
    final n = poly.length;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      final (xi, yi) = poly[i];
      final (xj, yj) = poly[j];
      if (((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// Near-surface reference depth: the [_refPercentile] of valid depths in a
  /// window around the tap. Null if the window holds no valid depth.
  static double? _refDepth(DepthMap depth, int cx, int cy) {
    final x0 = math.max(0, cx - _refWindow);
    final x1 = math.min(depth.width - 1, cx + _refWindow);
    final y0 = math.max(0, cy - _refWindow);
    final y1 = math.min(depth.height - 1, cy + _refWindow);
    final vals = <double>[];
    for (var y = y0; y <= y1; y++) {
      final row = y * depth.width;
      for (var x = x0; x <= x1; x++) {
        final d = depth.data[row + x];
        if (d.isFinite && d > 0) vals.add(d);
      }
    }
    if (vals.isEmpty) return null;
    vals.sort();
    final i = (_refPercentile * (vals.length - 1))
        .round()
        .clamp(0, vals.length - 1);
    return vals[i];
  }

  /// Distance (px) a ray travels from ([cx],[cy]) along ([dx],[dy]) while it is
  /// still on the object. The object plateau is the running minimum depth seen
  /// along the ray (its surface can curve slightly nearer); the ray ends at the
  /// first point where depth **jumps** above that plateau by [_jumpFrac] (a
  /// discontinuity = the step back to the surface behind the object), or has
  /// drifted [_maxDriftFrac] past [ref] with no clean step, or leaves the image
  /// / hits [maxReach]. A short jump run is tolerated so a single noisy pixel
  /// doesn't cut the ray short.
  static double _rayReach(
    DepthMap depth,
    int cx,
    int cy,
    double dx,
    double dy,
    double ref,
    double maxReach,
  ) {
    var plateau = ref;
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
      if (!d.isFinite) {
        over++;
        if (over > _tolerateRun) return lastGood.toDouble();
        continue;
      }
      if (d < plateau) plateau = d;
      final jumped = (d - plateau) > math.max(_jumpFloorM, plateau * _jumpFrac);
      final drifted = (d - ref) > ref * _maxDriftFrac;
      if (jumped || drifted) {
        over++;
        if (over > _tolerateRun) return lastGood.toDouble();
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
