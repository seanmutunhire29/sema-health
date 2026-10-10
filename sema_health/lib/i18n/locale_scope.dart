import 'package:flutter/widgets.dart';

import '../data/seed.dart';
import 'strings.dart';

/// Holds the app's selected language and exposes its [SemaStrings]. Lives at
/// the root of the widget tree so any screen can read the current language
/// and any setter (onboarding, settings) can change it live.
class LocaleController extends ChangeNotifier {
  LocaleController(SemaLanguage initial) : _language = initial;

  SemaLanguage _language;
  SemaLanguage get language => _language;

  /// Convenience: the resolved string bundle for the current language.
  SemaStrings get strings => stringsFor(_language.code);

  void setLanguage(SemaLanguage next) {
    if (next.code == _language.code) return;
    _language = next;
    notifyListeners();
  }
}

/// Inherited entry point for the [LocaleController]. Backed by
/// [InheritedNotifier] so that `LocaleScope.of(context)` listens to the
/// underlying [ChangeNotifier] and rebuilds dependents on language change.
class LocaleScope extends InheritedNotifier<LocaleController> {
  const LocaleScope({
    super.key,
    required LocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  static LocaleController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocaleScope>();
    assert(scope != null, 'LocaleScope not found above this widget.');
    return scope!.notifier!;
  }

  /// Read without subscribing to rebuilds.
  static LocaleController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<LocaleScope>();
    assert(scope != null, 'LocaleScope not found above this widget.');
    return scope!.notifier!;
  }
}
