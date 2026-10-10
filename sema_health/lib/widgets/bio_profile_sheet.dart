import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../data/profile/bio_profile_store.dart';
import '../data/profile/conditions_catalog.dart';
import '../domain/triage/triage_input.dart';
import '../theme/tokens.dart';
import 'press_scale.dart';

/// One-time bio-profile gate shown before a user's first symptom turn
/// in the chat. Collects the fields the triage engine and Gemma's
/// system prompt actually use:
///
/// - `displayName` (optional) — chat chrome only, never reaches the LLM.
/// - `ageMonths` (years + months) — drives age-gated rules
///   (infant fever <3 mo, no aspirin under 12, infant Heimlich).
/// - `sexAtBirth` — needed for the pregnancy gate and a few clinical
///   defaults; kept clinical (not "gender identity") because the rules
///   are physiological.
/// - `isPregnant` — only surfaced when sex is female and age ≥ 10.
///   Pregnancy contraindications matter for choking (chest thrusts),
///   bleeding (emergency), drug whitelist, etc.
/// - `conditions` — chip multi-select against [kConditionsCatalog].
///   Matches `profile.conditions_contains` rules in `rules.yaml`.
/// - `isChw` — community health worker mode (deferred UI; flag only).
///
/// Fills are persisted to [BioProfileStore]. v1 is in-memory; the
/// architecture's encrypted-at-rest contract is a follow-up swap.
class BioProfileSheet extends StatefulWidget {
  const BioProfileSheet({super.key, this.initial});

  final BioProfile? initial;

  /// Show as a modal bottom sheet. Returns `true` if the user saved.
  static Future<bool> show(BuildContext context, {BioProfile? initial}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BioProfileSheet(initial: initial),
    );
    return result == true;
  }

  @override
  State<BioProfileSheet> createState() => _BioProfileSheetState();
}

class _BioProfileSheetState extends State<BioProfileSheet> {
  late final TextEditingController _name;
  late int _years;
  late int _months;
  String? _sex;
  bool _isPregnant = false;
  late Set<String> _conditions;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _name = TextEditingController(text: i?.displayName ?? '');
    final m = i?.ageMonths ?? 360; // default 30y
    _years = m ~/ 12;
    _months = m % 12;
    _sex = i?.sexAtBirth;
    _isPregnant = i?.isPregnant ?? false;
    _conditions = {...?i?.conditions};
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _showPregnancy {
    if (_sex != 'female') return false;
    return (_years * 12 + _months) >= 12 * 10;
  }

  bool get _canSave {
    // Sex must be answered (even if "prefer not to say"). Age default
    // is fine. Name is optional.
    return _sex != null;
  }

  void _save() {
    if (!_canSave) return;
    final profile = BioProfile(
      ageMonths: _years * 12 + _months,
      sexAtBirth: _sex,
      isPregnant: _showPregnancy && _isPregnant,
      conditions: _conditions.toList()..sort(),
      displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
    );
    BioProfileStore.instance.save(profile);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final mq = MediaQuery.of(context);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.92),
        decoration: const BoxDecoration(
          color: SemaColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: SemaColors.hairline,
                borderRadius: BorderRadius.circular(SemaRadii.pill),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Before we begin',
                      style: t.displaySmall?.copyWith(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sema gives clearer guidance when it knows who '
                      "we're caring for. Nothing leaves this phone.",
                      style: t.bodyMedium?.copyWith(color: SemaColors.inkMid),
                    ),
                    const SizedBox(height: 24),

                    // ----- Name (optional) ------------------------------
                    _Label('Their name (optional)'),
                    const SizedBox(height: 8),
                    _TextField(
                      controller: _name,
                      hint: 'e.g. Me, Adwoa, baby Kojo',
                    ),
                    const SizedBox(height: 22),

                    // ----- Age ------------------------------------------
                    _Label('Age'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _NumberStepper(
                            label: 'years',
                            value: _years,
                            min: 0,
                            max: 110,
                            onChanged: (v) => setState(() => _years = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _NumberStepper(
                            label: 'months',
                            value: _months,
                            min: 0,
                            max: 11,
                            onChanged: (v) => setState(() => _months = v),
                          ),
                        ),
                      ],
                    ),
                    if (_years == 0 && _months < 12)
                      _InfoRow(
                        icon: PhosphorIconsRegular.babyCarriage,
                        text: _months < 3
                            ? 'Sema treats any fever in a baby under 3 months '
                                'as an emergency.'
                            : 'Sema uses infant-specific first-aid steps '
                                '(back blows + chest thrusts for choking).',
                      ),
                    const SizedBox(height: 22),

                    // ----- Sex assigned at birth ------------------------
                    _Label('Sex assigned at birth'),
                    const SizedBox(height: 4),
                    Text(
                      'Used for clinical defaults only. You can change this.',
                      style: t.bodySmall?.copyWith(color: SemaColors.inkMid),
                    ),
                    const SizedBox(height: 10),
                    _SegChoice(
                      options: const [
                        ('male', 'Male'),
                        ('female', 'Female'),
                        ('unknown', 'Prefer not to say'),
                      ],
                      value: _sex,
                      onChanged: (v) => setState(() {
                        _sex = v;
                        if (v != 'female') _isPregnant = false;
                      }),
                    ),
                    const SizedBox(height: 22),

                    // ----- Pregnancy (conditional) ----------------------
                    if (_showPregnancy) ...[
                      _Label('Currently pregnant?'),
                      const SizedBox(height: 10),
                      _SegChoice(
                        options: const [
                          ('no', 'No'),
                          ('yes', 'Yes'),
                        ],
                        value: _isPregnant ? 'yes' : 'no',
                        onChanged: (v) =>
                            setState(() => _isPregnant = v == 'yes'),
                      ),
                      const SizedBox(height: 22),
                    ],

                    // ----- Existing conditions --------------------------
                    _Label('Existing conditions'),
                    const SizedBox(height: 4),
                    Text(
                      'Tap any that apply. This sharpens Sema\'s '
                      'recommendations — for example, treating sudden '
                      'rapid breathing differently for someone with asthma.',
                      style: t.bodySmall?.copyWith(color: SemaColors.inkMid),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in kConditionsCatalog)
                          _ConditionChip(
                            option: c,
                            selected: _conditions.contains(c.slug),
                            onTap: () => setState(() {
                              if (_conditions.contains(c.slug)) {
                                _conditions.remove(c.slug);
                              } else {
                                _conditions.add(c.slug);
                              }
                            }),
                          ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    // ----- Privacy note ---------------------------------
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: SemaColors.cardSoft,
                        borderRadius: BorderRadius.circular(SemaRadii.m),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            PhosphorIconsRegular.shieldCheck,
                            size: 18,
                            color: SemaColors.forestSoft,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Your details stay on this device. Sema works '
                              'fully offline — no health data ever leaves '
                              'the phone. Sema is a guide, not a diagnosis.',
                              style: t.bodySmall?.copyWith(
                                color: SemaColors.inkMid,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ----- Save bar ------------------------------------------
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: PressScale(
                    onTap: _canSave ? _save : () {},
                    child: Container(
                      decoration: BoxDecoration(
                        color: _canSave
                            ? SemaColors.ink
                            : SemaColors.inkSoft,
                        borderRadius:
                            BorderRadius.circular(SemaRadii.pill),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Save & continue',
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Colors.white,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Plus Jakarta Sans',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: SemaColors.ink,
        letterSpacing: -0.1,
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({required this.controller, required this.hint});
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: SemaColors.card,
        borderRadius: BorderRadius.circular(SemaRadii.m),
      ),
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          border: InputBorder.none,
          hintStyle: const TextStyle(color: SemaColors.inkMuted, fontSize: 14),
        ),
        style: const TextStyle(
          fontSize: 14,
          color: SemaColors.ink,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

class _NumberStepper extends StatelessWidget {
  const _NumberStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: SemaColors.card,
        borderRadius: BorderRadius.circular(SemaRadii.m),
      ),
      child: Row(
        children: [
          _StepBtn(
            icon: PhosphorIconsRegular.minus,
            onTap: value > min ? () => onChanged(value - 1) : null,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: SemaColors.ink,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: SemaColors.inkMid,
                  ),
                ),
              ],
            ),
          ),
          _StepBtn(
            icon: PhosphorIconsRegular.plus,
            onTap: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return PressScale(
      onTap: onTap ?? () {},
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled ? SemaColors.bg : SemaColors.cardSoft,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 16,
          color: enabled ? SemaColors.ink : SemaColors.inkSoft,
        ),
      ),
    );
  }
}

class _SegChoice extends StatelessWidget {
  const _SegChoice({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(String, String)> options;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (slug, label) in options)
          PressScale(
            onTap: () => onChanged(slug),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: value == slug ? SemaColors.ink : SemaColors.card,
                borderRadius: BorderRadius.circular(SemaRadii.pill),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color:
                      value == slug ? Colors.white : SemaColors.ink,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ConditionChip extends StatelessWidget {
  const _ConditionChip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ConditionOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: option.description,
      child: PressScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: selected ? SemaColors.forest : SemaColors.card,
            borderRadius: BorderRadius.circular(SemaRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(
                  PhosphorIconsBold.check,
                  size: 12,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                option.label,
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color:
                      selected ? Colors.white : SemaColors.ink,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: SemaColors.forestSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: SemaColors.inkMid,
                height: 1.4,
                letterSpacing: -0.05,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
