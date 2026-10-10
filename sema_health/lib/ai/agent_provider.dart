import 'dart:async';
import 'dart:io';

import '../data/seed/first_aid_repo.dart';
import '../data/seed/first_aid_repo_provider.dart';
import '../domain/triage/triage_engine.dart';
import '../domain/triage/triage_engine_assets.dart';
import '../ml/model_paths.dart';
import '../ml/mt.dart';
import '../ml/mt_onnx.dart';
import 'chat_agent.dart';
import 'llm.dart';
import 'symptom_agent.dart';
import 'symptom_extractor.dart';
import 'tool_dispatch_agent.dart';
import 'tools/clinical_tools.dart';
import 'translating_symptom_agent.dart';
import 'verbalizer.dart';

/// Filename (without extension) Sema looks for under
/// `<models>/llm/<variant>.task`. Matches the dev-time push convention
/// in `ModelPaths.llmPushHint`. Override via [overrideLlmVariant] for
/// experiments without a rebuild.
const String _defaultGemmaVariant = 'gemma_3n_e2b_int4';

/// Test/integration override.
String? overrideLlmVariant;

/// Locales for which we route through the NLLB MT bridge instead of
/// asking Gemma to think directly in the user's language. Per product
/// decision: Gemma stays English-only and we translate at the seams.
/// Other locales (en, fr, yo, ga) keep using the inner pipeline as-is
/// — for `ga` because NLLB has no Ga vocabulary, for `yo`/`fr` because
/// the deterministic content already speaks their language.
const Set<String> _mtBridgedLocales = {'sw', 'tw'};

/// Per-locale cache. We rebuild the agent when the user switches
/// language because the wrapper, the tokenizer, and the MT model are
/// all bound to a specific source/target pair.
final Map<String, Future<ChatAgent>> _cached = {};

/// Build (or fetch from cache) the chat agent appropriate for [localeCode].
///
/// `localeCode` is Sema's UI code (`'en'`, `'sw'`, `'tw'`, ...). For
/// MT-bridged locales we build the deterministic agent in English mode
/// and wrap it with [TranslatingSymptomAgent]; for everything else we
/// return the deterministic agent directly.
Future<ChatAgent> symptomAgentFuture({String localeCode = 'en'}) {
  return _cached.putIfAbsent(localeCode, () => _build(localeCode));
}

/// Test hook: drop the cached agents (e.g. between locale changes in
/// integration tests). Production code shouldn't need this — the cache
/// is keyed by locale.
void resetSymptomAgentCache() {
  _cached.clear();
}

Future<ChatAgent> _build(String localeCode) async {
  final results = await Future.wait([
    firstAidRepoFuture(),
    loadTriageEngineFromAssets(),
  ]);
  final repo = results[0] as FirstAidRepo;
  final engine = results[1] as TriageEngine;
  final extractor = SymptomExtractor.fromSymptoms(repo.allSymptoms);

  // Gemma is optional. If the model file isn't on the device yet, we
  // still ship the deterministic agent — it's a complete symptom
  // checker on its own. The verbalizer + tool-dispatch agent add
  // warmth and off-script reach, not safety.
  final llm = await gemmaLlmFuture();

  // For Gemma-out locales we deliberately SKIP the English verbalize
  // step. The out-translate Gemma call already produces warm,
  // localized prose from the deterministic body — running verbalize in
  // English first and then translating the warmed-up text would burn
  // a second ~3-5s MediaPipe session per turn for zero quality gain.
  //
  // For all other locales (en/fr/yo/ga/tw NLLB-bridged) we keep
  // GemmaVerbalizer so the body still reads warmer than the templated
  // clinical default.
  final useGemmaOutForLocale =
      _gemmaOutLocales.contains(localeCode) && llm != null;
  final verbalizer = (llm == null || useGemmaOutForLocale)
      ? const NullVerbalizer()
      : GemmaVerbalizer(llm: llm);
  // Same logic for the ToolDispatchAgent fallback: when triage fails to
  // match (e.g. a greeting like "hi"), the deterministic path emits a
  // generic "tell me more" reply, and the out-translate Gemma call
  // makes that warm. Running the freeform Gemma fallback here too
  // adds ~30 s per turn for no clinical gain — the architecture's
  // safety case rests on the deterministic match anyway. For other
  // locales the fallback still fires (it's the one place users get
  // off-script reach).
  final fallback = (llm == null || useGemmaOutForLocale)
      ? null
      : ToolDispatchAgent(
          llm: llm,
          tools: defaultClinicalTools(repo: repo, engine: engine),
        );

  final inner = SymptomAgent(
    engine: engine,
    repo: repo,
    extractor: extractor,
    verbalizer: verbalizer,
    fallbackAgent: fallback,
  );

  // TTFT win: kick off the model load now, so the first user turn
  // doesn't pay the cold-load tax (mmap'ing the 1GB+ .task file +
  // MediaPipe session init — measured at 2–5 s on mid-tier Android).
  // After load, fire a tiny throwaway generate to warm the LiteRT
  // / OpenCL session pipeline — saves ~1 s on the user's first turn
  // because the first session-create per app run is the slowest one.
  // Fire-and-forget; failures fall back transparently because all
  // call sites use `if (!llm.isLoaded) await llm.load()` anyway.
  if (llm != null) {
    unawaited(() async {
      try {
        await llm.load();
        // Drain a 1-token generate. The output is discarded; the goal
        // is just to make MediaPipe spin up its decoder once now,
        // off the user's critical path.
        await for (final _ in llm.generate('hi', maxTokens: 1, temperature: 0.0)) {
          break;
        }
        // ignore: avoid_print
        print('[Sema] Gemma session pre-warmed.');
      } catch (_) {
        // Pre-warm is best-effort; real calls will retry the load.
      }
    }());
  }

  // Direct-passthrough locales: the deterministic agent answers in
  // English (with whatever native Gemma the device is running).
  if (!_mtBridgedLocales.contains(localeCode)) {
    return inner;
  }

  // MT-bridged locales (sw / tw). If the NLLB bundle is present we
  // wrap; if it isn't, fall back to the inner agent so the chat keeps
  // working in English rather than dead-ending.
  final translator = await _resolveTranslator();
  if (translator == null) {
    // ignore: avoid_print
    print('[Sema MT] locale=$localeCode → NLLB bundle missing on device, '
        'falling back to English. Replies + TTS will be in English. '
        'Push the bundle via ModelPaths.mtPushHint() to enable translation.');
    return inner;
  }

  final nllbLang = semaCodeToNllb(localeCode);
  if (nllbLang == null) {
    // ignore: avoid_print
    print('[Sema MT] locale=$localeCode has no NLLB language code mapping, '
        'falling back to English.');
    return inner;
  }

  // Cold-load the MT sessions in the background so the first turn
  // doesn't eat the encoder/decoder mmap latency. Failures here are
  // logged + the wrapper catches load errors per-turn and falls through
  // to its passthrough path.
  unawaited(translator.load().then(
    (_) {
      // ignore: avoid_print
      print('[Sema MT] NLLB loaded for locale=$localeCode (nllb=$nllbLang)');
    },
    onError: (Object e, StackTrace st) {
      // ignore: avoid_print
      print('[Sema MT] NLLB background load FAILED for locale=$localeCode: $e');
    },
  ));

  // Locales where Gemma 3n has solid coverage take the fast Gemma
  // out-translate path (~3-5s/reply). Twi stays on NLLB (Gemma's Akan
  // is shaky); accept the slower path there until we ship a per-language
  // verbalize-in-target prompt set.
  final useGemmaOut = _gemmaOutLocales.contains(localeCode) && llm != null;
  final outputLanguageName = useGemmaOut ? _languageNameFor(localeCode) : null;

  // ignore: avoid_print
  print('[Sema MT] locale=$localeCode wrapped with TranslatingSymptomAgent '
      '(nllb=$nllbLang, out=${useGemmaOut ? "Gemma($outputLanguageName)" : "NLLB"}). '
      'Replies will be translated back to $localeCode.');
  return TranslatingSymptomAgent(
    inner: inner,
    translator: translator,
    userLang: nllbLang,
    outputLlm: useGemmaOut ? llm : null,
    outputLanguageName: outputLanguageName,
  );
}

/// Locales for which we delegate out-translation to Gemma instead of
/// NLLB. Add a language here only after confirming Gemma 3n produces
/// faithful, clinically-safe target-language output for the kinds of
/// short paragraphs Sema emits.
const Set<String> _gemmaOutLocales = {'sw'};

String? _languageNameFor(String localeCode) {
  switch (localeCode) {
    case 'sw':
      return 'Swahili';
    case 'tw':
      return 'Twi';
    case 'fr':
      return 'French';
    case 'yo':
      return 'Yoruba';
    case 'ga':
      return 'Ga';
    default:
      return null;
  }
}

/// Process-wide cache: at most one [GemmaLlm] handle exists. We share
/// it across the verbalizer, the tool-dispatch fallback, the Gemma-based
/// out-translator, and the camera/vision flow so MediaPipe holds the
/// model in memory once, not four times.
Future<Llm?>? _llmFuture;

/// Public accessor. Returns null when the `.task` file is missing or the
/// resolver throws — the chat falls back to the deterministic agent in
/// that case, and the camera affordance hides itself.
Future<Llm?> gemmaLlmFuture() => _llmFuture ??= _resolveLlm();

/// Test hook: drop the cached LLM. Mirrors [resetSymptomAgentCache].
void resetGemmaLlmCache() {
  _llmFuture = null;
}

/// Probe the device for the Gemma `.task` file. Returns a single shared
/// [Llm] — we don't `load()` it eagerly: the first verbalize / fallback
/// call triggers the load, so cold-start of the chat stays fast.
Future<Llm?> _resolveLlm() async {
  final variant = overrideLlmVariant ?? _defaultGemmaVariant;
  try {
    final paths = await ModelPaths.resolve();
    final modelFile = await paths.llmFor(variant);
    if (modelFile == null) return null;
    return GemmaLlm(variant: variant);
  } catch (_) {
    return null;
  }
}

/// Probe the device for the NLLB MT bundle (encoder + decoder +
/// tokenizer). Returns null when any file is missing — the agent
/// builder then drops the wrapper and the chat stays English-only.
Future<Translator?> _resolveTranslator() async {
  try {
    final paths = await ModelPaths.resolve();
    final files = await Future.wait([
      paths.mtEncoder(),
      paths.mtDecoder(),
      paths.mtTokenizer(),
    ]);
    final missing = <String>[
      if (files[0] == null) 'encoder_model.onnx',
      if (files[1] == null) 'decoder_model.onnx',
      if (files[2] == null) 'tokenizer.json',
    ];
    if (missing.isNotEmpty) {
      // List whatever IS in the mt/ dir so we can spot path mismatches
      // (wrong filename in the Firebase manifest, files written to the
      // wrong subdir, etc.) instead of just "missing".
      final mtDir = Directory('${paths.root}/mt');
      String onDisk;
      if (!await mtDir.exists()) {
        onDisk = '<mt/ dir does not exist — download never wrote anything>';
      } else {
        final entries = await mtDir
            .list()
            .map((e) => e.path.split('/').last)
            .toList();
        onDisk = entries.isEmpty ? '<empty>' : entries.join(', ');
      }
      // ignore: avoid_print
      print('[Sema MT] _resolveTranslator: missing ${missing.join(", ")}. '
          'Expected under ${paths.root}/mt/. Actually present: $onDisk');
      return null;
    }
    return OnnxNllbTranslator(paths: paths);
  } catch (e) {
    // ignore: avoid_print
    print('[Sema MT] _resolveTranslator: threw $e');
    return null;
  }
}
