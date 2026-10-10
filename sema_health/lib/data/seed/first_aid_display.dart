import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/triage/severity.dart';
import '../../theme/tokens.dart';
import 'first_aid_models.dart';

/// UI decoration for clinical KG entries.
///
/// The clinical YAML deliberately contains no display fields — clinicians
/// reviewing the corpus shouldn't reason about icons or pastel colors.
/// This file maps each known entry id to a phosphor icon and accent.
///
/// `accent` is severity-aware: emergency entries get the blush (red-ish)
/// accent regardless of the per-entry override below, so a future entry
/// added to the YAML without a display override still renders distinctly
/// when severe.
class FirstAidDisplay {
  const FirstAidDisplay({
    required this.icon,
    required this.accent,
    required this.estimatedDuration,
  });

  final IconData icon;
  final SemaAccent accent;

  /// Coarse "how long the audio guide takes" estimate for the tile pill.
  /// Derived from step count; not a clinical promise.
  final String estimatedDuration;

  static FirstAidDisplay forEntry(FirstAidEntry e) {
    final base = _byId[e.id] ?? _fallbackForCategory(e);
    final accent = e.isEmergency ? SemaAccent.blush : base.accent;
    return FirstAidDisplay(
      icon: base.icon,
      accent: accent,
      estimatedDuration: _durationFor(e.steps.length),
    );
  }

  static String _durationFor(int steps) {
    if (steps <= 3) return '1 min';
    if (steps <= 5) return '2 min';
    if (steps <= 7) return '3 min';
    return '4 min';
  }

  /// Per-entry override table. Keys must match `first_aid.yaml` ids.
  /// Adding a new entry to the YAML without a row here falls through
  /// to `_fallbackForCategory` — safe, just generic.
  static final Map<String, FirstAidDisplay> _byId = {
    'severe-bleeding': const FirstAidDisplay(
      icon: PhosphorIconsRegular.drop,
      accent: SemaAccent.blush,
      estimatedDuration: '2 min',
    ),
    'minor-wounds': const FirstAidDisplay(
      icon: PhosphorIconsRegular.bandaids,
      accent: SemaAccent.sand,
      estimatedDuration: '2 min',
    ),
    'burns-minor': const FirstAidDisplay(
      icon: PhosphorIconsRegular.flame,
      accent: SemaAccent.butter,
      estimatedDuration: '3 min',
    ),
    'choking-adult-child': const FirstAidDisplay(
      icon: PhosphorIconsRegular.person,
      accent: SemaAccent.mint,
      estimatedDuration: '2 min',
    ),
    'choking-infant': const FirstAidDisplay(
      icon: PhosphorIconsRegular.babyCarriage,
      accent: SemaAccent.lilac,
      estimatedDuration: '3 min',
    ),
    'snake-bite': const FirstAidDisplay(
      icon: PhosphorIconsRegular.bandaids,
      accent: SemaAccent.sand,
      estimatedDuration: '4 min',
    ),
    'heat-stroke': const FirstAidDisplay(
      icon: PhosphorIconsRegular.thermometer,
      accent: SemaAccent.sky,
      estimatedDuration: '2 min',
    ),
    'anaphylaxis': const FirstAidDisplay(
      icon: PhosphorIconsRegular.heartbeat,
      accent: SemaAccent.blush,
      estimatedDuration: '3 min',
    ),
    'poisoning-ingestion': const FirstAidDisplay(
      icon: PhosphorIconsRegular.flask,
      accent: SemaAccent.lilac,
      estimatedDuration: '2 min',
    ),
    'seizure': const FirstAidDisplay(
      icon: PhosphorIconsRegular.brain,
      accent: SemaAccent.lilac,
      estimatedDuration: '2 min',
    ),
    'fever': const FirstAidDisplay(
      icon: PhosphorIconsRegular.thermometer,
      accent: SemaAccent.butter,
      estimatedDuration: '2 min',
    ),
    'headache': const FirstAidDisplay(
      icon: PhosphorIconsRegular.brain,
      accent: SemaAccent.sky,
      estimatedDuration: '2 min',
    ),
    'dehydration-diarrhea': const FirstAidDisplay(
      icon: PhosphorIconsRegular.drop,
      accent: SemaAccent.sky,
      estimatedDuration: '2 min',
    ),
    'fainting': const FirstAidDisplay(
      icon: PhosphorIconsRegular.heartbeat,
      accent: SemaAccent.lilac,
      estimatedDuration: '1 min',
    ),
    'nosebleed': const FirstAidDisplay(
      icon: PhosphorIconsRegular.drop,
      accent: SemaAccent.blush,
      estimatedDuration: '1 min',
    ),
    'foreign-object-eye': const FirstAidDisplay(
      icon: PhosphorIconsRegular.eye,
      accent: SemaAccent.sky,
      estimatedDuration: '2 min',
    ),
    'broken-limb': const FirstAidDisplay(
      icon: PhosphorIconsRegular.bone,
      accent: SemaAccent.sand,
      estimatedDuration: '3 min',
    ),
    'frostbite-hypothermia': const FirstAidDisplay(
      icon: PhosphorIconsRegular.snowflake,
      accent: SemaAccent.sky,
      estimatedDuration: '2 min',
    ),
    'electric-shock': const FirstAidDisplay(
      icon: PhosphorIconsRegular.lightning,
      accent: SemaAccent.butter,
      estimatedDuration: '2 min',
    ),
    'knocked-out-tooth': const FirstAidDisplay(
      icon: PhosphorIconsRegular.tooth,
      accent: SemaAccent.mint,
      estimatedDuration: '2 min',
    ),
    'sprains-strains-rice': const FirstAidDisplay(
      icon: PhosphorIconsRegular.bandaids,
      accent: SemaAccent.mint,
      estimatedDuration: '2 min',
    ),
    'sprain-strain-clarifier': const FirstAidDisplay(
      icon: PhosphorIconsRegular.bandaids,
      accent: SemaAccent.mint,
      estimatedDuration: '1 min',
    ),
    'bee-sting-insect-bite': const FirstAidDisplay(
      icon: PhosphorIconsRegular.bug,
      accent: SemaAccent.butter,
      estimatedDuration: '1 min',
    ),
    'skin-itch-rash': const FirstAidDisplay(
      icon: PhosphorIconsRegular.handPalm,
      accent: SemaAccent.lilac,
      estimatedDuration: '1 min',
    ),
    'splinter': const FirstAidDisplay(
      icon: PhosphorIconsRegular.bandaids,
      accent: SemaAccent.sand,
      estimatedDuration: '1 min',
    ),
    'blister-friction': const FirstAidDisplay(
      icon: PhosphorIconsRegular.handPalm,
      accent: SemaAccent.sand,
      estimatedDuration: '1 min',
    ),
    'sunburn': const FirstAidDisplay(
      icon: PhosphorIconsRegular.sun,
      accent: SemaAccent.butter,
      estimatedDuration: '1 min',
    ),
    'hyperventilation': const FirstAidDisplay(
      icon: PhosphorIconsRegular.wind,
      accent: SemaAccent.sky,
      estimatedDuration: '1 min',
    ),
  };

  static FirstAidDisplay _fallbackForCategory(FirstAidEntry e) {
    final accent = switch (e.severity) {
      Severity.emergency => SemaAccent.blush,
      Severity.high => SemaAccent.sand,
      Severity.medium => SemaAccent.butter,
      Severity.low => SemaAccent.mint,
    };
    return FirstAidDisplay(
      icon: PhosphorIconsRegular.firstAidKit,
      accent: accent,
      estimatedDuration: _durationFor(e.steps.length),
    );
  }
}
