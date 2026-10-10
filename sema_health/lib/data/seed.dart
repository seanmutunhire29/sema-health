import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../theme/tokens.dart';

class SemaLanguage {
  const SemaLanguage({
    required this.code,
    required this.name,
    required this.endonym,
    required this.greeting,
  });
  final String code;
  final String name;
  final String endonym;
  final String greeting;
}

const semaLanguages = <SemaLanguage>[
  SemaLanguage(code: 'en', name: 'English',  endonym: 'English',    greeting: 'Hello'),
  SemaLanguage(code: 'fr', name: 'French',   endonym: 'Français',   greeting: 'Bonjour'),
  SemaLanguage(code: 'sw', name: 'Swahili',  endonym: 'Kiswahili',  greeting: 'Jambo'),
  SemaLanguage(code: 'tw', name: 'Twi',      endonym: 'Twi',        greeting: 'Akwaaba'),
  SemaLanguage(code: 'ga', name: 'Ga',       endonym: 'Gã',         greeting: 'Ojekoo'),
  SemaLanguage(code: 'yo', name: 'Yoruba',   endonym: 'Yorùbá',     greeting: 'Ẹ n lẹ'),
];

class QuickAction {
  const QuickAction(this.labelKey, this.icon, this.accent);
  /// String-table key resolved by `SemaStrings.t` at render time so the
  /// label follows the active language.
  final String labelKey;
  final IconData icon;
  final SemaAccent accent;
}

const quickActions = <QuickAction>[
  QuickAction('quick.symptoms',  PhosphorIconsRegular.stethoscope,  SemaAccent.mint),
  QuickAction('quick.firstAid',  PhosphorIconsRegular.firstAidKit,  SemaAccent.blush),
  QuickAction('quick.pregnancy', PhosphorIconsRegular.heartbeat,    SemaAccent.butter),
  QuickAction('quick.children',  PhosphorIconsRegular.babyCarriage, SemaAccent.lilac),
];

class FirstAidEntry {
  const FirstAidEntry(this.title, this.subtitle, this.duration, this.icon, this.accent);
  final String title;
  final String subtitle;
  final String duration;
  final IconData icon;
  final SemaAccent accent;
}

final firstAidEntries = <FirstAidEntry>[
  FirstAidEntry('Heavy bleeding',  'Stop, elevate, compress', '2 min',
      PhosphorIconsRegular.drop,         SemaAccent.blush),
  FirstAidEntry('Burn treatment',  'Cool water, no ice',      '3 min',
      PhosphorIconsRegular.flame,        SemaAccent.butter),
  FirstAidEntry('Snake bite',      'Stay still, reach care',  '4 min',
      PhosphorIconsRegular.bandaids,     SemaAccent.sand),
  FirstAidEntry('Choking · adult', 'Heimlich technique',      '2 min',
      PhosphorIconsRegular.person,       SemaAccent.mint),
  FirstAidEntry('Choking · child', 'Back blows, then thrusts','3 min',
      PhosphorIconsRegular.babyCarriage, SemaAccent.lilac),
  FirstAidEntry('Heat stroke',     'Cool, hydrate, monitor',  '2 min',
      PhosphorIconsRegular.thermometer,  SemaAccent.sky),
];
