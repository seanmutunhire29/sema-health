import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../data/seed/first_aid_display.dart';
import '../data/seed/first_aid_models.dart';
import '../data/seed/first_aid_repo.dart';
import '../data/seed/first_aid_repo_provider.dart';
import '../domain/triage/severity.dart';
import '../i18n/locale_scope.dart';
import '../theme/tokens.dart';
import '../widgets/first_aid_detail_sheet.dart';
import '../widgets/press_scale.dart';

class FirstAidScreen extends StatefulWidget {
  const FirstAidScreen({super.key});

  @override
  State<FirstAidScreen> createState() => _FirstAidScreenState();
}

class _FirstAidScreenState extends State<FirstAidScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  bool _showAll = false;

  static const _commonGridSize = 5;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
  }

  void _onQueryChanged() {
    final next = _searchController.text.trim().toLowerCase();
    if (next != _query) setState(() => _query = next);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onQueryChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FutureBuilder<FirstAidRepo>(
        future: firstAidRepoFuture(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error!);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          final repo = snapshot.data!;
          return _Body(
            tiles: _tilesFor(repo),
            query: _query,
            showAll: _showAll,
            commonGridSize: _commonGridSize,
            searchController: _searchController,
            searchFocus: _searchFocus,
            onClearSearch: () {
              _searchController.clear();
              _searchFocus.unfocus();
            },
            onShowAll: () => setState(() => _showAll = true),
            onCollapse: () => setState(() => _showAll = false),
            onOpenEntry: (id) {
              final entry = repo.getById(id);
              if (entry != null) {
                FirstAidDetailSheet.show(context, entry: entry);
              }
            },
          );
        },
      ),
    );
  }
}

FirstAidRepo? _cachedRepo;
List<_TileData>? _cachedTiles;

List<_TileData> _tilesFor(FirstAidRepo repo) {
  if (identical(_cachedRepo, repo) && _cachedTiles != null) {
    return _cachedTiles!;
  }
  _cachedRepo = repo;
  final ordered = _interleaveBySeverity(repo.all.toList());
  return _cachedTiles = [for (final e in ordered) _TileData.from(e)];
}

/// Bucket entries by severity, then round-robin through the buckets so
/// the grid surfaces a *mix* (red emergency, amber caution, sand
/// self-care…) instead of a wall of red.
///
/// The featured card still ends up showing the highest-severity entry
/// because emergencies are pulled first in each round — clinically
/// right (the most critical thing stays prominent), but the visible
/// grid below it alternates colors and severities so users learn the
/// catalog isn't only "panic" content.
///
/// Within each severity bucket we keep the entries' incoming order
/// (typically the YAML order) so the result is deterministic across
/// rebuilds — important since `_cachedTiles` keys off identity.
List<FirstAidEntry> _interleaveBySeverity(List<FirstAidEntry> all) {
  final buckets = <Severity, List<FirstAidEntry>>{
    for (final s in Severity.values) s: <FirstAidEntry>[],
  };
  for (final e in all) {
    buckets[e.severity]!.add(e);
  }
  // Round-robin order: emergency → high → medium → low → repeat.
  // Severity.values is enum-declaration order; reverse so most-urgent
  // pops first and the featured card lands on it.
  final order = Severity.values.reversed.toList();
  final out = <FirstAidEntry>[];
  var added = true;
  while (added) {
    added = false;
    for (final s in order) {
      final bucket = buckets[s]!;
      if (bucket.isEmpty) continue;
      out.add(bucket.removeAt(0));
      added = true;
    }
  }
  return out;
}

class _TileData {
  const _TileData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.surface,
    required this.ink,
    required this.subtitleColor,
    required this.duration,
    required this.isEmergency,
    required this.searchHaystack,
  });

  factory _TileData.from(FirstAidEntry e) {
    final display = FirstAidDisplay.forEntry(e);
    final accent = display.accent;
    final subtitle = _subtitleFor(e);
    return _TileData(
      id: e.id,
      title: e.title,
      subtitle: subtitle,
      icon: display.icon,
      surface: accent.surface,
      ink: accent.ink,
      subtitleColor: accent.ink.withValues(alpha: 0.65),
      duration: display.estimatedDuration,
      isEmergency: e.isEmergency,
      searchHaystack:
          '${e.title} $subtitle ${e.symptomSlugs.join(' ')}'.toLowerCase(),
    );
  }

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color surface;
  final Color ink;
  final Color subtitleColor;
  final String duration;
  final bool isEmergency;
  final String searchHaystack;
}

String _subtitleFor(FirstAidEntry entry) {
  final notes = entry.notes;
  if (notes != null && notes.isNotEmpty) {
    final firstSentence = notes.split(_sentenceBreak).first.trim();
    if (firstSentence.length <= 90) return firstSentence;
  }
  return switch (entry.severity) {
    Severity.emergency => 'Emergency · call services',
    Severity.high => 'Needs medical attention',
    Severity.medium => 'Monitor and care',
    Severity.low => 'Home self-care',
  };
}

final RegExp _sentenceBreak = RegExp(r'(?<=[.!?])\s');
final Color _pillSurface = Colors.white.withValues(alpha: 0.5);

class _Body extends StatelessWidget {
  const _Body({
    required this.tiles,
    required this.query,
    required this.showAll,
    required this.commonGridSize,
    required this.searchController,
    required this.searchFocus,
    required this.onClearSearch,
    required this.onShowAll,
    required this.onCollapse,
    required this.onOpenEntry,
  });

  final List<_TileData> tiles;
  final String query;
  final bool showAll;
  final int commonGridSize;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final VoidCallback onClearSearch;
  final VoidCallback onShowAll;
  final VoidCallback onCollapse;
  final ValueChanged<String> onOpenEntry;

  bool get _searching => query.isNotEmpty;
  List<_TileData> get _searchResults =>
      [for (final t in tiles) if (t.searchHaystack.contains(query)) t];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = LocaleScope.of(context).strings;
    final titleStyle = t.titleLarge?.copyWith(fontSize: 15, height: 1.2);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('firstAid.eyebrow'), style: t.labelMedium),
                const SizedBox(height: 8),
                RichText(
                  text: TextSpan(
                    style: t.displayMedium!.copyWith(
                      fontSize: 32, height: 1.12, letterSpacing: -1.2,
                    ),
                    children: [
                      TextSpan(text: s.t('firstAid.title.lead')),
                      TextSpan(
                        text: s.t('firstAid.title.emphasis'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(text: s.t('firstAid.title.tail')),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(s.t('firstAid.body'), style: t.bodyMedium),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          sliver: SliverToBoxAdapter(
            child: _SearchField(
              controller: searchController,
              focusNode: searchFocus,
              hasText: _searching,
              onClear: onClearSearch,
            ),
          ),
        ),
        if (_searching)
          ..._searchSlivers(context, titleStyle, t)
        else
          ..._browseSlivers(context, titleStyle, t),
      ],
    );
  }

  List<Widget> _browseSlivers(
    BuildContext context, TextStyle? titleStyle, TextTheme t,
  ) {
    if (tiles.isEmpty) return const [];
    final featured = tiles.first;
    final rest = tiles.skip(1).toList(growable: false);
    final commonCount = rest.length < commonGridSize ? rest.length : commonGridSize;
    final hidden = rest.length - commonCount;
    final visibleRest = showAll ? rest : rest.take(commonCount).toList();

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        sliver: SliverToBoxAdapter(
          child: _FeaturedCard(
            data: featured,
            onTap: () => onOpenEntry(featured.id),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        sliver: SliverToBoxAdapter(
          child: Text('Common', style: t.labelMedium),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, hidden > 0 || showAll ? 12 : 100),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 168,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => RepaintBoundary(
              child: _AidTile(
                data: visibleRest[i],
                titleStyle: titleStyle,
                onTap: () => onOpenEntry(visibleRest[i].id),
              ),
            ),
            childCount: visibleRest.length,
            addRepaintBoundaries: false,
          ),
        ),
      ),
      if (hidden > 0 || showAll)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
          sliver: SliverToBoxAdapter(
            child: _ShowAllButton(
              expanded: showAll,
              hiddenCount: hidden,
              onTap: showAll ? onCollapse : onShowAll,
            ),
          ),
        ),
    ];
  }

  List<Widget> _searchSlivers(
    BuildContext context, TextStyle? titleStyle, TextTheme t,
  ) {
    final results = _searchResults;
    if (results.isEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
          sliver: SliverToBoxAdapter(child: _NoResults(query: query)),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        sliver: SliverToBoxAdapter(
          child: Text(
            results.length == 1 ? '1 result' : '${results.length} results',
            style: t.labelMedium,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 168,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => RepaintBoundary(
              child: _AidTile(
                data: results[i],
                titleStyle: titleStyle,
                onTap: () => onOpenEntry(results[i].id),
              ),
            ),
            childCount: results.length,
            addRepaintBoundaries: false,
          ),
        ),
      ),
    ];
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.data, required this.onTap});
  final _TileData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 18, 20),
        decoration: BoxDecoration(
          color: data.surface,
          borderRadius: BorderRadius.circular(SemaRadii.xl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: _pillSurface,
                    borderRadius: BorderRadius.circular(SemaRadii.m),
                  ),
                  alignment: Alignment.center,
                  child: Icon(data.icon, size: 26, color: data.ink),
                ),
                const Spacer(),
                if (data.isEmergency)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 4,
                    ),
                    decoration: const BoxDecoration(
                      color: SemaColors.danger,
                      borderRadius: BorderRadius.all(
                        Radius.circular(SemaRadii.pill),
                      ),
                    ),
                    child: const Text(
                      'URGENT',
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              data.title,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: t.displayMedium!.copyWith(
                fontSize: 24, height: 1.1, letterSpacing: -0.6,
                fontWeight: FontWeight.w800, color: data.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              data.subtitle,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: data.subtitleColor,
                height: 1.35,
                letterSpacing: -0.05,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _pillSurface,
                    borderRadius: BorderRadius.circular(SemaRadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsRegular.play, size: 12, color: data.ink),
                      const SizedBox(width: 6),
                      Text(
                        data.duration,
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: data.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: data.ink,
                    borderRadius: BorderRadius.circular(SemaRadii.pill),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'Open guide',
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.05,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(
                        PhosphorIconsBold.arrowUpRight,
                        size: 12, color: Colors.white,
                      ),
                    ],
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

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hasText,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasText;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      decoration: BoxDecoration(
        color: SemaColors.card,
        borderRadius: BorderRadius.circular(SemaRadii.pill),
      ),
      child: Row(
        children: [
          const Icon(
            PhosphorIconsRegular.magnifyingGlass,
            size: 18, color: SemaColors.inkMid,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search first aid',
                border: InputBorder.none,
                isDense: true,
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: SemaColors.inkMuted,
                  letterSpacing: -0.1,
                ),
              ),
              style: const TextStyle(
                fontSize: 14, color: SemaColors.ink, letterSpacing: -0.1,
              ),
            ),
          ),
          if (hasText)
            IconButton(
              onPressed: onClear,
              icon: const Icon(
                PhosphorIconsRegular.x,
                size: 16, color: SemaColors.inkMid,
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            ),
        ],
      ),
    );
  }
}

class _ShowAllButton extends StatelessWidget {
  const _ShowAllButton({
    required this.expanded,
    required this.hiddenCount,
    required this.onTap,
  });

  final bool expanded;
  final int hiddenCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: SemaColors.bg,
          borderRadius: BorderRadius.circular(SemaRadii.pill),
          border: Border.all(color: SemaColors.hairline),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              expanded ? 'Show less' : 'Show all ($hiddenCount more)',
              style: const TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: SemaColors.ink,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              expanded
                  ? PhosphorIconsBold.caretUp
                  : PhosphorIconsBold.caretDown,
              size: 12, color: SemaColors.ink,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Column(
        children: [
          const Icon(
            PhosphorIconsRegular.magnifyingGlass,
            size: 36, color: SemaColors.inkSoft,
          ),
          const SizedBox(height: 12),
          Text(
            'No results for "$query"',
            style: t.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Try a different word — symptom, body part, or condition.',
            style: t.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AidTile extends StatelessWidget {
  const _AidTile({
    required this.data,
    required this.titleStyle,
    required this.onTap,
  });

  final _TileData data;
  final TextStyle? titleStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: data.surface,
          borderRadius: BorderRadius.circular(SemaRadii.l),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(data.icon, size: 26, color: data.ink),
                const Spacer(),
                Text(
                  data.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: titleStyle?.copyWith(color: data.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  data.subtitle,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: data.subtitleColor,
                    letterSpacing: -0.05,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _pillSurface,
                        borderRadius: BorderRadius.circular(SemaRadii.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIconsRegular.play,
                            size: 10, color: data.ink,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            data.duration,
                            style: TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: data.ink,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: data.ink, shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        PhosphorIconsBold.arrowUpRight,
                        size: 12, color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (data.isEmergency) const _UrgentPip(),
          ],
        ),
      ),
    );
  }
}

class _UrgentPip extends StatelessWidget {
  const _UrgentPip();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: const BoxDecoration(
          color: SemaColors.danger,
          borderRadius: BorderRadius.all(Radius.circular(SemaRadii.pill)),
        ),
        child: const Text(
          'URGENT',
          style: TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              PhosphorIconsRegular.warning,
              size: 36, color: SemaColors.danger,
            ),
            const SizedBox(height: 12),
            Text(
              "Couldn't load the first-aid library",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
