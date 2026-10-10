import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'asr.dart';
import 'model_paths.dart';

/// Wav2Vec2 + CTC implementation backed by ONNX Runtime.
///
/// Contract observed from the model export:
/// - Input  : float32 raw waveform, shape [1, num_samples], 16 kHz, mono
/// - Output : float32 logits,        shape [1, time, vocab_size]
///
/// Decoding is **CTC greedy**:
///   1. argmax along the vocab axis → token IDs per frame
///   2. collapse consecutive duplicates (CTC's "merge repeats")
///   3. drop pad/blank tokens (id = pad_id)
///   4. replace word_delimiter ('|') with space, drop other special tokens
///   5. concatenate
class OnnxAsr implements Asr {
  OnnxAsr({
    required this.langCode,
    this.normalizeWaveform = true,
    ModelPaths? paths,
    OnnxRuntime? runtime,
  })  : _runtime = runtime ?? OnnxRuntime(),
        _paths = paths;

  final String langCode;

  /// If true, applies per-utterance zero-mean / unit-variance normalisation
  /// to the float32 waveform before feeding the model. Most Wav2Vec2
  /// exports were trained with this on; turn off if your export does the
  /// normalisation internally.
  final bool normalizeWaveform;

  final OnnxRuntime _runtime;
  ModelPaths? _paths;

  OrtSession? _session;
  Map<String, int>? _vocab;
  Map<int, String>? _reverseVocab;
  int _padId = 0;
  String _wordDelimiter = '|';
  String _inputName = 'input_values';
  String _outputName = 'logits';

  @override
  int get sampleRate => 16000;

  bool get isLoaded => _session != null;
  String get inputName => _inputName;
  String get outputName => _outputName;

  @override
  Future<void> load() async {
    if (_session != null) return;

    // 1. Vocab bundle from assets.
    final raw = await rootBundle
        .loadString('assets/models/stt/stt_${langCode}_vocab.json');
    final bundle = jsonDecode(raw) as Map<String, dynamic>;

    _vocab = (bundle['vocab'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, (v as num).toInt()));
    _reverseVocab = {
      for (final e in _vocab!.entries) e.value: e.key,
    };
    final padToken = (bundle['pad_token'] as String?) ?? '<pad>';
    _padId = _vocab![padToken] ?? 0;
    _wordDelimiter =
        (bundle['word_delimiter_token'] as String?) ?? '|';

    // 2. Model file from internal storage.
    _paths ??= await ModelPaths.resolve();
    final modelFile = await _paths!.asrFor(langCode);
    if (modelFile == null) {
      throw StateError(
        'STT model file missing for "$langCode". '
        'Push it via run-as. App-side root: ${_paths!.root}',
      );
    }

    _session = await _runtime.createSession(modelFile.path);

    if (_session!.inputNames.isNotEmpty) {
      _inputName = _session!.inputNames.first;
    }
    if (_session!.outputNames.isNotEmpty) {
      _outputName = _session!.outputNames.firstWhere(
        (n) =>
            n.toLowerCase().contains('logit') ||
            n.toLowerCase() == 'output',
        orElse: () => _session!.outputNames.first,
      );
    }
  }

  @override
  Future<AsrResult> transcribe(Int16List pcm) async {
    if (_session == null) {
      throw StateError('Asr.load() must be called before transcribe().');
    }
    if (pcm.isEmpty) {
      return const AsrResult(text: '', confidence: 0);
    }

    // 1. Int16 → Float32 in [-1.0, 1.0]
    final samples = Float32List(pcm.length);
    for (int i = 0; i < pcm.length; i++) {
      samples[i] = pcm[i] / 32768.0;
    }
    if (normalizeWaveform) {
      _zNormalize(samples);
    }

    // 2. Run inference.
    final input =
        await OrtValue.fromList(samples, [1, samples.length]);
    final outputs = await _session!.run({_inputName: input});
    final logitsValue = outputs[_outputName];
    if (logitsValue == null) {
      throw StateError(
        'Output "$_outputName" missing. '
        'Available: ${outputs.keys.toList()}',
      );
    }

    final shape = logitsValue.shape;
    if (shape.length != 3) {
      throw StateError(
        'Expected logits rank 3 ([batch, time, vocab]) but got $shape',
      );
    }
    final timeSteps = shape[1];
    final vocabSize = shape[2];
    final flat = await logitsValue.asFlattenedList();

    // 3. Argmax + average top-1 logit gap as a rough confidence.
    final tokens = List<int>.filled(timeSteps, 0);
    double topLogitSum = 0;
    int frames = 0;
    for (int t = 0; t < timeSteps; t++) {
      double max1 = double.negativeInfinity;
      int max1Idx = 0;
      for (int v = 0; v < vocabSize; v++) {
        final value = (flat[t * vocabSize + v] as num).toDouble();
        if (value > max1) {
          max1 = value;
          max1Idx = v;
        }
      }
      tokens[t] = max1Idx;
      // Only count non-blank frames toward confidence so silence doesn't
      // dominate the average.
      if (max1Idx != _padId) {
        topLogitSum += max1;
        frames++;
      }
    }
    final avgTopLogit = frames > 0 ? topLogitSum / frames : 0.0;
    final confidence = _logitToConfidence(avgTopLogit);

    // 4. CTC collapse repeats.
    final collapsed = <int>[];
    int prev = -1;
    for (final id in tokens) {
      if (id != prev) collapsed.add(id);
      prev = id;
    }

    // 5. Drop blanks, map to chars, handle delimiter + special tokens.
    final buf = StringBuffer();
    for (final id in collapsed) {
      if (id == _padId) continue;
      final ch = _reverseVocab![id];
      if (ch == null) continue;
      if (ch == _wordDelimiter) {
        buf.write(' ');
        continue;
      }
      // Skip BOS/EOS/UNK style tokens.
      if (ch.length > 1 && ch.startsWith('<') && ch.endsWith('>')) continue;
      buf.write(ch);
    }

    return AsrResult(
      text: buf.toString().trim().replaceAll(RegExp(r'\s+'), ' '),
      confidence: confidence,
    );
  }

  /// Per-utterance zero-mean, unit-variance normalisation. This is the
  /// default Wav2Vec2 feature extractor behaviour
  /// (`do_normalize=True`).
  static void _zNormalize(Float32List samples) {
    if (samples.isEmpty) return;
    double sum = 0;
    for (final s in samples) {
      sum += s;
    }
    final mean = sum / samples.length;
    double sqSum = 0;
    for (final s in samples) {
      final d = s - mean;
      sqSum += d * d;
    }
    final std = math.sqrt(sqSum / samples.length) + 1e-7;
    for (int i = 0; i < samples.length; i++) {
      samples[i] = (samples[i] - mean) / std;
    }
  }

  /// Map an averaged top-1 logit into a [0, 1] confidence via a soft
  /// squash. Logits aren't probabilities; this is a heuristic for the
  /// "ask the user to repeat" threshold in [Asr] callers.
  static double _logitToConfidence(double avgTopLogit) {
    if (avgTopLogit.isNaN || avgTopLogit.isInfinite) return 0;
    // Most useful ASR turns sit around logit 5–15 on the top class.
    // Squash via 1/(1+exp(-(x-3))).
    final s = 1 / (1 + math.exp(-(avgTopLogit - 3)));
    return s.clamp(0.0, 1.0);
  }

  @override
  Future<void> dispose() async {
    final s = _session;
    _session = null;
    await s?.close();
  }
}
