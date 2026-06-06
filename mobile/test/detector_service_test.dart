import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visual_ingredient_scanner/services/detector_service.dart';

void main() {
  group('preprocess (letterbox)', () {
    test('produces a CHW tensor with centre padding and correct transform', () {
      final src = img.Image(width: 100, height: 50);
      img.fill(src, color: img.ColorRgb8(255, 0, 0)); // solid red

      final input = DetectorService.preprocess(src, 640);
      const area = 640 * 640;

      expect(input.data.length, 3 * area);
      expect(input.scale, 6.4); // min(640/100, 640/50)
      expect(input.padX, 0);
      expect(input.padY, 160); // (640 - 320) / 2

      // First image pixel lands at canvas (0, 160) -> index 160*640.
      const idx = 160 * 640;
      expect(input.data[idx], 1.0); // R = 255/255
      expect(input.data[area + idx], 0.0); // G
      expect(input.data[2 * area + idx], 0.0); // B

      // Top padding region is grey 114/255.
      expect(input.data[0], closeTo(114 / 255.0, 1e-6));
    });
  });

  group('decodeDetections', () {
    const labels = ['apple', 'banana', 'carrot'];

    test('thresholds, maps to original px, and labels', () {
      final rows = <List<double>>[
        [0, 160, 640, 480, 0.9, 0], // full image, apple
        [320, 240, 360, 280, 0.05, 1], // below threshold -> dropped
        [0, 0, 0, 0, 0, 0], // NMS padding row -> dropped
      ];

      final detections = DetectorService.decodeDetections(
        rows,
        scale: 6.4,
        padX: 0,
        padY: 160,
        imageWidth: 100,
        imageHeight: 50,
        labels: labels,
        confThreshold: 0.10,
      );

      expect(detections, hasLength(1));
      final d = detections.single;
      expect(d.className, 'apple');
      expect(d.classId, 0);
      expect(d.confidence, 0.9);
      expect(d.bbox.x1, closeTo(0, 1e-6));
      expect(d.bbox.y1, closeTo(0, 1e-6));
      expect(d.bbox.x2, closeTo(100, 1e-6));
      expect(d.bbox.y2, closeTo(50, 1e-6));
    });

    test('clamps boxes that spill outside the image', () {
      final rows = <List<double>>[
        [-64, 160, 704, 480, 0.8, 2], // spills left & right
      ];

      final d = DetectorService.decodeDetections(
        rows,
        scale: 6.4,
        padX: 0,
        padY: 160,
        imageWidth: 100,
        imageHeight: 50,
        labels: labels,
        confThreshold: 0.10,
      ).single;

      expect(d.className, 'carrot');
      expect(d.bbox.x1, 0); // clamped from -10
      expect(d.bbox.x2, 100); // clamped from 110
    });

    test('falls back to class_<id> for an out-of-range label', () {
      final rows = <List<double>>[
        [0, 0, 64, 64, 0.5, 99],
      ];

      final d = DetectorService.decodeDetections(
        rows,
        scale: 1,
        padX: 0,
        padY: 0,
        imageWidth: 640,
        imageHeight: 640,
        labels: labels,
        confThreshold: 0.10,
      ).single;

      expect(d.className, 'class_99');
    });
  });
}
