import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart' show AccumulatorSink;
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'model_manifest.dart';
import 'model_paths.dart';

/// One file's progress within a language bundle.
class FileProgress {
  const FileProgress({
    required this.file,
    required this.received,
    required this.total,
    required this.state,
    this.error,
  });

  final ModelFile file;
  final int received;
  final int total;
  final FileState state;
  final Object? error;

  double get fraction => total == 0 ? 0 : (received / total).clamp(0.0, 1.0);
}

enum FileState { pending, downloading, verifying, done, failed, alreadyPresent }

/// Aggregate progress across the whole bundle being downloaded.
class BundleProgress {
  const BundleProgress({
    required this.langCode,
    required this.files,
    required this.bytesReceived,
    required this.bytesTotal,
  });

  final String langCode;
  final List<FileProgress> files;
  final int bytesReceived;
  final int bytesTotal;

  double get fraction =>
      bytesTotal == 0 ? 0 : (bytesReceived / bytesTotal).clamp(0.0, 1.0);

  bool get isComplete =>
      files.isNotEmpty && files.every((f) => f.state == FileState.done || f.state == FileState.alreadyPresent);
}

/// Streams ONNX model files from Firebase Storage public URLs into the
/// app's sandbox at the same paths `ModelPaths` reads from.
///
/// Strategy:
/// - Fetch and parse the JSON manifest.
/// - For each file in the requested language bundle:
///   - If the destination already exists with the right size and sha256,
///     skip it (allows resuming after app restart).
///   - Else stream into `<dest>.part`, sha256 as we go, atomic-rename on
///     success, delete on hash mismatch or interruption.
///
/// No Firebase SDK dependency — plain HTTPS via `package:http`. Bucket
/// rules must allow public read on the model prefix.
class ModelDownloader {
  ModelDownloader({
    required this.manifestUrl,
    ModelPaths? paths,
    http.Client? client,
  })  : _paths = paths,
        _client = client ?? http.Client();

  /// Full URL to `manifest.json`, e.g.
  /// `https://firebasestorage.googleapis.com/v0/b/<bucket>/o/models%2Fv1%2Fmanifest.json?alt=media`.
  final String manifestUrl;

  ModelPaths? _paths;
  final http.Client _client;
  ModelManifest? _manifest;

  /// Fetch + cache the manifest. Cheap to call repeatedly within one
  /// session. Throws on network/parse failure so callers can show an
  /// error state.
  Future<ModelManifest> loadManifest() async {
    if (_manifest != null) return _manifest!;
    final resp = await _client.get(Uri.parse(manifestUrl));
    if (resp.statusCode != 200) {
      throw HttpException(
        'Manifest fetch failed: HTTP ${resp.statusCode}',
        uri: Uri.parse(manifestUrl),
      );
    }
    _manifest = ModelManifest.parse(utf8.decode(resp.bodyBytes));
    return _manifest!;
  }

  /// Returns true iff every file in [langCode]'s bundle already exists on
  /// disk at the right size. Hash check is intentionally skipped here —
  /// it would re-read ~1 GB on every call; we only verify after a fresh
  /// download. Use [verifyLanguage] for an explicit deep check.
  Future<bool> isLanguageReady(String langCode) async {
    final manifest = await loadManifest();
    final bundle = manifest.languages[langCode];
    if (bundle == null) return false;
    _paths ??= await ModelPaths.resolve();
    for (final f in bundle.files) {
      final dest = File('${_paths!.root}/${f.path}');
      if (!await dest.exists()) return false;
      if (await dest.length() != f.bytes) return false;
    }
    return true;
  }

  /// Download (or skip-if-present) every file for [langCode]. Emits
  /// progress on the returned stream. Closes the stream when done or on
  /// fatal error.
  Stream<BundleProgress> ensureLanguage(String langCode) async* {
    final manifest = await loadManifest();
    final bundle = manifest.languages[langCode];
    if (bundle == null) {
      throw ArgumentError('No manifest entry for language "$langCode"');
    }
    _paths ??= await ModelPaths.resolve();

    final progress = <FileProgress>[
      for (final f in bundle.files)
        FileProgress(file: f, received: 0, total: f.bytes, state: FileState.pending),
    ];

    BundleProgress snapshot() {
      final received = progress.fold<int>(0, (sum, p) => sum + p.received);
      return BundleProgress(
        langCode: langCode,
        files: List.unmodifiable(progress),
        bytesReceived: received,
        bytesTotal: bundle.totalBytes,
      );
    }

    yield snapshot();

    for (var i = 0; i < bundle.files.length; i++) {
      final file = bundle.files[i];
      final dest = File('${_paths!.root}/${file.path}');
      await dest.parent.create(recursive: true);

      // Fast path: already on disk with the right size. Trust it.
      if (await dest.exists() && await dest.length() == file.bytes) {
        progress[i] = FileProgress(
          file: file,
          received: file.bytes,
          total: file.bytes,
          state: FileState.alreadyPresent,
        );
        yield snapshot();
        continue;
      }

      try {
        await for (final received in _downloadOne(file, dest)) {
          progress[i] = FileProgress(
            file: file,
            received: received,
            total: file.bytes,
            state: FileState.downloading,
          );
          yield snapshot();
        }
        progress[i] = FileProgress(
          file: file,
          received: file.bytes,
          total: file.bytes,
          state: FileState.done,
        );
        yield snapshot();
      } catch (e) {
        progress[i] = FileProgress(
          file: file,
          received: progress[i].received,
          total: file.bytes,
          state: FileState.failed,
          error: e,
        );
        yield snapshot();
        rethrow;
      }
    }
  }

  /// Streams cumulative bytes-received as the file downloads. On success
  /// the file is atomically renamed into place. On hash mismatch or any
  /// error the partial file is deleted.
  Stream<int> _downloadOne(ModelFile file, File dest) async* {
    final url = '${_manifest!.baseUrl}'
        '${Uri.encodeComponent(file.remote)}?alt=media';
    final partial = File('${dest.path}.part');
    if (await partial.exists()) await partial.delete();

    final req = http.Request('GET', Uri.parse(url));
    final resp = await _client.send(req);
    if (resp.statusCode != 200) {
      throw HttpException(
        'Download failed: HTTP ${resp.statusCode} for ${file.remote}',
        uri: Uri.parse(url),
      );
    }

    final sink = partial.openWrite();
    final digestSink = AccumulatorSink<Digest>();
    final hasher = sha256.startChunkedConversion(digestSink);
    int received = 0;

    try {
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        yield received;
      }
      await sink.flush();
      await sink.close();
      hasher.close();

      if (received != file.bytes) {
        await partial.delete();
        throw StateError(
          'Size mismatch for ${file.path}: expected ${file.bytes}, got $received',
        );
      }
      final got = digestSink.events.single.toString();
      if (got != file.sha256) {
        await partial.delete();
        throw StateError(
          'Hash mismatch for ${file.path}: expected ${file.sha256}, got $got',
        );
      }

      // Atomic on the same filesystem (which APP_SUPPORT/<file> always is).
      await partial.rename(dest.path);
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      if (await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Optional deep check: re-hashes files on disk and returns the names of
  /// any that don't match. Slow (reads the whole file). Use sparingly.
  Future<List<String>> verifyLanguage(String langCode) async {
    final manifest = await loadManifest();
    final bundle = manifest.languages[langCode];
    if (bundle == null) return const ['<unknown language>'];
    _paths ??= await ModelPaths.resolve();
    final bad = <String>[];
    for (final f in bundle.files) {
      final dest = File('${_paths!.root}/${f.path}');
      if (!await dest.exists()) {
        bad.add(f.path);
        continue;
      }
      final digestSink = AccumulatorSink<Digest>();
      final hasher = sha256.startChunkedConversion(digestSink);
      await for (final chunk in dest.openRead()) {
        hasher.add(chunk);
      }
      hasher.close();
      if (digestSink.events.single.toString() != f.sha256) bad.add(f.path);
    }
    return bad;
  }

  void dispose() => _client.close();
}
