import '../data/seed/first_aid_repo.dart';
import '../domain/triage/severity.dart';
import '../domain/triage/triage_engine.dart';
import '../domain/triage/triage_input.dart';
import 'chat_agent.dart';
import 'reply_formatter.dart';
import 'safety_guard.dart';
import 'sema_reply.dart';
import 'symptom_extractor.dart';
import 'tool_dispatch_agent.dart';
import 'verbalizer.dart';

/// Orchestrates one user-turn → reply.
///
/// Pipeline (matches the architecture's "Pipeline at a glance"):
///
/// ```
/// user text
///   → SymptomExtractor (slugs + vitals)
///   → TriageEngine.evaluate (deterministic rule match)
///     ├─ matched   → ReplyFormatter → Verbalizer (Gemma) → SafetyGuard
///     └─ no match  → ToolDispatchAgent (Gemma + KG tools) → SafetyGuard
/// ```
///
/// Streaming. Both the verbalizer and the tool-dispatch fallback emit
/// progressive replies as Gemma writes them. [respondStream] yields
/// each snapshot; the chat replaces the in-flight bubble per event.
/// The deterministic-only path emits a single event and completes.
///
/// Safety. The safety guard runs ONLY on the final emission of the
/// stream — running it 30× per turn would burn cycles, and the bubble
/// is rebuilt anyway when the guard repairs. If the guard repairs, the
/// stream emits one extra (final) event with the repaired reply.
class SymptomAgent implements ChatAgent {
  SymptomAgent({
    required this.engine,
    required this.repo,
    required this.extractor,
    Verbalizer? verbalizer,
    ToolDispatchAgent? fallbackAgent,
    SafetyGuard? guard,
    ReplyFormatter? formatter,
  })  : _verbalizer = verbalizer ?? const NullVerbalizer(),
        _fallbackAgent = fallbackAgent,
        _guard = guard ?? SafetyGuard(),
        _formatter = formatter ?? const ReplyFormatter();

  final TriageEngine engine;
  final FirstAidRepo repo;
  final SymptomExtractor extractor;
  final Verbalizer _verbalizer;

  /// Optional Gemma-backed agent with native function calling against
  /// the clinical KG. Drives the "no triage rule fired" fallback when
  /// available, so off-script questions still get grounded answers.
  /// Stays null on devices without the Gemma .task file — the chat then
  /// falls back to the formatter's generic clarifying-question reply.
  final ToolDispatchAgent? _fallbackAgent;

  final SafetyGuard _guard;
  final ReplyFormatter _formatter;

  /// Reply Sema sends right after the bio-profile sheet closes.
  /// Personalized when the profile has a `displayName`.
  @override
  SemaReply greeting(BioProfile? profile) => _formatter.greeting(profile);

  /// Run a turn and stream progressive replies.
  ///
  /// Emits at least one event:
  /// - For the deterministic-matched path with no Gemma loaded: one
  ///   event with the final reply.
  /// - For the Gemma-verbalized path: progressive events as tokens
  ///   arrive, plus a final event with the post-processed reply.
  /// - For the no-match-fallback Gemma path: a placeholder event so
  ///   the chat can render an empty bubble immediately, then
  ///   progressive token events, then the final.
  /// - On guard repair: one additional final event with the repaired
  ///   safe-template reply.
  @override
  Stream<AgentTurn> respondStream({
    required String userText,
    required BioProfile? profile,
  }) async* {
    if (userText.trim().isEmpty) {
      final reply = _formatter.fallback();
      final guarded = _guard.check(reply);
      yield AgentTurn(reply: guarded.reply, extracted: const {});
      return;
    }

    // Smalltalk fast-path: greetings/thanks/farewells get a friendly
    // canned reply without engaging triage or the LLM. Without this, "hi"
    // either falls through to the clinical clarifying question or hits
    // Gemma in clinical-agent mode and produces awkward output.
    final smalltalk = ReplyFormatter.detectSmalltalk(userText);
    if (smalltalk != null) {
      final reply = _formatter.smalltalk(smalltalk, profile: profile);
      yield AgentTurn(reply: reply, extracted: const {});
      return;
    }

    final extraction = extractor.extract(userText);
    final input = TriageInput(
      symptoms: extraction.slugs,
      profile: profile ?? const BioProfile(ageMonths: 360),
      vitals: extraction.vitals,
    );
    final outcome = engine.evaluate(input);

    // The engine has a synthetic `no-match-fallback` rule that always
    // fires when the extractor returned no slugs. Treat that the same
    // as a true miss so the LLM dispatcher gets to ground the answer
    // in the KG instead of bouncing the user with a generic clarifying
    // question.
    final fired = outcome != null && outcome.ruleId != _noMatchFallbackRuleId;

    if (!fired) {
      // No deterministic rule matched. Hand the turn to Gemma's tool-
      // dispatch agent if available; otherwise emit the clarifying
      // question once.
      if (_fallbackAgent != null) {
        var sawRealReply = false;
        await for (final turn in _streamFallbackAgent(
          agent: _fallbackAgent,
          userText: userText,
          extraction: extraction,
          profile: profile,
          guard: _guard,
        )) {
          if (turn.reply.body.length >= 8) sawRealReply = true;
          yield turn;
        }
        if (sawRealReply) return;
        // Fallback agent failed before producing usable text. We may
        // have already emitted a placeholder turn — the next yield
        // replaces it with the clarifying question.
      }
      final reply = _formatter.fallback(extracted: extraction.slugs);
      final guarded = _guard.check(reply);
      yield AgentTurn(reply: guarded.reply, extracted: extraction.slugs);
      return;
    }

    // Past the `fired` gate the analyzer knows outcome is non-null.
    final entry = outcome.entryRef == null
        ? null
        : repo.getById(outcome.entryRef!);
    final formatted = _formatter.format(
      outcome: outcome,
      entry: entry,
      profile: profile,
      symptomsExtracted: extraction.slugs,
      userText: userText,
      vitalsExtracted: extraction.vitals,
    );

    // TTFT win: yield the deterministic reply *immediately* so the
    // bubble pops with structured content (headline, steps, donts, CTA,
    // English body) in the same frame as send-tap. The verbalizer then
    // streams a body rewrite which replaces the bubble in place as
    // Gemma writes — without making the user stare at typing dots
    // while the model warms up.
    yield AgentTurn(
      reply: formatted,
      extracted: extraction.slugs,
      vitals: extraction.vitals,
    );

    SemaReply lastReply = formatted;
    await for (final partial in _verbalizer.verbalizeStream(
      reply: formatted,
      matchedEntry: entry,
      profile: profile,
      userText: userText,
    )) {
      // NullVerbalizer (and the GemmaVerbalizer error path) re-emits the
      // input reply by identity. We've already shown that snapshot, so
      // skip the duplicate rebuild.
      if (identical(partial, formatted)) continue;
      lastReply = partial;
      yield AgentTurn(
        reply: partial,
        extracted: extraction.slugs,
        vitals: extraction.vitals,
      );
    }

    // Final guard sweep on the polished body. Steps/donts already pass
    // through the KG and don't need re-checking.
    final guarded = _guard.check(lastReply, matchedEntry: entry);
    if (!guarded.passed) {
      yield AgentTurn(
        reply: guarded.reply,
        extracted: extraction.slugs,
        vitals: extraction.vitals,
        guardViolation: guarded.violation,
      );
    }
  }

  /// Future variant for callers (tests, single-shot use cases) that
  /// want only the final settled reply. Drains [respondStream] and
  /// returns the last emission.
  @override
  Future<AgentTurn> respond({
    required String userText,
    required BioProfile? profile,
  }) async {
    AgentTurn? last;
    await for (final t
        in respondStream(userText: userText, profile: profile)) {
      last = t;
    }
    return last!;
  }
}

/// Rule id of the synthetic catch-all rule in `assets/triage/rules.yaml`.
/// When the extractor finds no symptoms, the engine still returns this
/// rule's outcome so the deterministic-only path has something to say.
/// In streaming, we treat it as a miss instead and let Gemma try.
const String _noMatchFallbackRuleId = 'no-match-fallback';

/// Stream the tool-dispatch agent's tokens as a [Stream<AgentTurn>].
///
/// Yields a placeholder turn first (empty body) so the chat can swap
/// the typing-dots for an empty bubble immediately. Then yields a
/// progressive turn per throttled token batch. The final emission
/// goes through the safety guard.
///
/// On any failure (LLM not loaded, OOM, no usable text) the stream
/// ends without a "real" reply and the caller falls through to the
/// deterministic clarifying question.
Stream<AgentTurn> _streamFallbackAgent({
  required ToolDispatchAgent agent,
  required String userText,
  required ExtractionResult extraction,
  required BioProfile? profile,
  required SafetyGuard guard,
}) async* {
  const placeholder = SemaReply(
    tone: ReplyTone.calm,
    headline: 'Let me think this through with you',
    body: '',
  );
  yield AgentTurn(
    reply: placeholder,
    extracted: extraction.slugs,
    vitals: extraction.vitals,
  );

  final buf = StringBuffer();
  SemaReply progressing = placeholder;

  try {
    DateTime? lastEmit;
    await for (final chunk in agent.reply(userText: userText)) {
      buf.write(chunk);
      if (buf.length > 1200) break;
      final now = DateTime.now();
      if (lastEmit != null &&
          now.difference(lastEmit) < const Duration(milliseconds: 60)) {
        continue;
      }
      lastEmit = now;
      progressing = placeholder.copyWith(body: buf.toString().trimLeft());
      yield AgentTurn(
        reply: progressing,
        extracted: extraction.slugs,
        vitals: extraction.vitals,
      );
    }
  } catch (_) {
    return;
  }

  final body = buf.toString().trim();
  if (body.length < 8) return;
  progressing = placeholder.copyWith(body: body);

  // Final guard pass. Tool-dispatch can name drugs the LLM made up,
  // so we run with no `matchedEntry` — the guard's drug whitelist
  // refuses any drug name without a matching entry.
  final guarded = guard.check(progressing);

  // Synthetic audit: Gemma drove this turn, so there's no rule id, no
  // citations, and severity is a placeholder. The flag tells the
  // drawer to render this case distinctively rather than making it
  // look like a clinical decision.
  final fallbackAudit = ReplyAudit(
    ruleId: 'gemma-fallback',
    severity: Severity.low,
    escalation: Escalation.selfCare,
    userText: userText,
    symptomsExtracted: extraction.slugs,
    vitalsExtracted: extraction.vitals,
    profileAtDecision: profile,
    source: AuditSource.gemmaFallback,
  );

  yield AgentTurn(
    reply: guarded.reply.copyWith(audit: fallbackAudit),
    extracted: extraction.slugs,
    vitals: extraction.vitals,
    guardViolation: guarded.violation,
  );
}

/// One round-trip's metadata. `reply` is what the chat bubble shows.
class AgentTurn {
  const AgentTurn({
    required this.reply,
    required this.extracted,
    this.vitals = const {},
    this.guardViolation,
  });

  final SemaReply reply;
  final Set<String> extracted;
  final Map<String, num> vitals;
  final GuardViolation? guardViolation;
}
