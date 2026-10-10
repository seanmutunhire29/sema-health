import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../ml/model_paths.dart';

/// Streaming generation interface — model-agnostic. Today only [GemmaLlm]
/// implements it; a future ONNX-Runtime variant could swap in without
/// touching callers.
abstract class Llm {
  bool get isLoaded;

  /// Whether this LLM's loaded model has vision modality enabled. When
  /// false, [describeImage] throws — callers should check before
  /// surfacing camera affordances in the UI.
  bool get supportsVision;

  /// Idempotent. Loads the model into the runtime. Slow on first call
  /// (model can be 1+ GB), instant on repeat.
  Future<void> load();

  /// Streams tokens (or token chunks) for [prompt]. Caller can `await for`
  /// or `.listen`. The returned stream completes when the model emits its
  /// stop token or [maxTokens] is reached.
  Stream<String> generate(
    String prompt, {
    int maxTokens,
    String? systemPrompt,
    double? temperature,
  });

  /// One-shot image + text inference. Returns the model's full reply as
  /// a single string — we drain the stream internally because the chat
  /// surfaces the description as a *finished* user-side bubble rather
  /// than streaming live. Throws when [supportsVision] is false.
  Future<String> describeImage({
    required Uint8List imageBytes,
    required String prompt,
    int maxTokens,
    double? temperature,
  });

  /// Release native resources. Call when switching variants or on app
  /// background if memory is tight.
  Future<void> dispose();
}

/// Gemma backed by `flutter_gemma` (MediaPipe LLM Inference). Loads from
/// a local `.task` file (no copy) — same dev-time push-via-run-as
/// procedure we use for the ONNX models.
class GemmaLlm implements Llm {
  GemmaLlm({
    required this.variant,
    this.maxContextTokens = 1024,
    this.defaultTemperature = 0.8,
    this.topK = 40,
    this.topP,
    this.preferredBackend,
    this.enableVision = false,
    ModelPaths? paths,
  }) : _paths = paths;

  /// Filename (no extension) — e.g. `gemma_3n_e2b_int4`. Resolves to
  /// `<root>/llm/<variant>.task`.
  final String variant;

  /// Max context window the session is built with. Bigger = more memory
  /// but supports longer conversations. Capped at 1024 on mid-tier
  /// Android — 2048 with `supportImage: true` pushed the device over
  /// its app memory budget (observed OOM mid-session on Pixel 7a).
  final int maxContextTokens;
  final double defaultTemperature;
  final int topK;
  final double? topP;
  final PreferredBackend? preferredBackend;

  /// Whether to request vision modality at install time. Gemma 3n's
  /// E2B int4 supports vision; other variants may not, in which case
  /// MediaPipe silently ignores the flag.
  ///
  /// Default is **false** on the hackathon build because enabling vision
  /// reserves ~200-500 MB of image-encoder buffers at session creation,
  /// even on text-only turns. Combined with the 2 GB Gemma weight set
  /// and ~1.1 GB of NLLB ONNX, that pushed mid-tier Android (6 GB total,
  /// ~3-4 GB app budget) past its memory ceiling and produced a native
  /// SIGSEGV mid-decode on emergency-severity replies like a choking
  /// turn that triggers a long response. The camera affordance in the
  /// chat UI is gated on `supportsVision` so it auto-hides while this
  /// is false. To re-enable later: flip this default back to true and
  /// also drop NLLB to free room, or move NLLB inference off-thread.
  final bool enableVision;

  ModelPaths? _paths;
  InferenceModel? _model;
  bool _initialized = false;

  @override
  bool get isLoaded => _model != null;

  @override
  bool get supportsVision => enableVision && _model != null;

  @override
  Future<void> load() async {
    if (_model != null) return;

    if (!_initialized) {
      // Idempotent in flutter_gemma; safe to call once per app session.
      await FlutterGemma.initialize();
      _initialized = true;
    }

    _paths ??= await ModelPaths.resolve();
    final modelFile = await _paths!.llmFor(variant);
    if (modelFile == null) {
      throw StateError(
        'Gemma model "$variant.task" missing on device. '
        'Push it via run-as. App-side root: ${_paths!.root}',
      );
    }

    // Register the .task at its current path. flutter_gemma's FileSource
    // does NOT copy the file — keeps the 1+ GB blob in one place. The
    // installer just records the spec; vision/audio modality is selected
    // when we actually materialize the InferenceModel below.
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.task,
    ).fromFile(modelFile.path).install();

    _model = await FlutterGemma.getActiveModel(
      maxTokens: maxContextTokens,
      preferredBackend: preferredBackend,
      // Audio left off — Gemma 3n E4B only; our E2B int4 ships without
      // an audio encoder.
      supportImage: enableVision,
      maxNumImages: enableVision ? 1 : null,
    );
  }

  @override
  Stream<String> generate(
    String prompt, {
    int maxTokens = 256,
    String? systemPrompt,
    double? temperature,
  }) async* {
    if (_model == null) {
      throw StateError('Llm.load() must be called before generate().');
    }

    // Session reuse was tried (cached by systemPrompt+temperature) but
    // produced a native SIGSEGV inside MediaPipe's LiteRT decoder when
    // callers break-early on the response stream (e.g. on a sentinel
    // like `###END###`): the half-consumed session was reused on the
    // next call and the decoder read a freed KV-cache pointer.
    // Back to per-call create+close — eats ~1 s of LiteRT init per
    // call but is stable. The performance loss is real but acceptable;
    // the crash was not.
    final session = await _model!.createSession(
      temperature: temperature ?? defaultTemperature,
      topK: topK,
      topP: topP,
      systemInstruction: systemPrompt,
    );
    try {
      await session.addQueryChunk(Message.text(text: prompt, isUser: true));
      yield* session.getResponseAsync();
    } finally {
      try {
        await session.close();
      } catch (_) {
        // Already gone or never created — ignore so we don't mask a
        // real upstream error from generate().
      }
    }
  }

  @override
  Future<String> describeImage({
    required Uint8List imageBytes,
    required String prompt,
    int maxTokens = 160,
    double? temperature,
  }) async {
    if (_model == null) {
      throw StateError('Llm.load() must be called before describeImage().');
    }
    if (!enableVision) {
      throw StateError(
        'GemmaLlm "$variant" was constructed with enableVision=false. '
        'Rebuild with enableVision: true to use vision modality.',
      );
    }

    // Low temperature: image descriptions should be factual, not creative.
    final session = await _model!.createSession(
      temperature: temperature ?? 0.2,
      topK: topK,
      topP: topP,
    );
    try {
      await session.addQueryChunk(
        Message.withImage(text: prompt, imageBytes: imageBytes, isUser: true),
      );
      final buf = StringBuffer();
      await for (final chunk in session.getResponseAsync()) {
        buf.write(chunk);
        // Defensive ceiling — vision responses sometimes ramble.
        if (buf.length > 800) break;
      }
      return buf.toString().trim();
    } finally {
      await session.close();
    }
  }

  @override
  Future<void> dispose() async {
    final m = _model;
    _model = null;
    await m?.close();
  }
}

/// Helper: returns `true` if the .task file is present at the expected
/// path. Used by the inspector before attempting a load.
Future<File?> resolveLlmFile(String variant) async {
  final paths = await ModelPaths.resolve();
  return paths.llmFor(variant);
}
