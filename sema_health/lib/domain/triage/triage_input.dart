/// Bio profile collected at chat onboarding. Drives age-gated rules
/// (infant fever <3 mo, no aspirin for kids), pregnancy contraindications,
/// and pre-existing condition routing (asthma, epilepsy, etc.).
class BioProfile {
  const BioProfile({
    required this.ageMonths,
    this.sexAtBirth,
    this.isPregnant = false,
    this.conditions = const [],
    this.isChw = false,
    this.displayName,
  });

  /// Canonical age unit. UI displays years; rules read months so
  /// "infant <3 mo" is a single integer comparison.
  final int ageMonths;

  /// 'male' | 'female' | 'unknown' — null means the user has not
  /// answered yet, which the engine treats as 'unknown'.
  final String? sexAtBirth;

  final bool isPregnant;

  /// Pre-existing condition slugs (`asthma`, `epilepsy`, etc.). Used by
  /// `profile.conditions_contains` predicates.
  final List<String> conditions;

  /// True when the active profile is a community health worker — unlocks
  /// CHW-specific structured fields. Not currently read by triage rules
  /// but exposed for future expansion.
  final bool isChw;

  /// Optional human label ("Me", "Adwoa", "baby Kojo") shown in chat
  /// chrome. Pure UI — never reaches Gemma's prompt.
  final String? displayName;

  BioProfile copyWith({
    int? ageMonths,
    String? sexAtBirth,
    bool? isPregnant,
    List<String>? conditions,
    bool? isChw,
    String? displayName,
  }) {
    return BioProfile(
      ageMonths: ageMonths ?? this.ageMonths,
      sexAtBirth: sexAtBirth ?? this.sexAtBirth,
      isPregnant: isPregnant ?? this.isPregnant,
      conditions: conditions ?? this.conditions,
      isChw: isChw ?? this.isChw,
      displayName: displayName ?? this.displayName,
    );
  }
}

/// Input bundle for one triage evaluation.
class TriageInput {
  const TriageInput({
    required this.symptoms,
    required this.profile,
    this.vitals = const {},
    this.context = const {},
  });

  /// Symptom slugs extracted from the user's turn (Gemma-as-NLU in v1,
  /// in-house NLU later). Both ordinary symptoms and red-flag predicates
  /// arrive as flat slugs in this set.
  final Set<String> symptoms;

  final BioProfile profile;

  /// Optional measured values (`body_temp_c`, `heart_rate_bpm`, ...).
  final Map<String, num> vitals;

  /// Conversation-level state (`seizure_duration_min`, `bleeding_minutes`,
  /// `flushing_minutes`, ...). Tracked by the chat agent across turns.
  final Map<String, num> context;
}
