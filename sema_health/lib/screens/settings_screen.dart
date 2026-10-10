import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../data/seed.dart';
import '../i18n/locale_scope.dart';
import '../theme/tokens.dart';
import '../widgets/press_scale.dart';
import '../widgets/sema_button.dart';

/// Settings — currently a single section: language. The picker reuses the
/// same accent palette as onboarding so the choice feels consistent.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // One accent per language — mirrors onboarding's palette.
  static const _accents = <SemaAccent>[
    SemaAccent.mint,    // English
    SemaAccent.lilac,   // French
    SemaAccent.butter,  // Swahili
    SemaAccent.blush,   // Twi
    SemaAccent.sand,    // Ga
    SemaAccent.sky,     // Yoruba
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final locale = LocaleScope.of(context);
    final s = locale.strings;
    final currentCode = locale.language.code;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  PressScale(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40, height: 40,
                      decoration: const BoxDecoration(
                        color: SemaColors.card,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        PhosphorIconsRegular.caretLeft,
                        size: 14, color: SemaColors.ink,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(s.t('settings.title'), style: t.labelMedium),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.t('settings.language'), style: t.labelMedium),
                  const SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      style: t.displayMedium!.copyWith(
                        fontSize: 30, height: 1.12, letterSpacing: -1.0,
                      ),
                      children: [
                        TextSpan(
                          text: locale.language.endonym,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        TextSpan(text: ' · ${locale.language.name}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(s.t('settings.languageDesc'), style: t.bodyMedium),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Language list — tap-to-switch.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (int i = 0; i < semaLanguages.length; i++)
                    _LanguageRow(
                      language: semaLanguages[i],
                      accent: _accents[i],
                      selected: semaLanguages[i].code == currentCode,
                      onTap: () => locale.setLanguage(semaLanguages[i]),
                      showDivider: i != semaLanguages.length - 1,
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // About card — small affordance to fill the screen and reinforce
            // the offline-first identity.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
                decoration: BoxDecoration(
                  color: SemaColors.card,
                  borderRadius: BorderRadius.circular(SemaRadii.l),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: SemaAccent.mint.surface,
                        borderRadius: BorderRadius.circular(SemaRadii.s),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        PhosphorIconsRegular.lockSimple,
                        size: 18, color: SemaAccent.mint.ink,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.t('settings.about'),
                            style: t.titleMedium?.copyWith(
                              fontSize: 14, fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.t('settings.aboutDesc'),
                            style: t.bodyMedium?.copyWith(
                              fontSize: 12.5, height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // CTA — done returns to where settings was opened from.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: SemaButton(
                label: s.t('common.done'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.language,
    required this.accent,
    required this.selected,
    required this.onTap,
    required this.showDivider,
  });
  final SemaLanguage language;
  final SemaAccent accent;
  final bool selected;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
        decoration: BoxDecoration(
          border: showDivider
              ? const Border(
                  bottom: BorderSide(color: SemaColors.hairlineSoft),
                )
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: accent.surface,
                borderRadius: BorderRadius.circular(SemaRadii.s),
              ),
              alignment: Alignment.center,
              child: Text(
                language.code.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: accent.ink,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    language.endonym,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: SemaColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${language.name} · ${language.greeting}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: SemaColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Selection indicator — filled circle when active, hollow when not.
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: selected ? SemaColors.ink : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? SemaColors.ink : SemaColors.hairline,
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: selected
                  ? const Icon(
                      PhosphorIconsBold.check,
                      size: 11, color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
