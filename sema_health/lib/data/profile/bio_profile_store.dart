import 'package:flutter/foundation.dart';

import '../../domain/triage/triage_input.dart';

/// Process-wide store for the active [BioProfile].
///
/// **v1 persistence is in-memory only.** Restarting the app loses the
/// profile. The follow-up M1 migration is to wrap this in
/// `flutter_secure_storage` (Keychain / Android KeyStore) — the
/// architecture's privacy contract requires bio data to be encrypted
/// at rest. This stub lets the chat plumb against a real reactive
/// source today; the swap is a single-file change later.
///
/// Reactive access via `ValueListenable<BioProfile?>` so widgets can
/// `ValueListenableBuilder` directly. When Riverpod lands this becomes
/// a `Notifier<BioProfile?>` and the singleton goes away.
class BioProfileStore {
  BioProfileStore._();

  static final BioProfileStore instance = BioProfileStore._();

  final ValueNotifier<BioProfile?> _current =
      ValueNotifier<BioProfile?>(null);

  ValueListenable<BioProfile?> get listenable => _current;
  BioProfile? get current => _current.value;
  bool get hasProfile => _current.value != null;

  void save(BioProfile profile) {
    _current.value = profile;
  }

  /// Clears the active profile. Used by the eventual "wipe" gesture
  /// (architecture: biometric-locked emergency wipe).
  void clear() {
    _current.value = null;
  }
}
