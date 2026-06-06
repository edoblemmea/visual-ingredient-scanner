import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/scan_result.dart';
import '../models/weighted_item.dart';
import '../state/scan_controller.dart';

/// Shows the scan outcome: per-ingredient weights with expandable detail.
/// Recipes are added in S11; visualisations/corrections in S14–S16.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: Consumer<ScanController>(
        builder: (context, controller, _) {
          switch (controller.status) {
            case ScanStatus.running:
              return const _Centered(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Analyzing…'),
                  ],
                ),
              );
            case ScanStatus.error:
              return _Centered(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Scan failed:\n${controller.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              );
            case ScanStatus.idle:
              return const _Centered(child: Text('No scan yet.'));
            case ScanStatus.success:
              return _ResultList(result: controller.result);
          }
        },
      ),
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.result});

  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    if (result.isEmpty) {
      return const _Centered(child: Text('No ingredients detected.'));
    }
    final items = result.items;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '${items.length} items · ${result.ingredientWeights.length} ingredients',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final item in items) _ItemTile(item: item),
      ],
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
      leading: det.isManual ? const Icon(Icons.edit) : const Icon(Icons.label),
      title: Text(det.className),
      subtitle: Text('${item.weightG.round()} g'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        _detail('Shape', item.shape.name),
        _detail('Confidence', '${(det.confidence * 100).round()} %'),
        _detail('Depth', '${(item.depthM * 100).toStringAsFixed(1)} cm'),
        _detail(
          'Size',
          '${(item.realWidthM * 100).toStringAsFixed(1)} × '
              '${(item.realHeightM * 100).toStringAsFixed(1)} cm',
        ),
        _detail('Density', '${item.densityKgM3.round()} kg/m³'),
        if (det.isManual) _detail('Source', 'manually added'),
      ],
    );
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value),
          ],
        ),
      );
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(child: child);
}
