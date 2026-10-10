import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../ai/sema_reply.dart';
import '../theme/tokens.dart';
import '../util/text_clean.dart';
import 'press_scale.dart';

/// Rich Sema-side chat bubble. The plain Sema/user-text bubble in
/// `conversation_screen.dart` handles user input and short Sema
/// asides; this widget renders the structured agent reply (severity
/// banner, headline, steps, don'ts, CTA).
///
/// Visual rule of thumb:
/// - **Emergency** — red banner stripe, white headline pill, danger CTA.
/// - **Caution** — amber accent, no banner stripe but headline is bold.
/// - **Calm** — neutral card, no banner, optional CTA.
class SemaReplyBubble extends StatelessWidget {
  const SemaReplyBubble({
    super.key,
    required this.reply,
    this.onCtaTap,
    this.onOpenEntry,
    this.onOpenAudit,
    this.onPlayAudio,
  });

  final SemaReply reply;

  /// Called when the user taps the bubble's primary CTA. The chat
  /// owner decides what to do (call dialer, push nearest-provider
  /// sheet, etc.).
  final void Function(ReplyCta cta)? onCtaTap;

  /// Called when the user taps the "see full guide" affordance on the
  /// bubble's bottom-right (only visible when [reply.entryRef] is set).
  final void Function(String entryRef)? onOpenEntry;

  /// Called when the user taps the audit-trail affordance. Only shown
  /// when [reply.audit] is populated (deterministic-rule-driven turns).
  /// The chat owner opens [AuditDrawer].
  final void Function(SemaReply reply)? onOpenAudit;

  /// Called when the user taps the play-aloud affordance. Non-null
  /// only when the active locale has on-device TTS — the bubble hides
  /// the speaker icon when null. The chat owner runs the TTS pipeline.
  final void Function(SemaReply reply)? onPlayAudio;

  @override
  Widget build(BuildContext context) {
    final tone = reply.tone;
    final maxW = MediaQuery.of(context).size.width * 0.86;
    // Calm replies blend into the page so the chat doesn't read as a
    // stack of cards. Caution + emergency keep their fill so clinical
    // severity stays visually distinct.
    final isCalm = tone == ReplyTone.calm;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: Container(
        decoration: BoxDecoration(
          color: _surfaceFor(tone),
          borderRadius:
              isCalm ? null : BorderRadius.circular(SemaRadii.l),
          border: tone == ReplyTone.emergency
              ? Border.all(color: SemaColors.danger, width: 1.4)
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tone == ReplyTone.emergency) const _EmergencyStripe(),
            Padding(
              padding: isCalm
                  ? EdgeInsets.zero
                  : const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Headline(reply: reply),
                  const SizedBox(height: 6),
                  Text(
                    stripEmDashes(reply.body),
                    style: const TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: SemaColors.ink,
                      letterSpacing: -0.05,
                    ),
                  ),
                  if (reply.steps.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _StepsList(steps: reply.steps),
                  ],
                  if (reply.donts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _DontsList(donts: reply.donts),
                  ],
                  if (reply.cta != null) ...[
                    const SizedBox(height: 14),
                    _CtaBar(
                      cta: reply.cta!,
                      tone: tone,
                      onTap: onCtaTap,
                    ),
                  ],
                  if ((reply.entryRef != null && reply.cta?.entryRef == null) ||
                      reply.audit != null ||
                      onPlayAudio != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          if (reply.entryRef != null &&
                              reply.cta?.entryRef == null)
                            Expanded(
                              child: PressScale(
                                onTap: () => onOpenEntry?.call(reply.entryRef!),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      PhosphorIconsRegular.bookOpen,
                                      size: 12,
                                      color: SemaColors.inkMid,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'See full first-aid guide',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Plus Jakarta Sans',
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: SemaColors.inkMid,
                                          decoration: TextDecoration.underline,
                                          decorationColor: SemaColors.inkMid
                                              .withValues(alpha: 0.4),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            const Spacer(),
                          if (onPlayAudio != null && reply.body.trim().isNotEmpty)
                            _PlayButton(onTap: () => onPlayAudio!(reply)),
                          if (onPlayAudio != null && reply.audit != null)
                            const SizedBox(width: 8),
                          if (reply.audit != null)
                            _AuditButton(
                              onTap: () => onOpenAudit?.call(reply),
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
    );
  }

  Color _surfaceFor(ReplyTone t) => switch (t) {
        ReplyTone.calm => Colors.transparent,
        ReplyTone.caution => SemaColors.butter,
        ReplyTone.emergency => Colors.white,
      };
}

class _AuditButton extends StatelessWidget {
  const _AuditButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: SemaColors.inkMid.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(SemaRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              PhosphorIconsRegular.info,
              size: 11,
              color: SemaColors.inkMid,
            ),
            const SizedBox(width: 5),
            Text(
              'How Sema decided',
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: SemaColors.inkMid,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Speaker pill that plays the reply aloud via the chat's TTS pipeline.
/// Visually mirrors [_AuditButton] so the bottom row reads as a row of
/// peers rather than a primary + secondary action pair.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: SemaColors.inkMid.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(SemaRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              PhosphorIconsFill.speakerHigh,
              size: 11,
              color: SemaColors.inkMid,
            ),
            SizedBox(width: 5),
            Text(
              'Play aloud',
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: SemaColors.inkMid,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyStripe extends StatelessWidget {
  const _EmergencyStripe();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: SemaColors.danger,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          const Icon(
            PhosphorIconsBold.warning,
            size: 14,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
          const Text(
            'EMERGENCY',
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.reply});
  final SemaReply reply;
  @override
  Widget build(BuildContext context) {
    return Text(
      stripEmDashes(reply.headline),
      style: TextStyle(
        fontFamily: 'Plus Jakarta Sans',
        fontSize: 15.5,
        fontWeight: reply.tone == ReplyTone.calm
            ? FontWeight.w600
            : FontWeight.w800,
        color: SemaColors.ink,
        letterSpacing: -0.2,
        height: 1.25,
      ),
    );
  }
}

class _StepsList extends StatelessWidget {
  const _StepsList({required this.steps});
  final List<SemaReplyStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: _StepRow(index: i + 1, step: steps[i]),
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.step});
  final int index;
  final SemaReplyStep step;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: step.critical
                ? SemaColors.danger
                : SemaColors.ink,
            borderRadius: BorderRadius.circular(SemaRadii.s),
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            stripEmDashes(step.text),
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 13.5,
              height: 1.42,
              fontWeight:
                  step.critical ? FontWeight.w600 : FontWeight.w500,
              color: SemaColors.ink,
              letterSpacing: -0.05,
            ),
          ),
        ),
      ],
    );
  }
}

class _DontsList extends StatelessWidget {
  const _DontsList({required this.donts});
  final List<String> donts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: SemaColors.danger,
            ),
          ),
          const SizedBox(height: 6),
          for (final d in donts)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(
                      PhosphorIconsRegular.prohibit,
                      size: 12,
                      color: SemaColors.danger,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      stripEmDashes(d),
                      style: const TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 12.5,
                        height: 1.4,
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

class _CtaBar extends StatelessWidget {
  const _CtaBar({
    required this.cta,
    required this.tone,
    required this.onTap,
  });
  final ReplyCta cta;
  final ReplyTone tone;
  final void Function(ReplyCta)? onTap;

  @override
  Widget build(BuildContext context) {
    final emergency = cta.kind == ReplyCtaKind.callEmergency ||
        tone == ReplyTone.emergency;
    final bg = emergency ? SemaColors.danger : SemaColors.ink;
    final icon = switch (cta.kind) {
      ReplyCtaKind.callEmergency => PhosphorIconsBold.phone,
      ReplyCtaKind.findHospital => PhosphorIconsBold.firstAidKit,
      ReplyCtaKind.findClinic => PhosphorIconsBold.heartbeat,
      ReplyCtaKind.openFirstAidEntry => PhosphorIconsBold.bookOpen,
      ReplyCtaKind.none => PhosphorIconsBold.arrowRight,
    };

    return PressScale(
      onTap: () => onTap?.call(cta),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(SemaRadii.pill),
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 10),
            Text(
              cta.label,
              style: const TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.1,
              ),
            ),
            const Spacer(),
            const Icon(
              PhosphorIconsBold.arrowRight,
              color: Colors.white,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}
