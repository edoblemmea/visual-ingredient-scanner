import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/asset_catalog.dart';
import '../state/settings_provider.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

/// Landing screen. Reads the bundled catalog and live settings from providers
/// (loaded at bootstrap). The scan flow lands in later steps; for now this is
/// the entry point and the route into settings.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.read<AppCatalog>();
    final settings = context.watch<SettingsProvider>();
    final choice = settings.modelChoice;
    final detectorLabel = catalog.registry.detectors
        .firstWhere((d) => d.id == choice.detectorId)
        .label;
    final depthLabel =
        catalog.registry.depth.firstWhere((d) => d.id == choice.depthId).label;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Visual Ingredient Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.kitchen, size: 96),
            const SizedBox(height: 16),
            Text(
              'Scan a fridge or counter to detect\ningredients, weights, and recipes.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${catalog.labels.length} classes loaded',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Detector: $detectorLabel · Depth: $depthLabel',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scan'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ScanScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
