import 'dart:io';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'model_paths.dart';

/// Loads a model and reports its input/output tensor specs. Replaces the
/// usual "run a Python script to look at the model" step — we just ask
/// ONNX Runtime to tell us itself, on the device.
class OrtInspector {
  OrtInspector(this._paths);

  final ModelPaths _paths;
  final OnnxRuntime _ort = OnnxRuntime();

  /// Inspect both ASR + TTS for a given language.
  Future<InspectionReport> inspectLanguage(String langCode) async {
    final providers = await _ort.getAvailableProviders();

    // Diagnostic — list what the app can actually see in its model dirs.
    // Helps distinguish "wrong path" from "scoped storage blocking us".
    final diag = await _diagnoseFilesystem(langCode);

    final asr = await _paths.asrFor(langCode);
    final tts = await _paths.ttsFor(langCode);

    final asrSpec = asr == null
        ? ModelSpec.missing('stt_$langCode')
        : await _inspect(asr);
    final ttsSpec = tts == null
        ? ModelSpec.missing('tts_$langCode')
        : await _inspect(tts);

    return InspectionReport(
      languageCode: langCode,
      providers: providers.map((p) => p.name).toList(),
      asr: asrSpec,
      tts: ttsSpec,
      pushHint: _paths.pushHint(langCode),
      diagnostics: diag,
    );
  }

  Future<List<String>> _diagnoseFilesystem(String langCode) async {
    final lines = <String>[];
    lines.add('root = ${_paths.root}');
    final sttDir = Directory('${_paths.root}/stt');
    final ttsDir = Directory('${_paths.root}/tts');
    for (final d in [sttDir, ttsDir]) {
      lines.add('');
      lines.add(d.path);
      try {
        final exists = await d.exists();
        lines.add('  exists()      = $exists');
        if (exists) {
          final entries = await d.list().toList();
          lines.add('  entries.count = ${entries.length}');
          for (final e in entries) {
            FileStat? stat;
            try {
              stat = await e.stat();
            } catch (_) {}
            lines.add('    - ${e.path.split('/').last}'
                ' size=${stat?.size ?? '?'}'
                ' mode=${stat?.modeString() ?? '?'}'
                ' type=${stat?.type ?? '?'}');
          }
        }
      } catch (e) {
        lines.add('  list() threw: $e');
      }
    }
    // Try opening one specific candidate to see what error surfaces.
    final probe = File('${_paths.root}/stt/stt_${langCode}_int8.onnx');
    lines.add('');
    lines.add('probe ${probe.path}');
    try {
      lines.add('  exists() = ${await probe.exists()}');
      lines.add('  length() = ${await probe.length()}');
    } catch (e) {
      lines.add('  threw: $e');
    }
    return lines;
  }

  Future<ModelSpec> _inspect(File modelFile) async {
    OrtSession? session;
    try {
      session = await _ort.createSession(modelFile.path);
      final meta = await session.getMetadata();
      final inputs = await session.getInputInfo();
      final outputs = await session.getOutputInfo();
      return ModelSpec.loaded(
        path: modelFile.path,
        sizeBytes: await modelFile.length(),
        producer: meta.producerName,
        graphName: meta.graphName,
        description: meta.description,
        inputs: inputs.map(TensorSpec.fromMap).toList(),
        outputs: outputs.map(TensorSpec.fromMap).toList(),
      );
    } catch (e, st) {
      return ModelSpec.error(
        path: modelFile.path,
        sizeBytes: await modelFile.length(),
        error: '$e\n$st',
      );
    } finally {
      await session?.close();
    }
  }
}

class InspectionReport {
  InspectionReport({
    required this.languageCode,
    required this.providers,
    required this.asr,
    required this.tts,
    required this.pushHint,
    this.diagnostics = const [],
  });

  final String languageCode;
  final List<String> providers;
  final ModelSpec asr;
  final ModelSpec tts;
  final String pushHint;
  final List<String> diagnostics;

  String prettyPrint() {
    final b = StringBuffer();
    b.writeln('═══════════════════════════════════════════');
    b.writeln(' Sema · ORT inspection · lang=$languageCode');
    b.writeln('═══════════════════════════════════════════');
    b.writeln('Available providers: ${providers.join(', ')}');
    if (diagnostics.isNotEmpty) {
      b.writeln('');
      b.writeln('── filesystem diagnostics ──────────────────');
      for (final l in diagnostics) {
        b.writeln(l);
      }
    }
    b.writeln('');
    b.writeln('── ASR (stt_$languageCode) ────────────────');
    b.writeln(asr.prettyPrint());
    b.writeln('── TTS (tts_$languageCode) ────────────────');
    b.writeln(tts.prettyPrint());
    if (asr.kind == ModelStatus.missing || tts.kind == ModelStatus.missing) {
      b.writeln('');
      b.writeln('One or more models missing.');
      b.writeln(pushHint);
    }
    return b.toString();
  }
}

enum ModelStatus { loaded, error, missing }

class ModelSpec {
  ModelSpec._({
    required this.kind,
    required this.label,
    this.path,
    this.sizeBytes,
    this.producer,
    this.graphName,
    this.description,
    this.inputs = const [],
    this.outputs = const [],
    this.error,
  });

  final ModelStatus kind;
  final String label;
  final String? path;
  final int? sizeBytes;
  final String? producer;
  final String? graphName;
  final String? description;
  final List<TensorSpec> inputs;
  final List<TensorSpec> outputs;
  final String? error;

  factory ModelSpec.missing(String label) =>
      ModelSpec._(kind: ModelStatus.missing, label: label);

  factory ModelSpec.error({
    required String path,
    required int sizeBytes,
    required String error,
  }) =>
      ModelSpec._(
        kind: ModelStatus.error,
        label: path.split('/').last,
        path: path,
        sizeBytes: sizeBytes,
        error: error,
      );

  factory ModelSpec.loaded({
    required String path,
    required int sizeBytes,
    required String? producer,
    required String? graphName,
    required String? description,
    required List<TensorSpec> inputs,
    required List<TensorSpec> outputs,
  }) =>
      ModelSpec._(
        kind: ModelStatus.loaded,
        label: path.split('/').last,
        path: path,
        sizeBytes: sizeBytes,
        producer: producer,
        graphName: graphName,
        description: description,
        inputs: inputs,
        outputs: outputs,
      );

  String prettyPrint() {
    switch (kind) {
      case ModelStatus.missing:
        return '  ✗ missing on device\n';
      case ModelStatus.error:
        return '  ✗ failed to load ($label)\n  $error\n';
      case ModelStatus.loaded:
        final b = StringBuffer();
        b.writeln('  ✓ $label  (${_humanBytes(sizeBytes ?? 0)})');
        if (producer != null && producer!.isNotEmpty) {
          b.writeln('    producer: $producer');
        }
        if (graphName != null && graphName!.isNotEmpty) {
          b.writeln('    graph:    $graphName');
        }
        b.writeln('    inputs:');
        for (final t in inputs) {
          b.writeln('      - ${t.format()}');
        }
        b.writeln('    outputs:');
        for (final t in outputs) {
          b.writeln('      - ${t.format()}');
        }
        return b.toString();
    }
  }

  static String _humanBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class TensorSpec {
  const TensorSpec({required this.name, required this.shape, required this.type});
  final String name;
  final List<dynamic> shape;
  final String type;

  factory TensorSpec.fromMap(Map<String, dynamic> m) => TensorSpec(
        name: (m['name'] ?? '?') as String,
        shape: (m['shape'] as List?) ?? const [],
        type: (m['type'] ?? '?').toString(),
      );

  String format() => '$name : $type · shape=$shape';
}
