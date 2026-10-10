import 'package:flutter/services.dart' show rootBundle;

import 'triage_engine.dart';

/// Flutter-asset bridge for [TriageEngine]. See sibling `*_assets.dart`
/// in `data/seed/` for the same pattern — pure-Dart parser, flutter
/// loader split out so tests stay platform-free.
Future<TriageEngine> loadTriageEngineFromAssets() async {
  final src = await rootBundle.loadString('assets/triage/rules.yaml');
  return TriageEngine.parse(src);
}
