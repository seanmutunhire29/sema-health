import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../data/seed.dart';
import '../i18n/locale_scope.dart';
import '../theme/tokens.dart';
import '../widgets/hero_illustration.dart';
import '../widgets/press_scale.dart';
import '../widgets/sema_card.dart';
import 'conversation_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = LocaleScope.of(context).strings;
    return SafeArea(
      bottom: false,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          const _Header(),
          const SizedBox(height: 28),
          Text(
            s.t('home.dailyCheckIn'),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          _EmphasisHeadline(
            base: s.t('home.feeling.lead'),
            emphasis: s.t('home.feeling.emphasis'),
            tail: s.t('home.feeling.tail'),
          ),
          const SizedBox(height: 24),
          _HeroCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ConversationScreen(),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            s.t('home.getHelpFast'),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 10),
          const _QuickRow(),
          const SizedBox(height: 28),
          _SectionRow(
            title: s.t('home.recentConversations'),
            action: s.t('home.seeAll'),
            onAction: () {},
          ),
          const SizedBox(height: 12),
          const _RecentTile(
            title: 'Persistent cough',
            subtitle: 'Sema · suggested ginger and rest',
            time: 'Today',
            accent: SemaAccent.sand,
          ),
          const SizedBox(height: 8),
          const _RecentTile(
            title: 'Kojo — fever',
            subtitle: 'Family · checked overnight',
            time: 'Yesterday',
            accent: SemaAccent.sky,
          ),
        ],
      ),
    );
  }
}

class _EmphasisHeadline extends StatelessWidget {
  const _EmphasisHeadline({
    required this.base,
    required this.emphasis,
    this.tail = '',
  });
  final String base;
  final String emphasis;
  final String tail;

  @override
  Widget build(BuildContext context) {
    final hero = Theme.of(context).textTheme.displayMedium!.copyWith(
          fontSize: 32, height: 1.12, letterSpacing: -1.2,
        );
    return RichText(
      text: TextSpan(
        style: hero,
        children: [
          TextSpan(text: base),
          TextSpan(
            text: emphasis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (tail.isNotEmpty) TextSpan(text: tail),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40, height: 40,
          decoration: const BoxDecoration(
            color: SemaColors.card, shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Text(
            'A',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: SemaColors.forest,
            ),
          ),
        ),
        const Spacer(),
        _IconChip(icon: PhosphorIconsRegular.bell, onTap: () {}),
        const SizedBox(width: 8),
        _IconChip(
          icon: PhosphorIconsRegular.gearSix,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
        ),
      ],
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: const BoxDecoration(
          color: SemaColors.card, shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: SemaColors.ink),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = LocaleScope.of(context).strings;
    return SemaCard(
      onTap: onTap,
      color: SemaColors.forest,
      padding: EdgeInsets.zero,
      radius: SemaRadii.xl,
      clip: true,
      child: Stack(
        children: [
          const Positioned.fill(child: HeroIllustration()),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(SemaRadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        PhosphorIconsRegular.lockSimple,
                        size: 11, color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        s.t('home.private'),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          letterSpacing: 0.0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 60),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: -0.6,
                      height: 1.15,
                    ),
                    children: [
                      TextSpan(text: s.t('home.talkTo.lead')),
                      TextSpan(
                        text: s.t('home.talkTo.emphasis'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.t('home.tellMe'),
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 13.5,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(SemaRadii.pill),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        PhosphorIconsBold.microphone,
                        size: 16, color: SemaColors.ink,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        s.t('home.startNow'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: SemaColors.ink,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickRow extends StatelessWidget {
  const _QuickRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < quickActions.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _QuickItem(quickActions[i])),
        ],
      ],
    );
  }
}

class _QuickItem extends StatelessWidget {
  const _QuickItem(this.action);
  final QuickAction action;

  @override
  Widget build(BuildContext context) {
    final s = LocaleScope.of(context).strings;
    return PressScale(
      onTap: () {},
      child: Column(
        children: [
          Container(
            width: double.infinity, height: 64,
            decoration: BoxDecoration(
              color: action.accent.surface,
              borderRadius: BorderRadius.circular(SemaRadii.m),
            ),
            alignment: Alignment.center,
            child: Icon(action.icon, color: action.accent.ink, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            s.t(action.labelKey),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: SemaColors.ink,
              letterSpacing: -0.05,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.title,
    required this.action,
    required this.onAction,
  });
  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineMedium,
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        ),
        GestureDetector(
          onTap: onAction,
          behavior: HitTestBehavior.opaque,
          child: Text(
            action,
            style: const TextStyle(
              fontSize: 13.5,
              color: SemaColors.inkMid,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.05,
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.accent,
  });
  final String title;
  final String subtitle;
  final String time;
  final SemaAccent accent;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: SemaColors.hairlineSoft),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: accent.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                PhosphorIconsRegular.waveform,
                color: accent.ink, size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: SemaColors.ink,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13, color: SemaColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              time,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: SemaColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
