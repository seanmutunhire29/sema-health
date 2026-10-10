import 'package:flutter/services.dart' show rootBundle;

import 'first_aid_repo.dart';

/// Flutter-asset bridge for [FirstAidRepo]. Kept in its own file so that
/// pure-Dart unit tests can `parse()` raw YAML strings without dragging
/// in the flutter platform-channel layer.
Future<FirstAidRepo> loadFirstAidRepoFromAssets() async {
  final firstAidYaml = await rootBundle.loadString('assets/seed/first_aid.yaml');
  final symptomsYaml = await rootBundle.loadString('assets/seed/symptoms.yaml');
  return FirstAidRepo.parse(
    firstAidYaml: firstAidYaml,
    symptomsYaml: symptomsYaml,
  );
}
