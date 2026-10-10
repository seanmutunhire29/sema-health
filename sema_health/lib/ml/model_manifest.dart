import 'dart:convert';

/// Wire format for the JSON the app fetches from Firebase Storage at
/// `<baseUrl>/<urlEncoded(remote)>?alt=media`. The manifest itself is
/// uploaded to the same prefix as the models so a single base URL covers
/// everything.
class ModelManifest {
  ModelManifest({
    required this.version,
    required this.baseUrl,
    required this.languages,
  });

  /// Manifest schema version. Bump when fields change so old clients can
  /// surface a friendly "please update the app" message instead of
  /// silently parsing wrong fields.
  final int version;

  /// Firebase Storage `/o/` endpoint prefix, e.g.
  /// `https://firebasestorage.googleapis.com/v0/b/<bucket>/o/`. We append
  /// the URL-encoded `remote` path and `?alt=media` per file.
  final String baseUrl;

  /// model-langCode (e.g. `aka`, `swh`) → bundle for that language.
  final Map<String, ModelLanguageBundle> languages;

  factory ModelManifest.fromJson(Map<String, dynamic> json) {
    final langs = (json['languages'] as Map<String, dynamic>).map(
      (code, raw) => MapEntry(
        code,
        ModelLanguageBundle.fromJson(code, raw as Map<String, dynamic>),
      ),
    );
    return ModelManifest(
      version: (json['version'] as num).toInt(),
      baseUrl: json['baseUrl'] as String,
      languages: langs,
    );
  }

  static ModelManifest parse(String source) =>
      ModelManifest.fromJson(jsonDecode(source) as Map<String, dynamic>);
}

class ModelLanguageBundle {
  ModelLanguageBundle({
    required this.code,
    required this.name,
    required this.files,
  });

  final String code;
  final String name;
  final List<ModelFile> files;

  int get totalBytes =>
      files.fold(0, (sum, f) => sum + f.bytes);

  factory ModelLanguageBundle.fromJson(String code, Map<String, dynamic> json) {
    final files = (json['files'] as List<dynamic>)
        .map((raw) => ModelFile.fromJson(raw as Map<String, dynamic>))
        .toList(growable: false);
    return ModelLanguageBundle(
      code: code,
      name: json['name'] as String? ?? code,
      files: files,
    );
  }
}

class ModelFile {
  ModelFile({
    required this.kind,
    required this.path,
    required this.remote,
    required this.bytes,
    required this.sha256,
  });

  /// Logical role: `stt`, `tts`, `llm`. Only used for UI labelling — the
  /// downloader treats every file the same.
  final String kind;

  /// Path **relative to `ModelPaths.root`**. The downloader writes here.
  /// Must match what `OnnxAsr.load()` / `OnnxTts.load()` expect (see
  /// `ModelPaths.asrFor` / `ttsFor`).
  final String path;

  /// Path **relative to the bucket's `/o/` endpoint**. URL-encoded by
  /// the downloader before being appended to `baseUrl`.
  final String remote;

  final int bytes;

  /// Lowercase hex sha256. Verified after download; mismatch → discard.
  final String sha256;

  factory ModelFile.fromJson(Map<String, dynamic> json) => ModelFile(
        kind: json['kind'] as String,
        path: json['path'] as String,
        remote: json['remote'] as String,
        bytes: (json['bytes'] as num).toInt(),
        sha256: (json['sha256'] as String).toLowerCase(),
      );
}
