// The Dart onnxruntime package only auto-handles float32/float64 tensors, but
// the Metric3D fp16 export has float16 input *and* output. ORT stores float16
// as a 16-bit value (MLFloat16), so here we (a) convert float32<->IEEE-754
// half, and (b) create/read float16 tensors directly through the ORT C API,
// reusing the package's public OrtEnv api pointer. This needs the generated
// bindings, which are not in the package barrel.
// ignore_for_file: implementation_imports
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart'
    as bg;

/// IEEE-754 half-precision (binary16) <-> double codec.
class Float16 {
  Float16._();

  /// Encode a double as a binary16 bit pattern (round-to-nearest-even).
  static int fromDouble(double value) {
    final x = (ByteData(4)..setFloat32(0, value, Endian.little))
        .getUint32(0, Endian.little);

    final sign = (x >> 16) & 0x8000;
    final exp = (x >> 23) & 0xff;
    var mantissa = x & 0x007fffff;

    if (exp == 0xff) {
      // Inf (mantissa 0) or NaN.
      return mantissa != 0 ? sign | 0x7e00 : sign | 0x7c00;
    }

    final newExp = exp - 127 + 15;
    if (newExp >= 0x1f) {
      return sign | 0x7c00; // overflow -> Inf
    }
    if (newExp <= 0) {
      if (newExp < -10) return sign; // underflow -> signed zero
      mantissa |= 0x00800000; // restore implicit leading 1
      final shift = 14 - newExp;
      var half = mantissa >> shift;
      final roundBit = 1 << (shift - 1);
      if ((mantissa & roundBit) != 0 &&
          ((mantissa & (roundBit - 1)) != 0 || (half & 1) != 0)) {
        half += 1;
      }
      return sign | half;
    }

    var half = sign | (newExp << 10) | (mantissa >> 13);
    const roundBit = 1 << 12;
    if ((mantissa & roundBit) != 0 &&
        ((mantissa & (roundBit - 1)) != 0 || (half & 1) != 0)) {
      half += 1; // may carry into the exponent, which is correct
    }
    return half;
  }

  /// Decode a binary16 bit pattern to a double.
  static double toDouble(int h) {
    final sign = (h & 0x8000) << 16;
    final exp = (h >> 10) & 0x1f;
    final mant = h & 0x3ff;

    int f;
    if (exp == 0) {
      if (mant == 0) {
        f = sign;
      } else {
        var e = -1;
        var m = mant;
        do {
          e++;
          m <<= 1;
        } while ((m & 0x400) == 0);
        f = sign | ((127 - 15 - e) << 23) | ((m & 0x3ff) << 13);
      }
    } else if (exp == 0x1f) {
      f = sign | 0x7f800000 | (mant << 13);
    } else {
      f = sign | ((exp - 15 + 127) << 23) | (mant << 13);
    }
    return (ByteData(4)..setUint32(0, f, Endian.little))
        .getFloat32(0, Endian.little);
  }
}

/// Creates a float16 input tensor from float32 data, replicating the package's
/// `createTensorWithDataList` FFI flow but tagging the tensor as FLOAT16. The
/// returned tensor owns the native buffer; call `release()` after `run`.
OrtValueTensor createFloat16InputTensor(Float32List data, List<int> shape) {
  final count = data.length;
  final dataPtr = calloc<ffi.Uint16>(count);
  final halfView = dataPtr.asTypedList(count);
  for (var i = 0; i < count; i++) {
    halfView[i] = Float16.fromDouble(data[i]);
  }

  final shapePtr = calloc<ffi.Int64>(shape.length);
  shapePtr.asTypedList(shape.length).setRange(0, shape.length, shape);

  final memInfoPtrPtr = calloc<ffi.Pointer<bg.OrtMemoryInfo>>();
  final api = OrtEnv.instance.ortApiPtr.ref;
  var status = api.AllocatorGetInfo.asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtAllocator>,
              ffi.Pointer<ffi.Pointer<bg.OrtMemoryInfo>>)>()(
      OrtAllocator.instance.ptr, memInfoPtrPtr);
  OrtStatus.checkOrtStatus(status);

  final ortValuePtrPtr = calloc<ffi.Pointer<bg.OrtValue>>();
  status = api.CreateTensorWithDataAsOrtValue.asFunction<
          bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtMemoryInfo>,
              ffi.Pointer<ffi.Void>,
              int,
              ffi.Pointer<ffi.Int64>,
              int,
              int,
              ffi.Pointer<ffi.Pointer<bg.OrtValue>>)>()(
      memInfoPtrPtr.value,
      dataPtr.cast(),
      count * 2, // 2 bytes per float16
      shapePtr,
      shape.length,
      ONNXTensorElementDataType.float16.value,
      ortValuePtrPtr);
  OrtStatus.checkOrtStatus(status);

  final tensor = OrtValueTensor(ortValuePtrPtr.value, dataPtr.cast());
  calloc.free(shapePtr);
  calloc.free(ortValuePtrPtr);
  calloc.free(memInfoPtrPtr);
  return tensor;
}

/// Reads a float16 output tensor's [elementCount] values into float32.
Float32List readFloat16OutputTensor(OrtValue value, int elementCount) {
  final dataPtrPtr = calloc<ffi.Pointer<ffi.Void>>();
  final status = OrtEnv.instance.ortApiPtr.ref.GetTensorMutableData.asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>,
              ffi.Pointer<ffi.Pointer<ffi.Void>>)>()(value.ptr, dataPtrPtr);
  OrtStatus.checkOrtStatus(status);
  final halfView = dataPtrPtr.value.cast<ffi.Uint16>().asTypedList(elementCount);
  final out = Float32List(elementCount);
  for (var i = 0; i < elementCount; i++) {
    out[i] = Float16.toDouble(halfView[i]);
  }
  calloc.free(dataPtrPtr);
  return out;
}
