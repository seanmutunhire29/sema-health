import '../data/seed/first_aid_models.dart';
import '../domain/triage/severity.dart';
import '../domain/triage/triage_input.dart';
import '../domain/triage/triage_outcome.dart';
import 'sema_reply.dart';

/// Turns a [TriageOutcome] (+ matched first-aid entry, + active bio
/// profile) into a structured [SemaReply] ready for the chat bubble.
///
/// Why a deterministic formatter
/// -----------------------------
/// The architecture is explicit: "the LLM does **not** drive triage;
/// it drives expression. By the time it runs, severity and retrieved
/// context are already decided." This formatter is the safe-default
/// expression layer that runs even without Gemma loaded — every
/// emergency reply is correct and on-rails before the LLM is asked to
/// add warmth.
///
/// When Gemma is wired in (step 9), the verbalizer takes the
/// formatted [SemaReply] as structured context and may rewrite the
/// `body` field for tone. Steps and don'ts stay verbatim from the KG.
class ReplyFormatter {
  const ReplyFormatter();

  /// Build the user-facing reply.
  ///
  /// [outcome] is required; if `null`, callers should use [fallback]
  /// instead. [userText] and [vitalsExtracted] flow into the audit
  /// trail so clinicians can see exactly what Sema saw.
  SemaReply format({
    required TriageOutcome outcome,
    required FirstAidEntry? entry,
    required BioProfile? profile,
    required Set<String> symptomsExtracted,
    required String userText,
    Map<String, num> vitalsExtracted = const {},
  }) {
    final tone = ReplyTone.fromSeverity(outcome.severity);
    final headline = _headlineFor(outcome, entry, profile);
    final body = outcome.recommendation;

    // Steps/don'ts come from the KG entry verbatim. Cap step count so
    // an emergency bubble doesn't become a wall of text — the user can
    // tap into the full first-aid guide for the rest.
    final steps = entry == null
        ? const <SemaReplyStep>[]
        : _stepsFor(entry, outcome.severity);
    final donts = entry?.donts ?? const <String>[];

    final cta = _ctaFor(outcome, entry);

    return SemaReply(
      tone: tone,
      headline: headline,
      body: body,
      steps: steps,
      donts: donts,
      cta: cta,
      entryRef: outcome.entryRef ?? entry?.id,
      citation: outcome.citation,
      audit: ReplyAudit(
        ruleId: outcome.ruleId,
        severity: outcome.severity,
        escalation: outcome.escalation,
        userText: userText,
        symptomsExtracted: symptomsExtracted,
        vitalsExtracted: vitalsExtracted,
        profileAtDecision: profile,
        entryRef: outcome.entryRef ?? entry?.id,
        references: outcome.citation,
      ),
    );
  }

  /// Greeting shown after the bio-profile sheet closes for the first
  /// time. Personalized when [profile.displayName] is set.
  SemaReply greeting(BioProfile? profile) {
    final name = profile?.displayName?.trim();
    final hello = (name != null && name.isNotEmpty)
        ? "Hey, I'm Sema, and I'm here for $name."
        : "Hey, I'm Sema. Glad you're here.";
    return SemaReply(
      tone: ReplyTone.calm,
      headline: hello,
      body: "Just tell me what's going on in your own words: what "
          "hurts, when it started, how it feels. We'll figure it out "
          "together. If something's bleeding or burnt, I can walk you "
          "through first aid step by step.",
    );
  }

  /// Conversational reply for greetings, thanks, and farewells. Skips
  /// triage entirely — the LLM would only sound stilted answering "hi".
  SemaReply smalltalk(SmalltalkKind kind, {BioProfile? profile}) {
    final name = profile?.displayName?.trim();
    final youAre = (name != null && name.isNotEmpty) ? ', $name' : '';
    return switch (kind) {
      SmalltalkKind.greeting => SemaReply(
          tone: ReplyTone.calm,
          headline: 'Hey$youAre',
          body: "Good to hear from you. Whenever you're ready, tell me "
              "what's going on: what hurts, when it started, how it feels.",
        ),
      SmalltalkKind.thanks => SemaReply(
          tone: ReplyTone.calm,
          headline: 'Anytime',
          body: "I'm right here if anything else comes up.",
        ),
      SmalltalkKind.farewell => SemaReply(
          tone: ReplyTone.calm,
          headline: 'Take care$youAre',
          body: "I'll be here when you need me again.",
        ),
      SmalltalkKind.howAreYou => SemaReply(
          tone: ReplyTone.calm,
          headline: "I'm doing well, thanks for asking",
          body: "More importantly, how are you feeling? If something's "
              "off, walk me through it.",
        ),
    };
  }

  /// Used when the triage engine returns null (extracted slugs didn't
  /// match any rule). When [extracted] is non-empty we acknowledge the
  /// named symptoms and ask the two universal clinical follow-ups
  /// (onset + 1-10 severity) instead of a generic clarifying question
  /// — gives the chat a "Sema heard me" feel without requiring per-
  /// symptom question banks.
  SemaReply fallback({String? hint, Set<String> extracted = const {}}) {
    if (extracted.isEmpty) {
      return SemaReply(
        tone: ReplyTone.calm,
        headline: 'Walk me through that',
        body: hint ??
            "I want to make sure I understand. What's hurting, when did "
                "it start, and how does it feel (sharp, dull, getting "
                "worse)? Take your time.",
      );
    }
    final label = _joinSymptoms(extracted);
    return SemaReply(
      tone: ReplyTone.calm,
      headline: 'Got it: $label',
      body: hint ??
          "Two quick things to help me figure this out: how long has "
              "it been going on, and on a 1-10 scale, how bad is the "
              "worst of it right now?",
    );
  }

  /// Slugs → readable phrase. "back-pain", "headache" → "back pain and
  /// headache". Three+ uses Oxford comma so it reads like a sentence.
  static String _joinSymptoms(Set<String> slugs) {
    final words = slugs.map((s) => s.replaceAll('-', ' ')).toList();
    return switch (words.length) {
      0 => '',
      1 => words.first,
      2 => '${words.first} and ${words.last}',
      _ => '${words.take(words.length - 1).join(', ')}, and ${words.last}',
    };
  }

  // ─── Helpers ────────────────────────────────────────────────────

  String _headlineFor(
    TriageOutcome outcome,
    FirstAidEntry? entry,
    BioProfile? profile,
  ) {
    if (outcome.severity == Severity.emergency) {
      // Pregnancy bleeding has a special headline — not in the KG
      // entry's title.
      if (outcome.ruleId == 'pregnancy-vaginal-bleeding') {
        return "Okay, this is a pregnancy emergency";
      }
      if (outcome.ruleId == 'infant-fever') {
        return "Let's get the baby to a clinic now";
      }
      if (entry != null) return 'Sounds like ${_lc(entry.title)}.';
      return "This is urgent, let's get help now";
    }
    if (outcome.severity == Severity.high) {
      if (entry != null) {
        return "Sounds like ${_lc(entry.title)}. Let's get you to a clinician";
      }
      return "Best to see a clinician for this one";
    }
    if (entry != null) return entry.title;
    return _capitalize(_titleFromRule(outcome.ruleId));
  }

  /// Turn the title-case KG title into sentence case ("Severe bleeding"
  /// → "severe bleeding") so it flows into "This looks like ..." naturally.
  String _lc(String s) {
    if (s.isEmpty) return s;
    return s[0].toLowerCase() + s.substring(1);
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String _titleFromRule(String ruleId) =>
      ruleId.replaceAll('-', ' ').replaceAll('_', ' ');

  List<SemaReplyStep> _stepsFor(FirstAidEntry e, Severity severity) {
    // Emergency bubbles show all critical steps + up to 2 supporting
    // steps; lower severities show up to 5 steps total. The full guide
    // is one tap away on the bubble.
    final critical = <SemaReplyStep>[];
    final supporting = <SemaReplyStep>[];
    for (final s in e.steps) {
      final step = SemaReplyStep(
        order: s.order,
        text: s.action,
        critical: s.critical,
      );
      (s.critical ? critical : supporting).add(step);
    }
    if (severity == Severity.emergency) {
      return [
        ...critical,
        ...supporting.take(2),
      ];
    }
    return e.steps
        .take(5)
        .map((s) => SemaReplyStep(
              order: s.order,
              text: s.action,
              critical: s.critical,
            ))
        .toList();
  }

  /// Detects short social messages so we can answer them conversationally
  /// instead of feeding "hi" through the clinical pipeline. Returns null
  /// when the text looks like an actual symptom report.
  ///
  /// Heuristic, not exhaustive — keep entries short and high-precision so
  /// we never mis-classify a real complaint as smalltalk.
  static SmalltalkKind? detectSmalltalk(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty || t.length > 40) return null;
    // Strip trailing punctuation: "hi!" / "hello." → "hi" / "hello"
    final stripped = t.replaceAll(RegExp(r'[!?.,;:\s]+$'), '');
    if (_greetings.contains(stripped)) return SmalltalkKind.greeting;
    if (_thanks.contains(stripped)) return SmalltalkKind.thanks;
    if (_farewells.contains(stripped)) return SmalltalkKind.farewell;
    if (_howAreYou.any((p) => stripped == p)) return SmalltalkKind.howAreYou;
    return null;
  }

  static const _greetings = <String>{
    'hi', 'hii', 'hiii', 'hello', 'hey', 'heya', 'yo', 'sup',
    'good morning', 'morning', 'good afternoon', 'afternoon',
    'good evening', 'evening', 'gm', 'ge',
    'habari', 'jambo', 'mambo', 'salama', // sw greetings
    'akwaaba', 'maakye', 'maaha', 'maadwo', // tw greetings
  };

  static const _thanks = <String>{
    'thanks', 'thank you', 'ty', 'thx', 'tysm',
    'asante', 'asante sana', // sw
    'medaase', 'meda wo ase', // tw
  };

  static const _farewells = <String>{
    'bye', 'goodbye', 'see ya', 'see you', 'cya', 'gn', 'good night',
    'kwaheri', // sw
    'nante yiye', // tw
  };

  static const _howAreYou = <String>{
    'how are you', 'how are u', 'how r u', 'how you doing',
    'how are you doing', 'whats up', "what's up", 'wassup',
  };

  ReplyCta? _ctaFor(TriageOutcome outcome, FirstAidEntry? entry) {
    return switch (outcome.escalation) {
      Escalation.callEmergency =>
        const ReplyCta(kind: ReplyCtaKind.callEmergency, label: 'Call emergency'),
      Escalation.goToEr => const ReplyCta(
          kind: ReplyCtaKind.findHospital,
          label: 'Find nearest hospital',
        ),
      Escalation.nearestClinic => const ReplyCta(
          kind: ReplyCtaKind.findClinic,
          label: 'Find nearest clinic',
        ),
      Escalation.selfCare => entry == null
          ? null
          : ReplyCta(
              kind: ReplyCtaKind.openFirstAidEntry,
              label: 'Open full guide',
              entryRef: entry.id,
            ),
    };
  }
}

/// Categories the smalltalk fast-path can route to. Each gets its own
/// canned reply via [ReplyFormatter.smalltalk].
enum SmalltalkKind { greeting, thanks, farewell, howAreYou }
