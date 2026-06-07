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
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/branding/app_icon.png',
                        width: 168,
                        height: 168,
                        semanticLabel: 'Foodie Lens',
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Scan ingredients, confirm weights, and turn them into recipes.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 28),
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 64,
                            child: FilledButton.icon(
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Scan'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ScanScreen(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 64,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.bookmarks_outlined),
                              label: const Text('My recipes'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const SavedRecipesScreen(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Text(
                '${catalog.labels.length} classes loaded · $detectorLabel · $depthLabel',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
