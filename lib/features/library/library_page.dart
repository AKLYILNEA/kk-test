import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/my/service_settings_page.dart';
import 'package:koneko/features/detail/subject_detail_page.dart';
import 'package:koneko/features/player/player_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

/// Pure FlClash responsive Library page (03-library-collect):
/// Completely escapes Kazumi's secondary toolbar & grid/list toggle button.
/// Uses minimal floating top circular action buttons, horizontal category pills,
/// and responsive 1 / 2 / 3-column FlClash cards with inline progress & direct resume.
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key, this.bottomPadding = 0});

  final double bottomPadding;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  CollectionStatus? _filter = CollectionStatus.watching;
  bool _showSearch = false;
  bool _sortByRecent = true;
  String _query = '';

  static const _tabs = <(CollectionStatus?, String)>[
    (CollectionStatus.watching, '在看'),
    (CollectionStatus.wish, '想看'),
    (CollectionStatus.watched, '看过'),
    (CollectionStatus.onHold, '搁置'),
    (null, '全部'),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    ref.watch(catalogUpdatesProvider);
    final catalog = ref.watch(catalogRepositoryProvider);
    final entries = ref.watch(libraryProvider);
    final history = ref.watch(historyProvider);

    int countOf(CollectionStatus? status) => status == null
        ? entries.length
        : entries.where((e) => e.status == status).length;

    final filtered = entries.where((entry) {
      if (_filter != null && entry.status != _filter) return false;
      final subject = catalog.getSubjectById(entry.subjectId);
      if (subject == null) return false;
      if (_query.trim().isEmpty) return true;
      final q = _query.trim().toLowerCase();
      return subject.title.toLowerCase().contains(q) ||
          subject.originalTitle.toLowerCase().contains(q);
    }).toList();

    if (_sortByRecent) {
      filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } else {
      filtered.sort((a, b) {
        final sa = catalog.getSubjectById(a.subjectId)?.score ?? 0;
        final sb = catalog.getSubjectById(b.subjectId)?.score ?? 0;
        return sb.compareTo(sa);
      });
    }

    return KonekoScaffold(
      title: '追番',
      actions: [
        IconButtonData(
          glyph: Glyphs.search,
          tooltip: '筛选收藏',
          onPressed: () => setState(() => _showSearch = !_showSearch),
        ),
        IconButtonData(
          glyph: Glyphs.sort,
          tooltip: _sortByRecent ? '当前：最近观看' : '当前：按评分排序',
          onPressed: () {
            setState(() => _sortByRecent = !_sortByRecent);
            showKonekoBanner(
              context,
              _sortByRecent ? '已切换为：最近观看排序' : '已切换为：评分优先排序',
            );
          },
        ),
        IconButtonData(
          glyph: KonekoGlyphs.sync,
          tooltip: '同步 Bangumi',
          onPressed: () =>
              BaseNavigator.push<void>(context, const ServiceSettingsPage()),
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns = width >= 1080
              ? 3
              : width >= 700
              ? 2
              : 1;

          return CustomScrollView(
            cacheExtent: 600,
            slivers: [
              const KonekoScrollStart(),
              if (_showSearch)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: SearchField(
                      fill: SurfaceLevel.card.colorOf(colorScheme),
                      hintText: '筛选追番库...',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 40,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    scrollDirection: Axis.horizontal,
                    itemCount: _tabs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, index) {
                      final (status, label) = _tabs[index];
                      final selected = status == _filter;
                      return KonekoChip(
                        label: '$label  ${countOf(status)}',
                        height: 36,
                        fontSize: 13,
                        selected: selected,
                        backgroundColor: selected
                            ? colorScheme.primary
                            : SurfaceLevel.card.colorOf(colorScheme),
                        onPressed: () => setState(() => _filter = status),
                      );
                    },
                  ),
                ),
              ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      '该分类下暂无番剧',
                      style: AppTextStyle.subheadline
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    14,
                    16,
                    24 + widget.bottomPadding,
                  ),
                  sliver: columns == 1
                      ? SliverList.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final entry = filtered[index];
                            final subject = catalog.getSubjectById(
                              entry.subjectId,
                            )!;
                            final hist = history
                                .where((h) => h.subjectId == entry.subjectId)
                                .firstOrNull;
                            return _FlClashWatchCard(
                              subject: subject,
                              entry: entry,
                              history: hist,
                              onOpenDetail: () => _openDetail(subject),
                              onQuickPlay: () => _openPlayer(
                                subject,
                                hist?.lastEpisode ??
                                    (entry.watchedEpisodes > 0
                                        ? entry.watchedEpisodes
                                        : 1),
                                hist?.lastRuleId ?? 'rule_yhdmp',
                                hist?.lastRuleName ?? '樱花源 · XPath',
                              ),
                              onCycleStatus: () {
                                const values = CollectionStatus.values;
                                final next =
                                    values[(values.indexOf(entry.status) + 1) %
                                        4];
                                ref
                                    .read(libraryProvider.notifier)
                                    .setStatus(entry.subjectId, next);
                              },
                            );
                          },
                        )
                      : SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                mainAxisExtent: 186,
                              ),
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final entry = filtered[index];
                            final subject = catalog.getSubjectById(
                              entry.subjectId,
                            )!;
                            final hist = history
                                .where((h) => h.subjectId == entry.subjectId)
                                .firstOrNull;
                            return _FlClashWatchCard(
                              subject: subject,
                              entry: entry,
                              history: hist,
                              onOpenDetail: () => _openDetail(subject),
                              onQuickPlay: () => _openPlayer(
                                subject,
                                hist?.lastEpisode ??
                                    (entry.watchedEpisodes > 0
                                        ? entry.watchedEpisodes
                                        : 1),
                                hist?.lastRuleId ?? 'rule_yhdmp',
                                hist?.lastRuleName ?? '樱花源 · XPath',
                              ),
                              onCycleStatus: () {
                                const values = CollectionStatus.values;
                                final next =
                                    values[(values.indexOf(entry.status) + 1) %
                                        4];
                                ref
                                    .read(libraryProvider.notifier)
                                    .setStatus(entry.subjectId, next);
                              },
                            );
                          }, childCount: filtered.length),
                        ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _openDetail(AnimeSubject subject) {
    BaseNavigator.push<void>(
      context,
      SubjectDetailPage(subjectId: subject.subjectId),
    );
  }

  void _openPlayer(
    AnimeSubject subject,
    int episode,
    String ruleId,
    String ruleName,
  ) {
    BaseNavigator.push<void>(
      context,
      PlayerPage(
        subjectId: subject.subjectId,
        initialEpisode: episode,
        initialRuleId: ruleId,
        initialRuleName: ruleName,
      ),
    );
  }
}

class _FlClashWatchCard extends StatelessWidget {
  const _FlClashWatchCard({
    required this.subject,
    required this.entry,
    required this.history,
    required this.onOpenDetail,
    required this.onQuickPlay,
    required this.onCycleStatus,
  });

  final AnimeSubject subject;
  final CollectionEntry entry;
  final MergedHistoryEntry? history;
  final VoidCallback onOpenDetail;
  final VoidCallback onQuickPlay;
  final VoidCallback onCycleStatus;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final total = subject.totalEpisodes > 0 ? subject.totalEpisodes : 12;
    final ratio = (entry.watchedEpisodes / total).clamp(0.0, 1.0);
    final pct = (ratio * 100).round();

    final String progressText;
    if (entry.watchedEpisodes <= 0) {
      progressText = '尚未开始 · 更新至第 ${subject.airedEpisodes} 话';
    } else if (entry.watchedEpisodes >= total) {
      progressText = '已看完 · 共 $total 话';
    } else {
      progressText = '看到 第 ${entry.watchedEpisodes} 话 · 共 $total 话';
    }

    return KonekoCard(
      corner: 26,
      padding: const EdgeInsets.all(14),
      onPressed: onOpenDetail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                height: 90,
                child: KonekoPosterArt(
                  subject: subject,
                  borderRadius: AppRadius.all(16),
                  overlayBadges: [
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: KonekoChip(
                        label: subject.score.toStringAsFixed(1),
                        height: 18,
                        fontSize: 9.5,
                        backgroundColor: Colors.black.withValues(alpha: 0.62),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.callout
                          .of(context, emphasized: true)
                          .copyWith(color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subject.originalTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption1
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        KonekoChip(
                          label: entry.status.label,
                          height: 24,
                          fontSize: 11,
                          backgroundColor: colorScheme.primary.withValues(
                            alpha: 0.14,
                          ),
                          foregroundColor: colorScheme.primary,
                          trailing: GlyphIcon(
                            Glyphs.chevronDown,
                            size: 12,
                            color: colorScheme.primary,
                          ),
                          onPressed: onCycleStatus,
                        ),
                        KonekoChip(
                          label: subject.isCompleted
                              ? '${subject.year} 年'
                              : '更至 ${subject.airedEpisodes} 话',
                          height: 24,
                          fontSize: 11,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          KonekoBlock(
            corner: 18,
            padding: const EdgeInsets.fromLTRB(12, 8, 9, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              progressText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.caption1
                                  .of(context, emphasized: true)
                                  .copyWith(
                                    color: entry.watchedEpisodes > 0
                                        ? colorScheme.onSurface
                                        : colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$pct%',
                            style: AppTextStyle.caption1
                                .of(context, emphasized: true)
                                .copyWith(
                                  color: entry.watchedEpisodes > 0
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: AppRadius.full,
                        child: Container(
                          height: 4.5,
                          color: colorScheme.primary.withValues(alpha: 0.12),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: ratio,
                            child: Container(color: colorScheme.primary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                KonekoCircleButton(
                  size: 34,
                  iconSize: 15,
                  glyph: KonekoGlyphs.play,
                  fillColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  tooltip: '续播',
                  onPressed: onQuickPlay,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
