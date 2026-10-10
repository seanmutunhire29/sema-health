import 'first_aid_repo.dart';
import 'first_aid_repo_assets.dart';

/// Process-wide cached future for the bundled clinical knowledge graph.
///
/// First call kicks off the load (asset bundle → YAML parse → typed
/// repo). Every subsequent caller in the same isolate gets the same
/// future — `FutureBuilder` widgets re-await it without re-parsing.
///
/// When Riverpod lands, this becomes a `FutureProvider<FirstAidRepo>`
/// and this file goes away. Until then the static cache keeps the
/// screens simple.
Future<FirstAidRepo>? _cached;

Future<FirstAidRepo> firstAidRepoFuture() {
  return _cached ??= loadFirstAidRepoFromAssets();
}
