import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../models/depth_map.dart';
import '../models/detection.dart';
import '../models/weighted_item.dart';
import '../services/depth_visualizer.dart';
import '../state/scan_controller.dart';
import '../state/settings_provider.dart';
import '../widgets/bbox_overlay.dart';
import 'annotate_screen.dart';
import 'recipe_screen.dart';

/// Shows the scan outcome: per-ingredient weights with expandable detail,
/// recipes, and optional debug overlays (bbox / depth map, FR5).
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ScanController>(
      builder: (context, controller, _) {
        final result = controller.result;
        final canGetRecipes =
            controller.status == ScanStatus.success && !result.isEmpty;
        return Scaffold(
          appBar: AppBar(title: const Text('Detected ingredients')),
          bottomNavigationBar: canGetRecipes
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.restaurant_menu),
                      label: const Text('Get recipes'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RecipeScreen(
                            ingredientWeights: Map.unmodifiable(
                              result.ingredientWeights,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : null,
          body: switch (controller.status) {
            ScanStatus.running => const _Centered(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Analyzing…'),
                ],
              ),
            ),
            ScanStatus.error => _Centered(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _ScanErrorState(
                  message: controller.error ?? 'Unknown scan error',
                ),
              ),
            ),
            ScanStatus.idle => const _Centered(child: _NoScanState()),
            ScanStatus.success => _ResultList(
              controller: controller,
              settings: context.watch<SettingsProvider>().settings,
            ),
          },
        );
      },
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.controller, required this.settings});

  final ScanController controller;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final result = controller.result;
    if (result.isEmpty) {
      return _EmptyResultState(
        controller: controller,
        showTiming: settings.showBoxes || settings.showDepthMap,
      );
    }
    final items = result.items;
    return ListView(
      children: [
        _ScanStats(
          duration: controller.scanDuration,
          items: items.length,
          depthScale: controller.depthScale,
        ),
        _ScanMedia(
          controller: controller,
          items: items,
          imageBytes: controller.imageBytes,
          depthMap: controller.depthMap,
          showBoxes: settings.showBoxes,
          showDepthMap: settings.showDepthMap,
        ),
        if (!settings.showBoxes && !settings.showDepthMap)
          _EditIngredientsButton(controller: controller),
        _DistanceCorrection(controller: controller, items: items),
        const Divider(height: 16),
        _IngredientSummary(items: items),
        const SizedBox(height: 104),
      ],
    );
  }
}

class _EditIngredientsButton extends StatelessWidget {
  const _EditIngredientsButton({required this.controller});

  final ScanController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.edit_location_alt_outlined),
        label: const Text('Edit ingredients'),
        onPressed: controller.hasScan
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AnnotateScreen()),
              )
            : null,
      ),
    );
  }
}

class _ScanMedia extends StatelessWidget {
  const _ScanMedia({
    required this.controller,
    required this.items,
    required this.imageBytes,
    required this.depthMap,
    required this.showBoxes,
    required this.showDepthMap,
  });

  final ScanController controller;
  final List<WeightedItem> items;
  final Uint8List? imageBytes;
  final DepthMap? depthMap;
  final bool showBoxes;
  final bool showDepthMap;

  @override
  Widget build(BuildContext context) {
    if (!showBoxes && !showDepthMap) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: _DebugViews(
        imageBytes: imageBytes,
        depthMap: depthMap,
        items: items,
        showBoxes: showBoxes,
        showDepthMap: showDepthMap,
        editButton: _FloatingEditButton(controller: controller),
      ),
    );
  }
}

class _FloatingEditButton extends StatelessWidget {
  const _FloatingEditButton({required this.controller});

  final ScanController controller;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      icon: const Icon(Icons.edit_location_alt_outlined),
      label: const Text('Edit'),
      onPressed: controller.hasScan
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AnnotateScreen()),
            )
          : null,
    );
  }
}

class _IngredientSummary extends StatelessWidget {
  const _IngredientSummary({required this.items});

  final List<WeightedItem> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          'Ingredients',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      for (final item in items) _ItemTile(item: item),
    ],
  );
}

class _ScanErrorState extends StatelessWidget {
  const _ScanErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
        const SizedBox(height: 12),
        Text('Scan failed', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          icon: const Icon(Icons.camera_alt),
          label: const Text('Back to scan'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

class _NoScanState extends StatelessWidget {
  const _NoScanState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.camera_alt_outlined, size: 56),
          const SizedBox(height: 12),
          Text('No scan yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.camera_alt),
            label: const Text('Start scan'),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class _EmptyResultState extends StatelessWidget {
  const _EmptyResultState({required this.controller, required this.showTiming});

  final ScanController controller;
  final bool showTiming;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (showTiming)
          _ScanStats(
            duration: controller.scanDuration,
            items: 0,
            depthScale: controller.depthScale,
          ),
        const SizedBox(height: 32),
        const Icon(Icons.search_off, size: 56),
        const SizedBox(height: 12),
        Text(
          'No ingredients detected',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Lower the confidence threshold, try another angle, or add visible items manually.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: const Text('Edit items'),
              onPressed: controller.hasScan
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AnnotateScreen(),
                      ),
                    )
                  : null,
            ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scan again'),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ],
    );
  }
}

class _ScanStats extends StatelessWidget {
  const _ScanStats({
    required this.duration,
    required this.items,
    required this.depthScale,
  });

  final Duration? duration;
  final int items;
  final double depthScale;

  @override
  Widget build(BuildContext context) {
    final elapsed = duration == null
        ? 'not recorded'
        : '${(duration!.inMilliseconds / 1000).toStringAsFixed(2)} s';
    final scale = depthScale == 1.0
        ? null
        : 'scale ×${depthScale.toStringAsFixed(2)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(avatar: const Icon(Icons.timer, size: 18), label: Text(elapsed)),
          Chip(
            avatar: const Icon(Icons.scale, size: 18),
            label: Text('$items weighed'),
          ),
          if (scale != null)
            Chip(
              avatar: const Icon(Icons.straighten, size: 18),
              label: Text(scale),
            ),
        ],
      ),
    );
  }
}

/// FR6 — manual scale anchor. Pick a detected object and set its real
/// camera-to-object distance; the controller rescales the cached depth and
/// recomputes all weights (G6). Applied on slider release to avoid copying the
/// depth map on every tick.
class _DistanceCorrection extends StatefulWidget {
  const _DistanceCorrection({required this.controller, required this.items});

  final ScanController controller;
  final List<WeightedItem> items;

  @override
  State<_DistanceCorrection> createState() => _DistanceCorrectionState();
}

class _DistanceCorrectionState extends State<_DistanceCorrection> {
  static const double _min = 0.10;
  static const double _max = 1.20;

  int _selected = 0;
  late double _distanceM = _clampedDepth(widget.items[_selected]);

  double _clampedDepth(WeightedItem item) =>
      item.depthM.clamp(_min, _max).toDouble();

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (_selected >= items.length) _selected = 0;
    final corrected = widget.controller.depthScale != 1.0;

    return ExpansionTile(
      leading: const Icon(Icons.straighten),
      title: const Text('Adjust scale (optional)'),
      subtitle: Text(
        corrected
            ? 'Scale ×${widget.controller.depthScale.toStringAsFixed(2)}'
            : 'Set a known distance if sizes look off',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        DropdownButton<int>(
          isExpanded: true,
          value: _selected,
          items: [
            for (var i = 0; i < items.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text(
                  '${items[i].className} '
                  '(${(items[i].depthM * 100).toStringAsFixed(0)} cm)',
                ),
              ),
          ],
          onChanged: (v) => setState(() {
            _selected = v!;
            _distanceM = _clampedDepth(items[_selected]);
          }),
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _distanceM.clamp(_min, _max),
                min: _min,
                max: _max,
                divisions: ((_max - _min) / 0.01).round(),
                label: '${(_distanceM * 100).round()} cm',
                onChanged: (v) => setState(() => _distanceM = v),
                onChangeEnd: (v) => widget.controller.applyDistanceCorrection(
                  items[_selected].detection,
                  v,
                ),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                '${(_distanceM * 100).round()} cm',
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        if (corrected)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.undo),
              label: const Text('Reset scale'),
              onPressed: () {
                widget.controller.resetDistanceCorrection();
                setState(() => _distanceM = _clampedDepth(items[_selected]));
              },
            ),
          ),
      ],
    );
  }
}

/// Debug overlays (FR5): the captured image with detection boxes, and a
/// colour-mapped depth map. Hidden unless the matching setting is on. The depth
/// PNG is rendered once per depth map and cached.
class _DebugViews extends StatefulWidget {
  const _DebugViews({
    required this.imageBytes,
    required this.depthMap,
    required this.items,
    required this.showBoxes,
    required this.showDepthMap,
    required this.editButton,
  });

  final Uint8List? imageBytes;
  final DepthMap? depthMap;
  final List<WeightedItem> items;
  final bool showBoxes;
  final bool showDepthMap;
  final Widget editButton;

  @override
  State<_DebugViews> createState() => _DebugViewsState();
}

class _DebugViewsState extends State<_DebugViews> {
  Uint8List? _depthPng;
  DepthMap? _renderedFor;

  @override
  void initState() {
    super.initState();
    _maybeRenderDepth();
  }

  @override
  void didUpdateWidget(_DebugViews old) {
    super.didUpdateWidget(old);
    _maybeRenderDepth();
  }

  Future<void> _maybeRenderDepth() async {
    final depth = widget.depthMap;
    if (!widget.showDepthMap ||
        depth == null ||
        identical(depth, _renderedFor)) {
      return;
    }
    _renderedFor = depth;
    final png = await Future(() => renderDepthMapPng(depth));
    if (mounted) setState(() => _depthPng = png);
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (widget.showBoxes && widget.imageBytes != null) {
      final depth = widget.depthMap;
      children.add(
        AspectRatio(
          aspectRatio: depth != null && depth.height > 0
              ? depth.width / depth.height
              : 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(widget.imageBytes!, fit: BoxFit.fill),
              if (depth != null)
                CustomPaint(
                  painter: BoxOverlayPainter(
                    items: widget.items,
                    imageWidth: depth.width,
                    imageHeight: depth.height,
                  ),
                ),
              Positioned(top: 12, right: 12, child: widget.editButton),
            ],
          ),
        ),
      );
    }

    if (widget.showDepthMap && _depthPng != null) {
      children.add(
        Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(_depthPng!, fit: BoxFit.contain),
          ),
        ),
      );
    }

    if (children.isEmpty) {
      return Align(alignment: Alignment.centerRight, child: widget.editButton);
    }
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final WeightedItem item;

  @override
  Widget build(BuildContext context) {
    final det = item.detection;
    return ExpansionTile(
      leading: Icon(_sourceIcon(det)),
      title: Text(det.className),
      subtitle: Text('${item.weightG.round()} g · ${_sourceLabel(det)}'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        _detail('Shape', item.shape.name),
        if (det.isRelabeled && det.source != null)
          _detail(
            'Model label',
            '${det.source!.className} '
                '(${(det.source!.confidence * 100).round()} %)',
          )
        else if (det.origin == DetectionOrigin.model)
          _detail('Model confidence', '${(det.confidence * 100).round()} %'),
        _detail('Depth', '${(item.depthM * 100).toStringAsFixed(1)} cm'),
        _detail(
          'Size',
          '${(item.realWidthM * 100).toStringAsFixed(1)} × '
              '${(item.realHeightM * 100).toStringAsFixed(1)} cm',
        ),
        _detail('Density', '${item.densityKgM3.round()} kg/m³'),
        if (det.origin == DetectionOrigin.smart)
          _detail('Source', 'smart selection')
        else if (det.origin == DetectionOrigin.manual)
          _detail('Source', 'manual selection'),
      ],
    );
  }

  IconData _sourceIcon(Detection det) {
    if (det.isRelabeled) return Icons.edit;
    return switch (det.origin) {
      DetectionOrigin.model => Icons.center_focus_strong,
      DetectionOrigin.smart || DetectionOrigin.manual => Icons.add_circle,
    };
  }

  String _sourceLabel(Detection det) {
    if (det.isRelabeled) return 'AI + Manual edit';
    return switch (det.origin) {
      DetectionOrigin.model => 'AI detected',
      DetectionOrigin.smart || DetectionOrigin.manual => 'New ingredient',
    };
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label), Text(value)],
    ),
  );
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(child: child);
}
