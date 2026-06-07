import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/model_registry.dart';
import '../state/model_manager_provider.dart';

/// Settings sub-screen listing all available models. Each entry shows its
/// download status and lets the user download or delete it individually.
class ModelManagerScreen extends StatelessWidget {
  const ModelManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<ModelManagerProvider>();
    final registry = manager.registry;

    return Scaffold(
      appBar: AppBar(title: const Text('Manage models')),
      body: ListView(
        children: [
          _SectionHeader('Detector models'),
          for (final det in registry.detectors)
            _DetectorTile(model: det, manager: manager),
          const Divider(),
          _SectionHeader('Depth models'),
          for (final dep in registry.depth)
            _DepthTile(model: dep, manager: manager),
          const SizedBox(height: 24),
        ],
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
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _DetectorTile extends StatelessWidget {
  const _DetectorTile({required this.model, required this.manager});
  final DetectorModel model;
  final ModelManagerProvider manager;

  @override
  Widget build(BuildContext context) => _ModelTile(
    id: model.id,
    label: model.label,
    sizeMb: '${(model.sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB',
    isDefault: model.isDefault,
    state: manager.stateFor(model.id),
    manager: manager,
  );
}

class _DepthTile extends StatelessWidget {
  const _DepthTile({required this.model, required this.manager});
  final DepthModel model;
  final ModelManagerProvider manager;

  @override
  Widget build(BuildContext context) => _ModelTile(
    id: model.id,
    label: model.label,
    sizeMb: '${(model.totalSizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB',
    isDefault: model.isDefault,
    state: manager.stateFor(model.id),
    manager: manager,
  );
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.id,
    required this.label,
    required this.sizeMb,
    required this.isDefault,
    required this.state,
    required this.manager,
  });

  final String id;
  final String label;
  final String sizeMb;
  final bool isDefault;
  final ModelDownloadState state;
  final ModelManagerProvider manager;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      isThreeLine: state.isDownloading,
      title: Row(
        children: [
          Expanded(child: Text(label)),
          if (isDefault)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'default',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sizeMb),
          if (state.isDownloading) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: state.progress == 0.0 ? null : state.progress,
            ),
            const SizedBox(height: 2),
            Text(
              '${(state.progress * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.labelSmall,
            ),
          ],
          if (state.status == DownloadStatus.error && state.error != null)
            Text(
              state.error!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
      trailing: state.isDownloading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : state.isDownloaded
              ? IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(context),
                )
              : IconButton(
                  icon: const Icon(Icons.download),
                  tooltip: 'Download',
                  onPressed: () => manager.downloadModel(id),
                ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete model?'),
        content: Text('This will remove "$label" from your device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await manager.deleteModel(id);
  }
}
