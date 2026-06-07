import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/asset_catalog.dart';
import '../state/model_manager_provider.dart';
import '../state/settings_provider.dart';
import 'model_download_screen.dart';
import 'saved_recipes_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.read<AppCatalog>();
    final settings = context.watch<SettingsProvider>();
    final choice = settings.modelChoice;
    final modelManager = context.watch<ModelManagerProvider>();
    final canScan = modelManager.canScan(choice.detectorId, choice.depthId);
    final registry = catalog.registry;

    // A type is "covered" if ANY model of that type is on disk, regardless of
    // which specific checkpoint is selected. Only missing types contribute to
    // the pending download size shown in the banner.
    final anyDetectorReady =
        registry.detectors.any((d) => modelManager.isDownloaded(d.id));
    final anyDepthReady =
        registry.depth.any((d) => modelManager.isDownloaded(d.id));

    var pendingBytes = 0;
    if (!anyDetectorReady) pendingBytes += registry.defaultDetector.sizeBytes;
    if (!anyDepthReady) pendingBytes += registry.defaultDepth.totalSizeBytes;

    final detectorLabel =
        registry.detectors.firstWhere((d) => d.id == choice.detectorId).label;
    final depthLabel =
        registry.depth.firstWhere((d) => d.id == choice.depthId).label;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Foodie Lens'),
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
      body: SafeArea(
        child: Column(
          children: [
            if (!canScan)
              _DownloadBanner(
                manager: modelManager,
                needsDetector: !anyDetectorReady,
                needsDepth: !anyDepthReady,
                pendingBytes: pendingBytes,
                onDownload: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ModelDownloadScreen(),
                  ),
                ),
              ),
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
                              onPressed: canScan
                                  ? () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const ScanScreen(),
                                        ),
                                      )
                                  : null,
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

class _DownloadBanner extends StatelessWidget {
  const _DownloadBanner({
    required this.manager,
    required this.needsDetector,
    required this.needsDepth,
    required this.pendingBytes,
    required this.onDownload,
  });

  final ModelManagerProvider manager;
  final bool needsDetector;
  final bool needsDepth;
  final int pendingBytes;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final registry = manager.registry;

    // Edge case: user has a model of each type but the selected ones aren't
    // downloaded — steer them toward Settings instead of re-downloading defaults.
    if (!needsDetector && !needsDepth) {
      return ColoredBox(
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  color: theme.colorScheme.onTertiaryContainer, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Selected models not downloaded. '
                  'Change selection in Settings → Manage models.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final pendingMb = (pendingBytes / (1024 * 1024)).round();

    // Determine overall download progress for the pending model types.
    var downloadingWeightedSum = 0.0;
    var downloadingTotalBytes = 0;
    var isAnyDownloading = false;

    if (needsDetector) {
      final s = manager.stateFor(registry.defaultDetector.id);
      if (s.isDownloading) {
        isAnyDownloading = true;
        final bytes = registry.defaultDetector.sizeBytes;
        downloadingWeightedSum += s.progress * bytes;
        downloadingTotalBytes += bytes;
      }
    }
    if (needsDepth) {
      final s = manager.stateFor(registry.defaultDepth.id);
      if (s.isDownloading) {
        isAnyDownloading = true;
        final bytes = registry.defaultDepth.totalSizeBytes;
        downloadingWeightedSum += s.progress * bytes;
        downloadingTotalBytes += bytes;
      }
    }
    final overallProgress = downloadingTotalBytes > 0
        ? downloadingWeightedSum / downloadingTotalBytes
        : 0.0;

    return ColoredBox(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.download_for_offline_outlined,
                    color: theme.colorScheme.onPrimaryContainer, size: 22),
                const SizedBox(width: 8),
                Text(
                  'AI models required to scan',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (needsDetector)
              _ModelLine(
                name: registry.defaultDetector.label,
                sizeMb:
                    (registry.defaultDetector.sizeBytes / (1024 * 1024)).round(),
                theme: theme,
              ),
            if (needsDetector && needsDepth) const SizedBox(height: 4),
            if (needsDepth)
              _ModelLine(
                name: registry.defaultDepth.label,
                sizeMb: (registry.defaultDepth.totalSizeBytes / (1024 * 1024))
                    .round(),
                theme: theme,
              ),
            const SizedBox(height: 16),
            if (isAnyDownloading) ...[
              LinearProgressIndicator(
                value: overallProgress > 0 ? overallProgress : null,
                backgroundColor: theme.colorScheme.onPrimaryContainer
                    .withValues(alpha: 0.15),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                icon: Icon(
                  isAnyDownloading ? Icons.downloading : Icons.download,
                ),
                label: Text(
                  isAnyDownloading
                      ? 'Downloading…  ${(overallProgress * 100).toStringAsFixed(0)}%'
                      : 'Download  ($pendingMb MB)',
                ),
                onPressed: onDownload,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelLine extends StatelessWidget {
  const _ModelLine({required this.name, required this.sizeMb, required this.theme});

  final String name;
  final int sizeMb;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.circle, size: 6,
            color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        Text(
          '$sizeMb MB',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
