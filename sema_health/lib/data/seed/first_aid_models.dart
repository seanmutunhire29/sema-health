import '../../domain/triage/severity.dart';

class FirstAidStep {
  const FirstAidStep({
    required this.order,
    required this.action,
    this.critical = false,
  });

  final int order;
  final String action;
  final bool critical;
}

class Medication {
  const Medication({
    required this.name,
    required this.role,
    this.pediatricContraindication = false,
  });

  final String name;
  final String role;
  final bool pediatricContraindication;
}

class Contraindication {
  const Contraindication({
    this.profile,
    this.alternative,
    this.action,
    this.escalateTo,
  });

  /// Profile-level matcher: 'pregnant', 'age_lt_3_months', etc.
  final String? profile;

  /// Replacement step or guidance when this contraindication fires.
  final String? alternative;

  /// 'refuse_self_care' means the entry is not surfaced for this profile;
  /// the engine must escalate instead.
  final String? action;

  final Escalation? escalateTo;
}

class FirstAidEntry {
  const FirstAidEntry({
    required this.id,
    required this.title,
    required this.severity,
    required this.ageGroups,
    required this.symptomSlugs,
    required this.redFlags,
    required this.steps,
    required this.donts,
    required this.medications,
    required this.contraindications,
    required this.references,
    required this.reviewedBy,
    required this.escalation,
    this.notes,
    this.reviewedOn,
    this.crossReferences = const [],
  });

  final String id;
  final String title;
  final Severity severity;
  final List<String> ageGroups;
  final List<String> symptomSlugs;
  final List<String> redFlags;
  final List<FirstAidStep> steps;
  final List<String> donts;
  final List<Medication> medications;
  final List<Contraindication> contraindications;
  final String? notes;
  final List<String> references;
  final String reviewedBy;
  final String? reviewedOn;
  final Escalation escalation;
  final List<String> crossReferences;

  bool get isClinicianReviewed => reviewedBy != 'pending';
  bool get isEmergency => severity == Severity.emergency;

  /// True if the named drug appears in this entry's whitelist. The safety
  /// guard uses this to decide whether the LLM is allowed to mention a
  /// drug name in the reply for this entry.
  bool allowsMedication(String name) =>
      medications.any((m) => m.name.toLowerCase() == name.toLowerCase());
}

class Symptom {
  const Symptom({
    required this.id,
    required this.label,
    required this.category,
    required this.aliases,
    required this.severityHint,
    required this.ageGroups,
    required this.relatedEntries,
    this.requiresVital,
    this.isRedFlag = false,
  });

  final String id;
  final String label;
  final String category;
  final List<String> aliases;
  final Severity severityHint;
  final List<String> ageGroups;
  final String? requiresVital;
  final List<String> relatedEntries;
  final bool isRedFlag;
}
