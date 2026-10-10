import 'package:yaml/yaml.dart';

import 'severity.dart';
import 'triage_input.dart';
import 'triage_outcome.dart';

/// Pure-Dart triage engine. Loads `assets/triage/rules.yaml` once,
/// then evaluates rules top-to-bottom on each turn — first match wins.
///
/// This is the deterministic safety net described in
/// ARCHITECTURE/04-ml-and-ai.md. The LLM never bypasses it: the agent
/// loop calls `evaluate(...)` BEFORE asking Gemma to phrase a reply.
///
/// Predicate language (mirrors the YAML grammar):
/// - `match.all` — logical AND of contained predicates
/// - `match.any` — logical OR
/// - leaves:
///   - `symptom: <slug>` — slug present in `input.symptoms`
///     (special: `__no_symptoms_extracted__` fires when symptoms is empty)
///   - `any_symptom: [<slug>...]` — at least one slug present
///   - `all_symptoms: [<slug>...]` — all slugs present
///   - `profile.<field>: <value>` — equality on a profile field
///   - `profile.<field>_lt: <number>` — numeric comparison
///     (also `_gt`, `_lte`, `_gte`)
///   - `profile.conditions_contains: <slug>` — list membership
///   - `vital.<field>_lt: <number>` — same numeric ops on vitals
///   - `context.<field>_gt: <number>` — same on conversation context
class TriageEngine {
  TriageEngine._(this._rules);

  final List<_Rule> _rules;

  static TriageEngine parse(String yamlSource) {
    final root = loadYaml(yamlSource) as YamlMap;
    final rawRules = root['rules'];
    if (rawRules is! YamlList) {
      throw const FormatException('rules.yaml: missing `rules:` list');
    }
    return TriageEngine._([
      for (final r in rawRules) _Rule.fromYaml(r as YamlMap),
    ]);
  }

  /// Number of rules loaded — used by tests.
  int get ruleCount => _rules.length;

  /// Evaluate the input against every rule top-to-bottom. Returns the
  /// outcome of the first rule whose `match` block holds. If no rule
  /// matches, returns `null` and the agent should fall through to
  /// Gemma with the unstructured query.
  TriageOutcome? evaluate(TriageInput input) {
    for (final r in _rules) {
      if (r.matches(input)) return r.toOutcome();
    }
    return null;
  }
}

class _Rule {
  _Rule({
    required this.id,
    required this.match,
    required this.severity,
    required this.escalation,
    required this.recommendation,
    this.entryRef,
    this.toolsRequired = const [],
    this.citation = const [],
  });

  final String id;
  final _PredicateNode match;
  final Severity severity;
  final Escalation escalation;
  final String recommendation;
  final String? entryRef;
  final List<String> toolsRequired;
  final List<String> citation;

  factory _Rule.fromYaml(YamlMap m) {
    final matchNode = m['match'];
    if (matchNode is! YamlMap) {
      throw FormatException('rule ${m['id']}: `match:` must be a map');
    }
    return _Rule(
      id: m['id'] as String,
      match: _PredicateNode.fromYaml(matchNode),
      severity: Severity.parse(m['severity'] as String),
      escalation: Escalation.parse(m['escalation'] as String),
      recommendation: (m['recommendation'] as String).trim(),
      entryRef: m['entry_ref'] as String?,
      toolsRequired: _stringList(m['tools_required']),
      citation: _stringList(m['citation']),
    );
  }

  bool matches(TriageInput input) => match.evaluate(input);

  TriageOutcome toOutcome() => TriageOutcome(
        ruleId: id,
        severity: severity,
        escalation: escalation,
        recommendation: recommendation,
        entryRef: entryRef,
        toolsRequired: toolsRequired,
        citation: citation,
      );
}

// ---------------------------------------------------------------------------
// Predicate AST
//
// One YAML map node can be either:
//   - a combinator: { all: [...] } | { any: [...] }
//   - a leaf: { <key>: <value> }   (single entry)
//
// Combinator children are themselves predicate nodes — recursion handles
// arbitrarily nested all/any combinations (e.g. the pregnancy-bleeding
// rule uses `any: [ all: [...], all: [...] ]`).
// ---------------------------------------------------------------------------

abstract class _PredicateNode {
  const _PredicateNode();

  bool evaluate(TriageInput input);

  factory _PredicateNode.fromYaml(YamlMap node) {
    if (node.containsKey('all')) {
      return _AllOf(_childrenOf(node['all']));
    }
    if (node.containsKey('any')) {
      return _AnyOf(_childrenOf(node['any']));
    }
    if (node.length != 1) {
      throw FormatException(
        'predicate node must have exactly one key, got: ${node.keys.toList()}',
      );
    }
    final entry = node.entries.first;
    return _Leaf(entry.key as String, entry.value);
  }

  static List<_PredicateNode> _childrenOf(dynamic node) {
    if (node is! YamlList) {
      throw const FormatException('all/any expects a list of predicates');
    }
    return [for (final c in node) _PredicateNode.fromYaml(c as YamlMap)];
  }
}

class _AllOf extends _PredicateNode {
  const _AllOf(this.children);
  final List<_PredicateNode> children;
  @override
  bool evaluate(TriageInput input) =>
      children.every((c) => c.evaluate(input));
}

class _AnyOf extends _PredicateNode {
  const _AnyOf(this.children);
  final List<_PredicateNode> children;
  @override
  bool evaluate(TriageInput input) =>
      children.any((c) => c.evaluate(input));
}

class _Leaf extends _PredicateNode {
  const _Leaf(this.key, this.value);
  final String key;
  final dynamic value;

  static const _sentinelEmpty = '__no_symptoms_extracted__';
  static const _ops = ['_contains', '_lte', '_gte', '_lt', '_gt'];

  @override
  bool evaluate(TriageInput input) {
    switch (key) {
      case 'symptom':
        if (value == _sentinelEmpty) return input.symptoms.isEmpty;
        return input.symptoms.contains(value);
      case 'any_symptom':
        final list = _stringList(value);
        return list.any(input.symptoms.contains);
      case 'all_symptoms':
        final list = _stringList(value);
        return list.every(input.symptoms.contains);
      default:
        return _evaluateField(input);
    }
  }

  /// Field predicates use the form `<namespace>.<field>[_<op>]` where
  /// `<op>` is one of `lt|gt|lte|gte|contains`. Absence of an op means
  /// equality.
  bool _evaluateField(TriageInput input) {
    final parts = key.split('.');
    if (parts.length != 2) return false;
    final namespace = parts[0];
    String fieldAndOp = parts[1];

    String? op;
    for (final suf in _ops) {
      if (fieldAndOp.endsWith(suf)) {
        op = suf.substring(1);
        fieldAndOp = fieldAndOp.substring(0, fieldAndOp.length - suf.length);
        break;
      }
    }

    final lhs = _readField(namespace, fieldAndOp, input);
    if (lhs == null) return false;

    if (op == null) return lhs == value;

    switch (op) {
      case 'contains':
        if (lhs is List) return lhs.contains(value);
        return false;
      case 'lt':
        return lhs is num && value is num && lhs < value;
      case 'gt':
        return lhs is num && value is num && lhs > value;
      case 'lte':
        return lhs is num && value is num && lhs <= value;
      case 'gte':
        return lhs is num && value is num && lhs >= value;
    }
    return false;
  }

  static dynamic _readField(String ns, String field, TriageInput input) {
    switch (ns) {
      case 'profile':
        switch (field) {
          case 'age_months':
            return input.profile.ageMonths;
          case 'sex_at_birth':
            return input.profile.sexAtBirth;
          case 'is_pregnant':
            return input.profile.isPregnant;
          case 'is_chw':
            return input.profile.isChw;
          case 'conditions':
            return input.profile.conditions;
          default:
            return null;
        }
      case 'vital':
        return input.vitals[field];
      case 'context':
        return input.context[field];
    }
    return null;
  }
}

List<String> _stringList(dynamic node) {
  if (node is YamlList) return [for (final v in node) v.toString()];
  if (node is List) return [for (final v in node) v.toString()];
  return const [];
}
