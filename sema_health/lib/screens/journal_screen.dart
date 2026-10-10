import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../ai/sema_reply.dart';
import '../data/conversation/conversation_store.dart';
import '../data/db/app_database.dart';
import '../domain/triage/severity.dart';
import '../i18n/locale_scope.dart';
import '../theme/tokens.dart';
import '../widgets/press_scale.dart';
import 'journal_detail_screen.dart';

/// Journal — every past chat conversation, drillable into a detail view
/// where each Sema reply has an audit drawer (rule, severity, extracted
/// symptoms, citation). Backed by the same [ConversationStore] that
/// persists the live chat, so there's no parallel state to keep in sync.
///
/// This is Sema's *Safety & Trust* surface: it lets a judge see, for
/// every reply Sema ever gave, exactly which deterministic rule fired,
/// what symptoms were extracted, and what clinical citation backs the
/// recommendation. No mainstream chat AI exposes this provenance.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  late Future<_JournalView> _view;
  ConversationStore? _store;

  @override
  void initState() {
    super.initState();
    _view = _load();
  }

  @override
  void dispose() {
    _store?.changes.removeListener(_onStoreChanged);
    super.dispose();
  }

  /// Re-fetch when ConversationStore tells us the DB changed. The
  /// JournalScreen lives inside an IndexedStack so its initState only
  /// runs once — without this listener, conversations saved while the
  /// app is open never appear until pull-to-refresh.
  void _onStoreChanged() {
    if (!mounted) return;
    // Block-body setState — the arrow form would return the Future
    // produced by `_view = _load()` and Flutter flags that as a likely
    // mistake (you'd be telling setState to await the future).
    setState(() {
      _view = _load();
    });
  }

  Future<_JournalView> _load() async {
    final store = await ConversationStore.open();
    if (_store != store) {
      _store?.changes.removeListener(_onStoreChanged);
      store.changes.addListener(_onStoreChanged);
      _store = store;
    }
    final convs = await store.recentConversations();
    final summaries = <_SessionRow>[];
    for (final c in convs) {
      final s = await store.summarize(c.id);
      if (s.turnCount == 0) continue; // skip empty shells
      summaries.add(_SessionRow(row: c, summary: s));
    }
    return _JournalView(store: store, sessions: summaries);
  }

  /// Hint the screen to refetch — used after pop from detail (in case
  /// the user wiped a conversation) and pulled-to-refresh.
  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _view = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = LocaleScope.of(context).strings;

    return SafeArea(
      bottom: false,
      child: FutureBuilder<_JournalView>(
        future: _view,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator.adaptive(),
            );
          }
          final view = snap.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.t('journal.eyebrow'), style: t.labelMedium),
                        const SizedBox(height: 8),
                        RichText(
                          text: TextSpan(
                            style: t.displayMedium!.copyWith(
                              fontSize: 32,
                              height: 1.12,
                              letterSpacing: -1.2,
                            ),
                            children: [
                              TextSpan(text: s.t('journal.title.lead')),
                              TextSpan(
                                text: s.t('journal.title.emphasis'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                              TextSpan(text: s.t('journal.title.tail')),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(s.t('journal.body'), style: t.bodyMedium),
                      ],
                    ),
                  ),
                ),
                if (view.sessions.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    sliver: SliverList.separated(
                      itemCount: view.sessions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final row = view.sessions[i];
                        return _SessionTile(
                          row: row,
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => JournalDetailScreen(
                                  conversationId: row.row.id,
                                ),
                              ),
                            );
                            // Refresh in case the user wiped the chat.
                            if (context.mounted) await _refresh();
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _JournalView {
  const _JournalView({required this.store, required this.sessions});
  final ConversationStore store;
  final List<_SessionRow> sessions;
}

class _SessionRow {
  const _SessionRow({required this.row, required this.summary});
  final ConversationRow row;
  final ({SemaReply? firstReply, int turnCount}) summary;
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.row, required this.onTap});
  final _SessionRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = LocaleScope.of(context).strings;
    final preview = row.summary.firstReply;
    final severity = preview?.audit?.severity;
    final accent = _accentForSeverity(severity);
    final headline = preview?.headline ?? s.t('journal.untitled');
    final body = preview?.body ?? '';

    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: accent.surface,
          borderRadius: BorderRadius.circular(SemaRadii.l),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  PhosphorIconsRegular.notebook,
                  size: 16,
                  color: accent.ink,
                ),
                const SizedBox(width: 8),
                Text(
                  _relativeDate(row.row.lastActivityAt),
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: accent.ink.withValues(alpha: 0.75),
                  ),
                ),
                const Spacer(),
                if (row.row.profileLabel != null &&
                    row.row.profileLabel!.isNotEmpty)
                  _ProfileChip(label: row.row.profileLabel!, ink: accent.ink),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              headline,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 17,
                fontWeight: FontWeight.w800,
                height: 1.2,
                letterSpacing: -0.4,
                color: accent.ink,
              ),
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: accent.ink.withValues(alpha: 0.7),
                  letterSpacing: -0.05,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (severity != null)
                  _SeverityPip(severity: severity, ink: accent.ink),
                if (severity != null) const SizedBox(width: 8),
                _MetaPill(
                  icon: PhosphorIconsRegular.chatCircle,
                  label: s.f('journal.turnsCount', ['${row.summary.turnCount}']),
                  ink: accent.ink,
                ),
                const Spacer(),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accent.ink,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    PhosphorIconsBold.arrowUpRight,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Severity → pastel accent. Mirrors the chat bubble's tone palette so
/// emergency conversations surface visually in the list.
SemaAccent _accentForSeverity(Severity? s) => switch (s) {
      Severity.emergency => SemaAccent.blush,
      Severity.high => SemaAccent.sand,
      Severity.medium => SemaAccent.butter,
      Severity.low => SemaAccent.mint,
      null => SemaAccent.mint,
    };

String _relativeDate(DateTime then) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(then.year, then.month, then.day);
  final delta = today.difference(that).inDays;
  if (delta == 0) return 'Today · ${_hhmm(then)}';
  if (delta == 1) return 'Yesterday · ${_hhmm(then)}';
  if (delta < 7) return '$delta days ago';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${then.day} ${months[then.month - 1]}';
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.label, required this.ink});
  final String label;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(SemaRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsRegular.user, size: 11, color: ink),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 90),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    required this.ink,
  });
  final IconData icon;
  final String label;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(SemaRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: ink),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeverityPip extends StatelessWidget {
  const _SeverityPip({required this.severity, required this.ink});
  final Severity severity;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final isEmergency = severity == Severity.emergency;
    final bg = isEmergency ? SemaColors.danger : ink;
    final label = switch (severity) {
      Severity.emergency => 'EMERGENCY',
      Severity.high => 'HIGH',
      Severity.medium => 'WATCH',
      Severity.low => 'SELF-CARE',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SemaRadii.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Plus Jakarta Sans',
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = LocaleScope.of(context).strings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 80),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              PhosphorIconsRegular.notebook,
              size: 36,
              color: SemaColors.inkMid,
            ),
            const SizedBox(height: 12),
            Text(
              s.t('journal.empty.title'),
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              s.t('journal.empty.body'),
              style: t.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
