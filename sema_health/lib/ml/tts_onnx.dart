import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'model_paths.dart';
import 'tts.dart';

/// MMS-TTS implementation backed by ONNX Runtime.
///
/// Drives the model with the bundle JSON shipped under
/// `assets/models/tts/lang_<code>.json`. The bundle is the same one used
/// by the Python `tokenize_mms` reference implementation; this class is
/// a faithful Dart port of that function.
///
/// Output sample rate is 16 kHz (MMS-TTS standard for all languages).
class OnnxTts implements Tts {
  OnnxTts({required this.langCode, ModelPaths? paths, OnnxRuntime? runtime})
      : _runtime = runtime ?? OnnxRuntime(),
        _paths = paths;

  final String langCode;
  final OnnxRuntime _runtime;
  ModelPaths? _paths;

  OrtSession? _session;
  Map<String, int>? _vocab;
  int _padId = 0;
  bool _addBlank = true;
  bool _normalize = true;
  String _inputName = 'input_ids';
  String _outputName = 'waveform';

  @override
  int get sampleRate => 16000;

  bool get isLoaded => _session != null;

  /// MMS-TTS supports a single int64 input named `input_ids`. Exposed so
  /// callers can sanity-check the bundle/model contract.
  String get inputName => _inputName;

  /// The waveform output tensor name. Some exports name it differently;
  /// we resolve at load time.
  String get outputName => _outputName;

  @override
  Future<void> load() async {
    if (_session != null) return;

    // 1. Pull the tokenizer/config bundle from Flutter assets.
    final bundleRaw =
        await rootBundle.loadString('assets/models/tts/lang_$langCode.json');
    final bundle = jsonDecode(bundleRaw) as Map<String, dynamic>;
    _validateBundle(bundle);

    _vocab = (bundle['vocab'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, (v as num).toInt()));
    _padId = (bundle['pad_id'] as num).toInt();
    _addBlank = (bundle['add_blank'] as bool?) ?? true;
    _normalize = (bundle['normalize'] as bool?) ?? true;

    // 2. Resolve the on-device weights path.
    _paths ??= await ModelPaths.resolve();
    final modelFile = await _paths!.ttsFor(langCode);
    if (modelFile == null) {
      throw StateError(
        'TTS model file missing for "$langCode". '
        'Push it via run-as. App-side root: ${_paths!.root}',
      );
    }

    // 3. Open the session. flutter_onnxruntime handles the actual ORT
    // session lifetime; we keep the handle for repeated synthesize calls.
    _session = await _runtime.createSession(modelFile.path);

    // 4. Resolve real input/output names. The model spec we observed
    // had `input_ids` and `waveform`, but be defensive.
    if (_session!.inputNames.isNotEmpty) {
      _inputName = _session!.inputNames.first;
    }
    if (_session!.outputNames.isNotEmpty) {
      _outputName = _session!.outputNames.firstWhere(
        (n) => n.toLowerCase().contains('wave') || n.toLowerCase() == 'audio',
        orElse: () => _session!.outputNames.first,
      );
    }
  }

  void _validateBundle(Map<String, dynamic> bundle) {
    if (bundle['is_uroman'] == true) {
      throw StateError(
        'Language "$langCode" requires uroman romanization which is not '
        'available in Dart. Pre-romanize at export time, or switch to a '
        'lang variant where is_uroman = false.',
      );
    }
    if (bundle['phonemize'] == true) {
      throw StateError(
        'Language "$langCode" requires a phonemizer (espeak-ng) which is '
        'not available in Dart yet. Switch to a grapheme-trained variant '
        'or wire up an on-device phonemizer.',
      );
    }
    if (bundle['vocab'] is! Map) {
      throw StateError('Bundle missing or malformed `vocab`.');
    }
    if (bundle['pad_id'] == null) {
      throw StateError('Bundle missing `pad_id`.');
    }
  }

  /// Port of Python `tokenize_mms`. Returns int64 IDs.
  ///
  /// Algorithm (matches tts/infer.py):
  ///   1. Lowercase if `normalize`.
  ///   2. For each char, look up its ID in `vocab`. Drop unknown chars.
  ///   3. If `add_blank`, interleave `pad_id` between every kept char
  ///      (and at both ends).
  Int64List tokenize(String text) {
    if (_vocab == null) {
      throw StateError('Tts.load() must be called before tokenize().');
    }
    final source = _normalize ? text.toLowerCase() : text;
    final ids = <int>[];
    if (_addBlank) ids.add(_padId);
    for (final rune in source.runes) {
      final ch = String.fromCharCode(rune);
      final id = _vocab![ch];
      if (id == null) continue; // unknown char — silently skipped (matches Python)
      ids.add(id);
      if (_addBlank) ids.add(_padId);
    }
    return Int64List.fromList(ids);
  }

  @override
  Future<TtsResult> synthesize(String text) async {
    if (_session == null) {
      throw StateError('Tts.load() must be called before synthesize().');
    }

    final tokens = tokenize(text);
    if (tokens.isEmpty) {
      throw StateError('Tokenizer produced 0 ids for input "$text".');
    }

    final input =
        await OrtValue.fromList(tokens, [1, tokens.length]);

    final outputs = await _session!.run({_inputName: input});
    final waveformValue = outputs[_outputName];
    if (waveformValue == null) {
      throw StateError(
        'Model output "$_outputName" missing. '
        'Available outputs: ${outputs.keys.toList()}',
      );
    }

    final flat = await waveformValue.asFlattenedList();
    final pcm = _float32ToInt16Pcm(flat);

    return TtsResult(pcm: pcm, sampleRate: sampleRate);
  }

  /// Convert float32 samples in [-1.0, 1.0] to signed 16-bit PCM.
  /// Clamps before scaling to avoid wrap-around on rare clipping.
  static Int16List _float32ToInt16Pcm(List<dynamic> floats) {
    final out = Int16List(floats.length);
    for (int i = 0; i < floats.length; i++) {
      final v = (floats[i] as num).toDouble();
      final clamped = v < -1.0 ? -1.0 : (v > 1.0 ? 1.0 : v);
      out[i] = (clamped * 32767).round();
    }
    return out;
  }

  @override
  Future<void> dispose() async {
    final s = _session;
    _session = null;
    await s?.close();
  }
}
