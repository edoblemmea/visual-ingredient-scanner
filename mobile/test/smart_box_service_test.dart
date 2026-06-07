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
  test('sizes the box to the object extent and stops at the depth edge', () {
    // 0.4 m object on a 1.0 m background, occupying [30,70)×[30,70) (half-extent
    // 20 from the centre). The median ray radius lands between the axis
    // half-extent (20) and the diagonal corner (~28), so the box brackets it.
    final depth = _scene(100, 100,
        far: 1.0, near: 0.4, x1: 30, y1: 30, x2: 70, y2: 70);

    final box = SmartBoxService.boxAround(depth, 50, 50)!;

    final halfW = box.width / 2;
    expect(halfW, greaterThan(18)); // reaches the object's axis edge
    expect(halfW, lessThan(30)); // does not overshoot past the diagonal corner
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

  test('produces a box that samples the object depth, not the background', () {
    final depth = _scene(120, 120,
        far: 1.0, near: 0.4, x1: 40, y1: 40, x2: 80, y2: 80);
    final box = SmartBoxService.boxAround(depth, 60, 60) as BBox;
    expect(depth.medianIn(box), closeTo(0.4, 0.05));
  });

  test('a leak on one side cannot inflate the box (robust reach percentile)',
      () {
    // Object [30,70)×[30,70) at 0.5 m on a 1.0 m background, but with a
    // same-depth "bridge" leaking off the right edge (no depth step there). The
    // near-median reach percentile must reject the leaked rays and size to the
    // object (~20 px half-extent), not run away along the bridge.
    final depth = _scene(160, 100,
        far: 1.0, near: 0.5, x1: 30, y1: 30, x2: 70, y2: 70);
    for (var y = 45; y < 55; y++) {
      for (var x = 70; x < 160; x++) {
        depth.data[y * 160 + x] = 0.5; // same-depth bridge to the right edge
      }
    }
    final box = SmartBoxService.boxAround(depth, 50, 50)!;

    expect(box.width, closeTo(40, 14)); // sized to the object, not the bridge
    expect(box.x2, lessThan(90)); // does not follow the bridge to the edge
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

  test('follows an object on a depth gradient and stops at the jump', () {
    // An object [40,80)×[40,80) whose own depth ramps from 0.50 to 0.62 across
    // its width (a slanted item), sitting on a far 1.2 m surface. A fixed band
    // off the near reference would stop partway up the ramp; the jump detector
    // tracks the gradual surface and stops only at the sharp step to 1.2 m.
    final w = 120, h = 120;
    final data = Float32List(w * h)..fillRange(0, w * h, 1.2);
    for (var y = 40; y < 80; y++) {
      for (var x = 40; x < 80; x++) {
        data[y * w + x] = 0.50 + 0.12 * (x - 40) / 40; // ramps across the object
      }
    }
    final depth = DepthMap(width: w, height: h, data: data);

    final box = SmartBoxService.boxAround(depth, 60, 60)!;
    // The rightward edge should reach near the true object edge (x≈80), well
    // past where a 20%-of-ref band (0.50→0.60) would have cut it (~x67).
    expect(box.x2, greaterThan(74));
    expect(box.x2, lessThan(92)); // but not past the object into the surface
  });
}
