import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai/agent_provider.dart';
import 'data/seed.dart';
import 'data/seed/first_aid_repo_provider.dart';
import 'i18n/locale_scope.dart';
import 'screens/language_picker_screen.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: SemaColors.bg,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  // Fire-and-forget pre-warms while the user is in onboarding:
  //  - clinical KG YAML parses so the first-aid tab paints instantly.
  //  - SymptomAgent (rules.yaml + Gemma `.task` probe + lazy `.load()`)
  //    so the first chat turn doesn't pay the model cold-load tax
  //    (~2-5 s on mid-tier Android).
  // Errors surface where the futures are awaited (FutureBuilder /
  // ConversationScreen bootstrap).
  unawaited(firstAidRepoFuture());
  unawaited(symptomAgentFuture());
  runApp(const SemaApp());
}

class SemaApp extends StatefulWidget {
  const SemaApp({super.key});

  @override
  State<SemaApp> createState() => _SemaAppState();
}

class _SemaAppState extends State<SemaApp> {
  // Default to English; the onboarding language picker overwrites this and
  // the settings screen can change it later. In-memory only — the picker
  // re-runs on each launch.
  late final LocaleController _locale = LocaleController(semaLanguages.first);

  @override
  void dispose() {
    _locale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocaleScope(
      controller: _locale,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'sema',
        theme: SemaTheme.light(),
        home: const LanguagePickerScreen(),
      ),
    );
  }
}
