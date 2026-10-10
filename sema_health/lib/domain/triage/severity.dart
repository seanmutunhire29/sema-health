/// Clinical severity levels used across the first-aid KG and triage
/// engine. Ordered: a comparison is meaningful (`Severity.emergency >
/// Severity.high`).
enum Severity {
  low,
  medium,
  high,
  emergency;

  static Severity parse(String s) => switch (s) {
        'low' => Severity.low,
        'medium' => Severity.medium,
        'high' => Severity.high,
        'emergency' => Severity.emergency,
        _ => throw FormatException('unknown severity: $s'),
      };
}

/// What the chat agent must do when a triage outcome fires.
enum Escalation {
  /// Call emergency services immediately.
  callEmergency,

  /// Go to an emergency room now.
  goToEr,

  /// Visit the nearest clinic for non-life-threatening medical attention.
  nearestClinic,

  /// Self-care at home is appropriate.
  selfCare;

  static Escalation parse(String s) => switch (s) {
        // YAML snake_case (clinician-facing source-of-truth in rules.yaml).
        'call_emergency' => Escalation.callEmergency,
        'go_to_er' => Escalation.goToEr,
        'nearest_clinic' => Escalation.nearestClinic,
        'self_care' => Escalation.selfCare,
        // Dart enum `.name` form — what `SemaReplySerde` writes when it
        // persists a reply to SQLite. Accepting both keeps the JSON
        // round-trip symmetric without forcing the serde to translate.
        'callEmergency' => Escalation.callEmergency,
        'goToEr' => Escalation.goToEr,
        'nearestClinic' => Escalation.nearestClinic,
        'selfCare' => Escalation.selfCare,
        _ => throw FormatException('unknown escalation: $s'),
      };
}