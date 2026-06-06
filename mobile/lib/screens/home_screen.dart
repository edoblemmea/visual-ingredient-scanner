import 'package:flutter/material.dart';

import 'settings_screen.dart';

/// Landing screen. The scan flow (camera capture → results) lands in later
/// implementation steps; for now this is the entry point and the route into
/// settings.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scan (coming soon)'),
              onPressed: null,
            ),
          ],
        ),
      ),
    );
  }
}
