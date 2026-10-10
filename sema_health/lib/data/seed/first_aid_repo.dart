import 'package:yaml/yaml.dart';

import '../../domain/triage/severity.dart';
import 'first_aid_models.dart';

/// In-memory repository for the bundled clinical knowledge graph.
///
/// Pure Dart — no flutter imports — so unit tests can construct it
/// from raw YAML strings without booting the flutter test bindings.
/// The convenience `loadFromAssets()` method that calls `rootBundle`
/// lives in `first_aid_repo_assets.dart`.
class FirstAidRepo {
  FirstAidRepo._({
    required Map<String, FirstAidEntry> entriesById,
    required Map<String, Symptom> symptomsById,
    required Map<String, Set<String>> entriesBySlug,
  })  : _entriesById = entriesById,
        _symptomsById = symptomsById,
        _entriesBySlug = entriesBySlug;

  final Map<String, FirstAidEntry> _entriesById;
  final Map<String, Symptom> _symptomsById;

  /// Reverse index: symptom slug → set of entry ids that handle it.
  final Map<String, Set<String>> _entriesBySlug;

  /// Pure-data constructor — used by tests and by any path that
  /// loads the YAML from somewhere other than `rootBundle`.
  static FirstAidRepo parse({
    required String firstAidYaml,
    required String symptomsYaml,
  }) {
    final entries = _parseEntries(loadYaml(firstAidYaml) as YamlMap);
    final symptoms = _parseSymptoms(loadYaml(symptomsYaml) as YamlMap);

    final byId = {for (final e in entries) e.id: e};
    final byIdSym = {for (final s in symptoms) s.id: s};

    final bySlug = <String, Set<String>>{};
    for (final e in entries) {
      for (final slug in e.symptomSlugs) {
        bySlug.putIfAbsent(slug, () => <String>{}).add(e.id);
      }
    }

    return FirstAidRepo._(
      entriesById: byId,
      symptomsById: byIdSym,
      entriesBySlug: bySlug,
    );
  }

  Iterable<FirstAidEntry> get all => _entriesById.values;
  Iterable<Symptom> get allSymptoms => _symptomsById.values;

  FirstAidEntry? getById(String id) => _entriesById[id];
  Symptom? getSymptom(String id) => _symptomsById[id];

  /// All entries that list `slug` in their `symptom_slugs`. Used by the
  /// chat agent's `lookup_first_aid` tool to find candidates after the
  /// triage rules have classified the turn.
  List<FirstAidEntry> entriesForSlug(String slug) {
    final ids = _entriesBySlug[slug];
    if (ids == null) return const [];
    return [for (final id in ids) _entriesById[id]!];
  }

  List<FirstAidEntry> bySeverity(Severity s) =>
      [for (final e in all) if (e.severity == s) e];
}

// ---------------------------------------------------------------------------
// Internal parsing helpers — kept private; consumers see typed entities only.
// ---------------------------------------------------------------------------

List<FirstAidEntry> _parseEntries(YamlMap root) {
  final raw = root['entries'];
  if (raw is! YamlList) {
    throw const FormatException('first_aid.yaml: missing `entries:` list');
  }
  return [for (final node in raw) _entryFromYaml(node as YamlMap)];
}

FirstAidEntry _entryFromYaml(YamlMap m) {
  return FirstAidEntry(
    id: m['id'] as String,
    title: m['title'] as String,
    severity: Severity.parse(m['severity'] as String),
    ageGroups: _stringList(m['age_groups']),
    symptomSlugs: _stringList(m['symptom_slugs']),
    redFlags: _stringList(m['red_flags']),
    steps: _stepsFromYaml(m['steps']),
    donts: _stringList(m['donts']),
    medications: _medsFromYaml(m['medications']),
    contraindications: _contraFromYaml(m['contraindications']),
    notes: m['notes'] as String?,
    references: _stringList(m['references']),
    reviewedBy: (m['reviewed_by'] ?? 'pending') as String,
    reviewedOn: m['reviewed_on'] as String?,
    escalation: Escalation.parse(m['escalation'] as String),
    crossReferences: _stringList(m['cross_references']),
  );
}

List<FirstAidStep> _stepsFromYaml(dynamic node) {
  if (node is! YamlList) return const [];
  return [
    for (final s in node)
      FirstAidStep(
        order: (s as YamlMap)['order'] as int,
        action: s['action'] as String,
        critical: (s['critical'] as bool?) ?? false,
      ),
  ];
}

List<Medication> _medsFromYaml(dynamic node) {
  if (node is! YamlList) return const [];
  return [
    for (final m in node)
      Medication(
        name: (m as YamlMap)['name'] as String,
        role: m['role'] as String,
        pediatricContraindication:
            (m['pediatric_contraindication'] as bool?) ?? false,
      ),
  ];
}

List<Contraindication> _contraFromYaml(dynamic node) {
  if (node is! YamlList) return const [];
  return [
    for (final c in node)
      Contraindication(
        profile: (c as YamlMap)['profile'] as String?,
        alternative: c['alternative'] as String?,
        action: c['action'] as String?,
        escalateTo: c['escalate_to'] is String
            ? Escalation.parse(c['escalate_to'] as String)
            : null,
      ),
  ];
}

List<Symptom> _parseSymptoms(YamlMap root) {
  final raw = root['symptoms'];
  if (raw is! YamlList) {
    throw const FormatException('symptoms.yaml: missing `symptoms:` list');
  }
  return [
    for (final node in raw)
      Symptom(
        id: (node as YamlMap)['id'] as String,
        label: node['label'] as String,
        category: node['category'] as String,
        aliases: _stringList(node['aliases']),
        severityHint: Severity.parse(node['severity_hint'] as String),
        ageGroups: _stringList(node['age_groups']),
        requiresVital: node['requires_vital'] as String?,
        relatedEntries: _stringList(node['related_entries']),
        isRedFlag: (node['is_red_flag'] as bool?) ?? false,
      ),
  ];
}

List<String> _stringList(dynamic node) {
  if (node is YamlList) return [for (final v in node) v.toString()];
  return const [];
}
