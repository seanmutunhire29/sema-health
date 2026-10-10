import 'severity.dart';

/// Result of a triage evaluation. The chat agent reads this to decide
/// what to do next: surface an emergency banner, look up a first-aid
/// entry, ask a clarifying question, or fall through to the LLM.
class TriageOutcome {
  const TriageOutcome({
    required this.ruleId,
    required this.severity,
    required this.escalation,
    required this.recommendation,
    this.entryRef,
    this.toolsRequired = const [],
    this.citation = const [],
  });

  /// The triage rule that fired. Useful for telemetry and for the
  /// auditor showing why this outcome was chosen.
  final String ruleId;

  final Severity severity;
  final Escalation escalation;

  /// English template — pre-translated language banks (per-language)
  /// will share the same `recommendation` key in M2.
  final String recommendation;

  /// Optional first-aid KG entry to surface alongside the recommendation.
  /// The chat UI fetches this via `FirstAidRepo.getById(entryRef)`.
  final String? entryRef;

  /// Tool calls the agent should make next, e.g.
  /// `nearest_provider:hospital`. Parsed by the agent loop.
  final List<String> toolsRequired;

  /// WHO IMCI / Red Cross / etc. citations on this rule. Surfaced to
  /// the auditor view, not to the user directly.
  final List<String> citation;

  bool get isEmergency => severity == Severity.emergency;
}
