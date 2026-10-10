/// Streaming-free machine-translation interface.
///
/// One implementation today ([OnnxNllbTranslator]). The chat pipeline
/// only ever holds the abstract type so a future swap (e.g. a smaller
/// distilled model, or a server fallback for high-bandwidth devices)
/// doesn't ripple through the agent layer.
abstract class Translator {
  bool get isLoaded;

  /// Idempotent. Loads the encoder + decoder ONNX sessions and parses
  /// the tokenizer.json. Slow on first call (multi-second on mobile);
  /// cheap on repeats.
  Future<void> load();

  /// Translate [text] from [src] to [tgt]. Both codes are NLLB language
  /// tokens, e.g. `swh_Latn`, `aka_Latn`, `eng_Latn`, `yor_Latn`.
  ///
  /// Implementations must call [load] internally if not already loaded.
  /// Returns the empty string for empty input.
  Future<String> translate(
    String text, {
    required String src,
    required String tgt,
  });

  /// Release native sessions + tokenizer state.
  Future<void> dispose();
}

/// Pass-through translator used when MT isn't available on the device.
/// Lets the agent pipeline stay locale-aware without forcing every
/// caller to null-check.
class NullTranslator implements Translator {
  const NullTranslator();

  @override
  bool get isLoaded => true;

  @override
  Future<void> load() async {}

  @override
  Future<String> translate(String text, {required String src, required String tgt}) async => text;

  @override
  Future<void> dispose() async {}
}

/// Maps Sema's UI locale code to the NLLB language token used by the
/// model. Returns null when the language has no NLLB coverage —
/// callers treat that as "skip MT, pass text through unchanged".
///
/// Notable gap: **`ga` (Ga)** is not in the NLLB-200 vocabulary. The
/// closest neighbour by linguistic family + region would be `aka_Latn`
/// (Twi/Akan), but cross-lingual transfer for symptom language is too
/// risky to do silently — we return null and let the pipeline pass.
String? semaCodeToNllb(String code) {
  switch (code) {
    case 'en':
      return 'eng_Latn';
    case 'fr':
      return 'fra_Latn';
    case 'sw':
      return 'swh_Latn';
    case 'tw':
      return 'aka_Latn';
    case 'yo':
      return 'yor_Latn';
    case 'ga':
    default:
      return null;
  }
}
