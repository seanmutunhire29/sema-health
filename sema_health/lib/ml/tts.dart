import 'dart:typed_data';

/// Result of a TTS synthesize call.
class TtsResult {
  const TtsResult({required this.pcm, required this.sampleRate});

  /// Mono 16-bit PCM samples ready to feed into the audio output layer.
  final Int16List pcm;

  /// Sample rate the audio was produced at. Used by the player.
  final int sampleRate;
}

/// Text-to-speech for Sema. One implementation per language; the router
/// picks based on the active profile.
abstract class Tts {
  /// Output sample rate the model produces (e.g. 22050).
  int get sampleRate;

  /// Load the model file. Idempotent.
  Future<void> load();

  /// Synthesize speech for [text]. Implementations may throw if the
  /// active language's voice isn't available; the orchestrator will fall
  /// back to eSpeak NG in that case.
  Future<TtsResult> synthesize(String text);

  /// Release native resources.
  Future<void> dispose();
}
