import 'package:flutter/material.dart';

import '../models/detection.dart';
import '../models/weighted_item.dart';

/// Draws detection boxes + labels over the captured image, scaling from the
/// original image pixel space to the painted canvas. Used by the debug bbox
/// overlay (FR5).
class BoxOverlayPainter extends CustomPainter {
  BoxOverlayPainter({
    required this.items,
    required this.imageWidth,
    required this.imageHeight,
  });

  final List<WeightedItem> items;
  final int imageWidth;
  final int imageHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / imageWidth;
    final sy = size.height / imageHeight;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final item in items) {
      final b = item.detection.bbox;
      final color = _detectionColor(item.detection);
      final rect = Rect.fromLTRB(b.x1 * sx, b.y1 * sy, b.x2 * sx, b.y2 * sy);
      canvas.drawRect(rect, stroke..color = color);

      final label = '${item.className} ${item.weightG.round()}g';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelTop = (rect.top - tp.height).clamp(0.0, size.height);
      canvas.drawRect(
        Rect.fromLTWH(rect.left, labelTop, tp.width + 4, tp.height),
        Paint()..color = color,
      );
      tp.paint(canvas, Offset(rect.left + 2, labelTop));
    }
  }

  @override
  bool shouldRepaint(BoxOverlayPainter old) =>
      old.items != items ||
      old.imageWidth != imageWidth ||
      old.imageHeight != imageHeight;

  Color _detectionColor(Detection det) {
    if (det.isRelabeled) return Colors.yellowAccent;
    return switch (det.origin) {
      DetectionOrigin.model => Colors.greenAccent,
      DetectionOrigin.smart => Colors.lightBlueAccent,
      DetectionOrigin.manual => Colors.orangeAccent,
    };
  }
}
