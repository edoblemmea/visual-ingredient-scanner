import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visual_ingredient_scanner/models/models.dart';
import 'package:visual_ingredient_scanner/services/density_service.dart';
import 'package:visual_ingredient_scanner/services/weight_service.dart';

/// Reference values were produced by running pipeline/weight.py on the same
/// inputs (focal 800 px, see docs/phase3_prd.md S6). Dart must match within a
/// tiny tolerance (float32 depth + double arithmetic).
DepthMap _constantDepth(int w, int h, double metres) {
  final data = Float32List(w * h);
  data.fillRange(0, data.length, metres);
  return DepthMap(width: w, height: h, data: data);
}

Matcher _closeRel(double expected) =>
    closeTo(expected, expected.abs() * 1e-6 + 1e-9);

void main() {
  const focalPx = 800.0;

  group('parity with pipeline/weight.py', () {
    final depth = _constantDepth(600, 600, 0.5);
    const densities = DensityService(
      baseline: {'tomato': 950.0, 'carrot': 600.0, 'milk': 1030.0},
    );
    const service = WeightService(densityService: densities);

    test('sphere (tomato)', () {
      final item = service.estimate(
        detections: [
          const Detection(
            className: 'tomato',
            confidence: 0.9,
            bbox: BBox(400, 400, 500, 520),
          ),
        ],
        depthMap: depth,
        focalPx: focalPx,
      ).single;

      expect(item.shape, Shape.sphere);
      expect(item.realWidthM, _closeRel(0.0625));
      expect(item.realHeightM, _closeRel(0.075));
      expect(item.volumeM3, _closeRel(0.00012783173232380342));
      expect(item.weightG, _closeRel(121.44014570761324));
    });

    test('cylinder (carrot)', () {
      final item = service.estimate(
        detections: [
          const Detection(
            className: 'carrot',
            confidence: 0.9,
            bbox: BBox(100, 100, 160, 400),
          ),
        ],
        depthMap: depth,
        focalPx: focalPx,
      ).single;

      expect(item.shape, Shape.cylinder);
      expect(item.volumeM3, _closeRel(0.00020708740636456158));
      expect(item.weightG, _closeRel(124.25244381873695));
    });

    test('box (milk)', () {
      final item = service.estimate(
        detections: [
          const Detection(
            className: 'milk',
            confidence: 0.9,
            bbox: BBox(0, 0, 200, 300),
          ),
        ],
        depthMap: depth,
        focalPx: focalPx,
      ).single;

      expect(item.shape, Shape.box);
      expect(item.volumeM3, _closeRel(0.002197265625));
      expect(item.weightG, _closeRel(2263.18359375));
    });
  });

  test('median averages two middle values like np.median', () {
    final data = Float32List(200 * 200);
    // region [100:102, 100:102] = [[0.4, 0.5], [0.6, 0.7]]
    data[100 * 200 + 100] = 0.4;
    data[100 * 200 + 101] = 0.5;
    data[101 * 200 + 100] = 0.6;
    data[101 * 200 + 101] = 0.7;
    final depth = DepthMap(width: 200, height: 200, data: data);
    const service = WeightService(
      densityService: DensityService(baseline: {'apple': 800.0}),
    );

    final item = service.estimate(
      detections: [
        const Detection(
          className: 'apple',
          confidence: 0.9,
          bbox: BBox(100, 100, 102, 102),
        ),
      ],
      depthMap: depth,
      focalPx: 800,
    ).single;

    expect(item.depthM, _closeRel(0.550000011920929));
    expect(item.weightG, _closeRel(0.0010889218994323234));
  });

  test('depth is clamped to [0.1, 10] m', () {
    final depth = _constantDepth(200, 200, 50.0); // 50 m -> clamps to 10 m
    const service = WeightService(
      densityService: DensityService(baseline: {'apple': 800.0}),
    );

    final item = service.estimate(
      detections: [
        const Detection(
          className: 'apple',
          confidence: 0.9,
          bbox: BBox(100, 100, 140, 140),
        ),
      ],
      depthMap: depth,
      focalPx: 800,
    ).single;

    expect(item.depthM, 10.0);
    expect(item.realWidthM, _closeRel(0.5));
    expect(item.weightG, _closeRel(52359.87755982988));
  });

  test('empty ROI is skipped', () {
    final depth = _constantDepth(50, 50, 0.5);
    const service = WeightService(
      densityService: DensityService(baseline: {}),
    );

    // bbox fully outside the map -> no pixels -> skipped
    final items = service.estimate(
      detections: [
        const Detection(
          className: 'apple',
          confidence: 0.9,
          bbox: BBox(100, 100, 120, 120),
        ),
      ],
      depthMap: depth,
      focalPx: 800,
    );

    expect(items, isEmpty);
  });
}
