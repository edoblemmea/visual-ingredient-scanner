import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import '../models/app_settings.dart' show kDefaultConfidence;
import '../models/bbox.dart';
import '../models/detection.dart';
import 'ort_runtime.dart';

/// Result of letterboxing an image into the square model input: the CHW RGB
/// tensor data plus the transform needed to map detections back to original px.
class LetterboxInput {
  const LetterboxInput({
    required this.data,
    required this.scale,
    required this.padX,
    required this.padY,
  });

  final Float32List data;
  final double scale;
  final double padX;
  final double padY;
}

/// Stage ① — YOLO detector over ONNX Runtime. The exported graph has NMS baked
/// in (`images[1,3,640,640]` → `output0[1,300,6]`, rows
/// `[x1,y1,x2,y2,score,class]` in input-space px), so decoding is just a
/// threshold + un-letterbox; no manual NMS.
///
/// Preprocess and decode are pure static methods so they can be unit-tested
/// without native inference.
class DetectorService {
  DetectorService._(
    this._session,
    this._options,
    this._inputName,
    this._labels,
    this.inputSize,
  );

  final OrtSession _session;
  final OrtSessionOptions _options;
  final String _inputName;
  final List<String> _labels;
  final int inputSize;

  /// Letterbox padding grey, matching Ultralytics' default (114).
  static const int _padValue = 114;

  static Future<DetectorService> fromAsset({
    required String assetPath,
    required List<String> labels,
    int inputSize = 640,
  }) async {
    OrtRuntime.ensureInitialized();
    final raw = await rootBundle.load(assetPath);
    // Disable graph optimization: on the mobile ORT build, the optimizer can
    // emit fused/layout nodes with no matching kernel ("Could not find an
    // implementation for Reshape(19) …" on the v26m attention blocks).
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(2)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortDisableAll);
    final session = OrtSession.fromBuffer(raw.buffer.asUint8List(), options);
    return DetectorService._(
      session,
      options,
      session.inputNames.first,
      labels,
      inputSize,
    );
  }

  /// Runs inference on a background isolate (ORT RunAsync) so the UI thread
  /// stays free. Preprocess/decode are synchronous Dart (comparatively cheap).
  Future<List<Detection>> detect(
    img.Image image, {
    double confThreshold = kDefaultConfidence,
  }) async {
    final input = preprocess(image, inputSize);
    final inputTensor = OrtValueTensor.createTensorWithDataList(
      input.data,
      [1, 3, inputSize, inputSize],
    );
    final runOptions = OrtRunOptions();
    List<OrtValue?>? outputs;
    try {
      outputs = await _session.runAsync(runOptions, {_inputName: inputTensor});
      final rows = _toRows(outputs!.first?.value);
      return decodeDetections(
        rows,
        scale: input.scale,
        padX: input.padX,
        padY: input.padY,
        imageWidth: image.width,
        imageHeight: image.height,
        labels: _labels,
        confThreshold: confThreshold,
      );
    } finally {
      inputTensor.release();
      runOptions.release();
      outputs?.forEach((o) => o?.release());
    }
  }

  void dispose() {
    _session.release();
    _options.release();
  }

  /// Aspect-preserving resize into [size]×[size] with centre grey padding,
  /// written as a CHW RGB float tensor normalised to 0–1.
  static LetterboxInput preprocess(img.Image src, int size) {
    final scale = math.min(size / src.width, size / src.height);
    final newW = (src.width * scale).round();
    final newH = (src.height * scale).round();
    final padX = ((size - newW) / 2).floorToDouble();
    final padY = ((size - newH) / 2).floorToDouble();

    final resized = img.copyResize(
      src,
      width: newW,
      height: newH,
      interpolation: img.Interpolation.linear,
    );

    final area = size * size;
    final data = Float32List(3 * area)..fillRange(0, 3 * area, _padValue / 255.0);

    final offX = padX.toInt();
    final offY = padY.toInt();
    for (var y = 0; y < newH; y++) {
      final canvasRow = (offY + y) * size;
      for (var x = 0; x < newW; x++) {
        final idx = canvasRow + offX + x;
        final p = resized.getPixel(x, y);
        data[idx] = p.r / 255.0;
        data[area + idx] = p.g / 255.0;
        data[2 * area + idx] = p.b / 255.0;
      }
    }
    return LetterboxInput(data: data, scale: scale, padX: padX, padY: padY);
  }

  /// Filters NMS-baked rows by score and maps boxes from letterboxed input
  /// space back to original image pixels. Padding rows (all-zero) fall below the
  /// threshold and drop out.
  static List<Detection> decodeDetections(
    List<List<double>> rows, {
    required double scale,
    required double padX,
    required double padY,
    required int imageWidth,
    required int imageHeight,
    required List<String> labels,
    required double confThreshold,
  }) {
    final detections = <Detection>[];
    for (final row in rows) {
      final score = row[4];
      if (score < confThreshold) continue;
      final classId = row[5].round();
      final bbox = BBox(
        (row[0] - padX) / scale,
        (row[1] - padY) / scale,
        (row[2] - padX) / scale,
        (row[3] - padY) / scale,
      ).clampTo(imageWidth, imageHeight);
      detections.add(Detection(
        className: classId >= 0 && classId < labels.length
            ? labels[classId]
            : 'class_$classId',
        confidence: score,
        bbox: bbox,
        classId: classId,
      ));
    }
    return detections;
  }

  static List<List<double>> _toRows(Object? value) {
    final batch = (value as List)[0] as List; // [1, N, 6] -> N rows
    return [
      for (final r in batch)
        [for (final e in (r as List)) (e as num).toDouble()],
    ];
  }
}
