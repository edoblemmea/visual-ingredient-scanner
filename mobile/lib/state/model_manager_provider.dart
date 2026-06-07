import 'package:flutter/foundation.dart';

import '../models/model_registry.dart';
import '../services/model_download_service.dart';

enum DownloadStatus { idle, downloading, done, error }

class ModelDownloadState {
  const ModelDownloadState({
    this.status = DownloadStatus.idle,
    this.progress = 0.0,
    this.error,
  });

  final DownloadStatus status;
  final double progress;
  final String? error;

  bool get isDownloaded => status == DownloadStatus.done;
  bool get isDownloading => status == DownloadStatus.downloading;
}

/// Tracks which models are on-disk and orchestrates downloads / deletes.
class ModelManagerProvider extends ChangeNotifier {
  ModelManagerProvider({
    required this.modelsDir,
    required ModelRegistry registry,
    void Function(String id)? onFirstDetectorDownloaded,
    void Function(String id)? onFirstDepthDownloaded,
    String? Function()? getCurrentDetectorId,
    String? Function()? getCurrentDepthId,
  })  : _registry = registry,
        _onFirstDetectorDownloaded = onFirstDetectorDownloaded,
        _onFirstDepthDownloaded = onFirstDepthDownloaded,
        _getCurrentDetectorId = getCurrentDetectorId,
        _getCurrentDepthId = getCurrentDepthId;

  final void Function(String id)? _onFirstDetectorDownloaded;
  final void Function(String id)? _onFirstDepthDownloaded;
  final String? Function()? _getCurrentDetectorId;
  final String? Function()? _getCurrentDepthId;

  final String modelsDir;
  final ModelRegistry _registry;
  final Map<String, ModelDownloadState> _states = {};

  ModelRegistry get registry => _registry;

  bool isDownloaded(String modelId) =>
      _states[modelId]?.isDownloaded ?? false;

  bool isDownloading(String modelId) =>
      _states[modelId]?.isDownloading ?? false;

  ModelDownloadState stateFor(String modelId) =>
      _states[modelId] ?? const ModelDownloadState();

  bool canScan(String detectorId, String depthId) =>
      isDownloaded(detectorId) && isDownloaded(depthId);

  bool get defaultModelsReady =>
      isDownloaded(_registry.defaultDetector.id) &&
      isDownloaded(_registry.defaultDepth.id);

  /// True when at least one detector AND one depth model are on disk — i.e.
  /// scanning is possible regardless of which specific checkpoints are selected.
  bool get anySetReady =>
      _registry.detectors.any((d) => isDownloaded(d.id)) &&
      _registry.depth.any((d) => isDownloaded(d.id));

  Future<void> checkAllOnDisk() async {
    for (final det in _registry.detectors) {
      final exists =
          await ModelDownloadService.fileExists(modelsDir, det.filename);
      _states[det.id] = ModelDownloadState(
        status: exists ? DownloadStatus.done : DownloadStatus.idle,
      );
    }
    for (final dep in _registry.depth) {
      final mainExists =
          await ModelDownloadService.fileExists(modelsDir, dep.filename);
      final dataExists = dep.externalFilename == null ||
          await ModelDownloadService.fileExists(
              modelsDir, dep.externalFilename!);
      _states[dep.id] = ModelDownloadState(
        status: (mainExists && dataExists)
            ? DownloadStatus.done
            : DownloadStatus.idle,
      );
    }
    notifyListeners();
  }

  Future<void> downloadModel(String modelId) async {
    if (isDownloading(modelId) || isDownloaded(modelId)) return;

    final det =
        _registry.detectors.where((d) => d.id == modelId).firstOrNull;
    final dep = _registry.depth.where((d) => d.id == modelId).firstOrNull;
    if (det == null && dep == null) return;

    // Snapshot before mutating state: was any other model of this type already
    // on disk? If not, this will be the first — auto-select it on success.
    final wasFirstDetector = det != null &&
        !_registry.detectors
            .where((d) => d.id != modelId)
            .any((d) => _states[d.id]?.isDownloaded ?? false);
    final wasFirstDepth = dep != null &&
        !_registry.depth
            .where((d) => d.id != modelId)
            .any((d) => _states[d.id]?.isDownloaded ?? false);

    _states[modelId] =
        const ModelDownloadState(status: DownloadStatus.downloading);
    notifyListeners();

    try {
      if (det != null) {
        await _downloadFile(
          url: det.downloadUrl,
          filename: det.filename,
          modelId: modelId,
          range: (0.0, 1.0),
        );
      } else if (dep != null) {
        if (dep.externalDataUrl != null && dep.externalFilename != null) {
          final total = dep.totalSizeBytes;
          final mainFrac = total > 0 ? dep.sizeBytes / total : 0.5;
          await _downloadFile(
            url: dep.downloadUrl,
            filename: dep.filename,
            modelId: modelId,
            range: (0.0, mainFrac),
          );
          await _downloadFile(
            url: dep.externalDataUrl!,
            filename: dep.externalFilename!,
            modelId: modelId,
            range: (mainFrac, 1.0),
          );
        } else {
          await _downloadFile(
            url: dep.downloadUrl,
            filename: dep.filename,
            modelId: modelId,
            range: (0.0, 1.0),
          );
        }
      }
      _states[modelId] = const ModelDownloadState(status: DownloadStatus.done);
      if (wasFirstDetector) _onFirstDetectorDownloaded?.call(modelId);
      if (wasFirstDepth) _onFirstDepthDownloaded?.call(modelId);
    } catch (e) {
      _states[modelId] = ModelDownloadState(
        status: DownloadStatus.error,
        error: e.toString(),
      );
    }
    notifyListeners();
  }

  Future<void> _downloadFile({
    required String url,
    required String filename,
    required String modelId,
    required (double, double) range,
  }) async {
    final (start, end) = range;
    await ModelDownloadService.download(
      url,
      destPath: '$modelsDir/$filename',
      onProgress: (p) {
        _states[modelId] = ModelDownloadState(
          status: DownloadStatus.downloading,
          progress: start + p * (end - start),
        );
        notifyListeners();
      },
    );
  }

  Future<void> deleteModel(String modelId) async {
    final det =
        _registry.detectors.where((d) => d.id == modelId).firstOrNull;
    final dep = _registry.depth.where((d) => d.id == modelId).firstOrNull;

    // Snapshot current selection before mutating state.
    final currentDetId = _getCurrentDetectorId?.call();
    final currentDepId = _getCurrentDepthId?.call();

    if (det != null) {
      await ModelDownloadService.deleteFile(modelsDir, det.filename);
    } else if (dep != null) {
      await ModelDownloadService.deleteFile(modelsDir, dep.filename);
      if (dep.externalFilename != null) {
        await ModelDownloadService.deleteFile(modelsDir, dep.externalFilename!);
      }
    }
    _states[modelId] = const ModelDownloadState(status: DownloadStatus.idle);

    // If the deleted model was selected, switch to the next downloaded one of
    // the same type (if any exists).
    if (det != null && currentDetId == modelId) {
      final next = _registry.detectors
          .where((d) => d.id != modelId && (_states[d.id]?.isDownloaded ?? false))
          .firstOrNull;
      if (next != null) _onFirstDetectorDownloaded?.call(next.id);
    }
    if (dep != null && currentDepId == modelId) {
      final next = _registry.depth
          .where((d) => d.id != modelId && (_states[d.id]?.isDownloaded ?? false))
          .firstOrNull;
      if (next != null) _onFirstDepthDownloaded?.call(next.id);
    }

    notifyListeners();
  }
}
