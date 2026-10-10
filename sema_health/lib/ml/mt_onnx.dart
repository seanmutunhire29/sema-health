import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'model_paths.dart';
import 'mt.dart';
import 'mt_tokenizer.dart';

/// NLLB-200 (M2M100 architecture) translator backed by two ONNX
/// sessions and a pure-Dart BPE tokenizer.
///
/// Decoder export note. The decoder ONNX in `models/mt/` is the
/// **no-cache** variant: it accepts no `past_key_values`, so each
/// generation step rebuilds the full decoder forward pass on the
/// growing `[start, tgt_lang, ...generated]` prefix. That keeps the
/// implementation roughly 200 lines instead of 600+, at a real
/// throughput cost — measured at ~150–400 ms / token on a mid-tier
/// Android CPU. Acceptable for sentence-length symptom replies; if we
/// later need long-form translation the path is to swap in a cached
/// decoder export and feed `past_key_values` between steps.
///
/// Generation strategy: greedy argmax. NLLB's beam-4 decoding on
/// device would 4x the per-step cost; greedy is the right tradeoff
/// for a triage UX where structure matters more than fluency.
///
/// Memory: holds two ORT sessions (~1.1 GB combined for the FP32
/// distilled-600M export). [dispose] closes both sessions and clears
/// the tokenizer maps. Callers should dispose between long idle
/// periods to free the slot for Gemma — there's no headroom on a
/// 4 GB phone to hold all three models live.
class OnnxNllbTranslator implements Translator {
  OnnxNllbTranslator({
    this.maxNewTokens = 200,
    this.maxInputTokens = 256,
    ModelPaths? paths,
    OnnxRuntime? runtime,
  })  : _paths = paths,
        _runtime = runtime ?? OnnxRuntime();

  /// Cap on the number of decoder steps. Matches the NLLB
  /// `generation_config.json` default of 200.
  final int maxNewTokens;

  /// Cap on the encoder input length. NLLB's positional embedding
  /// supports up to 1024 but quality degrades past ~256 for our
  /// symptom-sized turns; we truncate to keep latency predictable.
  final int maxInputTokens;

  final OnnxRuntime _runtime;
  ModelPaths? _paths;

  OrtSession? _encoder;
  OrtSession? _decoder;
  NllbTokenizer? _tokenizer;

  String _encInputName = 'input_ids';
  String _encMaskName = 'attention_mask';
  String _encOutputName = 'last_hidden_state';

  String _decInputName = 'input_ids';
  String _decEncMaskName = 'encoder_attention_mask';
  String _decEncHiddenName = 'encoder_hidden_states';
  String _decLogitsName = 'logits';

  @override
  bool get isLoaded =>
      _encoder != null && _decoder != null && _tokenizer != null;

  @override
  Future<void> load() async {
    if (isLoaded) return;

    _paths ??= await ModelPaths.resolve();
    final encFile = await _paths!.mtEncoder();
    final decFile = await _paths!.mtDecoder();
    final tokFile = await _paths!.mtTokenizer();
    if (encFile == null || decFile == null || tokFile == null) {
      throw StateError(
        'NLLB MT model files missing on device. Need encoder_model.onnx, '
        'decoder_model.onnx and tokenizer.json under <root>/mt/.\n\n'
        '${_paths!.mtPushHint()}',
      );
    }

    _tokenizer = await NllbTokenizer.fromFile(tokFile);

    // Load both sessions in parallel — they're cold-mmap-bound and
    // independent. Saves ~1 s on device.
    final pair = await Future.wait([
      _runtime.createSession(encFile.path),
      _runtime.createSession(decFile.path),
    ]);
    _encoder = pair[0];
    _decoder = pair[1];

    // Pin actual input/output names from the session metadata. The
    // M2M100 ONNX export from optimum should match these defaults but
    // we don't want a quiet KeyError if someone re-exports the model.
    _encInputName = _pickName(_encoder!.inputNames, ['input_ids'], _encInputName);
    _encMaskName =
        _pickName(_encoder!.inputNames, ['attention_mask'], _encMaskName);
    _encOutputName = _pickName(
      _encoder!.outputNames,
      ['last_hidden_state', 'hidden_states', 'output'],
      _encOutputName,
    );

    _decInputName = _pickName(_decoder!.inputNames, ['input_ids'], _decInputName);
    _decEncMaskName = _pickName(
      _decoder!.inputNames,
      ['encoder_attention_mask', 'attention_mask'],
      _decEncMaskName,
    );
    _decEncHiddenName = _pickName(
      _decoder!.inputNames,
      ['encoder_hidden_states', 'last_hidden_state'],
      _decEncHiddenName,
    );
    _decLogitsName = _pickName(
      _decoder!.outputNames,
      ['logits'],
      _decLogitsName,
    );
  }

  static String _pickName(
    List<String> available,
    List<String> preferred,
    String fallback,
  ) {
    for (final name in preferred) {
      if (available.contains(name)) return name;
    }
    return available.isNotEmpty ? available.first : fallback;
  }

  @override
  Future<String> translate(
    String text, {
    required String src,
    required String tgt,
  }) async {
    if (text.trim().isEmpty) return '';
    if (!isLoaded) await load();
    final tok = _tokenizer!;

    final tgtId = tok.langTokenId(tgt);
    if (tgtId == null) {
      throw ArgumentError.value(
        tgt,
        'tgt',
        'Target language "$tgt" is not in the NLLB vocabulary. '
            'Use codes like swh_Latn, aka_Latn, eng_Latn, yor_Latn.',
      );
    }

    // 1. Tokenize. NLLB's TemplateProcessing wraps as
    //    [<src_lang_id>, ...subwords, </s>].
    var inputIds = tok.encode(text, srcLang: src);
    if (inputIds.length > maxInputTokens) {
      // Keep the leading src-lang token and the trailing </s>; drop
      // from the middle. Cheap heuristic — better would be to re-encode
      // a truncated string, but the model is robust to this.
      inputIds = [
        inputIds.first,
        ...inputIds.sublist(1, maxInputTokens - 1),
        tok.eosId,
      ];
    }
    final encLen = inputIds.length;

    // 2. Encoder forward.
    final encInputIds = await OrtValue.fromList(
      Int64List.fromList(inputIds),
      [1, encLen],
    );
    final encMaskIds = await OrtValue.fromList(
      Int64List.fromList(List<int>.filled(encLen, 1)),
      [1, encLen],
    );

    OrtValue? encHidden;
    final perStepValues = <OrtValue>[];
    try {
      final encOut = await _encoder!.run({
        _encInputName: encInputIds,
        _encMaskName: encMaskIds,
      });
      encHidden = encOut[_encOutputName];
      if (encHidden == null) {
        throw StateError(
          'Encoder did not produce "$_encOutputName". '
          'Available outputs: ${encOut.keys.toList()}',
        );
      }
      // Drop sibling outputs we don't need.
      for (final entry in encOut.entries) {
        if (entry.key != _encOutputName) {
          await entry.value.dispose();
        }
      }

      // 3. Decoder loop. NLLB / M2M100 generation:
      //   - decoder_start_token_id = 2 (</s>)
      //   - the model is forced to emit the target language token first
      // We seed the decoder input with both so step 0 already predicts a
      // content token.
      final decoded = <int>[tok.eosId, tgtId];
      int? lastTokenId;
      for (var step = 0; step < maxNewTokens; step++) {
        final decInputIds = await OrtValue.fromList(
          Int64List.fromList(decoded),
          [1, decoded.length],
        );
        perStepValues.add(decInputIds);

        final decOut = await _decoder!.run({
          _decInputName: decInputIds,
          _decEncMaskName: encMaskIds,
          _decEncHiddenName: encHidden,
        });

        final logitsValue = decOut[_decLogitsName];
        if (logitsValue == null) {
          throw StateError(
            'Decoder did not produce "$_decLogitsName". '
            'Available: ${decOut.keys.toList()}',
          );
        }
        // The no-cache decoder export also emits all `present.*.*.*`
        // KV-cache tensors. We don't feed them back (no past_key_values
        // input), so just dispose them so the native side reclaims memory.
        for (final entry in decOut.entries) {
          if (entry.key != _decLogitsName) {
            await entry.value.dispose();
          }
        }

        final shape = logitsValue.shape; // [1, dec_seq, vocab]
        final vocabSize = shape[2];
        final lastStepStart = (shape[1] - 1) * vocabSize;
        final flat = await logitsValue.asFlattenedList();
        await logitsValue.dispose();

        // Argmax over the final timestep only.
        var bestId = 0;
        var bestVal = double.negativeInfinity;
        for (var v = 0; v < vocabSize; v++) {
          final val = (flat[lastStepStart + v] as num).toDouble();
          if (val > bestVal) {
            bestVal = val;
            bestId = v;
          }
        }

        decoded.add(bestId);
        if (bestId == tok.eosId) break;
        // Defensive: M2M100 sometimes loops on `</s>` or the pad id when
        // confused; if we ever stall on a single repeated token, give up
        // rather than burn 200 steps for the same character.
        if (lastTokenId == bestId && _looksRepetitive(decoded)) break;
        lastTokenId = bestId;
      }

      // 4. Strip control prefix [eos_start, tgt_lang] before detokenizing.
      final body = decoded.sublist(2);
      return tok.decode(body);
    } finally {
      await encInputIds.dispose();
      await encMaskIds.dispose();
      await encHidden?.dispose();
      for (final v in perStepValues) {
        await v.dispose();
      }
    }
  }

  /// Trip the early-exit only when the tail looks like a degenerate
  /// repeat (e.g. last 6 tokens are the same id) — a single duplicate
  /// is normal in any language.
  static bool _looksRepetitive(List<int> ids) {
    if (ids.length < 8) return false;
    final tail = ids.sublist(ids.length - 6);
    final first = tail.first;
    return tail.every((id) => id == first);
  }

  @override
  Future<void> dispose() async {
    final enc = _encoder;
    final dec = _decoder;
    _encoder = null;
    _decoder = null;
    _tokenizer = null;
    await enc?.close();
    await dec?.close();
  }
}
