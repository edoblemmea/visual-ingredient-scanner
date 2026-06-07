import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/model_manager_provider.dart';

/// Shown when required models are not on disk. Each model has an explicit
/// Download button — nothing starts automatically. The "Get started" button
/// appears once both defaults are ready.
class ModelDownloadScreen extends StatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.88, end: 1.08).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _startDownloads());
  }

  Future<void> _startDownloads() async {
    final manager = context.read<ModelManagerProvider>();
    final registry = manager.registry;
    final futures = <Future<void>>[];
    // Only download a type if NO model of that type is on disk — mirrors the
    // banner's pending logic so we never download a model the user doesn't need.
    final anyDetectorReady =
        registry.detectors.any((d) => manager.isDownloaded(d.id));
    final anyDepthReady =
        registry.depth.any((d) => manager.isDownloaded(d.id));
    if (!anyDetectorReady) {
      futures.add(manager.downloadModel(registry.defaultDetector.id));
    }
    if (!anyDepthReady) {
      futures.add(manager.downloadModel(registry.defaultDepth.id));
    }
    await Future.wait(futures);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<ModelManagerProvider>();
    final registry = manager.registry;
    final theme = Theme.of(context);

    final needsDetector =
        !registry.detectors.any((d) => manager.isDownloaded(d.id));
    final needsDepth =
        !registry.depth.any((d) => manager.isDownloaded(d.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Download models'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: ScaleTransition(
                  scale: _scale,
                  child: Image.asset(
                    'assets/branding/app_icon.png',
                    width: 100,
                    height: 100,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Download required models',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'These AI models run entirely on your device. Download once, use offline.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              if (needsDetector)
                _ModelRow(
                  label: registry.defaultDetector.label,
                  subtitle: 'Ingredient detector',
                  modelId: registry.defaultDetector.id,
                  sizeMb: (registry.defaultDetector.sizeBytes / (1024 * 1024))
                      .round(),
                  manager: manager,
                ),
              if (needsDetector && needsDepth) const SizedBox(height: 20),
              if (needsDepth)
                _ModelRow(
                  label: registry.defaultDepth.label,
                  subtitle: 'Depth estimation',
                  modelId: registry.defaultDepth.id,
                  sizeMb:
                      (registry.defaultDepth.totalSizeBytes / (1024 * 1024))
                          .round(),
                  manager: manager,
                ),
              const Spacer(),
              Text(
                'More models are available to be downloaded and managed in Settings → Manage models.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              AnimatedOpacity(
                opacity: manager.anySetReady ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: manager.anySetReady
                        ? () => Navigator.of(context).pop()
                        : null,
                    child: const Text('Get started'),
                  ),
                ),
              ),
              if (!manager.anySetReady) const SizedBox(height: 56),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.label,
    required this.subtitle,
    required this.modelId,
    required this.sizeMb,
    required this.manager,
  });

  final String label;
  final String subtitle;
  final String modelId;
  final int sizeMb;
  final ModelManagerProvider manager;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = manager.stateFor(modelId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyMedium),
                  Text(
                    subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (state.isDownloaded)
              Row(
                children: [
                  Icon(Icons.check_circle,
                      color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    'Ready',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              )
            else if (state.isDownloading)
              Text(
                '${(state.progress * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              FilledButton.tonal(
                onPressed: () => manager.downloadModel(modelId),
                child: Text('Download ($sizeMb MB)'),
              ),
          ],
        ),
        if (!state.isDownloaded) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: state.isDownloaded
                ? 1.0
                : state.isDownloading && state.progress > 0
                    ? state.progress
                    : state.isDownloading
                        ? null
                        : 0.0,
          ),
        ],
        if (state.status == DownloadStatus.error && state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.error!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => manager.downloadModel(modelId),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
