import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visual_ingredient_scanner/models/models.dart';
import 'package:visual_ingredient_scanner/state/scan_controller.dart';

DepthMap _constantDepth(int w, int h, double metres) {
  final data = Float32List(w * h)..fillRange(0, w * h, metres);
  return DepthMap(width: w, height: h, data: data);
}

void main() {
  final depth = _constantDepth(200, 200, 0.5);
  const baseline = {'tomato': 950.0, 'onion': 850.0};

  Detection box(String name) => Detection(
        className: name,
        confidence: 0.9,
        bbox: const BBox(0, 0, 100, 100),
      );

  test('aggregates per-class weights from detections', () {
    final result = ScanController.computeResult(
      detections: [box('tomato'), box('tomato'), box('onion')],
      depthMap: depth,
      focalPx: 800,
      baselineDensities: baseline,
    );

    expect(result.ingredientWeights.keys, containsAll(['tomato', 'onion']));
    expect(result.ingredientWeights['tomato']! / result.ingredientWeights['onion']!,
        closeTo(2 * 950 / 850, 1e-9)); // two tomatoes, density ratio
  });

  test('density override changes weight proportionally (G7)', () {
    final base = ScanController.computeResult(
      detections: [box('tomato')],
      depthMap: depth,
      focalPx: 800,
      baselineDensities: baseline,
    );
    final overridden = ScanController.computeResult(
      detections: [box('tomato')],
      depthMap: depth,
      focalPx: 800,
      baselineDensities: baseline,
      densityOverrides: {'tomato': 475.0}, // half of 950
    );

    expect(overridden.ingredientWeights['tomato']!,
        closeTo(base.ingredientWeights['tomato']! / 2, 1e-6));
  });

  test('distance correction scales spherical weight by depth^3 (G7)', () {
    final base = ScanController.computeResult(
      detections: [box('tomato')], // sphere
      depthMap: depth,
      focalPx: 800,
      baselineDensities: baseline,
    );
    final scaled = ScanController.computeResult(
      detections: [box('tomato')],
      depthMap: depth,
      focalPx: 800,
      baselineDensities: baseline,
      depthScale: 2.0, // both real dims double -> volume x8
    );

    expect(scaled.ingredientWeights['tomato']!,
        closeTo(base.ingredientWeights['tomato']! * 8, 1e-6));
  });

  test('manual detections contribute to the result', () {
    final result = ScanController.computeResult(
      detections: [box('tomato'), box('onion')],
      depthMap: depth,
      focalPx: 800,
      baselineDensities: baseline,
    );
    expect(result.items, hasLength(2));
  });

  test('unknown class falls back to default density, still weighed', () {
    final result = ScanController.computeResult(
      detections: [box('dragonfruit')],
      depthMap: depth,
      focalPx: 800,
      baselineDensities: baseline,
    );
    expect(result.items.single.densityKgM3, 800.0);
  });

  test('distance correction makes the anchored object read the set distance (S15)', () {
    final raw = _constantDepth(200, 200, 0.8); // model says 0.8 m
    final det = box('tomato');
    final rawMedian = raw.medianIn(det.bbox)!;
    const realDistance = 0.4; // user says it is actually 0.4 m
    final scale = realDistance / rawMedian; // how applyDistanceCorrection derives it

    final result = ScanController.computeResult(
      detections: [det],
      depthMap: raw,
      focalPx: 800,
      baselineDensities: baseline,
      depthScale: scale,
    );

    expect(result.items.single.depthM, closeTo(realDistance, 1e-6));
  });
}
