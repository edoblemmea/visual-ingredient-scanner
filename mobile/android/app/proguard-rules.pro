# ONNX Runtime native JNI bridge — reflection-heavy, must not be stripped
-keep class ai.onnxruntime.** { *; }

# Flutter secure storage uses JNI to reach Android Keystore
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# photo_manager cursors are constructed via reflection
-keep class com.fluttercandies.photo_manager.** { *; }

# Suppress notes about dynamically-loaded classes we can't verify statically
-dontnote ai.onnxruntime.**
-dontnote com.google.android.gms.**
