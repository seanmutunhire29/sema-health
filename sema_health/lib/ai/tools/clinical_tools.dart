import 'dart:convert';

import '../../data/seed/first_aid_repo.dart';
import '../../domain/triage/severity.dart';
import '../../domain/triage/triage_engine.dart';
import '../../domain/triage/triage_input.dart';

/// One callable function exposed to Gemma. The shape mirrors the OpenAI/
/// Anthropic JSON-schema convention so prompts and parsers can be reused
/// across model families later. Pure Dart — no Flutter imports — so unit
/// tests can drive these without booting the engine.
abstract class Tool {
  String get name;
  String get description;

  /// JSON-schema-ish parameter spec. We keep it as a plain `Map` rather
  /// than dragging in a schema package: Gemma reads the system prompt
  /// rendition, the executor reads the args dynamically.
  Map<String, Object?> get parametersSchema;

  /// Run the tool. [args] is the JSON object the model emitted inside its
  /// `<tool_call>{ "name": ..., "args": ... }</tool_call>`. The result is a
  /// JSON-encoded string that gets fed back into Gemma's next turn.
  Future<String> call(Map<String, Object?> args);
}

/// Look up first-aid entries that handle a given symptom. The repo's
/// reverse index makes this O(1) per slug. Returns a small JSON list of
/// `{id, title, severity, escalation_hint}` tuples — the model can then
/// pick one and call [GetFullEntryTool] for the steps.
class LookupFirstAidBySymptom implements Tool {
  const LookupFirstAidBySymptom(this._repo);
  final FirstAidRepo _repo;

  @override
  String get name => 'lookup_first_aid_by_symptom';

  @override
  String get description =>
      'Find first-aid entries that handle a given symptom. Use this when '
      'the user mentions a symptom slug (e.g. "burn", "fever", "snake-bite") '
      'and you need to know which entries to surface.';

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'symptom': {
            'type': 'string',
            'description':
                'Symptom slug — see the symptoms catalog. Lower-case, '
                    'hyphenated. Examples: burn, fever, snake-bite.',
          },
        },
        'required': ['symptom'],
      };

  @override
  Future<String> call(Map<String, Object?> args) async {
    final symptom = (args['symptom'] as String?)?.trim().toLowerCase() ?? '';
    if (symptom.isEmpty) {
      return jsonEncode({'error': 'symptom is required'});
    }
    final entries = _repo.entriesForSlug(symptom);
    final results = [
      for (final e in entries)
        {
          'id': e.id,
          'title': e.title,
          'severity': e.severity.name,
          'escalation': e.escalation.name,
        },
    ];
    return jsonEncode(results);
  }
}

/// Hydrate a single entry's steps + don'ts + escalation. The chat agent
/// uses this to ground its reply: the LLM never paraphrases steps, it
/// surfaces them verbatim from the KG.
class GetFullEntryTool implements Tool {
  const GetFullEntryTool(this._repo);
  final FirstAidRepo _repo;

  @override
  String get name => 'get_full_entry';

  @override
  String get description =>
      'Fetch the full clinical entry by id: steps, don\'ts, allowed '
      'medications, contraindications, and escalation level. Use this '
      'after lookup_first_aid_by_symptom has narrowed the candidate.';

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'string',
            'description': 'KG entry id, e.g. "burns-minor".',
          },
        },
        'required': ['id'],
      };

  @override
  Future<String> call(Map<String, Object?> args) async {
    final id = (args['id'] as String?)?.trim() ?? '';
    if (id.isEmpty) return jsonEncode({'error': 'id is required'});
    final entry = _repo.getById(id);
    if (entry == null) return jsonEncode({'error': 'no entry with id "$id"'});
    return jsonEncode({
      'id': entry.id,
      'title': entry.title,
      'severity': entry.severity.name,
      'escalation': entry.escalation.name,
      'steps': [
        for (final s in entry.steps)
          {
            'order': s.order,
            'action': s.action,
            'critical': s.critical,
          },
      ],
      'donts': entry.donts,
      'allowed_medications': [
        for (final m in entry.medications)
          {
            'name': m.name,
            'role': m.role,
            'pediatric_contraindication': m.pediatricContraindication,
          },
      ],
      'red_flags': entry.redFlags,
      'notes': entry.notes,
    });
  }
}

/// Run the deterministic triage rules over a symptom set + bio profile.
/// This is the *primary* path for clinical decisions in the demo — Gemma
/// only verbalizes; it should not invent severity. We expose triage as a
/// tool so off-script LLM turns can still ask the engine "what would you
/// have decided?" and get a grounded answer.
class RunTriageTool implements Tool {
  RunTriageTool({
    required FirstAidRepo repo,
    required TriageEngine engine,
  })  : _repo = repo,
        _engine = engine;

  final FirstAidRepo _repo;
  final TriageEngine _engine;

  @override
  String get name => 'run_triage';

  @override
  String get description =>
      'Run the deterministic triage engine over a set of symptom slugs '
      'and the active bio profile. Returns severity + escalation + the '
      'rule id that fired. Always prefer this over your own judgment for '
      'severity decisions.';

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'symptoms': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Symptom slugs from the symptoms catalog.',
          },
          'age_months': {
            'type': 'integer',
            'description': 'Patient age in months. 360 = 30 years.',
          },
          'is_pregnant': {'type': 'boolean'},
          'conditions': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Pre-existing condition slugs (asthma, epilepsy, …).',
          },
          'vitals': {
            'type': 'object',
            'description': 'Optional measured values, e.g. body_temp_c.',
          },
        },
        'required': ['symptoms'],
      };

  @override
  Future<String> call(Map<String, Object?> args) async {
    final symptomsRaw = args['symptoms'];
    final symptoms = <String>{
      if (symptomsRaw is List)
        for (final v in symptomsRaw) v.toString().toLowerCase(),
    };
    final profile = BioProfile(
      ageMonths: (args['age_months'] as num?)?.toInt() ?? 360,
      isPregnant: args['is_pregnant'] as bool? ?? false,
      conditions: [
        if (args['conditions'] is List)
          for (final v in args['conditions'] as List) v.toString(),
      ],
    );
    final vitalsRaw = args['vitals'];
    final vitals = <String, num>{
      if (vitalsRaw is Map)
        for (final e in vitalsRaw.entries)
          if (e.value is num) e.key.toString(): e.value as num,
    };
    final input = TriageInput(
      symptoms: symptoms, profile: profile, vitals: vitals,
    );
    final outcome = _engine.evaluate(input);
    if (outcome == null) {
      return jsonEncode({
        'matched': false,
        'reason': 'no rule fired — ask a clarifying question',
      });
    }
    final entry = outcome.entryRef == null
        ? null
        : _repo.getById(outcome.entryRef!);
    return jsonEncode({
      'matched': true,
      'rule_id': outcome.ruleId,
      'severity': outcome.severity.name,
      'is_emergency': outcome.severity == Severity.emergency,
      'escalation': outcome.escalation.name,
      'recommendation': outcome.recommendation,
      'entry_ref': outcome.entryRef,
      'entry_title': entry?.title,
    });
  }
}

/// Convenience: build the standard tool palette for the chat agent.
List<Tool> defaultClinicalTools({
  required FirstAidRepo repo,
  required TriageEngine engine,
}) =>
    [
      LookupFirstAidBySymptom(repo),
      GetFullEntryTool(repo),
      RunTriageTool(repo: repo, engine: engine),
    ];
