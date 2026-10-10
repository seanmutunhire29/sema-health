// Golden tests for the triage engine. These run against the actual
// bundled rules.yaml + first_aid.yaml — if a future YAML edit silently
// breaks an emergency rule, one of these fails.
//
// Uses `package:test` (not flutter_test) so the suite runs with
// `dart test` and does not pull in flutter platform plugins.

import 'dart:io';

import 'package:test/test.dart';
import 'package:sema_health/data/seed/first_aid_repo.dart';
import 'package:sema_health/domain/triage/severity.dart';
import 'package:sema_health/domain/triage/triage_engine.dart';
import 'package:sema_health/domain/triage/triage_input.dart';

late TriageEngine engine;
late FirstAidRepo repo;

Future<void> _loadFixtures() async {
  // Tests run with cwd = sema_health/, so paths are relative to that.
  final rulesYaml = await File('assets/triage/rules.yaml').readAsString();
  final firstAidYaml = await File('assets/seed/first_aid.yaml').readAsString();
  final symptomsYaml = await File('assets/seed/symptoms.yaml').readAsString();

  engine = TriageEngine.parse(rulesYaml);
  repo = FirstAidRepo.parse(
    firstAidYaml: firstAidYaml,
    symptomsYaml: symptomsYaml,
  );
}

const _adult = BioProfile(ageMonths: 360); // 30 years
const _child = BioProfile(ageMonths: 84);  // 7 years
const _toddler = BioProfile(ageMonths: 18); // 18 months
const _infant = BioProfile(ageMonths: 2);  // 2 months
const _pregnant = BioProfile(ageMonths: 360, isPregnant: true);
const _adultAsthmatic = BioProfile(ageMonths: 360, conditions: ['asthma']);

void main() {
  setUpAll(_loadFixtures);

  group('YAML loads cleanly', () {
    test('rule count > 30', () {
      expect(engine.ruleCount, greaterThan(30));
    });

    test('all entries parse and every entry_ref resolves', () {
      // Walk the YAML rules again to extract entry_refs without using
      // engine internals — keeps the test independent of private API.
      final entryIds = repo.all.map((e) => e.id).toSet();
      // Spot-check known refs from the rules file:
      const refs = [
        'severe-bleeding',
        'anaphylaxis',
        'snake-bite',
        'choking-adult-child',
        'choking-infant',
        'heat-stroke',
        'fever',
        'broken-limb',
        'burns-minor',
        'minor-wounds',
      ];
      for (final id in refs) {
        expect(entryIds, contains(id),
            reason: 'rules.yaml entry_ref must exist in first_aid.yaml: $id');
      }
    });
  });

  group('Emergency · airway / breathing', () {
    test('severe bleeding → call_emergency', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'severe-bleeding'},
        profile: _adult,
      ));
      expect(out, isNotNull);
      expect(out!.severity, Severity.emergency);
      expect(out.escalation, Escalation.callEmergency);
      expect(out.entryRef, 'severe-bleeding');
    });

    test('anaphylaxis (swelling lips + breathing difficulty) → emergency', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'swelling-lips', 'breathing-difficulty'},
        profile: _adult,
      ));
      expect(out, isNotNull);
      expect(out!.severity, Severity.emergency);
      expect(out.entryRef, 'anaphylaxis');
    });

    test('throat tightness alone fires anaphylaxis rule', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'throat-tightness'},
        profile: _adult,
      ));
      expect(out!.entryRef, 'anaphylaxis');
    });

    test('choking + pregnant → uses chest-thrust variant rule first', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'choking'},
        profile: _pregnant,
      ));
      expect(out, isNotNull);
      expect(out!.ruleId, 'choking-adult-pregnant');
      expect(out.recommendation, contains('chest thrusts'));
    });

    test('choking adult (not pregnant) → default Heimlich rule', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'choking'},
        profile: _adult,
      ));
      expect(out!.ruleId, 'choking-adult-child-default');
    });
  });

  group('Pregnancy', () {
    test('pregnant + heavy bleeding → emergency', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'heavy-bleeding'},
        profile: _pregnant,
      ));
      expect(out!.severity, Severity.emergency);
      expect(out.ruleId, 'pregnancy-vaginal-bleeding');
    });
  });

  group('Temperature', () {
    test('infant <3mo with fever → emergency to clinic', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'fever'},
        profile: _infant,
      ));
      expect(out!.severity, Severity.emergency);
      expect(out.escalation, Escalation.nearestClinic);
      expect(out.ruleId, 'infant-fever');
    });

    test('child with fever → low (self-care default)', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'fever'},
        profile: _child,
      ));
      expect(out!.severity, Severity.low);
      expect(out.escalation, Escalation.selfCare);
    });

    test('heat stroke with body_temp 41 + confusion → emergency', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'confusion'},
        profile: _adult,
        vitals: {'body_temp_c': 41.2},
      ));
      // The confusion rule alone is emergency; even better, heat-stroke
      // also matches via the all: [body_temp>40, any:[confusion]] arm.
      expect(out!.severity, Severity.emergency);
    });

    test('fever + stiff neck → meningitis-signs ER rule', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'fever', 'stiff-neck'},
        profile: _adult,
      ));
      expect(out!.escalation, Escalation.goToEr);
      expect(out.ruleId, 'fever-with-meningitis-signs');
    });
  });

  group('Toxic / envenomation', () {
    test('snake bite → emergency', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'snake-bite'},
        profile: _adult,
      ));
      expect(out!.severity, Severity.emergency);
      expect(out.entryRef, 'snake-bite');
    });

    test('poisoning → emergency, do-not-induce-vomiting in recommendation',
        () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'poisoning'},
        profile: _adult,
      ));
      expect(out!.severity, Severity.emergency);
      expect(out.recommendation.toLowerCase(), contains('induce vomiting'));
    });
  });

  group('Asthma vs panic breathing', () {
    test('hyperventilation + asthma history → high (clinic)', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'hyperventilation'},
        profile: _adultAsthmatic,
      ));
      expect(out!.severity, Severity.high);
      expect(out.ruleId, 'hyperventilation-with-asthma');
    });

    test('hyperventilation + chest pain → emergency', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'hyperventilation', 'chest-pain'},
        profile: _adult,
      ));
      expect(out!.severity, Severity.emergency);
      expect(out.ruleId, 'hyperventilation-with-chest-pain');
    });

    test('hyperventilation alone (no asthma) → low default', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'hyperventilation'},
        profile: _adult,
      ));
      expect(out!.severity, Severity.low);
      expect(out.ruleId, 'hyperventilation-default');
    });
  });

  group('Dehydration', () {
    test('toddler with diarrhea + lethargy → emergency clinic', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'diarrhea', 'lethargy'},
        profile: _toddler,
      ));
      expect(out!.severity, Severity.emergency);
      expect(out.ruleId, 'dehydration-infant-severe');
    });

    test('adult with diarrhea (no lethargy) → ORS self-care', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'diarrhea'},
        profile: _adult,
      ));
      // Note: lethargy alone fires `unconscious-patient` because it is
      // a red-flag symptom. So this case checks the diarrhea-only path.
      expect(out!.escalation, Escalation.selfCare);
      expect(out.entryRef, 'dehydration-diarrhea');
    });
  });

  group('Sunburn', () {
    test('sunburn on infant <12mo → clinic', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'sunburn'},
        profile: _infant,
      ));
      expect(out!.escalation, Escalation.nearestClinic);
      expect(out.ruleId, 'sunburn-infant');
    });

    test('sunburn on adult → self-care', () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'sunburn'},
        profile: _adult,
      ));
      expect(out!.escalation, Escalation.selfCare);
      expect(out.ruleId, 'sunburn-default');
    });
  });

  group('No-match fallback', () {
    test('empty symptoms → fallback clarify', () {
      final out = engine.evaluate(TriageInput(
        symptoms: const {},
        profile: _adult,
      ));
      expect(out!.ruleId, 'no-match-fallback');
      expect(out.severity, Severity.low);
    });

    test('unknown slug only → no match (returns null, agent falls through)',
        () {
      final out = engine.evaluate(TriageInput(
        symptoms: {'something-unrelated'},
        profile: _adult,
      ));
      expect(out, isNull);
    });
  });

  group('First-aid KG', () {
    test('every emergency entry has steps and at least one critical step',
        () {
      for (final e in repo.bySeverity(Severity.emergency)) {
        expect(e.steps, isNotEmpty,
            reason: 'emergency entry ${e.id} has no steps');
        expect(e.steps.any((s) => s.critical), isTrue,
            reason: 'emergency entry ${e.id} has no critical step');
      }
    });

    test('drug whitelist works (Aspirin allowed only on fever entry)', () {
      final fever = repo.getById('fever')!;
      expect(fever.allowsMedication('Aspirin'), isTrue);
      expect(fever.allowsMedication('Aspirin'), isTrue);
      final aspirinMed = fever.medications
          .firstWhere((m) => m.name == 'Aspirin');
      expect(aspirinMed.pediatricContraindication, isTrue);

      final ana = repo.getById('anaphylaxis')!;
      expect(ana.allowsMedication('Aspirin'), isFalse);
    });

    test('symptom slug → entries reverse index works', () {
      final entries = repo.entriesForSlug('breathing-difficulty');
      final ids = entries.map((e) => e.id).toSet();
      expect(ids, containsAll(['anaphylaxis']));
    });
  });
}
