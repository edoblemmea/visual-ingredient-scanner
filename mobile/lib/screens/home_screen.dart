import 'package:flutter/material.dart';

import '../services/asset_catalog.dart';
import 'settings_screen.dart';

/// Landing screen. Loads the bundled model registry + labels + density table at
/// startup (proving the assets bundle and parse). The scan flow lands in later
/// steps; for now this is the entry point and the route into settings.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Future<AppCatalog> _catalog = AppCatalog.load();

  @override
  Widget build(BuildContext context) {
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
      body: FutureBuilder<AppCatalog>(
        future: _catalog,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load bundled assets:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            );
          }
          return _HomeBody(catalog: snapshot.requireData);
        },
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.catalog});

  final AppCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final registry = catalog.registry;
    return Center(
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
            '${registry.detectors.length} detectors · '
            '${registry.depth.length} depth models · '
            '${catalog.labels.length} classes loaded',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.camera_alt),
            label: const Text('Scan (coming soon)'),
            onPressed: null,
          ),
        ],
      ),
    );
  }
}
