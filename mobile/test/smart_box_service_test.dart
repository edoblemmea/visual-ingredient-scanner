import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visual_ingredient_scanner/models/bbox.dart';
import 'package:visual_ingredient_scanner/models/depth_map.dart';
import 'package:visual_ingredient_scanner/services/smart_box_service.dart';

/// A depth map that is [far] everywhere except a [near] square region
/// [x1,x2)×[y1,y2) — an object sitting in front of a far background.
DepthMap _scene(
  int w,
  int h, {
  required double far,
  required double near,
  required int x1,
  required int y1,
  required int x2,
  required int y2,
}) {
  final data = Float32List(w * h)..fillRange(0, w * h, far);
  for (var y = y1; y < y2; y++) {
    for (var x = x1; x < x2; x++) {
      data[y * w + x] = near;
    }
  }
  return DepthMap(width: w, height: h, data: data);
}

void main() {
  test('grows a box to the object extent and stops at the depth edge', () {
    // 0.4 m object on a 1.0 m background, occupying [40,60)×[40,60).
    final depth = _scene(100, 100,
        far: 1.0, near: 0.4, x1: 40, y1: 40, x2: 60, y2: 60);

    final box = SmartBoxService.boxAround(depth, 50, 50)!;

    // Should land close to the object square (centre 50, half-extent ~10).
    expect(box.x1, closeTo(40, 2));
    expect(box.y1, closeTo(40, 2));
    expect(box.x2, closeTo(60, 2));
    expect(box.y2, closeTo(60, 2));
  });

  test('returns null outside the depth map', () {
    final depth = _scene(20, 20,
        far: 1.0, near: 0.4, x1: 5, y1: 5, x2: 10, y2: 10);
    expect(SmartBoxService.boxAround(depth, -1, 5), isNull);
    expect(SmartBoxService.boxAround(depth, 5, 99), isNull);
  });

  test('returns null where depth is invalid', () {
    final data = Float32List(4 * 4); // all zeros
    final depth = DepthMap(width: 4, height: 4, data: data);
    expect(SmartBoxService.boxAround(depth, 2, 2), isNull);
  });

  test('a flat patch still yields a usable (clamped) box', () {
    final flat = DepthMap(
      width: 50,
      height: 50,
      data: Float32List(50 * 50)..fillRange(0, 50 * 50, 0.5),
    );
    final box = SmartBoxService.boxAround(flat, 25, 25);
    expect(box, isNotNull);
    expect(box!.width, greaterThan(0));
    expect(box.height, greaterThan(0));
    // Capped well under the full image by the half-extent fraction.
    expect(box.width, lessThan(50));
  });

  test('clamps the box to image bounds when the object touches the edge', () {
    final depth = _scene(40, 40,
        far: 1.0, near: 0.4, x1: 0, y1: 0, x2: 12, y2: 12);
    final box = SmartBoxService.boxAround(depth, 4, 4)!;
    expect(box.x1, greaterThanOrEqualTo(0));
    expect(box.y1, greaterThanOrEqualTo(0));
    expect(box.x2, lessThanOrEqualTo(40));
    expect(box.y2, lessThanOrEqualTo(40));
  });

  test('produces a box compatible with depth median sampling', () {
    final depth = _scene(80, 80,
        far: 1.0, near: 0.4, x1: 30, y1: 30, x2: 50, y2: 50);
    final box = SmartBoxService.boxAround(depth, 40, 40) as BBox;
    expect(depth.medianIn(box), closeTo(0.4, 0.01));
  });

  test('adapts the box aspect to a wide object', () {
    // A wide object: 60 px across, 16 px tall. The per-side radial extents
    // should make the box clearly wider than it is tall (an earlier 4-ray walk
    // collapsed both axes into one square).
    final depth = _scene(120, 80,
        far: 1.2, near: 0.5, x1: 20, y1: 32, x2: 80, y2: 48);
    final box = SmartBoxService.boxAround(depth, 50, 40)!;

    expect(box.width, greaterThan(box.height * 1.5)); // clearly wide
    expect(box.height, lessThan(24)); // does not run past the short side
  });

  test('a single noisy interior pixel does not truncate the box', () {
    // Object [30,70)×[30,70) at 0.5 m on a 1.0 m background, with one spike
    // pixel along the rightward ray. A single over-threshold pixel is tolerated
    // (tolerateRun), so the ray does not stop at the spike.
    final depth = _scene(100, 100,
        far: 1.0, near: 0.5, x1: 30, y1: 30, x2: 70, y2: 70);
    depth.data[50 * 100 + 55] = 1.0; // spike on the row through the centre

    final box = SmartBoxService.boxAround(depth, 50, 50)!;
    expect(box.x2, greaterThan(64)); // reaches well past the spike at x=55
  });

  test('does not leak across a sharp depth step to a neighbour', () {
    // Two objects at 0.5 m separated by a 1.2 m gap; tapping the left one must
    // not swallow the right one.
    final data = Float32List(100 * 60)..fillRange(0, 100 * 60, 1.2);
    void fill(int x1, int x2) {
      for (var y = 20; y < 40; y++) {
        for (var x = x1; x < x2; x++) {
          data[y * 100 + x] = 0.5;
        }
      }
    }

    fill(10, 30); // left object
    fill(70, 90); // right object
    final depth = DepthMap(width: 100, height: 60, data: data);

    final box = SmartBoxService.boxAround(depth, 20, 30)!;
    expect(box.x2, lessThan(50)); // stays on the left object
  });
}
