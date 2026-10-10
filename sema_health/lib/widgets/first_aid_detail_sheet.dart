import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../data/seed/first_aid_display.dart';
import '../data/seed/first_aid_models.dart';
import '../domain/triage/severity.dart';
import '../theme/tokens.dart';

/// Full-bleed detail view for one [FirstAidEntry]. Shown as a tall
/// modal bottom sheet so the chat / first-aid grid stays in flow.
///
/// Renders:
/// - Severity strip + headline
/// - Numbered steps (critical steps highlighted)
/// - Do NOT block
/// - Medications block (with pediatric-contraindication warnings)
/// - Clinician note (`notes:`)
/// - Citations (when present) — "audit only" tone, not user-prescriptive
class FirstAidDetailSheet extends StatelessWidget {
  const FirstAidDetailSheet({super.key, required this.entry});

  final FirstAidEntry entry;

  static Future<void> show(
    BuildContext context, {
    required FirstAidEntry entry,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FirstAidDetailSheet(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final display = FirstAidDisplay.forEntry(entry);
    return Container(
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
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(entry: entry, display: display),
                  const SizedBox(height: 22),
                  if (entry.steps.isNotEmpty) ...[
                    _SectionLabel('Step by step'),
                    const SizedBox(height: 12),
                    _StepsBlock(entry: entry),
                    const SizedBox(height: 22),
                  ],
                  if (entry.donts.isNotEmpty) ...[
                    _DontsBlock(donts: entry.donts),
                    const SizedBox(height: 22),
                  ],
                  if (entry.medications.isNotEmpty) ...[
                    _SectionLabel('Medications'),
                    const SizedBox(height: 10),
                    _MedicationsBlock(meds: entry.medications),
                    const SizedBox(height: 22),
                  ],
                  if (entry.notes != null && entry.notes!.isNotEmpty) ...[
                    _SectionLabel('Clinician note'),
                    const SizedBox(height: 8),
                    Text(
                      entry.notes!,
                      style: const TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        color: SemaColors.ink,
                        letterSpacing: -0.05,
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                  _ReferencesAndAudit(entry: entry),
                  const SizedBox(height: 16),
                  _Disclaimer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Header (title + severity strip) ─────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.entry, required this.display});
  final FirstAidEntry entry;
  final FirstAidDisplay display;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: display.accent.surface,
                borderRadius: BorderRadius.circular(SemaRadii.l),
              ),
              alignment: Alignment.center,
              child: Icon(display.icon, size: 28, color: display.accent.ink),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SeverityBadge(severity: entry.severity),
                  const SizedBox(height: 6),
                  Text(
                    entry.title,
                    style: t.displaySmall?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge({required this.severity});
  final Severity severity;

  @override
  Widget build(BuildContext context) {
    final (label, surface, ink) = switch (severity) {
      Severity.emergency => ('EMERGENCY', SemaColors.danger, Colors.white),
      Severity.high => ('HIGH', SemaColors.butterInk, Colors.white),
      Severity.medium => ('MONITOR', SemaColors.skyInk, Colors.white),
      Severity.low => ('SELF-CARE', SemaColors.mintInk, Colors.white),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(SemaRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Plus Jakarta Sans',
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: ink,
        ),
      ),
    );
  }
}

// ─── Sections ────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontFamily: 'Plus Jakarta Sans',
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: SemaColors.inkMid,
      ),
    );
  }
}

class _StepsBlock extends StatelessWidget {
  const _StepsBlock({required this.entry});
  final FirstAidEntry entry;

  @override
  Widget build(BuildContext context) {
    final steps = entry.steps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: steps[i].critical
                        ? SemaColors.danger
                        : SemaColors.ink,
                    borderRadius: BorderRadius.circular(SemaRadii.s),
                  ),
                  child: Text(
                    '${steps[i].order}',
                    style: const TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        steps[i].action,
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 14.5,
                          height: 1.45,
                          fontWeight: steps[i].critical
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: SemaColors.ink,
                          letterSpacing: -0.05,
                        ),
                      ),
                      if (steps[i].critical)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'Do not skip — do not reorder.',
                            style: TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: SemaColors.danger,
                              letterSpacing: -0.05,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DontsBlock extends StatelessWidget {
  const _DontsBlock({required this.donts});
  final List<String> donts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: SemaColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SemaRadii.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Do NOT",
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: SemaColors.danger,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < donts.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(
                      PhosphorIconsRegular.prohibit,
                      size: 14,
                      color: SemaColors.danger,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      donts[i],
                      style: const TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 13.5,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                        color: SemaColors.ink,
                        letterSpacing: -0.05,
                      ),
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

class _MedicationsBlock extends StatelessWidget {
  const _MedicationsBlock({required this.meds});
  final List<Medication> meds;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < meds.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: SemaColors.cardSoft,
                borderRadius: BorderRadius.circular(SemaRadii.m),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    PhosphorIconsRegular.pill,
                    size: 16,
                    color: SemaColors.inkMid,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          meds[i].name,
                          style: const TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: SemaColors.ink,
                            letterSpacing: -0.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _humanRole(meds[i].role),
                          style: const TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: SemaColors.inkMid,
                          ),
                        ),
                        if (meds[i].pediatricContraindication)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                const Icon(
                                  PhosphorIconsBold.warning,
                                  size: 12,
                                  color: SemaColors.danger,
                                ),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Text(
                                    'Do NOT give to children — risk of '
                                    "Reye's syndrome.",
                                    style: TextStyle(
                                      fontFamily: 'Plus Jakarta Sans',
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: SemaColors.danger,
                                      letterSpacing: -0.05,
                                    ),
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
            ),
          ),
      ],
    );
  }

  String _humanRole(String role) => switch (role) {
        'otc-pain-relief' => 'Over-the-counter pain relief',
        'otc-antihistamine' => 'Over-the-counter antihistamine',
        'otc-anti-itch' => 'Over-the-counter anti-itch',
        'otc-topical' => 'Over-the-counter topical',
        'rx-emergency-device' => 'Prescription emergency device',
        _ => role,
      };
}

// ─── Footer (refs + audit) ───────────────────────────────────────

class _ReferencesAndAudit extends StatelessWidget {
  const _ReferencesAndAudit({required this.entry});
  final FirstAidEntry entry;

  @override
  Widget build(BuildContext context) {
    if (entry.references.isEmpty &&
        !entry.isClinicianReviewed) {
      // Surface a "needs review" pip so the auditor can spot
      // un-reviewed emergency entries at a glance.
      return Row(
        children: [
          const Icon(
            PhosphorIconsRegular.flag,
            size: 12,
            color: SemaColors.inkMid,
          ),
          const SizedBox(width: 6),
          Text(
            entry.isEmergency
                ? 'Pending clinician review · emergency entry'
                : 'Pending clinician review',
            style: const TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: SemaColors.inkMid,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entry.references.isNotEmpty) ...[
          const _SectionLabel('References'),
          const SizedBox(height: 6),
          for (final r in entry.references)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '· $r',
                style: const TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: SemaColors.inkMid,
                  letterSpacing: -0.05,
                ),
              ),
            ),
        ],
        if (entry.isClinicianReviewed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Reviewed by ${entry.reviewedBy}'
              '${entry.reviewedOn != null ? " · ${entry.reviewedOn}" : ""}',
              style: const TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: SemaColors.forestSoft,
              ),
            ),
          ),
      ],
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: SemaColors.cardSoft,
        borderRadius: BorderRadius.circular(SemaRadii.m),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            PhosphorIconsRegular.info,
            size: 14,
            color: SemaColors.inkMid,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sema gives general first-aid education and is not a '
              'diagnosis. For anything serious, call emergency services '
              'or visit a clinician.',
              style: const TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: SemaColors.inkMid,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

