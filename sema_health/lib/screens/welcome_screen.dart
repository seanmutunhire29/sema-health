import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../data/seed.dart';
import '../i18n/locale_scope.dart';
import '../theme/tokens.dart';
import '../widgets/press_scale.dart';
import '../widgets/sema_button.dart';
import 'shell_screen.dart';

/// Final onboarding step. Echoes the language picker's typography hero plus
/// a bespoke "what's inside" preview list. Reads the active language from
/// [LocaleScope] — set by the language picker — so swapping language at
/// onboarding flows through here automatically.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final locale = LocaleScope.of(context);
    final s = locale.strings;
    final language = locale.language;

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
                        PhosphorIconsRegular.caretLeft,
                        size: 14, color: SemaColors.ink,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(s.t('welcome.step'), style: t.labelMedium),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.t('welcome.eyebrow'), style: t.labelMedium),
                  const SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      style: t.displayMedium!.copyWith(
                        fontSize: 32, height: 1.1, letterSpacing: -1.2,
                      ),
                      children: [
                        TextSpan(text: s.t('welcome.lead1')),
                        TextSpan(
                          text: s.t('welcome.emphasis'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        TextSpan(text: s.t('welcome.lead2')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _GreetingHero(language: language),
            ),
            const SizedBox(height: 28),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                physics: const BouncingScrollPhysics(),
                children: [
                  Text(s.t('welcome.whatsInside'), style: t.labelMedium),
                  const SizedBox(height: 12),
                  _FeatureRow(
                    accent: SemaAccent.mint,
                    icon: PhosphorIconsRegular.microphone,
                    title: s.t('welcome.feature.talk.title'),
                    body: s.f('welcome.feature.talk.body', [language.name]),
                  ),
                  _FeatureRow(
                    accent: SemaAccent.blush,
                    icon: PhosphorIconsRegular.firstAidKit,
                    title: s.t('welcome.feature.firstAid.title'),
                    body: s.t('welcome.feature.firstAid.body'),
                  ),
                  _FeatureRow(
                    accent: SemaAccent.butter,
                    icon: PhosphorIconsRegular.mapPin,
                    title: s.t('welcome.feature.care.title'),
                    body: s.t('welcome.feature.care.body'),
                  ),
                  _FeatureRow(
                    accent: SemaAccent.lilac,
                    icon: PhosphorIconsRegular.usersThree,
                    title: s.t('welcome.feature.family.title'),
                    body: s.t('welcome.feature.family.body'),
                    last: true,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: SemaButton(
                label: s.t('welcome.cta.open'),
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const ShellScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GreetingHero extends StatelessWidget {
  const _GreetingHero({required this.language});
  final SemaLanguage language;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = LocaleScope.of(context).strings;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: SemaColors.ink,
        borderRadius: BorderRadius.circular(SemaRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                'assets/illustrations/sema_mark.svg',
                width: 18, height: 18,
                colorFilter: const ColorFilter.mode(
                  Colors.white, BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Sema',
                style: t.titleMedium?.copyWith(
                  color: Colors.white, fontSize: 13, letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(SemaRadii.pill),
                ),
                child: Text(
                  language.code.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${language.greeting}.',
            style: t.displayLarge!.copyWith(
              fontSize: 40, height: 1.0, letterSpacing: -1.4,
              fontWeight: FontWeight.w800, color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            s.f('welcome.semaSpeaksWith', [language.endonym]),
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.accent,
    required this.icon,
    required this.title,
    required this.body,
    this.last = false,
  });
  final SemaAccent accent;
  final IconData icon;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: accent.surface,
              borderRadius: BorderRadius.circular(SemaRadii.s),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: accent.ink),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: t.titleMedium?.copyWith(
                    fontSize: 15, fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: t.bodyMedium?.copyWith(fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
