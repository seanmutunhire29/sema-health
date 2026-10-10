import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../ai/sema_reply.dart';
import '../data/conversation/chat_message.dart';
import '../data/conversation/conversation_store.dart';
import '../data/seed/first_aid_models.dart';
import '../data/seed/first_aid_repo.dart';
import '../data/seed/first_aid_repo_provider.dart';
import '../domain/triage/triage_input.dart';
import '../i18n/locale_scope.dart';
import '../theme/tokens.dart';
import '../widgets/first_aid_detail_sheet.dart';
import '../widgets/press_scale.dart';

/// Per-conversation transcript view with a per-Sema-turn audit drawer.
///
/// The drawer is the headline feature: tap any past Sema reply and see
/// the rule that fired, the severity, the symptoms the extractor pulled
/// from the user's turn, the bio profile snapshot at decision time, and
/// the WHO/Red Cross/MoH citations on the rule. Steps and don'ts are
/// re-hydrated live from the KG via the persisted entryRef so an updated
/// YAML shows in old transcripts too.
class JournalDetailScreen extends StatefulWidget {
  const JournalDetailScreen({super.key, required this.conversationId});
  final int conversationId;

  @override
  State<JournalDetailScreen> createState() => _JournalDetailScreenState();
}

class _JournalDetailScreenState extends State<JournalDetailScreen> {
  Future<({List<ChatMessage> messages, FirstAidRepo repo})>? _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<({List<ChatMessage> messages, FirstAidRepo repo})> _load() async {
    final store = await ConversationStore.open();
    final results = await Future.wait([
      store.read(widget.conversationId),
      firstAidRepoFuture(),
    ]);
    return (
      messages: results[0] as List<ChatMessage>,
      repo: results[1] as FirstAidRepo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleScope.of(context).strings;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _RoundIcon(
                  icon: PhosphorIconsRegular.caretLeft,
                  onTap: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    s.t('journal.detail.title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: SemaColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
          ),
        ),
      ),
      body: FutureBuilder<({List<ChatMessage> messages, FirstAidRepo repo})>(
        future: _data,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          final messages = snap.data!.messages;
          final repo = snap.data!.repo;
          if (messages.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  s.t('journal.detail.notFound'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            );
          }
          return ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemCount: messages.length,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (_, i) {
              final m = messages[i];
              return switch (m) {
                UserChatMessage() => _UserBubble(message: m),
                SemaTextChatMessage() => _PlainSemaBubble(message: m),
                SemaReplyChatMessage() => _SemaCard(
                    message: m,
                    repo: repo,
                  ),
              };
            },
          );
        },
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});
  final UserChatMessage message;

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.78;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          constraints: BoxConstraints(maxWidth: maxW),
          padding: const EdgeInsets.fromLTRB(15, 11, 15, 12),
          decoration: const BoxDecoration(
            color: SemaColors.ink,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Text(
            message.text,
            style: const TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 14.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: Colors.white,
              letterSpacing: -0.1,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            _hhmm(message.createdAt),
            style: const TextStyle(
              fontSize: 11,
              color: SemaColors.inkSoft,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlainSemaBubble extends StatelessWidget {
  const _PlainSemaBubble({required this.message});
  final SemaTextChatMessage message;

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.78;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: BoxConstraints(maxWidth: maxW),
          padding: const EdgeInsets.fromLTRB(15, 11, 15, 12),
          decoration: const BoxDecoration(
            color: SemaColors.card,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(6),
              bottomRight: Radius.circular(20),
            ),
          ),
          child: Text(
            message.text,
            style: const TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 14.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: SemaColors.ink,
              letterSpacing: -0.1,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            _hhmm(message.createdAt),
            style: const TextStyle(
              fontSize: 11,
              color: SemaColors.inkSoft,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _SemaCard extends StatefulWidget {
  const _SemaCard({required this.message, required this.repo});
  final SemaReplyChatMessage message;
  final FirstAidRepo repo;

  @override
  State<_SemaCard> createState() => _SemaCardState();
}

class _SemaCardState extends State<_SemaCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final reply = widget.message.reply;
    final entry = reply.entryRef == null
        ? null
        : widget.repo.getById(reply.entryRef!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: SemaColors.card,
            borderRadius: BorderRadius.circular(SemaRadii.l),
            border: reply.tone == ReplyTone.emergency
                ? Border.all(color: SemaColors.danger, width: 1.4)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reply.headline,
                style: const TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  letterSpacing: -0.2,
                  color: SemaColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                reply.body,
                style: const TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: SemaColors.ink,
                  letterSpacing: -0.05,
                ),
              ),
              if (entry != null) ...[
                const SizedBox(height: 10),
                _EntryLink(entry: entry),
              ],
              const SizedBox(height: 8),
              _AuditToggle(
                open: _open,
                onTap: () => setState(() => _open = !_open),
              ),
              if (_open) ...[
                const SizedBox(height: 10),
                _AuditDrawer(reply: reply, entry: entry),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            _hhmm(widget.message.createdAt),
            style: const TextStyle(
              fontSize: 11,
              color: SemaColors.inkSoft,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _EntryLink extends StatelessWidget {
  const _EntryLink({required this.entry});
  final FirstAidEntry entry;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () => FirstAidDetailSheet.show(context, entry: entry),
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
              'Open full guide · ${entry.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: SemaColors.inkMid,
                decoration: TextDecoration.underline,
                decorationColor: SemaColors.inkMid.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditToggle extends StatelessWidget {
  const _AuditToggle({required this.open, required this.onTap});
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = LocaleScope.of(context).strings;
    return PressScale(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            PhosphorIconsRegular.shieldCheck,
            size: 12,
            color: SemaColors.inkMid,
          ),
          const SizedBox(width: 6),
          Text(
            open ? s.t('journal.audit.hide') : s.t('journal.audit.show'),
            style: const TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: SemaColors.inkMid,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            open ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown,
            size: 10,
            color: SemaColors.inkMid,
          ),
        ],
      ),
    );
  }
}

class _AuditDrawer extends StatelessWidget {
  const _AuditDrawer({required this.reply, required this.entry});
  final SemaReply reply;
  final FirstAidEntry? entry;

  @override
  Widget build(BuildContext context) {
    final s = LocaleScope.of(context).strings;
    final audit = reply.audit;
    final rows = <Widget>[];
    if (audit?.severity != null) {
      rows.add(_AuditRow(
        label: s.t('journal.audit.severity'),
        value: audit!.severity.name.toUpperCase(),
      ));
    }
    if (audit?.ruleId != null && audit!.ruleId.isNotEmpty) {
      rows.add(_AuditRow(
        label: s.t('journal.audit.rule'),
        value: audit.ruleId,
      ));
    }
    if (entry != null) {
      rows.add(_AuditRow(
        label: s.t('journal.audit.entry'),
        value: entry!.id,
      ));
    }
    final symptoms = audit?.symptomsExtracted.toList() ?? const <String>[];
    if (symptoms.isNotEmpty) {
      rows.add(_AuditChips(
        label: s.t('journal.audit.symptoms'),
        values: symptoms,
      ));
    }
    final profile = audit?.profileAtDecision;
    if (profile != null) {
      rows.add(_AuditRow(
        label: s.t('journal.audit.profile'),
        value: _describeProfile(profile),
      ));
    }
    if (reply.citation.isNotEmpty) {
      rows.add(_AuditChips(
        label: s.t('journal.audit.citations'),
        values: reply.citation,
      ));
    }
    if (rows.isEmpty) {
      rows.add(_AuditRow(
        label: s.t('journal.audit.note'),
        value: s.t('journal.audit.empty'),
      ));
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: SemaColors.bg,
        borderRadius: BorderRadius.circular(SemaRadii.s),
        border: Border.all(color: SemaColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: rows[i],
            ),
        ],
      ),
    );
  }

  String _describeProfile(BioProfile p) {
    final years = p.ageMonths ~/ 12;
    final months = p.ageMonths % 12;
    final age = years == 0
        ? '$months mo'
        : (months == 0 ? '$years y' : '$years y $months mo');
    final parts = <String>[age];
    if (p.sexAtBirth != null) parts.add(p.sexAtBirth!);
    if (p.isPregnant) parts.add('pregnant');
    if (p.conditions.isNotEmpty) parts.add(p.conditions.join(','));
    return parts.join(' · ');
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: SemaColors.inkMuted,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: SemaColors.ink,
              letterSpacing: -0.05,
            ),
          ),
        ),
      ],
    );
  }
}

class _AuditChips extends StatelessWidget {
  const _AuditChips({required this.label, required this.values});
  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: SemaColors.inkMuted,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in values)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: SemaColors.card,
                    borderRadius: BorderRadius.circular(SemaRadii.pill),
                  ),
                  child: Text(
                    v,
                    style: const TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: SemaColors.ink,
                      letterSpacing: -0.05,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: SemaColors.card,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 17, color: SemaColors.ink),
      ),
    );
  }
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
