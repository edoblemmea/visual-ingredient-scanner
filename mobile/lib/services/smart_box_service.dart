import '../models/bbox.dart';
import '../models/depth_map.dart';

/// Smart manual-annotation helper (S16, FR7): from a single tap on the centre of
/// an object, estimate its bounding box from the depth map alone — no size
/// priors. The object sits at a roughly constant distance, so its pixels share a
/// depth close to the tapped centre while the surrounding counter/background is
/// farther; we grow a box outward from the centre while the *edge* depth stays
/// within a relative tolerance of the centre depth.
///
/// Pure and static so it is unit-testable and cheap (the data-driven box is only
/// a first guess the user can still drag to adjust).
class SmartBoxService {
  SmartBoxService._();

  /// Fraction of the centre depth a pixel may differ by and still count as part
  /// of the same object. 12 % comfortably separates a tabletop item from the
  /// counter behind it without bleeding into neighbours.
  static const double _depthTolerance = 0.12;

  /// Don't let a single tap claim more than this fraction of the image per side
  /// — guards against a featureless region growing to the whole frame.
  static const double _maxHalfExtentFrac = 0.45;

  /// Minimum half-extent (px) so a tap always yields a usable box even on a flat
  /// depth patch.
  static const double _minHalfExtent = 8.0;

  /// Estimate a bbox in original-image pixels around [cx], [cy] using [depth].
  /// Returns null if the tap is outside the depth map or has no valid depth.
  static BBox? boxAround(DepthMap depth, double cx, double cy) {
    final px = cx.round();
    final py = cy.round();
    if (px < 0 || py < 0 || px >= depth.width || py >= depth.height) return null;

    final centre = depth.at(px, py);
    if (!centre.isFinite || centre <= 0) return null;
    final band = centre * _depthTolerance;

    final maxX = (depth.width * _maxHalfExtentFrac);
    final maxY = (depth.height * _maxHalfExtentFrac);

    final left = _grow(depth, px, py, -1, 0, band, centre, maxX);
    final right = _grow(depth, px, py, 1, 0, band, centre, maxX);
    final up = _grow(depth, px, py, 0, -1, band, centre, maxY);
    final down = _grow(depth, px, py, 0, 1, band, centre, maxY);

    final halfW = ((left + right) / 2).clamp(_minHalfExtent, maxX);
    final halfH = ((up + down) / 2).clamp(_minHalfExtent, maxY);

    return BBox(cx - halfW, cy - halfH, cx + halfW, cy + halfH)
        .clampTo(depth.width, depth.height);
  }

  /// Walk from the centre along ([dx],[dy]) while depth stays within [band] of
  /// [centre]; return the distance (px) travelled before the object edge.
  static double _grow(
    DepthMap depth,
    int cx,
    int cy,
    int dx,
    int dy,
    double band,
    double centre,
    double maxExtent,
  ) {
    var steps = 0;
    var x = cx;
    var y = cy;
    while (steps < maxExtent) {
      x += dx;
      y += dy;
      if (x < 0 || y < 0 || x >= depth.width || y >= depth.height) break;
      final d = depth.at(x, y);
      if (!d.isFinite || (d - centre).abs() > band) break;
      steps++;
    }
    return steps.toDouble();
  }
}
