import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../theme/tokens.dart';
import '../widgets/press_scale.dart';

/// Bespoke family screen — promotes the active profile into a typographic
/// hero card and lists remaining profiles compactly. Mirrors the language
/// picker's hero + selector pattern.
class FamilyScreen extends StatelessWidget {
  const FamilyScreen({super.key});

  static const _members = <_Member>[
    _Member('A', 'Ama',  'You · 34',         SemaAccent.mint),
    _Member('K', 'Kojo', 'Son · 6',          SemaAccent.blush),
    _Member('E', 'Esi',  'Daughter · 3',     SemaAccent.butter),
    _Member('Y', 'Yaa',  'Mother · 68',      SemaAccent.lilac),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final active = _members.first;
    final others = _members.skip(1).toList();

    return SafeArea(
      bottom: false,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          Text('Household', style: t.labelMedium),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: t.displayMedium!.copyWith(
                fontSize: 32, height: 1.12, letterSpacing: -1.2,
              ),
              children: const [
                TextSpan(text: 'Your '),
                TextSpan(
                  text: 'family',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: ',\nin one place.'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'One phone, the whole household — switch profiles to chat for anyone.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 22),

          _ActiveProfileCard(member: active),

          const SizedBox(height: 24),
          Text('Other profiles', style: t.labelMedium),
          const SizedBox(height: 8),

          for (int i = 0; i < others.length; i++)
            _MemberRow(
              member: others[i],
              showDivider: i != others.length - 1,
            ),

          const SizedBox(height: 16),
          _AddMember(),
        ],
      ),
    );
  }
}

class _Member {
  const _Member(this.initial, this.name, this.meta, this.accent);
  final String initial;
  final String name;
  final String meta;
  final SemaAccent accent;
}

/// Hero card for the active profile — big initial, name in display weight,
/// quick-action chip row beneath.
class _ActiveProfileCard extends StatelessWidget {
  const _ActiveProfileCard({required this.member});
  final _Member member;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 18, 22),
      decoration: BoxDecoration(
        color: member.accent.surface,
        borderRadius: BorderRadius.circular(SemaRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Active profile',
                style: t.labelMedium?.copyWith(color: member.accent.ink.withValues(alpha: 0.7)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9, vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(SemaRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: member.accent.ink,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'On now',
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        color: member.accent.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  member.initial,
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.2,
                    color: member.accent.ink,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: t.displayMedium!.copyWith(
                        fontSize: 26, letterSpacing: -0.8,
                        fontWeight: FontWeight.w800,
                        color: member.accent.ink,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      member.meta,
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: member.accent.ink.withValues(alpha: 0.7),
                        letterSpacing: -0.05,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _ActionChip(
                icon: PhosphorIconsRegular.arrowsLeftRight,
                label: 'Switch',
                ink: member.accent.ink,
                onTap: () {},
              ),
              const SizedBox(width: 8),
              _ActionChip(
                icon: PhosphorIconsRegular.notePencil,
                label: 'Edit',
                ink: member.accent.ink,
                onTap: () {},
              ),
              const Spacer(),
              PressScale(
                onTap: () {},
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: member.accent.ink,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    PhosphorIconsBold.arrowUpRight,
                    size: 14, color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.ink,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(SemaRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: ink),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.05,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.showDivider});
  final _Member member;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return PressScale(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
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
                color: member.accent.surface,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                member.initial,
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: member.accent.ink,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleMedium?.copyWith(
                      fontSize: 15, fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    member.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium?.copyWith(
                      fontSize: 13, color: SemaColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              PhosphorIconsRegular.caretRight,
              size: 16, color: SemaColors.inkSoft,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddMember extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          color: SemaColors.bg,
          borderRadius: BorderRadius.circular(SemaRadii.l),
          border: Border.all(color: SemaColors.hairline),
        ),
        child: const Row(
          children: [
            Icon(PhosphorIconsRegular.plus, color: SemaColors.inkMid, size: 18),
            SizedBox(width: 10),
            Text(
              'Add a family member',
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: SemaColors.ink,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
