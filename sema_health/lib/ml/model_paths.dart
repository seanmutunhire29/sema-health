import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Resolves where on-device model files live at runtime.
///
/// Strategy (dev):
/// - Android: app's external-files dir (`/sdcard/Android/data/<pkg>/files`)
///   so we can `adb push` model files into it without rooting.
/// - iOS / others: app support dir (Xcode "Add files" or in-app download).
///
/// Strategy (prod, future): a manifest-driven downloader writes to the
/// same paths. The rest of the app reads from `pathFor(...)` and doesn't
/// care which strategy provided the bytes.
class ModelPaths {
  ModelPaths._(this._root);

  final Directory _root;

  /// Resolve once at app start. Cheap to call repeatedly.
  static Future<ModelPaths> resolve() async {
    final root = await _modelsRoot();
    return ModelPaths._(root);
  }

  static Future<Directory> _modelsRoot() async {
    // Internal app storage is owned by the app's UID. On Android 11+
    // scoped storage blocks the app from reading files in
    // /Android/data/<pkg>/files/ that were written by another UID
    // (e.g. via `adb push`), so we keep models inside the app sandbox
    // and rely on `run-as` for the dev-time copy.
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String get root => _root.path;

  /// Per-language ASR model path. Convention: `<root>/stt/stt_<lang>.onnx`
  /// or `stt_<lang>_int8.onnx`. We try both since quantized variants are
  /// common during dev.
  Future<File?> asrFor(String langCode) async {
    final candidates = [
      '${_root.path}/stt/stt_${langCode}_int8.onnx',
      '${_root.path}/stt/stt_$langCode.onnx',
    ];
    for (final p in candidates) {
      final f = File(p);
      if (await f.exists()) return f;
    }
    return null;
  }

  /// Per-language TTS model path.
  Future<File?> ttsFor(String langCode) async {
    final candidates = [
      '${_root.path}/tts/tts_${langCode}_int8.onnx',
      '${_root.path}/tts/tts_$langCode.onnx',
    ];
    for (final p in candidates) {
      final f = File(p);
      if (await f.exists()) return f;
    }
    return null;
  }

  /// LLM model file (Gemma .task bundle). [variant] is e.g.
  /// `gemma_3n_e2b_int4` or `gemma_3_1b_int4` — we try `<variant>.task`.
  Future<File?> llmFor(String variant) async {
    final f = File('${_root.path}/llm/$variant.task');
    return await f.exists() ? f : null;
  }

  /// NLLB-200 ONNX encoder. Same `<root>/mt/` directory holds the
  /// decoder + tokenizer files alongside it.
  Future<File?> mtEncoder() async {
    final f = File('${_root.path}/mt/encoder_model.onnx');
    return await f.exists() ? f : null;
  }

  /// NLLB-200 ONNX decoder (no-cache export — recomputes the full
  /// decoder forward pass each step).
  Future<File?> mtDecoder() async {
    final f = File('${_root.path}/mt/decoder_model.onnx');
    return await f.exists() ? f : null;
  }

  /// HuggingFace fast-tokenizer JSON for NLLB. Holds vocab + ranked
  /// merges + special tokens (including the 200 NLLB language tokens).
  Future<File?> mtTokenizer() async {
    final f = File('${_root.path}/mt/tokenizer.json');
    return await f.exists() ? f : null;
  }

  /// Used by the inspector + setup screens to tell the user how to get
  /// model files into the app's sandbox.
  ///
  /// Android scoped storage blocks the app from reading files in its own
  /// `/Android/data/[pkg]/files/` that were written by another UID, so we
  /// land them in `/data/local/tmp/` first and `run-as` to copy.
  String pushHint(String langCode) => '''
Push via /data/local/tmp/ then copy in as the app's UID (run-as
requires a debuggable build, which `flutter run` produces):

  adb push models/stt/stt_${langCode}_int8.onnx /data/local/tmp/
  adb push models/tts/tts_$langCode.onnx /data/local/tmp/

  adb shell "run-as com.example.sema_health mkdir -p files/models/stt"
  adb shell "run-as com.example.sema_health mkdir -p files/models/tts"

  adb shell "run-as com.example.sema_health cp /data/local/tmp/stt_${langCode}_int8.onnx files/models/stt/"
  adb shell "run-as com.example.sema_health cp /data/local/tmp/tts_$langCode.onnx files/models/tts/"

  adb shell "rm /data/local/tmp/stt_${langCode}_int8.onnx /data/local/tmp/tts_$langCode.onnx"

App-side root: $root
''';

  /// Push hint for the LLM `.task` bundle. Same run-as flow, different dir.
  String llmPushHint(String variant) => '''
Push the Gemma model via /data/local/tmp/ then copy in as the app's UID:

  adb push models/llm/$variant.task /data/local/tmp/

  adb shell "run-as com.example.sema_health mkdir -p files/models/llm"
  adb shell "run-as com.example.sema_health cp /data/local/tmp/$variant.task files/models/llm/"

  adb shell "rm /data/local/tmp/$variant.task"

App-side root: $root
''';

  /// Push hint for the NLLB-200 MT bundle. Three files (encoder +
  /// decoder + tokenizer.json) all land in `<root>/mt/`.
  String mtPushHint() => '''
Push NLLB-200 (encoder + decoder + tokenizer) via /data/local/tmp/:

  adb push models/mt/encoder_model.onnx   /data/local/tmp/
  adb push models/mt/decoder_model.onnx   /data/local/tmp/
  adb push models/mt/tokenizer.json       /data/local/tmp/

  adb shell "run-as com.example.sema_health mkdir -p files/models/mt"
  adb shell "run-as com.example.sema_health cp /data/local/tmp/encoder_model.onnx files/models/mt/"
  adb shell "run-as com.example.sema_health cp /data/local/tmp/decoder_model.onnx files/models/mt/"
  adb shell "run-as com.example.sema_health cp /data/local/tmp/tokenizer.json     files/models/mt/"

  adb shell "rm /data/local/tmp/encoder_model.onnx /data/local/tmp/decoder_model.onnx /data/local/tmp/tokenizer.json"

App-side root: $root
''';
}
