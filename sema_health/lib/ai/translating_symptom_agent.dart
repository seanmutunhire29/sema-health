import '../domain/triage/triage_input.dart' show BioProfile;
import '../ml/mt.dart';
import 'chat_agent.dart';
import 'llm.dart';
import 'sema_reply.dart';
import 'symptom_agent.dart';

/// A [SymptomAgent] wrapper that bridges a non-English UI locale to the
/// English-only inner pipeline via NLLB-200 MT.
///
/// Pipeline:
///
/// ```
/// user text (sw / tw)
///   → translator.translate(local → eng_Latn)
///     → inner SymptomAgent.respondStream  (extractor, triage, Gemma all see English)
///       ⤺ stream of progressive English AgentTurns — buffered, not surfaced
///   ← final English AgentTurn (post-guard)
///   → translator.translate(eng_Latn → local) on headline / body / steps / donts
/// ⇒ one localized AgentTurn yielded.
/// ```
///
/// Streaming caveat. We surface only the final reply to the user (with
/// a localized "thinking" placeholder up front). Per-token MT would re-
/// translate incomplete sentences and look terrible — and the no-cache
/// NLLB decoder is too slow to amortize across 30+ verbalizer chunks.
/// The user-perceived flow becomes: send → placeholder appears
/// immediately → fully-translated reply appears once Gemma + MT settle.
///
/// [activate] returns a wrapping translating agent only when the locale
/// has an NLLB language code (`sw`, `tw`, `yo`, `fr`); for `en` and
/// for unsupported codes (e.g. `ga`) callers should keep using the
/// inner agent directly.
class TranslatingSymptomAgent implements ChatAgent {
  TranslatingSymptomAgent({
    required this.inner,
    required this.translator,
    required this.userLang,
    this.outputLlm,
    this.outputLanguageName,
    String? thinkingHeadline,
  }) : _thinkingHeadline = thinkingHeadline ??
            _defaultThinkingHeadlineFor(userLang);

  /// English-only deterministic + Gemma agent.
  final SymptomAgent inner;

  /// NLLB translator. Loaded lazily on first turn.
  final Translator translator;

  /// NLLB language token for the user's locale, e.g. `swh_Latn`,
  /// `aka_Latn`. Always non-English — passing English here would round-
  /// trip text needlessly.
  final String userLang;

  /// When non-null, the wrapper uses Gemma (one tagged-output call) for
  /// the **output** translation step instead of running NLLB line-by-
  /// line — this drops a 60s reply down to ~3-5s. The English input
  /// translation still goes through NLLB (single encoder pass, cheap).
  ///
  /// Set this only for locales where Gemma's coverage is solid
  /// (currently Swahili). For low-resource targets like Twi, leave it
  /// null and let NLLB handle the out-translate.
  final Llm? outputLlm;

  /// Human-readable language name passed to Gemma's translate prompt
  /// (e.g. "Swahili"). Required iff [outputLlm] is set.
  final String? outputLanguageName;

  static const String _english = 'eng_Latn';
  final String _thinkingHeadline;

  /// Greeting passes through the inner formatter (which already honours
  /// the active locale via SemaStrings) so we don't burn an MT call on
  /// the post-onboarding "Karibu" line.
  @override
  SemaReply greeting(BioProfile? profile) => inner.greeting(profile);

  /// Run a turn end-to-end. Yields exactly two events for every
  /// non-empty input:
  ///   1. A localized placeholder so the chat bubble pops immediately.
  ///   2. The fully-translated final reply (post-MT, post-guard).
  ///
  /// Empty input short-circuits to the inner agent's clarifying-question
  /// fallback, translated once.
  @override
  Stream<AgentTurn> respondStream({
    required String userText,
    required BioProfile? profile,
  }) async* {
    final trimmed = userText.trim();
    if (trimmed.isEmpty) {
      // Drain the inner clarifier (single-event stream) and translate it.
      final inner0 = await inner.respond(userText: trimmed, profile: profile);
      yield await _translateTurn(inner0);
      return;
    }

    // Cold-load the translator. We don't lazy-load it inside translate()
    // because the encoder load is multi-second and we want the user to
    // see the placeholder bubble before that latency accrues.
    if (!translator.isLoaded) {
      try {
        await translator.load();
      } catch (e) {
        // ignore: avoid_print
        print('[Sema MT] translator.load() FAILED → English passthrough: $e');
        // MT unavailable → degrade gracefully. Pass the raw text to
        // Gemma; reply will come back in English. Better than blocking
        // the chat entirely.
        yield* _passthrough(trimmed, profile);
        return;
      }
    }

    // 1. Placeholder — gives the chat something to render immediately
    //    while we run encode → encoder → 30-step decoder loop.
    yield AgentTurn(
      reply: SemaReply(
        tone: ReplyTone.calm,
        headline: _thinkingHeadline,
        body: '',
      ),
      extracted: const {},
    );

    // 2. Translate user input local → English.
    final tStart = DateTime.now();
    final String englishInput;
    try {
      englishInput = await translator.translate(
        trimmed,
        src: userLang,
        tgt: _english,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[Sema MT] in-translate ($userLang→en) FAILED → English '
          'passthrough: $e');
      yield* _passthrough(trimmed, profile);
      return;
    }
    // ignore: avoid_print
    print('[Sema MT] in-translate ($userLang→en) done in '
        '${DateTime.now().difference(tStart).inMilliseconds}ms: '
        '"${trimmed.length > 40 ? "${trimmed.substring(0, 40)}…" : trimmed}" → '
        '"${englishInput.length > 60 ? "${englishInput.substring(0, 60)}…" : englishInput}"');
    if (englishInput.trim().isEmpty) {
      yield* _passthrough(trimmed, profile);
      return;
    }

    // 3. Drain the inner stream, keeping only the last (post-guard) turn.
    final tInner = DateTime.now();
    AgentTurn? finalTurn;
    try {
      await for (final t
          in inner.respondStream(userText: englishInput, profile: profile)) {
        finalTurn = t;
      }
    } catch (e) {
      // ignore: avoid_print
      print('[Sema MT] inner agent stream THREW → English passthrough: $e');
      yield* _passthrough(trimmed, profile);
      return;
    }
    // ignore: avoid_print
    print('[Sema MT] inner agent done in '
        '${DateTime.now().difference(tInner).inMilliseconds}ms '
        '(headline=${finalTurn?.reply.headline.length ?? 0}c, '
        'body=${finalTurn?.reply.body.length ?? 0}c)');
    if (finalTurn == null) return;

    // 4. Translate the user-visible fields back to the local language.
    //    For locales with a configured Gemma output target (currently
    //    Swahili) we do this in a single tagged-output Gemma call —
    //    ~3-5 s end-to-end. Otherwise we fall back to per-field NLLB,
    //    which is correct but ~30-90 s per reply (no-cache decoder).
    if (outputLlm != null && outputLanguageName != null) {
      var streamedSomething = false;
      try {
        await for (final t in _translateTurnWithGemmaStream(finalTurn)) {
          streamedSomething = true;
          yield t;
        }
        if (streamedSomething) return;
        // Stream produced nothing — fall through to NLLB.
      } catch (e) {
        // ignore: avoid_print
        print('[Sema MT] Gemma out-translate FAILED, falling back to NLLB: $e');
        // Fall through to NLLB path.
      }
    }
    yield await _translateTurn(finalTurn);
  }

  /// Future-shaped variant for non-streaming callers. Drains the stream
  /// and returns the last emission.
  @override
  Future<AgentTurn> respond({
    required String userText,
    required BioProfile? profile,
  }) async {
    AgentTurn? last;
    await for (final t in respondStream(userText: userText, profile: profile)) {
      last = t;
    }
    return last!;
  }

  /// Streaming Gemma translate. Builds a tagged-section prompt and
  /// yields progressively better `AgentTurn`s as Gemma decodes. The
  /// chat bubble updates per yield, so the user sees Swahili text
  /// appearing within ~2-3s instead of waiting for the full decode.
  ///
  /// Why tagged blocks instead of JSON: Gemma 3n int4 is decent at
  /// repeating literal markers but slips on JSON commas and quotes
  /// when content has its own punctuation. `###TAG###` style is
  /// forgiving.
  ///
  /// Throws on a complete parse failure so the caller can fall back
  /// to NLLB. Per-field misses (one section never parses) silently
  /// keep the English source for that field.
  Stream<AgentTurn> _translateTurnWithGemmaStream(AgentTurn turn) async* {
    final r = turn.reply;
    final llm = outputLlm!;
    final langName = outputLanguageName!;

    final t0 = DateTime.now();
    // ignore: avoid_print
    print('[Sema MT] Gemma out-translate START → $langName '
        '(headline=${r.headline.length}c, body=${r.body.length}c, '
        'steps=${r.steps.length}, donts=${r.donts.length})');

    if (!llm.isLoaded) await llm.load();

    // We translate only the prose fields (headline + body + cta label).
    // Steps and don'ts are kept verbatim in English because:
    //   1. They are clinical instructions where a soft mistranslation
    //      ("take 200mg paracetamol" → ambiguous Swahili paraphrase)
    //      can lose dose precision the safety guard already vetted.
    //   2. Translating 6-9 fields per turn blows past the 1024-token
    //      session window on this mid-tier hardware.
    //   3. The warmth/localization the user perceives lives in the
    //      headline + body — the steps are short numbered actions
    //      recognizable to anyone with primary-school English.
    final src = StringBuffer();
    src.writeln('HEADLINE: ${r.headline}');
    src.writeln('BODY: ${r.body}');
    if (r.cta != null) src.writeln('CTA: ${r.cta!.label}');

    final outputTags = <String>[
      if (r.headline.isNotEmpty) 'HEADLINE',
      if (r.body.isNotEmpty) 'BODY',
      if (r.cta != null) 'CTA',
    ];

    final expectedTemplate = outputTags
        .map((t) => '###$t###\n<$langName translation of $t>')
        .join('\n');

    // Shorter prompt = fewer prefill tokens = faster TTFT.
    final prompt = '''
Translate to natural, warm $langName. Keep meaning exact. Do not add or omit. Output ONLY the tagged blocks below, in the same order, with markers verbatim:

$expectedTemplate
###END###

Source:
$src''';

    AgentTurn buildTurnFromParsed(Map<String, String> parsed) {
      String fieldOrSource(String tag, String source) =>
          (parsed[tag]?.isNotEmpty == true) ? parsed[tag]! : source;
      return AgentTurn(
        reply: r.copyWith(
          headline: fieldOrSource('HEADLINE', r.headline),
          body: fieldOrSource('BODY', r.body),
          cta: r.cta == null
              ? null
              : ReplyCta(
                  kind: r.cta!.kind,
                  label: fieldOrSource('CTA', r.cta!.label),
                  entryRef: r.cta!.entryRef,
                ),
        ),
        extracted: turn.extracted,
        vitals: turn.vitals,
        guardViolation: turn.guardViolation,
      );
    }

    final buf = StringBuffer();
    DateTime? lastEmit;
    Map<String, String> lastParsed = const <String, String>{};
    var anyEmitted = false;

    await for (final chunk in llm.generate(
      prompt,
      maxTokens: 768,
      temperature: 0.2,
    )) {
      buf.write(chunk);
      if (buf.length > 4000) break;

      // Throttle re-parses + emissions to ~5 Hz so we don't rebuild
      // the chat bubble on every token.
      final now = DateTime.now();
      if (lastEmit != null && now.difference(lastEmit).inMilliseconds < 180) {
        continue;
      }

      // Mid-stream parse. The regex is tolerant of missing trailing
      // markers, so partial output yields whatever sections completed.
      final parsed = _parseTaggedOutput(buf.toString(), outputTags);
      if (parsed.isEmpty) continue;

      // Only re-emit if the parse meaningfully changed (new tag landed,
      // or an existing tag's content grew). Skip pure rebuilds where
      // the same content is repeated.
      if (_parsedChanged(parsed, lastParsed)) {
        lastParsed = Map<String, String>.from(parsed);
        lastEmit = now;
        anyEmitted = true;
        yield buildTurnFromParsed(parsed);
      }
    }

    final raw = buf.toString();
    final dt = DateTime.now().difference(t0);
    // ignore: avoid_print
    print('[Sema MT] Gemma out-translate raw output (${dt.inMilliseconds}ms, '
        '${raw.length}c): ${raw.length > 200 ? "${raw.substring(0, 200)}…" : raw}');

    if (raw.trim().isEmpty) {
      if (!anyEmitted) throw StateError('Gemma returned empty output');
      return;
    }

    final parsed = _parseTaggedOutput(raw, outputTags);
    // ignore: avoid_print
    print('[Sema MT] Gemma out-translate parsed ${parsed.length}/${outputTags.length} '
        'sections: ${parsed.keys.join(", ")}');

    if (parsed.isEmpty) {
      if (!anyEmitted) throw StateError('Gemma output had no parseable sections');
      return;
    }

    // Always emit a final settled turn — the stream contract is that
    // the last event is the polished result.
    yield buildTurnFromParsed(parsed);
  }

  /// True when [next] has more fields than [prev], or when any shared
  /// field has grown by ≥4 chars (tokens of meaningful Swahili content).
  /// Small noise like trailing whitespace is ignored.
  static bool _parsedChanged(
    Map<String, String> next,
    Map<String, String> prev,
  ) {
    if (next.length > prev.length) return true;
    for (final entry in next.entries) {
      final old = prev[entry.key] ?? '';
      if (entry.value.length - old.length >= 4) return true;
    }
    return false;
  }

  /// Splits a tagged Gemma response into a `tag → translation` map.
  /// Tolerant of: extra whitespace, missing trailing `###END###`,
  /// preamble before the first tag, partial sections at the tail,
  /// AND Gemma's occasional habit of dropping the leading `###` on the
  /// second tag in a stream (observed `BODY###` instead of `###BODY###`).
  static Map<String, String> _parseTaggedOutput(
    String raw,
    List<String> expectedTags,
  ) {
    final result = <String, String>{};
    // Tag marker: optional leading `###` (Gemma sometimes drops it after
    // the first tag), the tag name, then closing `###`. End-of-section
    // is the next marker OR end-of-string.
    final markerOpen = r'(?:###)?'; // 0 or 1 leading triple-hash
    final markerClose = r'###';
    final tagPattern = RegExp(
      '(?:^|\\n)$markerOpen([A-Z_0-9]+)$markerClose'
      r'\s*([\s\S]*?)'
      '(?=\\n$markerOpen[A-Z_0-9]+$markerClose|\$)',
    );
    for (final m in tagPattern.allMatches(raw)) {
      final tag = m.group(1)!;
      if (tag == 'END') continue;
      if (!expectedTags.contains(tag)) continue;
      final body = (m.group(2) ?? '').trim();
      if (body.isEmpty) continue;
      result[tag] = body;
    }
    return result;
  }

  /// Translate every user-visible string field on a single turn. Steps
  /// and donts go in one batched call each (joined on a marker the model
  /// won't merge across) to avoid paying the per-call encoder fixed cost
  /// for every line.
  Future<AgentTurn> _translateTurn(AgentTurn turn) async {
    final r = turn.reply;

    final headline = r.headline.isEmpty
        ? r.headline
        : await _safeTranslate(r.headline);
    final body = r.body.isEmpty ? r.body : await _safeTranslate(r.body);
    final steps = await _translateSteps(r.steps);
    final donts = await _translateLines(r.donts);
    final ctaLabel = r.cta == null ? null : await _safeTranslate(r.cta!.label);

    return AgentTurn(
      reply: r.copyWith(
        headline: headline,
        body: body,
        steps: steps,
        donts: donts,
        cta: r.cta == null
            ? null
            : ReplyCta(
                kind: r.cta!.kind,
                label: ctaLabel ?? r.cta!.label,
                entryRef: r.cta!.entryRef,
              ),
      ),
      extracted: turn.extracted,
      vitals: turn.vitals,
      guardViolation: turn.guardViolation,
    );
  }

  Future<List<SemaReplyStep>> _translateSteps(List<SemaReplyStep> steps) async {
    if (steps.isEmpty) return steps;
    final translated = await _translateLines([for (final s in steps) s.text]);
    return [
      for (var i = 0; i < steps.length; i++)
        SemaReplyStep(
          order: steps[i].order,
          text: translated[i],
          critical: steps[i].critical,
        ),
    ];
  }

  /// Translate a list of short lines individually. We considered batching
  /// via a marker token but NLLB has no guaranteed pass-through token,
  /// and the alternative (joining with a separator the model paraphrases)
  /// scrambles the round-trip. Per-line is more calls but reliable.
  Future<List<String>> _translateLines(List<String> lines) async {
    final out = <String>[];
    for (final line in lines) {
      out.add(line.isEmpty ? line : await _safeTranslate(line));
    }
    return out;
  }

  /// Best-effort translate; on failure return the English source so the
  /// user still sees content (degraded, but readable to bilingual users).
  Future<String> _safeTranslate(String english) async {
    try {
      final out = await translator.translate(
        english,
        src: _english,
        tgt: userLang,
      );
      return out.isEmpty ? english : out;
    } catch (e) {
      // ignore: avoid_print
      print('[Sema MT] out-translate (en→$userLang) FAILED, keeping English: '
          '"${english.length > 60 ? "${english.substring(0, 60)}…" : english}" '
          '($e)');
      return english;
    }
  }

  /// MT-bypass path: emit the English-pipeline output as-is. Used when
  /// translation fails so the chat doesn't dead-end.
  Stream<AgentTurn> _passthrough(String userText, BioProfile? profile) async* {
    await for (final t
        in inner.respondStream(userText: userText, profile: profile)) {
      yield t;
    }
  }

  /// Hardcoded one-shot placeholder copy per supported NLLB locale, so
  /// the bubble pops without burning an MT call on the same string every
  /// turn. Falls back to English when we don't have a curated phrase.
  static String _defaultThinkingHeadlineFor(String nllbLang) {
    switch (nllbLang) {
      case 'swh_Latn':
        return 'Hebu nifikirie hili pamoja nawe';
      case 'aka_Latn':
        return 'Ma me ne wo nsusuw eyi ho';
      case 'yor_Latn':
        return 'Jẹ́ kí n ronú lórí èyí pẹ̀lú rẹ';
      case 'fra_Latn':
        return 'Laissez-moi y réfléchir avec vous';
      default:
        return 'Let me think this through with you';
    }
  }
}
