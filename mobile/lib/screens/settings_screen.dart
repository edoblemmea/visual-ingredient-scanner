import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/asset_catalog.dart';
import '../state/settings_provider.dart';
import 'density_editor_screen.dart';

/// Settings: detector + depth model selection (applied on the next scan),
/// confidence threshold, and the Gemini API key. The density editor (S13),
/// visualisation toggles (S14) land in later steps.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final registry = context.read<AppCatalog>().registry;
    final settings = context.watch<SettingsProvider>();
    final choice = settings.modelChoice;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Detector model'),
          RadioGroup<String>(
            groupValue: choice.detectorId,
            onChanged: (v) => settings.setDetector(v!),
            child: Column(
              children: [
                for (final d in registry.detectors)
                  RadioListTile<String>(value: d.id, title: Text(d.label)),
              ],
            ),
          ),
          const Divider(),
          const _SectionHeader('Depth model'),
          RadioGroup<String>(
            groupValue: choice.depthId,
            onChanged: (v) => settings.setDepth(v!),
            child: Column(
              children: [
                for (final d in registry.depth)
                  RadioListTile<String>(
                    value: d.id,
                    title: Text(d.label),
                    subtitle: d.requiresManualDownload
                        ? const Text(
                            'Needs a manually downloaded model file (see README)',
                            style: TextStyle(fontStyle: FontStyle.italic),
                          )
                        : null,
                  ),
              ],
            ),
          ),
          const _Hint('Model changes apply on the next scan.'),
          const Divider(),
          const _SectionHeader('Density table'),
          ListTile(
            leading: const Icon(Icons.scale),
            title: const Text('Edit ingredient densities'),
            subtitle: const Text('Tune kg/m³ per class; recomputes weights'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DensityEditorScreen()),
            ),
          ),
          const Divider(),
          const _SectionHeader('Detection confidence'),
          _ConfidenceSlider(settings: settings),
          const Divider(),
          const _SectionHeader('Developer view'),
          SwitchListTile(
            title: const Text('Show bounding boxes'),
            subtitle: const Text('Overlay detections on the scanned image'),
            value: settings.settings.showBoxes,
            onChanged: settings.setShowBoxes,
          ),
          SwitchListTile(
            title: const Text('Show depth map'),
            subtitle: const Text('Colour-mapped depth of the last scan'),
            value: settings.settings.showDepthMap,
            onChanged: settings.setShowDepthMap,
          ),
          const Divider(),
          const _SectionHeader('Gemini API key'),
          _ApiKeyField(settings: settings),
          const _Hint('Used only for recipe generation. Stored on this device.'),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ConfidenceSlider extends StatelessWidget {
  const _ConfidenceSlider({required this.settings});

  final SettingsProvider settings;

  @override
  Widget build(BuildContext context) {
    final value = settings.settings.confidenceThreshold;
    return ListTile(
      title: Slider(
        value: value.clamp(0.05, 0.9),
        min: 0.05,
        max: 0.9,
        divisions: 17,
        label: value.toStringAsFixed(2),
        onChanged: settings.setConfidenceThreshold,
      ),
      trailing: Text(value.toStringAsFixed(2)),
    );
  }
}

class _ApiKeyField extends StatefulWidget {
  const _ApiKeyField({required this.settings});

  final SettingsProvider settings;

  @override
  State<_ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends State<_ApiKeyField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.settings.settings.geminiApiKey);
  bool _obscured = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _controller,
        obscureText: _obscured,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          hintText: 'Paste your Gemini API key',
          suffixIcon: IconButton(
            icon: Icon(_obscured ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscured = !_obscured),
          ),
        ),
        onChanged: widget.settings.setGeminiApiKey,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}
