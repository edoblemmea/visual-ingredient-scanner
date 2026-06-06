import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visual_ingredient_scanner/models/depth_map.dart';
import 'package:visual_ingredient_scanner/services/depth_visualizer.dart';

void main() {
  test('downscales to maxSize and produces a valid PNG', () {
    final data = Float32List(800 * 600);
    for (var y = 0; y < 600; y++) {
      for (var x = 0; x < 800; x++) {
        data[y * 800 + x] = x.toDouble(); // horizontal gradient
      }
    }
    final depth = DepthMap(width: 800, height: 600, data: data);

    final png = renderDepthMapPng(depth, maxSize: 384);
    final decoded = img.decodePng(png)!;

    expect(decoded.width, 384); // long edge clamped
    expect(decoded.height, 288); // 600 * 384/800
  });

  test('jet maps near→blue and far→red', () {
    final data = Float32List(100);
    for (var x = 0; x < 100; x++) {
      data[x] = x.toDouble();
    }
    final depth = DepthMap(width: 100, height: 1, data: data);

    final decoded = img.decodePng(renderDepthMapPng(depth, maxSize: 100))!;
    final near = decoded.getPixel(0, 0); // smallest depth
    final far = decoded.getPixel(99, 0); // largest depth

    expect(near.b, greaterThan(near.r)); // blue end
    expect(far.r, greaterThan(far.b)); // red end
  });

  test('constant depth does not divide by zero', () {
    final depth = DepthMap(
      width: 4,
      height: 4,
      data: Float32List(16)..fillRange(0, 16, 2.5),
    );
    expect(() => renderDepthMapPng(depth), returnsNormally);
  });
}
