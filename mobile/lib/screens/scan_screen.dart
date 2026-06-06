import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
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
  String? _cameraError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
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
      final file = await camera.takePicture();
      await _process(await file.readAsBytes());
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
      await _process(data.buffer.asUint8List());
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ResultScreen()),
    );
    controller.scan(decoded, focalPx: focalPx, settings: settings);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      floatingActionButton: _camera != null
          ? FloatingActionButton.large(
              onPressed: _busy ? null : _capture,
              child: const Icon(Icons.camera),
            )
          : null,
    );
  }

  Widget _preview() {
    final camera = _camera;
    if (camera != null) {
      return Stack(
        alignment: Alignment.center,
        children: [
          CameraPreview(camera),
          if (_busy) const CircularProgressIndicator(),
        ],
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
                  : 'Camera unavailable.\nPick a sample image below.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sampleStrip() {
    return SafeArea(
      top: false,
      child: Container(
        height: 96,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('Samples'),
            ),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kSampleImageAssets.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final asset = kSampleImageAssets[i];
                  return GestureDetector(
                    onTap: _busy ? null : () => _pickSample(asset),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(asset, width: 80, fit: BoxFit.cover),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
