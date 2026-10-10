import 'dart:convert';

import '../domain/triage/severity.dart';
import '../domain/triage/triage_input.dart';
import 'sema_reply.dart';

/// JSON serialization for [SemaReply] and friends.
///
/// Lives in its own file so the model file stays free of `dart:convert`
/// imports (we want it cleanly importable from non-IO contexts like
/// codegen-bound test runners). Round-trip is total: a reply
/// reconstituted from `fromJson(toJson(r))` is byte-equal to `r` for
/// every field the chat reads.
///
/// Format is intentionally explicit (no `freezed` etc.) so the
/// migration to Drift later doesn't have to chase generated code.

extension SemaReplyJson on SemaReply {
  Map<String, Object?> toJson() => {
        'tone': tone.name,
        'headline': headline,
        'body': body,
        if (steps.isNotEmpty)
          'steps': [for (final s in steps) s._toJson()],
        if (donts.isNotEmpty) 'donts': donts,
        if (cta != null) 'cta': cta!._toJson(),
        if (entryRef != null) 'entryRef': entryRef,
        if (citation.isNotEmpty) 'citation': citation,
        if (audit != null) 'audit': audit!._toJson(),
      };

  String toJsonString() => jsonEncode(toJson());
}

extension SemaReplyStepJsonExt on SemaReplyStep {
  Map<String, Object?> _toJson() => {
        'order': order,
        'text': text,
        'critical': critical,
      };
}

extension ReplyCtaJsonExt on ReplyCta {
  Map<String, Object?> _toJson() => {
        'kind': kind.name,
        'label': label,
        if (entryRef != null) 'entryRef': entryRef,
      };
}

extension ReplyAuditJsonExt on ReplyAudit {
  Map<String, Object?> _toJson() => {
        'ruleId': ruleId,
        'severity': severity.name,
        'escalation': escalation.name,
        'userText': userText,
        'symptomsExtracted': symptomsExtracted.toList(),
        if (vitalsExtracted.isNotEmpty) 'vitalsExtracted': vitalsExtracted,
        if (profileAtDecision != null)
          'profileAtDecision': profileAtDecision!._toJson(),
        if (entryRef != null) 'entryRef': entryRef,
        if (references.isNotEmpty) 'references': references,
        'source': source.name,
        'decidedAt': decidedAt.toIso8601String(),
      };
}

extension BioProfileJsonExt on BioProfile {
  Map<String, Object?> _toJson() => {
        'ageMonths': ageMonths,
        if (sexAtBirth != null) 'sexAtBirth': sexAtBirth,
        if (isPregnant) 'isPregnant': true,
        if (conditions.isNotEmpty) 'conditions': conditions,
        if (isChw) 'isChw': true,
        if (displayName != null) 'displayName': displayName,
      };
}

// ─── Decoders ────────────────────────────────────────────────────

SemaReply semaReplyFromJsonString(String s) =>
    semaReplyFromJson(jsonDecode(s) as Map<String, Object?>);

SemaReply semaReplyFromJson(Map<String, Object?> j) {
  return SemaReply(
    tone: _toneFromName(j['tone'] as String? ?? 'calm'),
    headline: (j['headline'] as String?) ?? '',
    body: (j['body'] as String?) ?? '',
    steps: [
      for (final s in (j['steps'] as List? ?? const []))
        _stepFromJson(s as Map<String, Object?>),
    ],
    donts: [
      for (final d in (j['donts'] as List? ?? const [])) d as String,
    ],
    cta: j['cta'] is Map
        ? _ctaFromJson(j['cta']! as Map<String, Object?>)
        : null,
    entryRef: j['entryRef'] as String?,
    citation: [
      for (final c in (j['citation'] as List? ?? const [])) c as String,
    ],
    audit: j['audit'] is Map
        ? _auditFromJson(j['audit']! as Map<String, Object?>)
        : null,
  );
}

SemaReplyStep _stepFromJson(Map<String, Object?> j) => SemaReplyStep(
      order: (j['order'] as num).toInt(),
      text: j['text']! as String,
      critical: (j['critical'] as bool?) ?? false,
    );

ReplyCta _ctaFromJson(Map<String, Object?> j) => ReplyCta(
      kind: _ctaKindFromName(j['kind']! as String),
      label: j['label']! as String,
      entryRef: j['entryRef'] as String?,
    );

ReplyAudit _auditFromJson(Map<String, Object?> j) {
  final symptoms = <String>{
    for (final s in (j['symptomsExtracted'] as List? ?? const []))
      s as String,
  };
  final vitalsRaw = j['vitalsExtracted'] as Map<String, Object?>?;
  final vitals = <String, num>{
    if (vitalsRaw != null)
      for (final e in vitalsRaw.entries)
        if (e.value is num) e.key: e.value! as num,
  };
  final references = [
    for (final r in (j['references'] as List? ?? const [])) r as String,
  ];
  final profile = j['profileAtDecision'] is Map
      ? _profileFromJson(j['profileAtDecision']! as Map<String, Object?>)
      : null;
  return ReplyAudit(
    ruleId: j['ruleId']! as String,
    severity: Severity.parse(j['severity']! as String),
    escalation: Escalation.parse(j['escalation']! as String),
    userText: (j['userText'] as String?) ?? '',
    symptomsExtracted: symptoms,
    vitalsExtracted: vitals,
    profileAtDecision: profile,
    entryRef: j['entryRef'] as String?,
    references: references,
    source: _auditSourceFromName((j['source'] as String?) ?? 'deterministicRule'),
    decidedAt: DateTime.tryParse((j['decidedAt'] as String?) ?? '') ??
        DateTime.now(),
  );
}

BioProfile _profileFromJson(Map<String, Object?> j) => BioProfile(
      ageMonths: (j['ageMonths'] as num).toInt(),
      sexAtBirth: j['sexAtBirth'] as String?,
      isPregnant: (j['isPregnant'] as bool?) ?? false,
      conditions: [
        for (final c in (j['conditions'] as List? ?? const [])) c as String,
      ],
      isChw: (j['isChw'] as bool?) ?? false,
      displayName: j['displayName'] as String?,
    );

// ─── Enum helpers ───────────────────────────────────────────────

ReplyTone _toneFromName(String name) =>
    ReplyTone.values.firstWhere((e) => e.name == name,
        orElse: () => ReplyTone.calm);

ReplyCtaKind _ctaKindFromName(String name) =>
    ReplyCtaKind.values.firstWhere((e) => e.name == name,
        orElse: () => ReplyCtaKind.none);

AuditSource _auditSourceFromName(String name) =>
    AuditSource.values.firstWhere((e) => e.name == name,
        orElse: () => AuditSource.deterministicRule);
