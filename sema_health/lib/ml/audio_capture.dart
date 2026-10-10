import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// Thin wrapper over the `record` package that gives us mono 16-bit PCM
/// at the model's expected sample rate, ready to feed into [Asr].
///
/// Two modes:
/// - [recordOneShot] — captures until [stop] is called and returns the
///   full PCM buffer. Use for a "hold to talk" UX.
/// - [stream] — yields [Uint8List] chunks of PCM as the mic produces
///   them. Use for streaming ASR (and waveform visualisation).
class AudioCapture {
  AudioCapture({this.sampleRate = 16000});

  /// The mic sample rate. Match the ASR model's expected sample rate
  /// (16 kHz is the typical ASR contract).
  final int sampleRate;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  final BytesBuilder _buffer = BytesBuilder();
  StreamController<Uint8List>? _streamCtrl;

  RecordConfig get _config => RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
      );

  /// Returns true once the user has granted mic access.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Start one-shot capture. Call [stopOneShot] to retrieve the buffer.
  Future<void> startOneShot() async {
    _buffer.clear();
    final stream = await _recorder.startStream(_config);
    _sub = stream.listen((chunk) => _buffer.add(chunk));
  }

  /// Stop one-shot capture and return the recorded PCM as Int16 samples.
  Future<Int16List> stopOneShot() async {
    await _recorder.stop();
    await _sub?.cancel();
    _sub = null;
    final bytes = _buffer.takeBytes();
    return _bytesToInt16(bytes);
  }

  /// Start streaming capture. Yields PCM chunks (raw little-endian Int16
  /// bytes). Caller stops by calling [stopStream].
  Stream<Uint8List> startStream() {
    _streamCtrl = StreamController<Uint8List>.broadcast();
    () async {
      final upstream = await _recorder.startStream(_config);
      _sub = upstream.listen(
        (chunk) {
          if (_streamCtrl?.isClosed ?? true) return;
          _streamCtrl!.add(chunk);
        },
        onError: (e, st) => _streamCtrl?.addError(e, st),
        onDone: () => _streamCtrl?.close(),
      );
    }();
    return _streamCtrl!.stream;
  }

  Future<void> stopStream() async {
    await _recorder.stop();
    await _sub?.cancel();
    _sub = null;
    await _streamCtrl?.close();
    _streamCtrl = null;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _streamCtrl?.close();
    await _recorder.dispose();
  }

  /// Reinterpret little-endian 16-bit PCM bytes as Int16 samples without
  /// copying when the buffer is already aligned.
  static Int16List _bytesToInt16(Uint8List bytes) {
    if (bytes.lengthInBytes % 2 != 0) {
      // Drop a trailing odd byte rather than crash; happens occasionally
      // at stream boundaries.
      bytes = bytes.sublist(0, bytes.lengthInBytes - 1);
    }
    return bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 2);
  }
}
