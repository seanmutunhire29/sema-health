import 'package:flutter/material.dart';

import '../data/seed.dart';
import '../i18n/locale_scope.dart';
import '../i18n/strings.dart';
import '../ml/model_downloader.dart';
import '../theme/tokens.dart';
import '../widgets/model_download_sheet.dart';
import '../widgets/press_scale.dart';
import '../widgets/sema_button.dart';
import 'welcome_screen.dart';

/// Public manifest URL for the runtime ML models.
/// Bucket rules grant `allow read: if true;` on `models/**`.
const _modelsManifestUrl =
    'https://firebasestorage.googleapis.com/v0/b/sema-health-2b88b.firebasestorage.app/o/models%2Fv1%2Fmanifest.json?alt=media';

/// Maps a picker display code (`tw`, `sw`, …) to the model code used by
/// the manifest and on-device file layout (`aka`, `swh`). Languages
/// without ML models map to `null` and skip the download flow.
String? _modelCodeFor(String displayCode) => switch (displayCode) {
      'tw' => 'aka',
      'sw' => 'swh',
      'en' => 'eng',
      'fr' => 'fra',
      _ => null,
    };

/// Bespoke language picker — penultimate step of onboarding.
///
/// Pattern: a typographic hero that previews the *selected* greeting in
/// display weight, sitting on its own pastel accent. Below, a horizontal
/// strip of language chips swaps the hero in real time. Selecting commits
/// nothing — only the Continue CTA navigates onward, so the picker doubles
/// as a delightful preview of how Sema will sound.
class LanguagePickerScreen extends StatefulWidget {
  const LanguagePickerScreen({super.key});

  @override
  State<LanguagePickerScreen> createState() => _LanguagePickerScreenState();
}

class _LanguagePickerScreenState extends State<LanguagePickerScreen> {
  int _index = 0;
  bool _continueBusy = false;
  ModelDownloader? _downloader;

  ModelDownloader _ensureDownloader() =>
      _downloader ??= ModelDownloader(manifestUrl: _modelsManifestUrl);

  @override
  void dispose() {
    _downloader?.dispose();
    super.dispose();
  }

  /// If the picked language has ML models, make sure they're on disk
  /// before pushing Welcome. For en/fr/ga/yo (no models yet) we just
  /// commit the selection and proceed.
  Future<void> _onContinue() async {
    final modelCode = _modelCodeFor(_selected.code);
    if (modelCode == null) {
      _commitAndProceed();
      return;
    }

    setState(() => _continueBusy = true);
    try {
      final downloader = _ensureDownloader();
      final ready = await downloader.isLanguageReady(modelCode);
      if (ready) {
        _commitAndProceed();
        return;
      }
      if (!mounted) return;
      final ok = await showModelDownloadSheet(
        context: context,
        downloader: downloader,
        langCode: modelCode,
        langDisplayName: _selected.name,
      );
      if (ok && mounted) _commitAndProceed();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t prepare models: $e')),
      );
    } finally {
      if (mounted) setState(() => _continueBusy = false);
    }
  }

  void _commitAndProceed() {
    LocaleScope.read(context).setLanguage(_selected);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    );
  }

  // One accent per language — the hero card morphs to this surface on select.
  static const _accents = <SemaAccent>[
    SemaAccent.mint,    // English
    SemaAccent.lilac,   // French
    SemaAccent.butter,  // Swahili
    SemaAccent.blush,   // Twi
    SemaAccent.sand,    // Ga
    SemaAccent.sky,     // Yoruba
  ];

  SemaLanguage get _selected => semaLanguages[_index];
  SemaAccent get _accent => _accents[_index];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = LocaleScope.of(context).strings;
    // Preview the picked language live: the CTA copy and the right-side
    // "Sema speaks" label render in the *selected* language so the user
    // sees their choice take effect before committing.
    final previewStrings = stringsFor(_selected.code);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  PressScale(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40, height: 40,
                      decoration: const BoxDecoration(
                        color: SemaColors.card, shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 14, color: SemaColors.ink,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(s.t('lang.step'), style: t.labelMedium),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.t('lang.eyebrow'), style: t.labelMedium),
                  const SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      style: t.displayMedium!.copyWith(
                        fontSize: 32, height: 1.1, letterSpacing: -1.2,
                      ),
                      children: [
                        TextSpan(text: s.t('lang.lead')),
                        TextSpan(
                          text: s.t('lang.emphasis'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        TextSpan(text: s.t('lang.tail')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _GreetingHero(
                language: _selected,
                accent: _accent,
                semaSpeaks: previewStrings.t('lang.semaSpeaks'),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: semaLanguages.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _LanguageChip(
                  language: semaLanguages[i],
                  accent: _accents[i],
                  selected: i == _index,
                  onTap: () => setState(() => _index = i),
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: SemaButton(
                label: previewStrings.f('lang.continueIn', [_selected.name]),
                onPressed: _continueBusy ? null : _onContinue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Big card that previews how the selected language will greet you.
/// The greeting and the accent surface cross-fade on selection change.
class _GreetingHero extends StatelessWidget {
  const _GreetingHero({
    required this.language,
    required this.accent,
    required this.semaSpeaks,
  });
  final SemaLanguage language;
  final SemaAccent accent;
  final String semaSpeaks;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        color: accent.surface,
        borderRadius: BorderRadius.circular(SemaRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(SemaRadii.pill),
                ),
                child: Text(
                  language.code.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: accent.ink,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                semaSpeaks,
                style: t.labelMedium?.copyWith(color: accent.ink.withValues(alpha: 0.65)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // The greeting — the star of the show.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.18),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: Text(
              '${language.greeting}.',
              key: ValueKey(language.code),
              style: t.displayLarge!.copyWith(
                fontSize: 52, height: 1.0, letterSpacing: -1.8,
                fontWeight: FontWeight.w800,
                color: accent.ink,
              ),
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: Text(
              '${language.endonym} · ${language.name}',
              key: ValueKey('${language.code}_meta'),
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                color: accent.ink.withValues(alpha: 0.78),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Selectable language chip — endonym in display weight, greeting underneath.
class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.language,
    required this.accent,
    required this.selected,
    required this.onTap,
  });
  final SemaLanguage language;
  final SemaAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 132,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: selected ? SemaColors.ink : SemaColors.bg,
          borderRadius: BorderRadius.circular(SemaRadii.l),
          border: Border.all(
            color: selected ? SemaColors.ink : SemaColors.hairline,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: accent.surface,
                shape: BoxShape.circle,
              ),
            ),
            const Spacer(),
            Text(
              language.endonym,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: selected ? Colors.white : SemaColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              language.greeting,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: selected
                    ? Colors.white.withValues(alpha: 0.65)
                    : SemaColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
