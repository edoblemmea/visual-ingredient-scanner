import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/depth_map.dart';

/// Renders a depth map to a colour-mapped PNG (jet) for the debug view (FR5).
/// Downsamples to at most [maxSize] on the long edge so colouring a full-res
/// depth map stays cheap; min/max-normalised so near = blue, far = red.
Uint8List renderDepthMapPng(DepthMap depth, {int maxSize = 384}) {
  final longEdge = depth.width > depth.height ? depth.width : depth.height;
  final factor = longEdge > maxSize ? longEdge / maxSize : 1.0;
  final outW = (depth.width / factor).round().clamp(1, depth.width);
  final outH = (depth.height / factor).round().clamp(1, depth.height);

  var min = double.infinity;
  var max = -double.infinity;
  for (final v in depth.data) {
    if (v < min) min = v;
    if (v > max) max = v;
  }
  final range = (max - min).abs() < 1e-9 ? 1.0 : max - min;

  final out = img.Image(width: outW, height: outH);
  for (var y = 0; y < outH; y++) {
    final sy = (y * depth.height ~/ outH).clamp(0, depth.height - 1);
    for (var x = 0; x < outW; x++) {
      final sx = (x * depth.width ~/ outW).clamp(0, depth.width - 1);
      final t = ((depth.data[sy * depth.width + sx] - min) / range).clamp(0.0, 1.0);
      final c = _jet(t);
      out.setPixelRgb(x, y, c[0], c[1], c[2]);
    }
  }
  return img.encodePng(out);
}

/// Classic jet colormap: blue → cyan → green → yellow → red.
List<int> _jet(double t) {
  double r;
  double g;
  double b;
  if (t < 0.25) {
    r = 0;
    g = 4 * t;
    b = 1;
  } else if (t < 0.5) {
    r = 0;
    g = 1;
    b = 1 - 4 * (t - 0.25);
  } else if (t < 0.75) {
    r = 4 * (t - 0.5);
    g = 1;
    b = 0;
  } else {
    r = 1;
    g = 1 - 4 * (t - 0.75);
    b = 0;
  }
  return [
    (r * 255).round().clamp(0, 255),
    (g * 255).round().clamp(0, 255),
    (b * 255).round().clamp(0, 255),
  ];
}
