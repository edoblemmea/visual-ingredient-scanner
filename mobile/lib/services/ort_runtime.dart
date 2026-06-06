import 'package:onnxruntime/onnxruntime.dart';

/// Initialises the ONNX Runtime environment exactly once for the whole app.
/// Both the detector and depth services call this before creating a session.
class OrtRuntime {
  OrtRuntime._();

  static bool _initialized = false;

  static void ensureInitialized() {
    if (_initialized) return;
    OrtEnv.instance.init();
    _initialized = true;
  }
}
