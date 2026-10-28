// ignore_for_file: implementation_imports
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart' as bg;

/// Small, allocation-friendly helpers over the ONNX Runtime C API.
///
/// The `onnxruntime` plugin is used for loading the native library and for
/// sessions; these helpers create tensors straight from typed data (including
/// zero-length tensors) and read float outputs without copying them into Dart
/// lists, which matters for the 256k-entry vocabulary logits.
class OrtTensors {
  /// Opens an ONNX model file. On Windows ONNX Runtime expects the path as
  /// UTF-16 (wchar_t), which the plugin's `OrtSession.fromFile` does not do,
  /// so the session is created directly through the C API there.
  static OrtSession openSession(String path, {int threads = 0}) {
    if (!Platform.isWindows) {
      final o = OrtSessionOptions();
      if (threads > 0) o.setIntraOpNumThreads(threads);
      return OrtSession.fromFile(File(path), o);
    }
    final api = OrtEnv.instance.ortApiPtr.ref;
    final optionsPP = calloc<ffi.Pointer<bg.OrtSessionOptions>>();
    var status = api.CreateSessionOptions.asFunction<
        bg.OrtStatusPtr Function(ffi.Pointer<ffi.Pointer<bg.OrtSessionOptions>>)>()(optionsPP);
    OrtStatus.checkOrtStatus(status);
    final options = optionsPP.value;
    calloc.free(optionsPP);
    try {
      if (threads > 0) {
        status = api.SetIntraOpNumThreads.asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, int)>()(options, threads);
        OrtStatus.checkOrtStatus(status);
      }
      final widePath = path.toNativeUtf16(allocator: calloc);
      final sessionPP = calloc<ffi.Pointer<bg.OrtSession>>();
      try {
        status = api.CreateSession.asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtEnv>, ffi.Pointer<ffi.Char>,
                ffi.Pointer<bg.OrtSessionOptions>, ffi.Pointer<ffi.Pointer<bg.OrtSession>>)>()(
          OrtEnv.instance.ptr,
          widePath.cast<ffi.Char>(),
          options,
          sessionPP,
        );
        OrtStatus.checkOrtStatus(status);
        return OrtSession.fromAddress(sessionPP.value.address);
      } finally {
        calloc.free(widePath);
        calloc.free(sessionPP);
      }
    } finally {
      api.ReleaseSessionOptions.asFunction<void Function(ffi.Pointer<bg.OrtSessionOptions>)>()(options);
    }
  }

  static const int _float = 1;
  static const int _int64 = 7;
  static const int _bool = 9;

  static OrtValueTensor _create(ffi.Pointer<ffi.Void> data, int byteCount, List<int> shape, int type) {
    final api = OrtEnv.instance.ortApiPtr.ref;
    final memInfoPP = calloc<ffi.Pointer<bg.OrtMemoryInfo>>();
    var status = api.AllocatorGetInfo.asFunction<
        bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtAllocator>, ffi.Pointer<ffi.Pointer<bg.OrtMemoryInfo>>)>()(
      OrtAllocator.instance.ptr,
      memInfoPP,
    );
    OrtStatus.checkOrtStatus(status);
    final shapePtr = calloc<ffi.Int64>(shape.isEmpty ? 1 : shape.length);
    for (var i = 0; i < shape.length; i++) {
      shapePtr[i] = shape[i];
    }
    final valuePP = calloc<ffi.Pointer<bg.OrtValue>>();
    status = api.CreateTensorWithDataAsOrtValue.asFunction<
        bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtMemoryInfo>, ffi.Pointer<ffi.Void>, int,
            ffi.Pointer<ffi.Int64>, int, int, ffi.Pointer<ffi.Pointer<bg.OrtValue>>)>()(
      memInfoPP.value,
      data,
      byteCount,
      shapePtr,
      shape.length,
      type,
      valuePP,
    );
    OrtStatus.checkOrtStatus(status);
    final value = valuePP.value;
    calloc.free(shapePtr);
    calloc.free(valuePP);
    calloc.free(memInfoPP);
    // The tensor owns `data`: OrtValueTensor.release() frees it.
    return OrtValueTensor(value, data);
  }

  static OrtValueTensor int64(List<int> values, List<int> shape) {
    final n = values.length;
    final p = calloc<ffi.Int64>(n == 0 ? 1 : n);
    p.asTypedList(n == 0 ? 1 : n).setRange(0, n, values);
    return _create(p.cast(), n * 8, shape, _int64);
  }

  static OrtValueTensor float32(Float32List values, List<int> shape) {
    final n = values.length;
    final p = calloc<ffi.Float>(n == 0 ? 1 : n);
    if (n > 0) p.asTypedList(n).setAll(0, values);
    return _create(p.cast(), n * 4, shape, _float);
  }

  /// A float tensor with a zero-sized dimension (no data).
  static OrtValueTensor emptyFloat(List<int> shape) => _create(calloc<ffi.Float>(1).cast(), 0, shape, _float);

  static OrtValueTensor boolean(List<bool> values, List<int> shape) {
    final n = values.length;
    final p = calloc<ffi.Bool>(n == 0 ? 1 : n);
    for (var i = 0; i < n; i++) {
      p[i] = values[i];
    }
    return _create(p.cast(), n, shape, _bool);
  }

  /// View of a float tensor's data (valid until the value is released).
  static Float32List floatView(OrtValue value, int count) {
    final api = OrtEnv.instance.ortApiPtr.ref;
    final dataPP = calloc<ffi.Pointer<ffi.Void>>();
    final status = api.GetTensorMutableData.asFunction<
        bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>, ffi.Pointer<ffi.Pointer<ffi.Void>>)>()(
      value.ptr,
      dataPP,
    );
    OrtStatus.checkOrtStatus(status);
    final data = dataPP.value.cast<ffi.Float>();
    calloc.free(dataPP);
    return data.asTypedList(count);
  }
}
