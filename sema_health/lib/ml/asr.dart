import 'dart:typed_data';

/// Result of an ASR turn.
///
/// `confidence` is per-utterance, summarising the model's certainty across
/// the decoded tokens. The router uses it to decide whether to ask the
/// user to repeat.
class AsrResult {
  const AsrResult({required this.text, required this.confidence});
  final String text;
  final double confidence;
}

/// Speech-to-text for Sema. Implementations are language-specific; the
/// router picks one per active profile language.
///
/// Contract:
/// - `transcribe` is called with raw 16-bit signed PCM mono samples at
///   the model's expected sample rate (set by [sampleRate]). Callers are
///   responsible for resampling/format conversion before calling.
/// - Implementations must be safe to call repeatedly; loading is one-shot
///   in [load].
abstract class Asr {
  /// Sample rate the model expects (e.g. 16000).
  int get sampleRate;

  /// Load the model file and warm any caches. Call once at app start (or
  /// lazy on first need). Idempotent.
  Future<void> load();

  /// Run inference. Returns the decoded transcript.
  Future<AsrResult> transcribe(Int16List pcm);

  /// Release native resources. Call when switching profiles to a
  /// different language to free memory.
  Future<void> dispose();
}
