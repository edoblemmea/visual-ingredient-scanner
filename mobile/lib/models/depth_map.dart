import 'dart:typed_data';

import 'bbox.dart';

/// A metric depth map in metres, row-major at the original image resolution —
/// the Dart counterpart of the `np.ndarray` returned by `pipeline/depth.py`.
class DepthMap {
  DepthMap({required this.width, required this.height, required this.data})
      : assert(data.length == width * height,
            'depth length ${data.length} != ${width * height}');

  final int width;
  final int height;

  /// Depth values in metres, length `width * height`.
  final Float32List data;

  double at(int x, int y) => data[y * width + x];

  /// Median depth (m) over the bbox region, or null if the clamped region is
  /// empty. Mirrors `np.median(depth_map[y1:y2, x1:x2])` in weight.py: integer
  /// half-open slicing, and numpy averages the two middle values for an even
  /// count.
  double? medianIn(BBox bbox) {
    final xa = bbox.x1.toInt().clamp(0, width);
    final ya = bbox.y1.toInt().clamp(0, height);
    final xb = bbox.x2.toInt().clamp(0, width);
    final yb = bbox.y2.toInt().clamp(0, height);
    if (xb <= xa || yb <= ya) return null;

    final values = <double>[];
    for (var y = ya; y < yb; y++) {
      final rowOffset = y * width;
      for (var x = xa; x < xb; x++) {
        values.add(data[rowOffset + x]);
      }
    }
    values.sort();
    final n = values.length;
    if (n.isOdd) return values[n ~/ 2];
    return (values[n ~/ 2 - 1] + values[n ~/ 2]) / 2.0;
  }
}
