import 'dart:async';

import '../ml/asr_onnx.dart';
import '../ml/audio_capture.dart';

/// Mic → STT controller for the chat composer.
///
/// One instance per ASR language code (`'aka'`, `'swh'`). Wraps the
/// existing [AudioCapture] + [OnnxAsr] pair into a tap-to-record /
/// tap-to-stop interface, hides permission handling, and lazy-loads
/// the ASR model on the first stop so cold-open of the chat doesn't
/// pay the mmap cost up front.
///
/// State machine:
/// ```
///   idle  ──start()──▶  recording  ──stop()──▶  transcribing  ──▶  idle
///                            │
///                            └──cancel()──▶  idle  (audio dropped)
/// ```
///
/// Concurrency: `start` while already recording is a no-op; `stop`
/// while idle returns an empty result. There is no parallel-recording
/// case to worry about because the chat only has one mic button.
class VoiceInput {
  VoiceInput({required this.langCode});

  /// ASR model + capture sample-rate code: `'aka'` for Twi, `'swh'` for
  /// Swahili. Matches the bundle filename under
  /// `assets/models/stt/stt_<langCode>_vocab.json` and the on-device
  /// model file `stt_<langCode>_int8.onnx`.
  final String langCode;

  AudioCapture? _capture;
  OnnxAsr? _asr;

  bool _recording = false;
  bool _transcribing = false;
  Object? _lastError;

  /// True between [start] and [stop].
  bool get isRecording => _recording;

  /// True while ASR inference is running on the captured PCM.
  bool get isTranscribing => _transcribing;

  /// True when neither recording nor transcribing.
  bool get isIdle => !_recording && !_transcribing;

  /// Last error from a load / start / transcribe call. Cleared on the
  /// next successful call. Useful for surfacing copy in the composer.
  Object? get lastError => _lastError;

  /// True if mic permission has been granted. Triggers the OS prompt
  /// the first time it's asked.
  Future<bool> hasPermission() async {
    _capture ??= AudioCapture(sampleRate: 16000);
    return _capture!.hasPermission();
  }

  /// Begin one-shot recording. Idempotent: a second call while already
  /// recording is dropped.
  ///
  /// Returns false (and records [lastError]) if the mic permission was
  /// denied or the recorder failed to start. The caller should surface
  /// a "grant mic permission" snackbar on false.
  Future<bool> start() async {
    if (_recording) return true;
    _lastError = null;
    _capture ??= AudioCapture(sampleRate: 16000);
    try {
      final ok = await _capture!.hasPermission();
      if (!ok) {
        _lastError = const _MicPermissionDenied();
        return false;
      }
      await _capture!.startOneShot();
      _recording = true;
      return true;
    } catch (e) {
      _lastError = e;
      return false;
    }
  }

  /// Stop the mic and run ASR over the captured buffer. Returns the
  /// decoded transcript (may be empty if the model heard nothing).
  ///
  /// Triggers the model's first-time mmap on initial use — expect a
  /// 500–1500 ms delay before this future resolves on a cold call.
  Future<String> stop() async {
    if (!_recording) return '';
    _recording = false;
    _transcribing = true;
    try {
      final pcm = await _capture!.stopOneShot();
      if (pcm.isEmpty) return '';
      _asr ??= OnnxAsr(langCode: langCode);
      if (!_asr!.isLoaded) await _asr!.load();
      final result = await _asr!.transcribe(pcm);
      return result.text;
    } catch (e) {
      _lastError = e;
      return '';
    } finally {
      _transcribing = false;
    }
  }

  /// Stop the mic and discard the captured audio without running ASR.
  /// Used when the composer is dismissed mid-record.
  Future<void> cancel() async {
    if (!_recording) return;
    _recording = false;
    try {
      await _capture?.stopOneShot();
    } catch (_) {
      // Cancel paths swallow capture errors — we're throwing the audio
      // away anyway.
    }
  }

  Future<void> dispose() async {
    _recording = false;
    _transcribing = false;
    await _capture?.dispose();
    await _asr?.dispose();
    _capture = null;
    _asr = null;
  }

  /// Map the Sema UI locale (`'sw'`, `'tw'`, …) to the ASR model code
  /// (`'swh'`, `'aka'`). Returns null when no on-device ASR model
  /// exists — callers treat that as "voice unavailable for this locale".
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

/// Sentinel error so the composer can render the right copy.
class _MicPermissionDenied implements Exception {
  const _MicPermissionDenied();
  @override
  String toString() =>
      'Mic permission denied. Grant it in Settings to use voice input.';
}
