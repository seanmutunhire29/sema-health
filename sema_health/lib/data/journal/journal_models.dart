import '../../ai/sema_reply.dart';
import '../../domain/triage/severity.dart';
import '../../domain/triage/triage_input.dart';

/// Render a structured [BioProfile] back into the legacy compact-string
/// snapshot the journal model stores. Kept verbatim so existing journal
/// rows on disk stay parseable. New ReplyAudit retains the structured
/// profile via `profileAtDecision`; this helper bridges the two shapes.
String? _profileSnapshotString(BioProfile? p) {
  if (p == null) return null;
  return [
    'age:${p.ageMonths}mo',
    if (p.sexAtBirth != null) 'sex:${p.sexAtBirth}',
    if (p.isPregnant) 'pregnant',
    if (p.conditions.isNotEmpty) 'conds:${p.conditions.join(",")}',
  ].join('|');
}

/// A single journal session — one conversation in the chat. Holds the
/// transcript turns the user can scroll back through, and is the unit
/// of persistence in [JournalStore].
class JournalSession {
  JournalSession({
    required this.id,
    required this.startedAt,
    required this.languageCode,
    List<JournalTurn>? turns,
  }) : turns = turns ?? <JournalTurn>[];

  /// Stable identifier, ISO-8601 timestamp by convention.
  final String id;

  /// When the chat screen mounted. Drives "today / yesterday / dd MMM"
  /// labels on the list view.
  final DateTime startedAt;

  /// Active app language at session start. Stored so the list view can
  /// render a language chip even after the user has switched.
  final String languageCode;

  /// Mutable transcript. The chat appends to this in-place; the store
  /// re-saves the whole session on each mutation.
  final List<JournalTurn> turns;

  /// First Sema-side turn — used by the list view as the headline
  /// preview ("Severe allergic reaction (anaphylaxis)" / etc.). Returns
  /// null when the session is user-only (Gemma never replied).
  SemaTurn? get firstSemaTurn {
    for (final t in turns) {
      if (t is SemaTurn) return t;
    }
    return null;
  }

  /// Maximum severity recorded in the session. Drives the tone color
  /// of the list-item card so emergencies surface visually.
  Severity? get peakSeverity {
    Severity? peak;
    for (final t in turns) {
      if (t is SemaTurn && t.severity != null) {
        if (peak == null || t.severity!.index > peak.index) {
          peak = t.severity;
        }
      }
    }
    return peak;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'languageCode': languageCode,
        'turns': [for (final t in turns) t.toJson()],
      };

  factory JournalSession.fromJson(Map<String, Object?> j) => JournalSession(
        id: j['id'] as String,
        startedAt: DateTime.parse(j['startedAt'] as String),
        languageCode: j['languageCode'] as String,
        turns: [
          if (j['turns'] is List)
            for (final t in j['turns'] as List)
              JournalTurn.fromJson(
                  Map<String, Object?>.from(t as Map)),
        ],
      );
}

/// One turn in a journal transcript. Sealed so `switch` exhaustively
/// covers every variant — no surprise turn types reach the renderer.
sealed class JournalTurn {
  const JournalTurn(this.time);

  /// Local clock at the time the turn was appended. Stored as UTC ISO.
  final DateTime time;

  Map<String, Object?> toJson();

  static JournalTurn fromJson(Map<String, Object?> j) {
    final kind = j['kind'];
    return switch (kind) {
      'user' => UserTurn.fromJson(j),
      'sema' => SemaTurn.fromJson(j),
      _ => throw FormatException('JournalTurn: unknown kind "$kind"'),
    };
  }
}

class UserTurn extends JournalTurn {
  const UserTurn({required DateTime time, required this.text}) : super(time);
  final String text;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'user',
        'time': time.toIso8601String(),
        'text': text,
      };

  factory UserTurn.fromJson(Map<String, Object?> j) => UserTurn(
        time: DateTime.parse(j['time'] as String),
        text: j['text'] as String,
      );
}

/// A Sema-side turn carrying everything the audit drawer needs.
///
/// We deliberately don't persist the full SemaReply (steps + don'ts +
/// medications): those are KG data and can be re-hydrated by entryRef
/// at render time. Persisting them duplicates the corpus and risks
/// drift if the YAML is updated. The audit fields are the unique value.
class SemaTurn extends JournalTurn {
  const SemaTurn({
    required DateTime time,
    required this.tone,
    required this.headline,
    required this.body,
    this.entryRef,
    this.ruleId,
    this.severity,
    this.extractedSymptoms = const [],
    this.profileSnapshot,
    this.citations = const [],
  }) : super(time);

  final ReplyTone tone;
  final String headline;
  final String body;

  /// First-aid KG entry id (re-hydrate steps/don'ts via FirstAidRepo).
  final String? entryRef;

  /// Triage rule that fired (e.g. `anaphylaxis-airway`). Surfaced in
  /// the audit drawer for transparency.
  final String? ruleId;

  final Severity? severity;

  /// Symptom slugs the extractor pulled from the user's turn. Lets the
  /// drawer show the user *why* this specific reply was generated.
  final List<String> extractedSymptoms;

  /// Compact "age:340mo|sex:female|conds:asthma" snapshot of the bio
  /// profile at decision time. Appears in the drawer so it's auditable
  /// even after the profile is later edited.
  final String? profileSnapshot;

  /// WHO IMCI / Red Cross / ministry-of-health citations on the rule.
  final List<String> citations;

  /// Hydrate a SemaTurn from the live SemaReply that flowed through the
  /// chat bubble. Used by the conversation screen on stream-completion.
  factory SemaTurn.fromReply(SemaReply reply, DateTime time) => SemaTurn(
        time: time,
        tone: reply.tone,
        headline: reply.headline,
        body: reply.body,
        entryRef: reply.entryRef,
        ruleId: reply.audit?.ruleId,
        severity: reply.audit?.severity,
        extractedSymptoms:
            reply.audit?.symptomsExtracted.toList(growable: false) ??
                const [],
        profileSnapshot: _profileSnapshotString(reply.audit?.profileAtDecision),
        citations: reply.citation,
      );

  @override
  Map<String, Object?> toJson() => {
        'kind': 'sema',
        'time': time.toIso8601String(),
        'tone': tone.name,
        'headline': headline,
        'body': body,
        if (entryRef != null) 'entryRef': entryRef,
        if (ruleId != null) 'ruleId': ruleId,
        if (severity != null) 'severity': severity!.name,
        if (extractedSymptoms.isNotEmpty)
          'extractedSymptoms': extractedSymptoms,
        if (profileSnapshot != null) 'profileSnapshot': profileSnapshot,
        if (citations.isNotEmpty) 'citations': citations,
      };

  factory SemaTurn.fromJson(Map<String, Object?> j) => SemaTurn(
        time: DateTime.parse(j['time'] as String),
        tone: _toneFromName(j['tone']),
        headline: j['headline'] as String,
        body: j['body'] as String,
        entryRef: j['entryRef'] as String?,
        ruleId: j['ruleId'] as String?,
        severity: _severityFromName(j['severity']),
        extractedSymptoms: [
          if (j['extractedSymptoms'] is List)
            for (final s in j['extractedSymptoms'] as List) s.toString(),
        ],
        profileSnapshot: j['profileSnapshot'] as String?,
        citations: [
          if (j['citations'] is List)
            for (final c in j['citations'] as List) c.toString(),
        ],
      );
}

ReplyTone _toneFromName(Object? name) {
  if (name is String) {
    for (final v in ReplyTone.values) {
      if (v.name == name) return v;
    }
  }
  return ReplyTone.calm;
}

Severity? _severityFromName(Object? name) {
  if (name is! String) return null;
  for (final v in Severity.values) {
    if (v.name == name) return v;
  }
  return null;
}
