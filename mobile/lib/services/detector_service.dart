import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import '../models/app_settings.dart' show kDefaultConfidence;
import '../models/bbox.dart';
import '../models/detection.dart';

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

/// Stage ① — YOLO detector over flutter_onnxruntime (ORT 1.22). The exported
/// graph has NMS baked in (`images[1,3,640,640]` → `output0[1,300,6]`, rows
/// `[x1,y1,x2,y2,score,class]` in input-space px), so decoding is just a
/// threshold + un-letterbox; no manual NMS.
///
/// Preprocess and decode are pure static methods, unit-tested without inference.
class DetectorService {
  DetectorService._(
    this._session,
    this._inputName,
    this._outputName,
    this._labels,
    this.inputSize,
  );

  final OrtSession _session;
  final String _inputName;
  final String _outputName;
  final List<String> _labels;
  final int inputSize;

  /// Letterbox padding grey, matching Ultralytics' default (114).
  static const int _padValue = 114;

  static Future<DetectorService> fromFile({
    required String filePath,
    required List<String> labels,
    int inputSize = 640,
  }) async {
    final session = await OnnxRuntime().createSession(
      filePath,
      options: OrtSessionOptions(intraOpNumThreads: 2),
    );
    return DetectorService._(
      session,
      session.inputNames.first,
      session.outputNames.first,
      labels,
      inputSize,
    );
  }

  Future<List<Detection>> detect(
    img.Image image, {
    double confThreshold = kDefaultConfidence,
  }) async {
    final input = preprocess(image, inputSize);
    final inputValue =
        await OrtValue.fromList(input.data, [1, 3, inputSize, inputSize]);
    Map<String, OrtValue>? outputs;
    try {
      outputs = await _session.run({_inputName: inputValue});
      final flat = await outputs[_outputName]!.asFlattenedList();
      return decodeDetections(
        _toRows(flat),
        scale: input.scale,
        padX: input.padX,
        padY: input.padY,
        imageWidth: image.width,
        imageHeight: image.height,
        labels: _labels,
        confThreshold: confThreshold,
      );
    } finally {
      await inputValue.dispose();
      if (outputs != null) {
        for (final v in outputs.values) {
          await v.dispose();
        }
      }
    }
  }

  Future<void> dispose() => _session.close();

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

  /// Reshapes a flat `[1,N,6]` output into N rows of 6 doubles.
  static List<List<double>> _toRows(List<dynamic> flat) {
    const cols = 6;
    final rows = <List<double>>[];
    for (var i = 0; i + cols <= flat.length; i += cols) {
      rows.add([for (var j = 0; j < cols; j++) (flat[i + j] as num).toDouble()]);
    }
    return rows;
  }
}
