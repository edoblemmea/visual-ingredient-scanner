import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation, rootBundle;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../services/asset_catalog.dart';
import '../services/focal.dart';
import '../state/scan_controller.dart';
import '../state/settings_provider.dart';
import 'result_screen.dart';

/// Camera capture, or pick a bundled sample image, then run a scan.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  CameraController? _camera;
  final ImagePicker _imagePicker = ImagePicker();
  List<AssetEntity> _galleryAssets = const [];
  String? _cameraError;
  bool _busy = false;
  bool _loadingGallery = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _loadGalleryAssets();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No camera available');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (e) {
      if (mounted) setState(() => _cameraError = e.toString());
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || _busy) return;
    setState(() => _busy = true);
    try {
      // Unlock so the capture EXIF reflects the true device orientation,
      // then immediately re-lock to keep the preview fixed in portrait.
      await camera.unlockCaptureOrientation();
      final file = await camera.takePicture();
      await camera.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await _confirmAndProcess(await file.readAsBytes());
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickSample(String asset) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = await rootBundle.load(asset);
      await _confirmAndProcess(data.buffer.asUint8List());
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      await _confirmAndProcess(await file.readAsBytes());
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickGalleryAsset(AssetEntity asset) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // asset.file asks iOS to convert HEIF/HEIC → JPEG before returning,
      // which the `image` decoder can handle. originBytes returns raw HEIF.
      final file = await asset.file;
      if (file == null) {
        _showError('Could not read gallery photo');
        return;
      }
      await _confirmAndProcess(await file.readAsBytes());
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadGalleryAssets() async {
    if (_loadingGallery) return;
    setState(() => _loadingGallery = true);
    try {
      const requestOption = PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.image,
          mediaLocation: false,
        ),
      );
      final permission = await PhotoManager.requestPermissionExtend(
        requestOption: requestOption,
      );
      if (!permission.hasAccess) return;
      final filter = FilterOptionGroup(
        orders: const [
          OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      );
      final albums = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: RequestType.image,
        filterOption: filter,
      );
      if (albums.isEmpty) return;
      final assets = await albums.first.getAssetListPaged(page: 0, size: 20);
      if (mounted) setState(() => _galleryAssets = assets);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loadingGallery = false);
    }
  }

  Future<void> _confirmAndProcess(Uint8List bytes) async {
    if (!mounted) return;
    // Decode into the image cache before opening the dialog so it appears
    // immediately without a blank-then-image flash.
    final provider = MemoryImage(bytes);
    await precacheImage(provider, context);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use this photo?'),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image(image: provider, fit: BoxFit.contain),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Retake'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Analyze'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _process(bytes);
  }

  Future<void> _process(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (!mounted) return;
    if (decoded == null) {
      _showError('Could not decode image');
      return;
    }
    final focalPx = focalPxFor(decoded);
    final controller = context.read<ScanController>();
    final settings = context.read<SettingsProvider>().settings;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ResultScreen()));
    controller.scan(
      decoded,
      focalPx: focalPx,
      settings: settings,
      imageBytes: bytes,
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan')),
      body: Column(
        children: [
          Expanded(child: _preview()),
          _sampleStrip(),
        ],
      ),
    );
  }

  Widget _preview() {
    final camera = _camera;
    if (camera != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: 1 / camera.value.aspectRatio,
          child: ClipRect(
            child: Stack(
              alignment: Alignment.center,
              children: [
                CameraPreview(camera),
                if (_busy) const CircularProgressIndicator(),
                Positioned(
                  bottom: 16,
                  child: FloatingActionButton.large(
                    onPressed: _busy ? null : _capture,
                    child: const Icon(Icons.camera),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, size: 64),
            const SizedBox(height: 12),
            Text(
              _cameraError == null
                  ? 'Starting camera…'
                  : 'Camera unavailable.\nPick a photo below.',
              textAlign: TextAlign.center,
            ),
            if (_cameraError != null) ...[
              const SizedBox(height: 8),
              Text(
                _cameraError!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sampleStrip() {
    final showSamples = context
        .watch<SettingsProvider>()
        .settings
        .showSampleImages;
    final itemCount =
        1 +
        _galleryAssets.length +
        (showSamples ? kSampleImageAssets.length : 0);
    return SafeArea(
      top: false,
      child: Container(
        height: 96,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: itemCount,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final sampleCount = showSamples ? kSampleImageAssets.length : 0;
            if (i < sampleCount) {
              final asset = kSampleImageAssets[i];
              return _SampleTile(
                asset: asset,
                disabled: _busy,
                onTap: () => _pickSample(asset),
              );
            }
            if (i == sampleCount) {
              return _GalleryTile(disabled: _busy, onTap: _pickGallery);
            }
            final asset = _galleryAssets[i - sampleCount - 1];
            return _GalleryAssetTile(
              asset: asset,
              disabled: _busy,
              onTap: () => _pickGalleryAsset(asset),
            );
          },
        ),
      ),
    );
  }
}

class _GalleryAssetTile extends StatelessWidget {
  const _GalleryAssetTile({
    required this.asset,
    required this.disabled,
    required this.onTap,
  });

  final AssetEntity asset;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FutureBuilder<Uint8List?>(
          future: asset.thumbnailDataWithSize(const ThumbnailSize.square(160)),
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data != null) {
              return Image.memory(data, width: 80, fit: BoxFit.cover);
            }
            return Container(
              width: 80,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Center(child: Icon(Icons.image_outlined)),
            );
          },
        ),
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({required this.disabled, required this.onTap});

  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        width: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined),
            SizedBox(height: 4),
            Text('Gallery'),
          ],
        ),
      ),
    );
  }
}

class _SampleTile extends StatelessWidget {
  const _SampleTile({
    required this.asset,
    required this.disabled,
    required this.onTap,
  });

  final String asset;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(asset, width: 80, fit: BoxFit.cover),
      ),
    );
  }
}
