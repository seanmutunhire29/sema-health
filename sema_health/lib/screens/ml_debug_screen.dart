import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../ai/llm.dart';
import '../ml/asr_onnx.dart';
import '../ml/audio_capture.dart';
import '../ml/audio_playback.dart';
import '../ml/model_paths.dart';
import '../ml/ort_inspector.dart';
import '../ml/tts_onnx.dart';
import '../theme/tokens.dart';
import '../widgets/press_scale.dart';
import '../widgets/sema_button.dart';

/// Variant we ship as primary. Maps to `<root>/llm/<variant>.task`.
const String _gemmaVariant = 'gemma_3n_e2b_int4';

/// Dev-only screen.
///
/// Section 1 (Inspect) loads STT + TTS and dumps tensor specs.
/// Section 2 (Speak) drives TTS end-to-end: type → synthesize → play.
class MlDebugScreen extends StatefulWidget {
  const MlDebugScreen({super.key, this.langCode = 'aka'});
  final String langCode;

  @override
  State<MlDebugScreen> createState() => _MlDebugScreenState();
}

/// Per-language metadata for the debug picker. Add a new entry here when
/// the model team ships a new language; everything else is wired through
/// the language code.
class _LangChoice {
  const _LangChoice(this.code, this.label, this.sampleText, this.accent);
  final String code;
  final String label;
  final String sampleText;
  final SemaAccent accent;
}

class _MlDebugScreenState extends State<MlDebugScreen> {
  static const _langs = <_LangChoice>[
    _LangChoice('aka', 'Twi (aka)', 'midin de richmond nawonsue', SemaAccent.mint),
    _LangChoice('swh', 'Swahili (swh)',
        'Habari yako, jina langu ni Richmond.', SemaAccent.butter),
  ];

  late _LangChoice _lang =
      _langs.firstWhere((l) => l.code == widget.langCode, orElse: () => _langs.first);

  // Inspect state
  String _inspectOutput =
      'Tap "Inspect models" to load and dump tensor specs.';
  bool _inspectBusy = false;

  // Speak state
  final _ttsCtl = TextEditingController();
  String _speakStatus = 'Type text and tap Speak.';
  bool _speakBusy = false;
  OnnxTts? _tts;
  AudioPlayback? _playback;

  // Listen state
  String _listenStatus = 'Tap Record to start. Tap Stop to transcribe.';
  String _transcript = '';
  bool _listening = false;
  bool _transcribing = false;
  OnnxAsr? _asr;
  AudioCapture? _capture;
  Stopwatch? _recordSw;

  // Generate (LLM) state — language-agnostic; same Gemma handles en/fr
  // direct and pivots for low-resource languages once the router lands.
  final _genCtl = TextEditingController(
    text: 'Tell me about Accra in 1 sentence.',
  );
  String _genStatus = 'Type a prompt and tap Generate.';
  String _genOutput = '';
  bool _genBusy = false;
  GemmaLlm? _llm;

  @override
  void initState() {
    super.initState();
    _ttsCtl.text = _lang.sampleText;
  }

  @override
  void dispose() {
    _ttsCtl.dispose();
    _genCtl.dispose();
    _tts?.dispose();
    _playback?.dispose();
    _asr?.dispose();
    _capture?.dispose();
    _llm?.dispose();
    super.dispose();
  }

  /// Switching language has to fully tear down the ORT sessions, the
  /// playback player, and any in-flight recording — otherwise we'd hand
  /// a Twi waveform to the Swahili decoder, etc.
  Future<void> _switchLanguage(_LangChoice next) async {
    if (next.code == _lang.code) return;
    if (_inspectBusy || _speakBusy || _transcribing || _listening) return;

    final oldTts = _tts;
    final oldAsr = _asr;
    final oldPlayback = _playback;
    final oldCapture = _capture;

    setState(() {
      _lang = next;
      _ttsCtl.text = next.sampleText;
      _inspectOutput =
          'Tap "Inspect models" to load and dump tensor specs.';
      _speakStatus = 'Type text and tap Speak.';
      _listenStatus = 'Tap Record to start. Tap Stop to transcribe.';
      _transcript = '';
      _tts = null;
      _asr = null;
      _playback = null;
      _capture = null;
    });

    await oldTts?.dispose();
    await oldAsr?.dispose();
    await oldPlayback?.dispose();
    await oldCapture?.dispose();
  }

  Future<void> _runInspect() async {
    setState(() {
      _inspectBusy = true;
      _inspectOutput = 'Resolving model paths…';
    });
    try {
      final paths = await ModelPaths.resolve();
      setState(() => _inspectOutput = 'Loading models from ${paths.root}…');
      final report =
          await OrtInspector(paths).inspectLanguage(_lang.code);
      final pretty = report.prettyPrint();
      // ignore: avoid_print
      print(pretty);
      setState(() => _inspectOutput = pretty);
    } catch (e, st) {
      setState(() => _inspectOutput = 'Failed:\n$e\n$st');
    } finally {
      setState(() => _inspectBusy = false);
    }
  }

  Future<void> _runSpeak() async {
    final text = _ttsCtl.text.trim();
    if (text.isEmpty) {
      setState(() => _speakStatus = 'Type something first.');
      return;
    }
    setState(() {
      _speakBusy = true;
      _speakStatus = 'Loading TTS model…';
    });
    final stopwatch = Stopwatch()..start();
    try {
      _tts ??= OnnxTts(langCode: _lang.code);
      if (!_tts!.isLoaded) await _tts!.load();
      final loadMs = stopwatch.elapsedMilliseconds;
      stopwatch.reset();

      setState(() => _speakStatus = 'Synthesising…');
      final result = await _tts!.synthesize(text);
      final synthMs = stopwatch.elapsedMilliseconds;
      final audioSeconds = result.pcm.length / result.sampleRate;
      final rtf = audioSeconds / (synthMs / 1000);

      _playback ??= AudioPlayback();
      setState(() => _speakStatus =
          'Playing ${audioSeconds.toStringAsFixed(2)}s '
          '(load=${loadMs}ms · synth=${synthMs}ms · rtf=${rtf.toStringAsFixed(1)}x)');
      await _playback!.play(result);
      setState(() => _speakStatus =
          'Done · ${audioSeconds.toStringAsFixed(2)}s '
          '(load=${loadMs}ms · synth=${synthMs}ms · rtf=${rtf.toStringAsFixed(1)}x)');
    } catch (e, st) {
      setState(() => _speakStatus = 'Failed:\n$e\n$st');
    } finally {
      setState(() => _speakBusy = false);
    }
  }

  Future<void> _toggleRecord() async {
    if (_transcribing) return;
    if (_listening) {
      await _stopAndTranscribe();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      _capture ??= AudioCapture(sampleRate: 16000);
      final ok = await _capture!.hasPermission();
      if (!ok) {
        setState(() => _listenStatus =
            'Mic permission denied. Grant it in Android Settings.');
        return;
      }
      await _capture!.startOneShot();
      _recordSw = Stopwatch()..start();
      setState(() {
        _listening = true;
        _transcript = '';
        _listenStatus = 'Recording… speak Twi, then tap Stop.';
      });
    } catch (e, st) {
      setState(() => _listenStatus = 'Failed to start recording:\n$e\n$st');
    }
  }

  Future<void> _stopAndTranscribe() async {
    final sw = Stopwatch()..start();
    setState(() {
      _listening = false;
      _transcribing = true;
      _listenStatus = 'Stopping mic…';
    });
    try {
      final pcm = await _capture!.stopOneShot();
      final captureMs = sw.elapsedMilliseconds;
      sw.reset();

      final recordedSec =
          (_recordSw?.elapsedMilliseconds ?? 0) / 1000.0;
      _recordSw = null;

      if (pcm.isEmpty) {
        setState(() => _listenStatus =
            'No audio captured. (recorded ${recordedSec.toStringAsFixed(2)}s)');
        return;
      }

      setState(() => _listenStatus =
          'Loading STT model… (recorded ${recordedSec.toStringAsFixed(2)}s)');
      _asr ??= OnnxAsr(langCode: _lang.code);
      if (!_asr!.isLoaded) await _asr!.load();
      final loadMs = sw.elapsedMilliseconds;
      sw.reset();

      setState(() => _listenStatus =
          'Transcribing ${pcm.length} samples '
          '(${(pcm.length / 16000).toStringAsFixed(2)}s)…');
      final result = await _asr!.transcribe(pcm);
      final inferMs = sw.elapsedMilliseconds;
      final rtf = (pcm.length / 16000) / (inferMs / 1000);

      setState(() {
        _transcript = result.text.isEmpty
            ? '(empty — confidence=${result.confidence.toStringAsFixed(2)})'
            : result.text;
        _listenStatus =
            'Done · stop=${captureMs}ms · load=${loadMs}ms · '
            'infer=${inferMs}ms · rtf=${rtf.toStringAsFixed(1)}x · '
            'conf=${result.confidence.toStringAsFixed(2)}';
      });
    } catch (e, st) {
      setState(() => _listenStatus = 'Failed:\n$e\n$st');
    } finally {
      setState(() => _transcribing = false);
    }
  }

  Future<void> _runGenerate() async {
    final prompt = _genCtl.text.trim();
    if (prompt.isEmpty) {
      setState(() => _genStatus = 'Type a prompt first.');
      return;
    }
    setState(() {
      _genBusy = true;
      _genOutput = '';
      _genStatus = 'Loading Gemma…';
    });
    final sw = Stopwatch()..start();
    try {
      _llm ??= GemmaLlm(variant: _gemmaVariant);
      if (!_llm!.isLoaded) await _llm!.load();
      final loadMs = sw.elapsedMilliseconds;
      sw.reset();

      setState(() => _genStatus = 'Generating…');

      int firstTokenMs = 0;
      int chunks = 0;
      int chars = 0;
      sw.start();
      await for (final chunk in _llm!.generate(prompt, maxTokens: 256)) {
        if (chunks == 0) {
          firstTokenMs = sw.elapsedMilliseconds;
        }
        chunks++;
        chars += chunk.length;
        setState(() => _genOutput += chunk);
      }
      final totalMs = sw.elapsedMilliseconds;
      // Rough token throughput proxy via character count (~4 chars/token).
      final approxTokens = (chars / 4).round();
      final tps = totalMs == 0
          ? 0
          : (approxTokens / (totalMs / 1000)).round();

      setState(() => _genStatus =
          'Done · load=${loadMs}ms · first-token=${firstTokenMs}ms · '
          'total=${totalMs}ms · ~$tps tok/s ($chars chars)');
    } catch (e, st) {
      setState(() => _genStatus = 'Failed:\n$e\n$st');
    } finally {
      setState(() => _genBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(langCode: _lang.code),
              const SizedBox(height: 14),
              _LanguageSwitcher(
                choices: _langs,
                current: _lang,
                onChanged: _switchLanguage,
                disabled: _inspectBusy ||
                    _speakBusy ||
                    _transcribing ||
                    _listening,
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    Text('Inspect models', style: t.labelMedium),
                    const SizedBox(height: 8),
                    SemaButton(
                      label: _inspectBusy ? 'Inspecting…' : 'Inspect models',
                      onPressed: _inspectBusy ? null : _runInspect,
                    ),
                    const SizedBox(height: 12),
                    _ConsoleBox(
                      text: _inspectOutput,
                      maxHeight: 280,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _CopyChip(text: _inspectOutput),
                    ),

                    const SizedBox(height: 24),
                    const Divider(color: SemaColors.hairlineSoft, height: 1),
                    const SizedBox(height: 20),

                    Text('Speak (TTS)', style: t.labelMedium),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: SemaColors.card,
                        borderRadius: BorderRadius.circular(SemaRadii.l),
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                      child: TextField(
                        controller: _ttsCtl,
                        maxLines: 3,
                        minLines: 2,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'midin de richmond nawonsue',
                          hintStyle: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 14,
                            color: SemaColors.inkMuted,
                          ),
                        ),
                        style: const TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 14,
                          height: 1.4,
                          color: SemaColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SemaButton(
                      icon: PhosphorIconsBold.speakerHigh,
                      label: _speakBusy ? 'Speaking…' : 'Speak',
                      onPressed: _speakBusy ? null : _runSpeak,
                    ),
                    const SizedBox(height: 10),
                    _ConsoleBox(text: _speakStatus, maxHeight: 140),

                    const SizedBox(height: 24),
                    const Divider(color: SemaColors.hairlineSoft, height: 1),
                    const SizedBox(height: 20),

                    Text('Listen (STT)', style: t.labelMedium),
                    const SizedBox(height: 8),
                    SemaButton(
                      icon: _listening
                          ? PhosphorIconsBold.stop
                          : PhosphorIconsBold.microphone,
                      label: _transcribing
                          ? 'Transcribing…'
                          : (_listening ? 'Stop' : 'Record'),
                      onPressed: _transcribing ? null : _toggleRecord,
                      variant: _listening
                          ? SemaButtonVariant.secondary
                          : SemaButtonVariant.primary,
                    ),
                    const SizedBox(height: 10),
                    _ConsoleBox(text: _listenStatus, maxHeight: 120),
                    if (_transcript.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _lang.accent.surface,
                          borderRadius:
                              BorderRadius.circular(SemaRadii.l),
                        ),
                        child: SelectableText(
                          _transcript,
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                            letterSpacing: -0.2,
                            color: _lang.accent.ink,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                    const Divider(color: SemaColors.hairlineSoft, height: 1),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Text('Generate (LLM)', style: t.labelMedium),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: SemaColors.card,
                            borderRadius:
                                BorderRadius.circular(SemaRadii.pill),
                          ),
                          child: Text(
                            _gemmaVariant,
                            style: const TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 10.5,
                              color: SemaColors.inkMid,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: SemaColors.card,
                        borderRadius: BorderRadius.circular(SemaRadii.l),
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                      child: TextField(
                        controller: _genCtl,
                        maxLines: 4,
                        minLines: 2,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'Tell me about Accra in 1 sentence.',
                          hintStyle: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 14,
                            color: SemaColors.inkMuted,
                          ),
                        ),
                        style: const TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 14,
                          height: 1.4,
                          color: SemaColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SemaButton(
                      icon: PhosphorIconsBold.sparkle,
                      label: _genBusy ? 'Generating…' : 'Generate',
                      onPressed: _genBusy ? null : _runGenerate,
                    ),
                    const SizedBox(height: 10),
                    _ConsoleBox(text: _genStatus, maxHeight: 100),
                    if (_genOutput.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: SemaColors.ink,
                          borderRadius:
                              BorderRadius.circular(SemaRadii.l),
                        ),
                        child: SelectableText(
                          _genOutput,
                          style: const TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            height: 1.45,
                            letterSpacing: -0.1,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.langCode});
  final String langCode;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PressScale(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40, height: 40,
                decoration: const BoxDecoration(
                  color: SemaColors.card,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  PhosphorIconsRegular.caretLeft,
                  size: 14, color: SemaColors.ink,
                ),
              ),
            ),
            const Spacer(),
            Text('ML debug', style: t.labelMedium),
          ],
        ),
        const SizedBox(height: 16),
        RichText(
          text: TextSpan(
            style: t.displayMedium!.copyWith(
              fontSize: 28, height: 1.1, letterSpacing: -1.0,
            ),
            children: [
              const TextSpan(text: 'STT + TTS for '),
              TextSpan(
                text: '`$langCode`',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConsoleBox extends StatelessWidget {
  const _ConsoleBox({required this.text, this.maxHeight = 240});
  final String text;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SemaColors.card,
        borderRadius: BorderRadius.circular(SemaRadii.l),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: const TextStyle(
            fontFamily: 'Courier',
            fontSize: 11.5,
            height: 1.45,
            color: SemaColors.ink,
          ),
        ),
      ),
    );
  }
}

class _CopyChip extends StatelessWidget {
  const _CopyChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () => Clipboard.setData(ClipboardData(text: text)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: SemaColors.card,
          borderRadius: BorderRadius.circular(SemaRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              PhosphorIconsRegular.copy,
              size: 14, color: SemaColors.ink,
            ),
            SizedBox(width: 6),
            Text(
              'Copy',
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: SemaColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageSwitcher extends StatelessWidget {
  const _LanguageSwitcher({
    required this.choices,
    required this.current,
    required this.onChanged,
    required this.disabled,
  });

  final List<_LangChoice> choices;
  final _LangChoice current;
  final ValueChanged<_LangChoice> onChanged;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Container(
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: SemaColors.card,
          borderRadius: BorderRadius.circular(SemaRadii.pill),
        ),
        child: Row(
          children: List.generate(choices.length, (i) {
            final c = choices[i];
            final selected = c.code == current.code;
            return Expanded(
              child: PressScale(
                onTap: disabled ? null : () => onChanged(c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: selected ? SemaColors.ink : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(SemaRadii.pill),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          color: c.accent.surface,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        c.label,
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.05,
                          color: selected
                              ? Colors.white
                              : SemaColors.ink.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
