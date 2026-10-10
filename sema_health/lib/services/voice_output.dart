import 'dart:async';

import '../ml/audio_playback.dart';
import '../ml/tts_onnx.dart';

/// TTS → speaker controller for the chat bubbles' play button.
///
/// One instance per TTS language code (`'aka'`, `'swh'`). Wraps the
/// existing [OnnxTts] + [AudioPlayback] pair, lazy-loads the model on
/// the first speak, and enforces single-utterance-at-a-time playback
/// (a new [speak] interrupts the previous one).
///
/// State surfaced for the UI:
/// - [isLoading] — model is mmap'ing for the first time.
/// - [isSpeaking] — audio is currently playing.
/// - [activeUtteranceId] — opaque id of the currently-playing utterance,
///   so a bubble can render its play icon as "now playing".
class VoiceOutput {
  VoiceOutput({required this.langCode});

  /// MMS-TTS bundle code: `'aka'` for Twi, `'swh'` for Swahili. Matches
  /// `assets/models/tts/lang_<langCode>.json` and the on-device file
  /// `tts_<langCode>.onnx`.
  final String langCode;

  OnnxTts? _tts;
  AudioPlayback? _playback;

  bool _loading = false;
  bool _speaking = false;
  int _seq = 0;
  int? _activeId;
  Object? _lastError;

  bool get isLoading => _loading;
  bool get isSpeaking => _speaking;
  int? get activeUtteranceId => _activeId;
  Object? get lastError => _lastError;

  /// Speak [text]. Returns the utterance id so the caller can compare
  /// against [activeUtteranceId] to know whether *its* utterance is
  /// still the one playing.
  ///
  /// Interrupts any currently-playing utterance. Empty input is a no-op.
  Future<int> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return -1;

    final id = ++_seq;
    _activeId = id;
    _lastError = null;

    // Stop any in-flight playback before we synthesize the next one.
    // synthesize() takes ~200–800 ms; without this stop the user would
    // hear the tail of the previous utterance overlap with the new one.
    if (_speaking) {
      try {
        await _playback?.stop();
      } catch (_) {/* tear-down errors are not user-actionable */}
    }

    try {
      _loading = _tts == null || !_tts!.isLoaded;
      _tts ??= OnnxTts(langCode: langCode);
      if (!_tts!.isLoaded) await _tts!.load();
      _loading = false;

      // Mid-load, the user may have already tapped a different bubble.
      // Bail before allocating playback to avoid stomping a newer call.
      if (_activeId != id) return id;

      final result = await _tts!.synthesize(trimmed);
      if (_activeId != id) return id;

      _playback ??= AudioPlayback();
      _speaking = true;
      try {
        await _playback!.play(result);
      } finally {
        // play() awaits the natural-completion event, so by here the
        // utterance is done — unless a newer speak() already updated
        // _activeId, in which case we leave the flags to that newer call.
        if (_activeId == id) {
          _speaking = false;
          _activeId = null;
        }
      }
    } on Object catch (e) {
      _lastError = e;
      if (_activeId == id) {
        _speaking = false;
        _activeId = null;
      }
    } finally {
      _loading = false;
    }
    return id;
  }

  /// Stop the currently-playing utterance, if any. Safe to call when
  /// nothing is speaking.
  Future<void> stop() async {
    _activeId = null;
    _speaking = false;
    try {
      await _playback?.stop();
    } catch (_) {/* nothing to do */}
  }

  Future<void> dispose() async {
    _activeId = null;
    _speaking = false;
    await _playback?.dispose();
    await _tts?.dispose();
    _playback = null;
    _tts = null;
  }

  /// Map the Sema UI locale to the TTS model code. Mirrors
  /// [VoiceInput.voiceCodeFor] — kept separate so future asymmetries
  /// (a language with STT but no TTS, or vice versa) stay easy to
  /// express.
  static String? voiceCodeFor(String semaLocale) {
    switch (semaLocale) {
      case 'sw':
        return 'swh';
      case 'tw':
        return 'aka';
      case 'en':
        return 'eng';
      case 'fr':
        return 'fra';
      default:
        return null;
    }
  }
}
