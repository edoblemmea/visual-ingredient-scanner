import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bbox.dart';
import '../models/detection.dart';
import '../services/asset_catalog.dart';
import '../state/scan_controller.dart';

/// S16 (FR7) — annotate the captured image: add boxes for missed items, relabel
/// or remove existing ones.
///
/// Two placement modes, toggled by the app-bar switch:
///  • **Smart** (default): tap the centre of an object; the box is auto-sized
///    from the depth map ([ScanController.smartBoxAt]).
///  • **Manual**: drag a rectangle by hand.
///
/// In both modes the new box opens a class picker. Tapping an existing box
/// offers relabel / remove. All edits recompute weights live (G6); nothing is
/// re-run through the models.
class AnnotateScreen extends StatefulWidget {
  const AnnotateScreen({super.key});

  @override
  State<AnnotateScreen> createState() => _AnnotateScreenState();
}

class _AnnotateScreenState extends State<AnnotateScreen> {
  bool _smart = true;

  // In-progress manual rectangle drag, in original-image pixel coordinates.
  Offset? _dragStart;
  Offset? _dragCurrent;

  // In-progress smart-mode lasso loop, in original-image pixel coordinates.
  final List<Offset> _loop = [];

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ScanController>();
    final imageBytes = controller.imageBytes;
    final imgW = controller.imageWidth;
    final imgH = controller.imageHeight;

    if (imageBytes == null || imgW == 0 || imgH == 0) {
      return Scaffold(
        appBar: AppBar(title: const Text('Annotate')),
        body: const Center(child: Text('No scan to annotate.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Annotate'),
        actions: [
          Row(
            children: [
              const Text('Smart'),
              Switch(
                value: _smart,
                onChanged: (v) => setState(() {
                  _smart = v;
                  _dragStart = null;
                  _dragCurrent = null;
                  _loop.clear();
                }),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _smart
                  ? 'Circle a missed item — the box snaps to it using depth. '
                        'Tap an existing box to edit it.'
                  : 'Drag to draw a box around a missed item.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: imgW / imgH,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final sx = constraints.maxWidth / imgW;
                    final sy = constraints.maxHeight / imgH;
                    Offset toImage(Offset local) =>
                        Offset(local.dx / sx, local.dy / sy);

                    return GestureDetector(
                      onTapUp: _smart
                          ? (d) => _onSmartTap(
                              context,
                              controller,
                              toImage(d.localPosition),
                            )
                          : (d) => _onExistingTap(
                              context,
                              controller,
                              toImage(d.localPosition),
                              sx,
                              sy,
                            ),
                      onPanStart: (d) => setState(() {
                        if (_smart) {
                          _loop
                            ..clear()
                            ..add(toImage(d.localPosition));
                        } else {
                          _dragStart = toImage(d.localPosition);
                          _dragCurrent = _dragStart;
                        }
                      }),
                      onPanUpdate: (d) => setState(() {
                        if (_smart) {
                          _loop.add(toImage(d.localPosition));
                        } else {
                          _dragCurrent = toImage(d.localPosition);
                        }
                      }),
                      onPanEnd: (_) => _smart
                          ? _onLoopDrawn(context, controller)
                          : _onManualDrawn(context, controller),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(imageBytes, fit: BoxFit.fill),
                          CustomPaint(
                            painter: _AnnotatePainter(
                              detections: controller.effectiveDetections,
                              draft: _draftBox(),
                              loop: List.unmodifiable(_loop),
                              imageWidth: imgW,
                              imageHeight: imgH,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  BBox? _draftBox() {
    final a = _dragStart;
    final b = _dragCurrent;
    if (a == null || b == null) return null;
    return BBox(
      a.dx < b.dx ? a.dx : b.dx,
      a.dy < b.dy ? a.dy : b.dy,
      a.dx < b.dx ? b.dx : a.dx,
      a.dy < b.dy ? b.dy : a.dy,
    );
  }

  Future<void> _onSmartTap(
    BuildContext context,
    ScanController controller,
    Offset p,
  ) async {
    // In smart mode a tap edits an existing box; new items are circled (drag).
    final hit = _hitTest(controller, p);
    if (hit != null) await _editExisting(context, controller, hit);
  }

  Future<void> _onLoopDrawn(
    BuildContext context,
    ScanController controller,
  ) async {
    final loop = _loop.map((o) => (o.dx, o.dy)).toList();
    setState(() => _loop.clear());
    if (loop.length < 3) return; // a tap, not a circle — handled by onTapUp
    final box = controller.boxFromLoop(loop);
    if (box == null || box.width < 6 || box.height < 6) {
      _toast(context, 'Circle a bit larger around the item.');
      return;
    }
    await _pickClassAndAdd(context, controller, box);
  }

  Future<void> _onManualDrawn(
    BuildContext context,
    ScanController controller,
  ) async {
    final box = _draftBox();
    setState(() {
      _dragStart = null;
      _dragCurrent = null;
    });
    if (box == null || box.width < 6 || box.height < 6) return;
    await _pickClassAndAdd(
      context,
      controller,
      box.clampTo(controller.imageWidth, controller.imageHeight),
    );
  }

  Future<void> _onExistingTap(
    BuildContext context,
    ScanController controller,
    Offset p,
    double sx,
    double sy,
  ) async {
    final hit = _hitTest(controller, p);
    if (hit != null) await _editExisting(context, controller, hit);
  }

  Detection? _hitTest(ScanController controller, Offset p) {
    for (final det in controller.effectiveDetections.reversed) {
      final b = det.bbox;
      if (p.dx >= b.x1 && p.dx <= b.x2 && p.dy >= b.y1 && p.dy <= b.y2) {
        return det;
      }
    }
    return null;
  }

  Future<void> _pickClassAndAdd(
    BuildContext context,
    ScanController controller,
    BBox box,
  ) async {
    final cls = await _pickClass(context);
    if (cls == null) return;
    controller.addManualDetection(
      Detection(className: cls, confidence: 1.0, bbox: box, isManual: true),
    );
  }

  Future<void> _editExisting(
    BuildContext context,
    ScanController controller,
    Detection det,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(det.className),
              subtitle: Text(det.isManual ? 'Manually added' : 'Detected'),
            ),
            const Divider(height: 0),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Change label'),
              onTap: () => Navigator.pop(context, 'relabel'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove'),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'remove') {
      controller.removeDetection(det);
    } else if (action == 'relabel') {
      final cls = await _pickClass(context, current: det.className);
      if (cls != null) controller.relabelDetection(det, cls);
    }
  }

  /// Searchable picker over all density-table classes.
  Future<String?> _pickClass(BuildContext context, {String? current}) {
    final classes = (context.read<AppCatalog>().labels.toList())..sort();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ClassPicker(classes: classes, current: current),
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _ClassPicker extends StatefulWidget {
  const _ClassPicker({required this.classes, this.current});

  final List<String> classes;
  final String? current;

  @override
  State<_ClassPicker> createState() => _ClassPickerState();
}

class _ClassPickerState extends State<_ClassPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = widget.classes.where((c) => c.contains(q)).toList();
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search ingredient',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final name = filtered[i];
                  return ListTile(
                    title: Text(name),
                    trailing: name == widget.current
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.pop(context, name),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints existing detections (green = detected, orange = manual) plus the
/// in-progress manual draft (dashed-ish solid blue) over the captured image.
class _AnnotatePainter extends CustomPainter {
  _AnnotatePainter({
    required this.detections,
    required this.draft,
    required this.loop,
    required this.imageWidth,
    required this.imageHeight,
  });

  final List<Detection> detections;
  final BBox? draft;
  final List<Offset> loop; // in-progress smart-mode lasso (image px)
  final int imageWidth;
  final int imageHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / imageWidth;
    final sy = size.height / imageHeight;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final det in detections) {
      final b = det.bbox;
      final color = det.isManual ? Colors.orangeAccent : Colors.greenAccent;
      final rect = Rect.fromLTRB(b.x1 * sx, b.y1 * sy, b.x2 * sx, b.y2 * sy);
      canvas.drawRect(rect, stroke..color = color);

      final tp = TextPainter(
        text: TextSpan(
          text: det.className,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final top = (rect.top - tp.height).clamp(0.0, size.height);
      canvas.drawRect(
        Rect.fromLTWH(rect.left, top, tp.width + 4, tp.height),
        Paint()..color = color,
      );
      tp.paint(canvas, Offset(rect.left + 2, top));
    }

    if (draft != null) {
      final r = Rect.fromLTRB(
        draft!.x1 * sx,
        draft!.y1 * sy,
        draft!.x2 * sx,
        draft!.y2 * sy,
      );
      canvas.drawRect(r, stroke..color = Colors.lightBlueAccent);
    }

    if (loop.length > 1) {
      final path = Path()..moveTo(loop.first.dx * sx, loop.first.dy * sy);
      for (final p in loop.skip(1)) {
        path.lineTo(p.dx * sx, p.dy * sy);
      }
      canvas.drawPath(path, stroke..color = Colors.lightBlueAccent);
    }
  }

  @override
  bool shouldRepaint(_AnnotatePainter old) =>
      old.detections != detections ||
      old.draft != draft ||
      old.loop != loop ||
      old.imageWidth != imageWidth ||
      old.imageHeight != imageHeight;
}
