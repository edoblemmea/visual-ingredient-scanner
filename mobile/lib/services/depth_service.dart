import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../models/depth_map.dart';

/// Which depth model family is loaded — selects the pre/post-processing branch,
/// mirroring the auto-detection in `pipeline/depth.py`. Keyed off the registry
/// `family` field on mobile rather than sniffing ONNX outputs.
enum DepthFamily { metric3d, depthAnything }

DepthFamily depthFamilyFromString(String value) =>
    value == 'depthanything' ? DepthFamily.depthAnything : DepthFamily.metric3d;

/// Letterboxed Metric3D input plus the transform needed to un-pad and rescale
/// the prediction back to the original image.
class Metric3dInput {
  const Metric3dInput({
    required this.data,
    required this.scale,
    required this.padTop,
    required this.padLeft,
    required this.resizedW,
    required this.resizedH,
  });

  final Float32List data;
  final double scale;
  final int padTop;
  final int padLeft;
  final int resizedW;
  final int resizedH;
}

/// Stage ② — metric depth over flutter_onnxruntime (ORT 1.22). Pure Dart port of
/// `pipeline/depth.py`. Metric3D is de-canonicalised with the camera focal
/// length; Depth Anything V2-S uses the metric-indoor checkpoint and returns
/// metres directly.
///
/// Pre/post-processing are pure static methods, unit-tested without inference.
class DepthService {
  DepthService._(
    this._session,
    this._inputName,
    this._outputName,
    this.family,
    this.float16,
  );

  final OrtSession _session;
  final String _inputName;
  final String _outputName;
  final DepthFamily family;

  /// True when the model has float16 I/O (the Metric3D fp16 export).
  final bool float16;

  // Metric3D canonical-camera recipe (pixel values in 0–255 scale).
  static const int m3dInputH = 616;
  static const int m3dInputW = 1064;
  static const List<double> m3dMean = [123.675, 116.28, 103.53];
  static const List<double> m3dStd = [58.395, 57.12, 57.375];
  static const double m3dCanonicalFocal = 1000.0;

  // Depth Anything V2 (ImageNet normalisation in 0–1 scale).
  static const int daInputSize = 518;
  static const List<double> imagenetMean = [0.485, 0.456, 0.406];
  static const List<double> imagenetStd = [0.229, 0.224, 0.225];

  static Future<DepthService> fromAsset({
    required String assetPath,
    required DepthFamily family,
    bool float16 = false,
    String? externalData,
  }) async {
    final options = OrtSessionOptions(intraOpNumThreads: 2);
    final session = externalData == null || kIsWeb
        ? await OnnxRuntime().createSessionFromAsset(
            assetPath,
            options: options,
          )
        : await _createSessionWithExternalData(
            assetPath: assetPath,
            externalData: externalData,
            options: options,
          );
    // Metric3D emits multiple outputs; we only need the depth map.
    final outputName = session.outputNames.contains('predicted_depth')
        ? 'predicted_depth'
        : session.outputNames.first;
    return DepthService._(
      session,
      session.inputNames.first,
      outputName,
      family,
      float16,
    );
  }

  static Future<OrtSession> _createSessionWithExternalData({
    required String assetPath,
    required String externalData,
    required OrtSessionOptions options,
  }) async {
    final directory = await getTemporaryDirectory();
    final modelFile = File(
      '${directory.path}${Platform.pathSeparator}${assetPath.split('/').last}',
    );
    final dataFile = File(
      '${directory.path}${Platform.pathSeparator}${externalData.split('/').last}',
    );

    await _extractAsset(assetPath, modelFile);
    await _extractAsset(externalData, dataFile);
    return OnnxRuntime().createSession(modelFile.path, options: options);
  }

  static Future<void> _extractAsset(String assetPath, File target) async {
    await target.parent.create(recursive: true);
    final data = await rootBundle.load(assetPath);
    await target.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }

  /// Returns a metric depth map in metres at the original image resolution.
  /// [focalPx] is required by the Metric3D de-canonicalisation; Depth Anything
  /// ignores it because the metric-indoor checkpoint already emits metres.
  Future<DepthMap> estimate(img.Image image, {required double focalPx}) {
    switch (family) {
      case DepthFamily.metric3d:
        return _estimateMetric3d(image, focalPx);
      case DepthFamily.depthAnything:
        return _estimateDepthAnything(image);
    }
  }

  Future<DepthMap> _estimateMetric3d(img.Image image, double focalPx) async {
    final pre = preprocessMetric3d(image);
    final out = await _infer(
      pre.data,
      [1, 3, m3dInputH, m3dInputW],
      outH: m3dInputH,
      outW: m3dInputW,
    );
    final unpadded = cropPlane(
      out,
      m3dInputW,
      pre.padLeft,
      pre.padTop,
      pre.resizedW,
      pre.resizedH,
    );
    final resized = bilinearResize(
      unpadded,
      pre.resizedW,
      pre.resizedH,
      image.width,
      image.height,
    );
    final factor = metric3dDecanonFactor(focalPx, pre.scale);
    for (var i = 0; i < resized.length; i++) {
      resized[i] *= factor;
    }
    return DepthMap(width: image.width, height: image.height, data: resized);
  }

  Future<DepthMap> _estimateDepthAnything(img.Image image) async {
    final data = preprocessDepthAnything(image);
    final out = await _infer(
      data,
      [1, 3, daInputSize, daInputSize],
      outH: daInputSize,
      outW: daInputSize,
    );
    final resized = bilinearResize(
      out,
      daInputSize,
      daInputSize,
      image.width,
      image.height,
    );
    return DepthMap(width: image.width, height: image.height, data: resized);
  }

  /// Runs inference and returns the depth plane as a flat `Float32List`
  /// (length `outH*outW`). Converts the input to float16 for fp16 models.
  Future<Float32List> _infer(
    Float32List data,
    List<int> shape, {
    required int outH,
    required int outW,
  }) async {
    var input = await OrtValue.fromList(data, shape);
    if (float16) {
      final converted = await input.to(OrtDataType.float16);
      await input.dispose();
      input = converted;
    }
    Map<String, OrtValue>? outputs;
    try {
      outputs = await _session.run({_inputName: input});
      final flat = await outputs[_outputName]!.asFlattenedList();
      final result = Float32List(outH * outW);
      final n = result.length < flat.length ? result.length : flat.length;
      for (var i = 0; i < n; i++) {
        result[i] = (flat[i] as num).toDouble();
      }
      return result;
    } finally {
      await input.dispose();
      if (outputs != null) {
        for (final v in outputs.values) {
          await v.dispose();
        }
      }
    }
  }

  Future<void> dispose() => _session.close();

  // ---- pure, testable helpers -------------------------------------------

  /// De-canonicalisation factor: `focal_px × resize_scale / 1000` (depth.py).
  static double metric3dDecanonFactor(double focalPx, double resizeScale) =>
      focalPx * resizeScale / m3dCanonicalFocal;

  /// Keep-aspect resize to fit 616×1064, centre-pad with the ImageNet mean,
  /// normalise in 0–255 scale, CHW. Pad regions normalise to 0 (mean − mean).
  static Metric3dInput preprocessMetric3d(img.Image src) {
    final scale = _min(m3dInputH / src.height, m3dInputW / src.width);
    final rw = (src.width * scale).round();
    final rh = (src.height * scale).round();
    final padLeft = (m3dInputW - rw) ~/ 2;
    final padTop = (m3dInputH - rh) ~/ 2;

    final resized = img.copyResize(
      src,
      width: rw,
      height: rh,
      interpolation: img.Interpolation.linear,
    );

    const area = m3dInputH * m3dInputW;
    final data = Float32List(3 * area); // pad area normalises to 0
    for (var y = 0; y < rh; y++) {
      final canvasRow = (padTop + y) * m3dInputW;
      for (var x = 0; x < rw; x++) {
        final idx = canvasRow + padLeft + x;
        final p = resized.getPixel(x, y);
        data[idx] = (p.r - m3dMean[0]) / m3dStd[0];
        data[area + idx] = (p.g - m3dMean[1]) / m3dStd[1];
        data[2 * area + idx] = (p.b - m3dMean[2]) / m3dStd[2];
      }
    }
    return Metric3dInput(
      data: data,
      scale: scale,
      padTop: padTop,
      padLeft: padLeft,
      resizedW: rw,
      resizedH: rh,
    );
  }

  /// Resize to 518×518, scale to 0–1, ImageNet-normalise, CHW.
  static Float32List preprocessDepthAnything(img.Image src) {
    final resized = img.copyResize(
      src,
      width: daInputSize,
      height: daInputSize,
      interpolation: img.Interpolation.linear,
    );
    const area = daInputSize * daInputSize;
    final data = Float32List(3 * area);
    for (var y = 0; y < daInputSize; y++) {
      final rowOffset = y * daInputSize;
      for (var x = 0; x < daInputSize; x++) {
        final idx = rowOffset + x;
        final p = resized.getPixel(x, y);
        data[idx] = (p.r / 255.0 - imagenetMean[0]) / imagenetStd[0];
        data[area + idx] = (p.g / 255.0 - imagenetMean[1]) / imagenetStd[1];
        data[2 * area + idx] = (p.b / 255.0 - imagenetMean[2]) / imagenetStd[2];
      }
    }
    return data;
  }

  /// Extracts a [cropW]×[cropH] window at ([x0],[y0]) from a row-major plane of
  /// width [srcW] — the un-pad step.
  static Float32List cropPlane(
    Float32List src,
    int srcW,
    int x0,
    int y0,
    int cropW,
    int cropH,
  ) {
    final out = Float32List(cropW * cropH);
    var k = 0;
    for (var y = 0; y < cropH; y++) {
      final srcRow = (y0 + y) * srcW + x0;
      for (var x = 0; x < cropW; x++) {
        out[k++] = src[srcRow + x];
      }
    }
    return out;
  }

  /// Half-pixel-centred bilinear resize of a single-channel float plane
  /// (approximates cv2 INTER_LINEAR / PIL BILINEAR).
  static Float32List bilinearResize(
    Float32List src,
    int srcW,
    int srcH,
    int dstW,
    int dstH,
  ) {
    final out = Float32List(dstW * dstH);
    final sx = srcW / dstW;
    final sy = srcH / dstH;
    for (var y = 0; y < dstH; y++) {
      var fy = (y + 0.5) * sy - 0.5;
      if (fy < 0) fy = 0;
      if (fy > srcH - 1) fy = (srcH - 1).toDouble();
      final y0 = fy.floor();
      final y1 = y0 + 1 < srcH ? y0 + 1 : y0;
      final wy = fy - y0;
      for (var x = 0; x < dstW; x++) {
        var fx = (x + 0.5) * sx - 0.5;
        if (fx < 0) fx = 0;
        if (fx > srcW - 1) fx = (srcW - 1).toDouble();
        final x0 = fx.floor();
        final x1 = x0 + 1 < srcW ? x0 + 1 : x0;
        final wx = fx - x0;
        final v00 = src[y0 * srcW + x0];
        final v01 = src[y0 * srcW + x1];
        final v10 = src[y1 * srcW + x0];
        final v11 = src[y1 * srcW + x1];
        final top = v00 + (v01 - v00) * wx;
        final bot = v10 + (v11 - v10) * wx;
        out[y * dstW + x] = top + (bot - top) * wy;
      }
    }
    return out;
  }

  static double _min(double a, double b) => a < b ? a : b;
}
