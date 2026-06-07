import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/asset_catalog.dart';
import '../state/settings_provider.dart';
import 'saved_recipes_screen.dart';
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
    final depthLabel = catalog.registry.depth
        .firstWhere((d) => d.id == choice.depthId)
        .label;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Foodie Lens'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
            Center(
              child: Image.asset(
                'assets/branding/app_icon.png',
                width: 168,
                height: 168,
                semanticLabel: 'Foodie Lens',
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Scan ingredients, confirm weights, and turn them into recipes.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scan ingredients'),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ScanScreen())),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.bookmarks_outlined),
              label: const Text('My recipes'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SavedRecipesScreen()),
              ),
            ),
            const SizedBox(height: 28),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text('${catalog.labels.length} classes loaded'),
              subtitle: Text('Detector: $detectorLabel\nDepth: $depthLabel'),
            ),
          ],
        ),
      ),
    );
  }
}
