import 'dart:typed_data';

/// Build an in-memory WAV (RIFF) byte buffer for mono 16-bit PCM at the
/// given sample rate. 44-byte header + raw PCM payload. Used to hand
/// generated audio to `just_audio` (which speaks file/byte sources, not
/// raw PCM).
Uint8List wrapPcm16AsWav({
  required Int16List pcm,
  required int sampleRate,
  int channels = 1,
}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final dataBytes = pcm.lengthInBytes;
  final fileSize = 36 + dataBytes; // RIFF chunk size
  final out = BytesBuilder(copy: false);

  // RIFF header
  out.add(_ascii('RIFF'));
  out.add(_uint32Le(fileSize));
  out.add(_ascii('WAVE'));

  // fmt subchunk
  out.add(_ascii('fmt '));
  out.add(_uint32Le(16));        // PCM subchunk size
  out.add(_uint16Le(1));         // audio format = PCM
  out.add(_uint16Le(channels));
  out.add(_uint32Le(sampleRate));
  out.add(_uint32Le(byteRate));
  out.add(_uint16Le(blockAlign));
  out.add(_uint16Le(bitsPerSample));

  // data subchunk
  out.add(_ascii('data'));
  out.add(_uint32Le(dataBytes));
  out.add(pcm.buffer.asUint8List(pcm.offsetInBytes, dataBytes));

  return out.toBytes();
}

List<int> _ascii(String s) => s.codeUnits;

Uint8List _uint16Le(int v) {
  final b = ByteData(2)..setUint16(0, v, Endian.little);
  return b.buffer.asUint8List();
}

Uint8List _uint32Le(int v) {
  final b = ByteData(4)..setUint32(0, v, Endian.little);
  return b.buffer.asUint8List();
}
