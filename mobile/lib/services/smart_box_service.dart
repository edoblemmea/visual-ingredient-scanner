import 'dart:collection';
import 'dart:math' as math;

import '../models/bbox.dart';
import '../models/depth_map.dart';

/// Smart manual-annotation helper (S16, FR7): from a single tap on the centre of
/// an object, estimate its bounding box from the depth map alone — no size
/// priors.
///
/// The object sits at a roughly constant distance, so its pixels form a
/// connected blob whose depth is close to the tapped centre, while the
/// surrounding counter/background recedes. We **flood-fill** the connected
/// region of similar-depth pixels (4-connectivity BFS) starting at the tap, then
/// take a percentile-trimmed bounding box of that region. Looking at the whole
/// 2-D component — rather than four straight rays — makes it robust to single
/// noisy pixels and to a depth gradient across the surface, which the old ray
/// walk handled badly (it either stopped short or ran across the whole counter).
///
/// Pure and static so it is unit-testable and cheap (the data-driven box is only
/// a first guess the user can still drag to adjust).
class SmartBoxService {
  SmartBoxService._();

  /// A neighbour joins the region if its depth is within this fraction of the
  /// **running region mean** (not the fixed centre): tracking the mean lets the
  /// fill follow a gently sloped object without the tolerance drifting away from
  /// it, while still stopping at the sharp depth step to the background.
  static const double _relTolerance = 0.06;

  /// Hard cap on how far (fraction of the image per side) the region may extend
  /// from the tap — guards against a leak through a featureless seam swallowing
  /// the frame.
  static const double _maxHalfExtentFrac = 0.45;

  /// Cap on the number of pixels visited, so a pathological fill can't stall the
  /// UI thread. Scaled to the image; plenty for a single tabletop item.
  static const int _maxRegionFrac = 4; // up to image_area / 4 pixels.

  /// Percentile used to trim the region's bounding box: we take the 2nd/98th
  /// percentile of the filled pixels' x and y instead of the raw min/max, so a
  /// thin leak of a few pixels can't blow the box up.
  static const double _trimPercentile = 0.02;

  /// Minimum half-extent (px) so a tap always yields a usable box even on a
  /// near-flat depth patch where the region barely grows.
  static const double _minHalfExtent = 6.0;

  /// Estimate a bbox in original-image pixels around [cx], [cy] using [depth].
  /// Returns null if the tap is outside the depth map or has no valid depth.
  static BBox? boxAround(DepthMap depth, double cx, double cy) {
    final w = depth.width;
    final h = depth.height;
    final sx = cx.round();
    final sy = cy.round();
    if (sx < 0 || sy < 0 || sx >= w || sy >= h) return null;

    final seed = depth.at(sx, sy);
    if (!seed.isFinite || seed <= 0) return null;

    final region = _floodFill(depth, sx, sy, seed);

    // Trimmed bbox of the filled region: 2nd/98th percentile of each axis, so a
    // thin leak of a few pixels can't inflate the box. We use the region's own
    // extent (not a re-centring on the tap) so an off-centre tap still yields
    // the object's true footprint.
    final xs = region.xs..sort();
    final ys = region.ys..sort();
    var x1 = _percentile(xs, _trimPercentile).toDouble();
    var y1 = _percentile(ys, _trimPercentile).toDouble();
    var x2 = _percentile(xs, 1 - _trimPercentile) + 1.0;
    var y2 = _percentile(ys, 1 - _trimPercentile) + 1.0;

    // Guarantee a minimum size around the tap if the region barely grew.
    if (x2 - x1 < 2 * _minHalfExtent) {
      x1 = cx - _minHalfExtent;
      x2 = cx + _minHalfExtent;
    }
    if (y2 - y1 < 2 * _minHalfExtent) {
      y1 = cy - _minHalfExtent;
      y2 = cy + _minHalfExtent;
    }

    return BBox(x1, y1, x2, y2).clampTo(w, h);
  }

  /// Bounded 4-connectivity flood fill collecting all pixels whose depth is
  /// within [_relTolerance] of the region's running mean depth, starting from
  /// [(sx, sy)] with seed depth [seed].
  static _Region _floodFill(DepthMap depth, int sx, int sy, double seed) {
    final w = depth.width;
    final h = depth.height;
    final visited = List<bool>.filled(w * h, false);

    // Constrain the search window so the BFS can't wander across the frame.
    final winX = (w * _maxHalfExtentFrac).round();
    final winY = (h * _maxHalfExtentFrac).round();
    final minX = math.max(0, sx - winX);
    final maxXb = math.min(w - 1, sx + winX);
    final minY = math.max(0, sy - winY);
    final maxYb = math.min(h - 1, sy + winY);

    final maxPixels = (w * h) ~/ _maxRegionFrac;

    final xs = <int>[];
    final ys = <int>[];
    var sum = 0.0;
    var count = 0;

    final queue = Queue<int>()..add(sy * w + sx);
    visited[sy * w + sx] = true;

    while (queue.isNotEmpty && count < maxPixels) {
      final idx = queue.removeFirst();
      final x = idx % w;
      final y = idx ~/ w;
      final d = depth.data[idx];
      if (!d.isFinite) continue;

      final mean = count == 0 ? seed : sum / count;
      if ((d - mean).abs() > mean * _relTolerance) continue;

      xs.add(x);
      ys.add(y);
      sum += d;
      count++;

      // 4-connected neighbours, kept inside the search window.
      if (x > minX && !visited[idx - 1]) {
        visited[idx - 1] = true;
        queue.add(idx - 1);
      }
      if (x < maxXb && !visited[idx + 1]) {
        visited[idx + 1] = true;
        queue.add(idx + 1);
      }
      if (y > minY && !visited[idx - w]) {
        visited[idx - w] = true;
        queue.add(idx - w);
      }
      if (y < maxYb && !visited[idx + w]) {
        visited[idx + w] = true;
        queue.add(idx + w);
      }
    }

    // Always include the seed so a lone-pixel region still has extent.
    if (xs.isEmpty) {
      xs.add(sx);
      ys.add(sy);
    }
    return _Region(xs, ys);
  }

  /// Value at fractional [p] in a pre-sorted ascending [sorted] list.
  static int _percentile(List<int> sorted, double p) {
    if (sorted.isEmpty) return 0;
    final i = (p * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
    return sorted[i];
  }
}

class _Region {
  _Region(this.xs, this.ys);
  final List<int> xs;
  final List<int> ys;
}
