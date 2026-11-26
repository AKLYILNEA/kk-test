import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/detail/subject_detail_page.dart';
import 'package:koneko/features/discover/discover_page.dart';
import 'package:koneko/features/player/player_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_icon.dart';
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
  static const _tags = ['全部', '奇幻', '治愈', '日常', '科幻', '悬疑', '音乐'];
  String _selectedTag = '全部';

  void _openDetail(AnimeSubject subject) {
    Navigator.of(context).push(
      CardPageRoute<void>(
        builder: (_) => SubjectDetailPage(subjectId: subject.subjectId),
      ),
    );
  }

  void _openPlayer(AnimeSubject subject, int episode, String ruleId, String ruleName) {
    Navigator.of(context).push(
      CardPageRoute<void>(
        builder: (_) => PlayerPage(
          subjectId: subject.subjectId,
          initialEpisode: episode,
          initialRuleId: ruleId,
          initialRuleName: ruleName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final catalog = ref.watch(catalogRepositoryProvider);
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

    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
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
            slivers: [
              SliverToBoxAdapter(
                child: KonekoPageHeader(
                  title: '推荐',
                  subtitle: '2026 秋季新番 · 纯净 prism_ui 视图',
                  actions: [
                    KonekoCircleButton(
                      glyph: Glyphs.search,
                      tooltip: '发现搜索',
                      onPressed: () {
                        Navigator.of(context).push(
                          CardPageRoute<void>(
                            builder: (_) => const DiscoverPage(),
                          ),
                        );
                      },
                    ),
                    KonekoCircleButton(
                      glyph: KonekoGlyphs.refresh,
                      tooltip: '刷新榜单',
                      onPressed: () {
                        showKonekoBanner(
                          context,
                          '已刷新 2026 秋季热门榜单',
                          level: BannerLevel.success,
                        );
                      },
                    ),
                  ],
                ),
              ),
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
                        latestHistory?.lastRuleId ?? 'rule_yhdmp',
                        latestHistory?.lastRuleName ?? '樱花源 · XPath',
                      ),
                      onOpenDetail: () => _openDetail(resumeSubject),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 36,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: _tags.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, index) {
                      final tag = _tags[index];
                      return KonekoChip(
                        label: tag,
                        height: 34,
                        fontSize: 13,
                        selected: tag == _selectedTag,
                        backgroundColor: tag == _selectedTag
                            ? colorScheme.primary
                            : SurfaceLevel.card.colorOf(colorScheme),
                        onPressed: () => setState(() => _selectedTag = tag),
                      );
                    },
                  ),
                ),
              ),
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
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final subject = subjects[index];
                      return UnifiedAnimeCard(
                        subject: subject,
                        isTracking: trackingIds.contains(subject.subjectId),
                        showTopRank: _selectedTag == '全部',
                        onTap: () => _openDetail(subject),
                      );
                    },
                    childCount: subjects.length,
                  ),
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
    final pct = ((history?.progressRatio ?? 0.62) * 100).round();
    final timeLabel = history != null
        ? '${formatDurationShort(history!.lastPositionSeconds)} / ${formatDurationShort(history!.lastDurationSeconds)}'
        : '00:00 / 23:45';

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
                          label: '继续观看',
                          height: 22,
                          fontSize: 10.5,
                          backgroundColor:
                              colorScheme.primary.withValues(alpha: 0.14),
                          foregroundColor: colorScheme.primary,
                        ),
                        if (history != null && history!.mergedSourceCount > 1)
                          KonekoChip(
                            label: '合并 ${history!.mergedSourceCount} 源',
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
                      '第 $ep 话 · $timeLabel · ${history?.lastRuleName ?? '樱花源'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.footnote.of(context).copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              KonekoCircleButton(
                size: 46,
                iconSize: 20,
                icon: KonekoIcons.play,
                fillColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                tooltip: '立即续播',
                onPressed: onResume,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: KonekoBlock(
                  corner: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    spacing: 6,
                    children: [
                      Flexible(
                        child: Text(
                          '在追',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.caption1.of(context).copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        '$watchingCount 部',
                        maxLines: 1,
                        style: AppTextStyle.subheadline
                            .of(context, emphasized: true)
                            .copyWith(color: colorScheme.onSurface),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: KonekoBlock(
                  corner: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    spacing: 6,
                    children: [
                      Flexible(
                        child: Text(
                          '规则',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.caption1.of(context).copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        '$enabledRulesCount 源 · $pct%',
                        maxLines: 1,
                        style: AppTextStyle.subheadline
                            .of(context, emphasized: true)
                            .copyWith(color: colorScheme.primary),
                      ),
                    ],
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
