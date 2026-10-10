import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../ai/sema_reply.dart';
import '../data/profile/conditions_catalog.dart';
import '../data/seed/first_aid_models.dart';
import '../domain/triage/severity.dart';
import '../domain/triage/triage_input.dart';
import '../theme/tokens.dart';
import 'press_scale.dart';

/// "Why did Sema say this?" — auditor / clinician view.
///
/// Surfaces every input the deterministic engine saw plus what it
/// decided. Designed to be the single regulatory artefact a clinician
/// can read in 30 seconds and a user can copy-paste into a clinic
/// referral message.
///
/// Audit data lives on [SemaReply.audit]. Replies without audit (the
/// greeting, the no-rule-fallback when Gemma is off) don't surface an
/// audit button — there's nothing to show.
class AuditDrawer extends StatelessWidget {
  const AuditDrawer({
    super.key,
    required this.reply,
    this.matchedEntry,
  });

  final SemaReply reply;

  /// Resolved KG entry the audited rule pointed to, when applicable.
  /// Lets the drawer render the entry's title + clinician review state
  /// without re-reading the YAML.
  final FirstAidEntry? matchedEntry;

  static Future<void> show(
    BuildContext context, {
    required SemaReply reply,
    FirstAidEntry? matchedEntry,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AuditDrawer(reply: reply, matchedEntry: matchedEntry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final audit = reply.audit;
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
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: audit == null
                  ? const _NoAuditView()
                  : _AuditBody(
                      audit: audit,
                      reply: reply,
                      matchedEntry: matchedEntry,
                    ),
            ),
          ),
          if (audit != null)
            _ActionBar(
              audit: audit,
              reply: reply,
              matchedEntry: matchedEntry,
            ),
        ],
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────

class _AuditBody extends StatelessWidget {
  const _AuditBody({
    required this.audit,
    required this.reply,
    required this.matchedEntry,
  });

  final ReplyAudit audit;
  final SemaReply reply;
  final FirstAidEntry? matchedEntry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(audit: audit),
        const SizedBox(height: 16),
        const _Disclaimer(),
        if (audit.source == AuditSource.gemmaFallback) ...[
          const SizedBox(height: 12),
          const _GemmaFallbackBanner(),
        ],
        const SizedBox(height: 22),
        _Section(
          label: audit.source == AuditSource.gemmaFallback
              ? 'Source'
              : 'Decision',
          child: _DecisionBlock(audit: audit, reply: reply),
        ),
        const SizedBox(height: 22),
        _Section(label: 'What you said', child: _UserTextBlock(audit: audit)),
        if (audit.symptomsExtracted.isNotEmpty) ...[
          const SizedBox(height: 22),
          _Section(
            label: 'Symptoms recognised',
            child: _SymptomsBlock(slugs: audit.symptomsExtracted),
          ),
        ],
        if (audit.vitalsExtracted.isNotEmpty) ...[
          const SizedBox(height: 22),
          _Section(
            label: 'Measured values',
            child: _VitalsBlock(vitals: audit.vitalsExtracted),
          ),
        ],
        if (audit.profileAtDecision != null) ...[
          const SizedBox(height: 22),
          _Section(
            label: 'Profile at decision time',
            child: _ProfileBlock(profile: audit.profileAtDecision!),
          ),
        ],
        if (matchedEntry != null) ...[
          const SizedBox(height: 22),
          _Section(
            label: 'Source first-aid entry',
            child: _EntryBlock(entry: matchedEntry!),
          ),
        ],
        if (audit.references.isNotEmpty) ...[
          const SizedBox(height: 22),
          _Section(
            label: 'References',
            child: _ReferencesBlock(refs: audit.references),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.audit});
  final ReplyAudit audit;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SeverityBadge(severity: audit.severity),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Audit trail',
                style: t.displaySmall?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _humanTime(audit.decidedAt),
                style: const TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: SemaColors.inkMid,
                ),
              ),
            ],
          ),
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
    final (label, surface) = switch (severity) {
      Severity.emergency => ('EMERGENCY', SemaColors.danger),
      Severity.high => ('HIGH', SemaColors.butterInk),
      Severity.medium => ('MONITOR', SemaColors.skyInk),
      Severity.low => ('SELF-CARE', SemaColors.mintInk),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(SemaRadii.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Plus Jakarta Sans',
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: Colors.white,
        ),
      ),
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
            PhosphorIconsRegular.shieldCheck,
            size: 14,
            color: SemaColors.forestSoft,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Sema is a guide, not a diagnosis. This page is what Sema "
              "saw and how it decided. Show it to a clinician if you "
              "want a second opinion.",
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

// ─── Sections ─────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: SemaColors.inkMid,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _DecisionBlock extends StatelessWidget {
  const _DecisionBlock({required this.audit, required this.reply});
  final ReplyAudit audit;
  final SemaReply reply;
  @override
  Widget build(BuildContext context) {
    final isFallback = audit.source == AuditSource.gemmaFallback;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: SemaColors.cardSoft,
        borderRadius: BorderRadius.circular(SemaRadii.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isFallback) ...[
            const _Kv(
              label: 'Source',
              value: 'Gemma fallback (no clinical rule matched)',
            ),
            const _Kv(
              label: 'Severity',
              value: 'not assessed by rules',
            ),
          ] else ...[
            _Kv(label: 'Rule', value: audit.ruleId),
            _Kv(label: 'Severity', value: audit.severity.name),
            _Kv(label: 'Action', value: _humanEscalation(audit.escalation)),
          ],
          if (reply.headline.isNotEmpty)
            _Kv(label: 'Headline', value: reply.headline),
        ],
      ),
    );
  }
}

class _GemmaFallbackBanner extends StatelessWidget {
  const _GemmaFallbackBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: SemaColors.lilac.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(SemaRadii.m),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            PhosphorIconsRegular.sparkle,
            size: 14,
            color: SemaColors.lilacInk,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No deterministic rule matched. Sema asked Gemma for a '
              'grounded, KG-backed answer instead. Severity is NOT a '
              'clinical assessment for this turn.',
              style: const TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: SemaColors.lilacInk,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserTextBlock extends StatelessWidget {
  const _UserTextBlock({required this.audit});
  final ReplyAudit audit;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: SemaColors.card,
        borderRadius: BorderRadius.circular(SemaRadii.m),
      ),
      child: Text(
        audit.userText,
        style: const TextStyle(
          fontFamily: 'Plus Jakarta Sans',
          fontSize: 13.5,
          height: 1.45,
          fontWeight: FontWeight.w500,
          color: SemaColors.ink,
          letterSpacing: -0.05,
        ),
      ),
    );
  }
}

class _SymptomsBlock extends StatelessWidget {
  const _SymptomsBlock({required this.slugs});
  final Set<String> slugs;
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final s in slugs) _Chip(text: s, accent: SemaColors.forestSoft),
      ],
    );
  }
}

class _VitalsBlock extends StatelessWidget {
  const _VitalsBlock({required this.vitals});
  final Map<String, num> vitals;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: SemaColors.cardSoft,
        borderRadius: BorderRadius.circular(SemaRadii.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in vitals.entries)
            _Kv(label: _humanVital(entry.key), value: '${entry.value}'),
        ],
      ),
    );
  }
}

class _ProfileBlock extends StatelessWidget {
  const _ProfileBlock({required this.profile});
  final BioProfile profile;
  @override
  Widget build(BuildContext context) {
    final years = profile.ageMonths ~/ 12;
    final months = profile.ageMonths % 12;
    final ageStr = years == 0
        ? '$months months'
        : (months == 0
            ? '$years years'
            : '$years years $months months');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: SemaColors.cardSoft,
        borderRadius: BorderRadius.circular(SemaRadii.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (profile.displayName != null && profile.displayName!.isNotEmpty)
            _Kv(label: 'Name', value: profile.displayName!),
          _Kv(label: 'Age', value: ageStr),
          if (profile.sexAtBirth != null)
            _Kv(label: 'Sex at birth', value: profile.sexAtBirth!),
          _Kv(label: 'Pregnant', value: profile.isPregnant ? 'yes' : 'no'),
          _Kv(
            label: 'Conditions',
            value: profile.conditions.isEmpty
                ? 'none'
                : profile.conditions.map(_humanCondition).join(', '),
          ),
          if (profile.isChw) const _Kv(label: 'CHW mode', value: 'yes'),
        ],
      ),
    );
  }
}

class _EntryBlock extends StatelessWidget {
  const _EntryBlock({required this.entry});
  final FirstAidEntry entry;
  @override
  Widget build(BuildContext context) {
    final reviewed = entry.isClinicianReviewed;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: SemaColors.cardSoft,
        borderRadius: BorderRadius.circular(SemaRadii.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Kv(label: 'Title', value: entry.title),
          _Kv(label: 'Id', value: entry.id),
          _Kv(label: 'Steps', value: '${entry.steps.length}'),
          _Kv(label: '"Do NOT"s', value: '${entry.donts.length}'),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                reviewed
                    ? PhosphorIconsRegular.shieldCheck
                    : PhosphorIconsRegular.flag,
                size: 12,
                color: reviewed ? SemaColors.forestSoft : SemaColors.inkMid,
              ),
              const SizedBox(width: 6),
              Text(
                reviewed
                    ? 'Reviewed by ${entry.reviewedBy}'
                        '${entry.reviewedOn != null ? " · ${entry.reviewedOn}" : ""}'
                    : 'Pending clinician review',
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: reviewed ? SemaColors.forestSoft : SemaColors.inkMid,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReferencesBlock extends StatelessWidget {
  const _ReferencesBlock({required this.refs});
  final List<String> refs;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in refs)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
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
    );
  }
}

// ─── Action bar (copy / done) ────────────────────────────────────

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.audit,
    required this.reply,
    required this.matchedEntry,
  });

  final ReplyAudit audit;
  final SemaReply reply;
  final FirstAidEntry? matchedEntry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
        child: Row(
          children: [
            Expanded(
              child: PressScale(
                onTap: () => _shareSummary(context),
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: SemaColors.bg,
                    border: Border.all(color: SemaColors.hairline),
                    borderRadius: BorderRadius.circular(SemaRadii.pill),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PhosphorIconsRegular.shareNetwork,
                        size: 16,
                        color: SemaColors.ink,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Share with clinician',
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: SemaColors.ink,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PressScale(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: SemaColors.ink,
                    borderRadius: BorderRadius.circular(SemaRadii.pill),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.1,
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

  Future<void> _shareSummary(BuildContext context) async {
    final text = _buildSummary(audit, reply, matchedEntry);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Use the system share sheet so the user can pick WhatsApp /
      // SMS / email at hand-off time. Subject is used by some targets
      // (mail apps) as the email subject line.
      final params = ShareParams(
        text: text,
        subject: 'Sema audit · ${_humanTime(audit.decidedAt)}',
      );
      final result = await SharePlus.instance.share(params);
      if (result.status == ShareResultStatus.success) return;
      // Fall through to clipboard fallback for `unavailable` /
      // `dismissed` so the user always has *some* way to grab the text.
    } catch (_) {
      // Same fallback path on plugin failure (rare; happens on
      // platforms without a share sheet).
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          "Couldn't open share sheet — copied to clipboard instead.",
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────

class _NoAuditView extends StatelessWidget {
  const _NoAuditView();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Center(
        child: Column(
          children: [
            const Icon(
              PhosphorIconsRegular.info,
              size: 32,
              color: SemaColors.inkSoft,
            ),
            const SizedBox(height: 10),
            Text(
              'No audit trail for this reply',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bits ────────────────────────────────────────────────────────

class _Kv extends StatelessWidget {
  const _Kv({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: SemaColors.inkMid,
                letterSpacing: -0.05,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: SemaColors.ink,
                letterSpacing: -0.05,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.accent});
  final String text;
  final Color accent;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SemaRadii.pill),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Plus Jakarta Sans',
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: accent,
          letterSpacing: -0.05,
        ),
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────

String _humanEscalation(Escalation e) => switch (e) {
      Escalation.callEmergency => 'Call emergency services',
      Escalation.goToEr => 'Go to the ER',
      Escalation.nearestClinic => 'Visit nearest clinic',
      Escalation.selfCare => 'Self-care at home',
    };

String _humanVital(String key) => switch (key) {
      'body_temp_c' => 'Body temperature',
      'heart_rate_bpm' => 'Heart rate',
      'resp_rate' => 'Respiratory rate',
      'spo2' => 'Oxygen saturation',
      _ => key,
    };

String _humanCondition(String slug) {
  for (final c in kConditionsCatalog) {
    if (c.slug == slug) return c.label;
  }
  return slug;
}

String _humanTime(DateTime t) {
  final l = t.toLocal();
  final hh = l.hour.toString().padLeft(2, '0');
  final mm = l.minute.toString().padLeft(2, '0');
  return '${l.year}-${_two(l.month)}-${_two(l.day)} $hh:$mm';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Plain-text summary for the clipboard. Designed to paste cleanly into
/// SMS / WhatsApp / a clinician's notes app.
String _buildSummary(
  ReplyAudit audit,
  SemaReply reply,
  FirstAidEntry? entry,
) {
  final isFallback = audit.source == AuditSource.gemmaFallback;
  final buf = StringBuffer()
    ..writeln('Sema audit trail · ${_humanTime(audit.decidedAt)}');
  if (isFallback) {
    buf.writeln('Source: Gemma fallback (no clinical rule matched)');
  } else {
    buf
      ..writeln('Severity: ${audit.severity.name}')
      ..writeln('Action: ${_humanEscalation(audit.escalation)}')
      ..writeln('Rule: ${audit.ruleId}');
  }
  buf
    ..writeln()
    ..writeln('What was said:')
    ..writeln(audit.userText)
    ..writeln();
  if (audit.symptomsExtracted.isNotEmpty) {
    buf
      ..writeln('Symptoms recognised:')
      ..writeln(audit.symptomsExtracted.join(', '))
      ..writeln();
  }
  if (audit.vitalsExtracted.isNotEmpty) {
    buf.writeln('Measured values:');
    for (final v in audit.vitalsExtracted.entries) {
      buf.writeln('  ${_humanVital(v.key)}: ${v.value}');
    }
    buf.writeln();
  }
  final p = audit.profileAtDecision;
  if (p != null) {
    final years = p.ageMonths ~/ 12;
    buf
      ..writeln('Profile:')
      ..writeln('  Age: $years yrs (${p.ageMonths} months)')
      ..writeln('  Sex at birth: ${p.sexAtBirth ?? "unknown"}')
      ..writeln('  Pregnant: ${p.isPregnant ? "yes" : "no"}')
      ..writeln('  Conditions: '
          '${p.conditions.isEmpty ? "none" : p.conditions.join(", ")}')
      ..writeln();
  }
  if (entry != null) {
    buf
      ..writeln('Source first-aid entry:')
      ..writeln('  ${entry.title} (${entry.id})')
      ..writeln('  Reviewed: '
          '${entry.isClinicianReviewed ? entry.reviewedBy : "pending"}')
      ..writeln();
  }
  if (audit.references.isNotEmpty) {
    buf
      ..writeln('References:')
      ..writeln('  ${audit.references.join(", ")}')
      ..writeln();
  }
  buf
    ..writeln('Sema response:')
    ..writeln('  ${reply.headline}')
    ..writeln('  ${reply.body}')
    ..writeln()
    ..write('Sema is a guide, not a diagnosis.');
  return buf.toString();
}
