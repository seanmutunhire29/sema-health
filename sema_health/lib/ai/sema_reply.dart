import '../domain/triage/severity.dart';
import '../domain/triage/triage_input.dart';

/// Visual & emotional tone of a Sema reply. Drives the chat bubble's
/// banner color, headline weight, and accompanying iconography. The
/// rule of thumb: a calm tone is always more frequent than an emergency
/// tone; emergency replies should feel rare and serious by contrast.
enum ReplyTone {
  /// Self-care / informational. Neutral surface, no banner.
  calm,

  /// Watch-this carefully — high-severity rule fired. Amber accent.
  caution,

  /// Emergency triage outcome. Red banner, prominent CTA.
  emergency;

  static ReplyTone fromSeverity(Severity s) => switch (s) {
        Severity.low => ReplyTone.calm,
        Severity.medium => ReplyTone.calm,
        Severity.high => ReplyTone.caution,
        Severity.emergency => ReplyTone.emergency,
      };
}

/// What the chat agent wants the user to do next, surfaced as a tap
/// target. Concrete CTAs depend on the triage outcome's `escalation`.
enum ReplyCtaKind {
  none,
  callEmergency,
  findHospital,
  findClinic,
  openFirstAidEntry,
}

class ReplyCta {
  const ReplyCta({required this.kind, required this.label, this.entryRef});

  final ReplyCtaKind kind;
  final String label;

  /// For [ReplyCtaKind.openFirstAidEntry] — id of the KG entry to open.
  final String? entryRef;
}

/// One reply turn from Sema.
///
/// This is what flows out of the agent and into the chat bubble. The
/// safety guard runs over [headline], [body], and every step/dont line
/// before the bubble is appended — nothing here reaches the user
/// without that pass.
class SemaReply {
  const SemaReply({
    required this.tone,
    required this.headline,
    required this.body,
    this.steps = const [],
    this.donts = const [],
    this.cta,
    this.entryRef,
    this.citation = const [],
    this.audit,
  });

  final ReplyTone tone;

  /// One-line summary, e.g. "This looks like anaphylaxis."
  final String headline;

  /// Two- to four-sentence body. The clinical recommendation in
  /// human-readable form. Emergency replies always start with the
  /// action ("Call emergency services now.") to honor the
  /// time-to-action goal.
  final String body;

  /// KG steps surfaced verbatim. `critical: true` steps render with a
  /// red dot in the bubble; the formatter preserves order.
  final List<SemaReplyStep> steps;

  /// "Do NOT" lines surfaced verbatim from the KG entry's `donts:`
  /// array. Never paraphrased — the source text is clinician-curated.
  final List<String> donts;

  /// Optional follow-up action, e.g. "Find nearest hospital".
  final ReplyCta? cta;

  /// First-aid KG id this reply was sourced from, when applicable.
  /// Lets the bubble offer a "see full guide" tap.
  final String? entryRef;

  /// WHO IMCI / ministry-of-health citations on the rule that fired.
  /// Surfaced in an audit drawer, not the user-facing bubble.
  final List<String> citation;

  /// Internal trace for debugging / clinician audit. Never user-facing.
  final ReplyAudit? audit;

  /// Used by the verbalizer / tool-dispatch streaming paths to swap
  /// only the prose [body] while keeping every clinically-load-bearing
  /// field (steps, donts, headline, cta) verbatim.
  SemaReply copyWith({
    ReplyTone? tone,
    String? headline,
    String? body,
    List<SemaReplyStep>? steps,
    List<String>? donts,
    ReplyCta? cta,
    String? entryRef,
    List<String>? citation,
    ReplyAudit? audit,
  }) {
    return SemaReply(
      tone: tone ?? this.tone,
      headline: headline ?? this.headline,
      body: body ?? this.body,
      steps: steps ?? this.steps,
      donts: donts ?? this.donts,
      cta: cta ?? this.cta,
      entryRef: entryRef ?? this.entryRef,
      citation: citation ?? this.citation,
      audit: audit ?? this.audit,
    );
  }
}

class SemaReplyStep {
  const SemaReplyStep({
    required this.order,
    required this.text,
    this.critical = false,
  });

  final int order;
  final String text;
  final bool critical;
}

/// Trace data the chat persists alongside the bubble for the
/// per-conversation audit drawer.
///
/// Captures everything a clinician (or the user themselves) would need
/// to understand "why did Sema say what it said." Stored next to the
/// reply so it survives transcript persistence — when Drift lands, the
/// audit row goes alongside the message row.
class ReplyAudit {
  ReplyAudit({
    required this.ruleId,
    required this.severity,
    required this.escalation,
    required this.userText,
    required this.symptomsExtracted,
    this.vitalsExtracted = const {},
    this.profileAtDecision,
    this.entryRef,
    this.references = const [],
    this.source = AuditSource.deterministicRule,
    DateTime? decidedAt,
  }) : decidedAt = decidedAt ?? DateTime.now();

  /// `rules.yaml` rule id that fired. e.g. `pregnancy-vaginal-bleeding`.
  final String ruleId;

  final Severity severity;
  final Escalation escalation;

  /// What the user said when this reply was generated. Stored verbatim
  /// (no PHI scrubbing in v1 since the device is offline).
  final String userText;

  /// Slugs the extractor pulled out of [userText].
  final Set<String> symptomsExtracted;

  /// Numeric vitals the extractor recovered (`body_temp_c`, etc.).
  final Map<String, num> vitalsExtracted;

  /// Snapshot of the bio profile at decision time. A subsequent profile
  /// edit doesn't muddy the audit — clinicians always see the inputs
  /// the engine actually used.
  final BioProfile? profileAtDecision;

  /// First-aid KG entry the rule pointed to, when applicable.
  final String? entryRef;

  /// WHO IMCI / Red Cross / ministry-of-health citations on the rule.
  final List<String> references;

  /// Wall-clock time the deterministic decision was made.
  final DateTime decidedAt;

  /// What produced this reply. Drives the drawer copy: a deterministic
  /// rule fired (with a name and citations), or Gemma's open-ended
  /// tool-dispatch agent answered an off-script question.
  final AuditSource source;
}

/// Origin of a reply for the audit trail.
enum AuditSource {
  /// A `rules.yaml` rule fired and produced the recommendation.
  deterministicRule,

  /// No deterministic rule matched. Gemma's tool-dispatch agent
  /// answered using KG-grounded function calls. Severity is a default
  /// (low / self-care) — Gemma never decides severity in v1.
  gemmaFallback,
}
