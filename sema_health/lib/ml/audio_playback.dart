import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'tts.dart';
import 'wav.dart';

/// Plays one [TtsResult] at a time via just_audio.
///
/// Writes a tiny WAV (44-byte header + PCM) to a temp file because
/// just_audio expects file/URL sources, not raw PCM streams. Cheap —
/// for a 5-second utterance the file is ~160 KB. When we move to true
/// streaming we'll swap this for `flutter_pcm_sound`.
class AudioPlayback {
  AudioPlayback();

  final AudioPlayer _player = AudioPlayer();
  int _seq = 0;

  /// Play a synthesized result. Awaits completion so callers can chain
  /// turn-by-turn output.
  Future<void> play(TtsResult result) async {
    final wavBytes = wrapPcm16AsWav(
      pcm: result.pcm,
      sampleRate: result.sampleRate,
    );
    final file = await _writeTempWav(wavBytes);
    await _player.setAudioSource(AudioSource.file(file.path));
    await _player.play();
    // Wait for natural completion. We don't `await player.processingState`
    // because just_audio's `.play()` future only completes when the
    // playback ends (when `setAudioSource` was used with a finite file).
    await _player.playerStateStream.firstWhere(
      (s) => s.processingState == ProcessingState.completed,
    );
  }

  Future<void> stop() => _player.stop();

  Future<void> dispose() async {
    await _player.dispose();
  }

  Future<File> _writeTempWav(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/sema_tts_${DateTime.now().millisecondsSinceEpoch}_${_seq++}.wav';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
