import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visual_ingredient_scanner/services/depth_service.dart';

void main() {
  test('family parsing', () {
    expect(depthFamilyFromString('metric3d'), DepthFamily.metric3d);
    expect(depthFamilyFromString('depthanything'), DepthFamily.depthAnything);
  });

  test('metric3d de-canonicalisation factor = focal*scale/1000', () {
    expect(DepthService.metric3dDecanonFactor(800, 1.064), closeTo(0.8512, 1e-9));
  });

  group('preprocessMetric3d', () {
    test('letterbox sizing, transform, normalisation, and zero padding', () {
      final src = img.Image(width: 1000, height: 500);
      img.fill(src, color: img.ColorRgb8(255, 255, 255));

      final pre = DepthService.preprocessMetric3d(src);
      const area = 616 * 1064;

      expect(pre.data.length, 3 * area);
      expect(pre.scale, closeTo(1.064, 1e-9)); // min(616/500, 1064/1000)
      expect(pre.resizedW, 1064);
      expect(pre.resizedH, 532);
      expect(pre.padLeft, 0);
      expect(pre.padTop, 42); // (616 - 532) ~/ 2

      // First real pixel lands at canvas (0, 42).
      const idx = 42 * 1064;
      expect(pre.data[idx], closeTo((255 - 123.675) / 58.395, 1e-4));
      expect(pre.data[area + idx], closeTo((255 - 116.28) / 57.12, 1e-4));
      expect(pre.data[2 * area + idx], closeTo((255 - 103.53) / 57.375, 1e-4));

      // Top padding row normalises to 0 (mean - mean).
      expect(pre.data[0], 0.0);
    });
  });

  test('preprocessDepthAnything sizing and ImageNet normalisation', () {
    final src = img.Image(width: 200, height: 100);
    img.fill(src, color: img.ColorRgb8(255, 255, 255));

    final data = DepthService.preprocessDepthAnything(src);
    const area = 518 * 518;

    expect(data.length, 3 * area);
    expect(data[0], closeTo((1.0 - 0.485) / 0.229, 1e-4));
    expect(data[area], closeTo((1.0 - 0.456) / 0.224, 1e-4));
  });

  test('cropPlane extracts the un-pad window', () {
    // 3 rows x 4 cols: 0..11
    final src = Float32List.fromList(
      List<double>.generate(12, (i) => i.toDouble()),
    );
    final crop = DepthService.cropPlane(src, 4, 1, 1, 2, 2);
    expect(crop, [5, 6, 9, 10]);
  });

  group('bilinearResize', () {
    test('identity returns the same values', () {
      final src = Float32List.fromList([1, 2, 3, 4]);
      final out = DepthService.bilinearResize(src, 2, 2, 2, 2);
      expect(out, [1, 2, 3, 4]);
    });

    test('half-pixel upscale interpolates and clamps edges', () {
      final src = Float32List.fromList([0, 10]); // width 2, height 1
      final out = DepthService.bilinearResize(src, 2, 1, 4, 1);
      expect(out[0], closeTo(0, 1e-9));
      expect(out[1], closeTo(2.5, 1e-9));
      expect(out[2], closeTo(7.5, 1e-9));
      expect(out[3], closeTo(10, 1e-9));
    });
  });
}
