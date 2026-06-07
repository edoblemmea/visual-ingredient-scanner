import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/asset_catalog.dart';
import '../services/density_service.dart';
import '../state/scan_controller.dart';
import '../state/settings_provider.dart';

/// FR3 — editable density table. Searchable list of all classes with their
/// current kg/m³ (override or baseline), per-row + global reset. Edits persist
/// and recompute the current scan's weights live (G6).
class DensityEditorScreen extends StatefulWidget {
  const DensityEditorScreen({super.key});

  @override
  State<DensityEditorScreen> createState() => _DensityEditorScreenState();
}

class _DensityEditorScreenState extends State<DensityEditorScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final catalog = context.read<AppCatalog>();
    final settings = context.watch<SettingsProvider>();
    final density = DensityService(
      baseline: catalog.densities,
      overrides: settings.settings.densityOverrides,
    );

    final q = _query.trim().toLowerCase();
    final classes = (catalog.labels.where((c) => c.contains(q)).toList())
      ..sort();
    final hasOverrides = settings.settings.densityOverrides.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Density table'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Reset all',
            onPressed: hasOverrides ? () => _resetAll(settings) : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
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
              itemCount: classes.length,
              itemBuilder: (context, i) {
                final name = classes[i];
                final overridden = density.isOverridden(name);
                return ListTile(
                  title: Text(name),
                  subtitle: Text(
                    '${density.densityFor(name).round()} kg/m³'
                    '${overridden ? '  ·  edited (default ${density.baselineFor(name).round()})' : ''}',
                  ),
                  trailing: overridden
                      ? IconButton(
                          icon: const Icon(Icons.undo),
                          tooltip: 'Reset to default',
                          onPressed: () => _clear(settings, name),
                        )
                      : null,
                  onTap: () => _edit(settings, name, density.densityFor(name)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(
    SettingsProvider settings,
    String name,
    double current,
  ) async {
    final controller = TextEditingController(text: current.round().toString());
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(suffixText: 'kg/m³'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null && value > 0) {
      await settings.setDensityOverride(name, value);
      _recompute(settings);
    }
  }

  Future<void> _clear(SettingsProvider settings, String name) async {
    await settings.clearDensityOverride(name);
    _recompute(settings);
  }

  Future<void> _resetAll(SettingsProvider settings) async {
    await settings.clearAllDensityOverrides();
    _recompute(settings);
  }

  /// Push the new overrides into the current scan so weights update live (G6).
  void _recompute(SettingsProvider settings) {
    if (!mounted) return;
    context.read<ScanController>().updateSettings(settings.settings);
  }
}
