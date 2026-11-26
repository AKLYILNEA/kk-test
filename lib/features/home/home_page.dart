import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/detail/subject_detail_page.dart';
import 'package:koneko/features/discover/discover_page.dart';
import 'package:koneko/features/player/player_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key, this.bottomPadding = 0});

  final double bottomPadding;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  static const _tags = [
    '全部',
    '奇幻',
    '治愈',
    '日常',
    '恋爱',
    '校园',
    '科幻',
    '悬疑',
    '喜剧',
    '音乐',
    '冒险',
    '动作',
  ];
  String _selectedTag = '全部';

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

  @override
  Widget build(BuildContext context) {
    ref.watch(catalogUpdatesProvider);
    final catalog = ref.watch(catalogRepositoryProvider);
    final loading = ref.watch(loadHomeCatalogProvider);
    final library = ref.watch(libraryProvider);
    final history = ref.watch(historyProvider);
    final rules = ref.watch(rulesProvider);

    final subjects = catalog.getTrending(tag: _selectedTag);
    final trackingIds = {
      for (final e in library)
        if (e.status == CollectionStatus.watching) e.subjectId,
    };
    final latestHistory = history.isNotEmpty ? history.first : null;
    final resumeSubject = latestHistory != null
        ? catalog.getSubjectById(latestHistory.subjectId)
        : (subjects.isNotEmpty ? subjects.first : null);
    final enabledRulesCount = rules.where((r) => r.enabled).length;

    return KonekoScaffold(
      title: '推荐',
      actions: [
        IconButtonData(
          glyph: Glyphs.search,
          tooltip: '发现搜索',
          onPressed: () {
            BaseNavigator.push<void>(context, const DiscoverPage());
          },
        ),
        IconButtonData(
          glyph: KonekoGlyphs.refresh,
          tooltip: '刷新榜单',
          isLoading: loading.isLoading && subjects.isEmpty,
          onPressed: () => ref.invalidate(loadHomeCatalogProvider),
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final crossAxisCount = width >= 1020
              ? 5
              : width >= 760
              ? 4
              : width >= 500
              ? 3
              : 2;

          return CustomScrollView(
            scrollCacheExtent: const ScrollCacheExtent.pixels(800),
            slivers: [
              const KonekoScrollStart(),
              if (resumeSubject != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: _TopSummaryDeck(
                      subject: resumeSubject,
                      history: latestHistory,
                      watchingCount: trackingIds.length,
                      enabledRulesCount: enabledRulesCount,
                      onResume: () => _openPlayer(
                        resumeSubject,
                        latestHistory?.lastEpisode ?? 1,
                        latestHistory?.lastRuleId ?? '',
                        latestHistory?.lastRuleName ?? '',
                      ),
                      onOpenDetail: () => _openDetail(resumeSubject),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: KonekoAutoScrollChipBar(
                  height: 40,
                  chipHeight: 34,
                  fontSize: 13,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  labels: _tags,
                  selectedIndex: _tags
                      .indexOf(_selectedTag)
                      .clamp(0, _tags.length - 1)
                      .toInt(),
                  onSelected: (index) =>
                      setState(() => _selectedTag = _tags[index]),
                ),
              ),
              if (subjects.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: loading.isLoading
                        ? const ActivityIndicator()
                        : Text(
                            loading.hasError ? '番剧目录加载失败，点右上角重试' : '此分类暂无番剧',
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
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.56,
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final subject = subjects[index];
                      return UnifiedAnimeCard(
                        subject: subject,
                        isTracking: trackingIds.contains(subject.subjectId),
                        showTopRank: _selectedTag == '全部',
                        onTap: () => _openDetail(subject),
                      );
                    }, childCount: subjects.length),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TopSummaryDeck extends StatelessWidget {
  const _TopSummaryDeck({
    required this.subject,
    required this.history,
    required this.watchingCount,
    required this.enabledRulesCount,
    required this.onResume,
    required this.onOpenDetail,
  });

  final AnimeSubject subject;
  final MergedHistoryEntry? history;
  final int watchingCount;
  final int enabledRulesCount;
  final VoidCallback onResume;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final ep = history?.lastEpisode ?? 1;
    final ratio = (history?.progressRatio ?? 0.0).clamp(0.0, 1.0);
    final pct = (ratio * 100).round();
    final timeLabel = history != null
        ? '${formatDurationShort(history!.lastPositionSeconds)} / ${formatDurationShort(history!.lastDurationSeconds)}'
        : '尚未观看';
    final ruleLabel = history?.lastRuleName.trim() ?? '';

    return KonekoCard(
      corner: 28,
      padding: const EdgeInsets.all(16),
      onPressed: onOpenDetail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 58,
                height: 82,
                child: KonekoPosterArt(
                  subject: subject,
                  borderRadius: AppRadius.all(14),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        KonekoChip(
                          label: history != null ? '继续观看' : '推荐观看',
                          height: 22,
                          fontSize: 10.5,
                          backgroundColor: colorScheme.primary.withValues(
                            alpha: 0.14,
                          ),
                          foregroundColor: colorScheme.primary,
                        ),
                        if (ruleLabel.isNotEmpty)
                          KonekoChip(
                            label: ruleLabel,
                            height: 22,
                            fontSize: 10.5,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subject.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.headline
                          .of(context, emphasized: true)
                          .copyWith(color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      history != null
                          ? '第 $ep 话 · $timeLabel ($pct%)'
                          : subjectMetaCaption(subject),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              KonekoCircleButton(
                size: 46,
                iconSize: 20,
                glyph: KonekoGlyphs.play,
                fillColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                tooltip: '立即续播',
                onPressed: onResume,
              ),
            ],
          ),
          if (history != null) ...[
            const SizedBox(height: 11),
            ClipRRect(
              borderRadius: AppRadius.full,
              child: Container(
                height: 5,
                color: colorScheme.primary.withValues(alpha: 0.14),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(color: colorScheme.primary),
                ),
              ),
            ),
          ],
          const SizedBox(height: 11),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                Expanded(
                  child: _SummaryStat(label: '在追', value: '$watchingCount 部'),
                ),
                Expanded(
                  child: _SummaryStat(
                    label: '已启用规则',
                    value: '$enabledRulesCount 个源',
                    color: colorScheme.primary,
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

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return KonekoBlock(
      corner: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(
                label,
                style: AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: context.colorScheme.onSurfaceVariant),
              ),
              Text(
                value,
                style: AppTextStyle.subheadline
                    .of(context, emphasized: true)
                    .copyWith(color: color ?? context.colorScheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
