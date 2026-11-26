import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/player/player_page.dart';
import 'package:koneko/features/player/rule_verify_page.dart';
import 'package:koneko/features/rules/rules_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_image.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

enum _DetailSection { overview, comments }

class SubjectDetailPage extends ConsumerStatefulWidget {
  const SubjectDetailPage({super.key, required this.subjectId});

  final int subjectId;

  @override
  ConsumerState<SubjectDetailPage> createState() => _SubjectDetailPageState();
}

class _SubjectDetailPageState extends ConsumerState<SubjectDetailPage> {
  String _selectedRuleId = '';
  String _selectedRuleName = '';
  _DetailSection _section = _DetailSection.overview;

  // Live parallel probe results per enabled rule (mirrors PlayerPage).
  final Map<String, RuleProbeResult> _liveProbes = {};
  int _probeGeneration = 0;
  int? _probedSubjectId;

  // Pagination state for Bangumi comments beyond the first page.
  List<SubjectComment>? _extraComments;
  int? _extraTotal;
  bool _extraHasMore = false;
  bool _loadingMoreComments = false;

  @override
  void dispose() {
    _probeGeneration++;
    super.dispose();
  }

  void _ensureProbed(AnimeSubject subject) {
    if (_probedSubjectId == subject.subjectId) return;
    _probedSubjectId = subject.subjectId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_probeAllEnabledRules(subject));
    });
  }

  Future<void> _probeAllEnabledRules(AnimeSubject subject) async {
    final resolver = ref.read(playbackSourcesProvider);
    if (resolver == null) return;
    final enabledRules = ref
        .read(rulesProvider)
        .where((r) => r.enabled)
        .toList();
    if (enabledRules.isEmpty) {
      if (mounted) setState(() => _liveProbes.clear());
      return;
    }

    final gen = ++_probeGeneration;
    setState(() {
      _liveProbes
        ..clear()
        ..addEntries(
          enabledRules.map(
            (r) => MapEntry(
              r.id,
              RuleProbeResult(
                ruleId: r.id,
                ruleName: r.name,
                state: RuleProbeState.searching,
                message: '正在检测可用性...',
              ),
            ),
          ),
        );
    });

    await Future.wait(
      enabledRules.map((rule) async {
        final result = await resolver.probeRule(subject, rule.id);
        if (!mounted || gen != _probeGeneration) return;
        setState(() => _liveProbes[rule.id] = result);
      }),
    );
  }

  Future<void> _verifyRule(
    AnimeSubject subject,
    String ruleId,
    String ruleName,
    Uri verifyUrl,
  ) async {
    final verified = await showRuleVerifySheet(
      context: context,
      ruleId: ruleId,
      ruleName: ruleName,
      verifyUrl: verifyUrl,
    );
    if (!mounted || verified != true) return;
    showKonekoBanner(
      context,
      '$ruleName 验证已保存，正在重新检测',
      level: BannerLevel.success,
    );
    final resolver = ref.read(playbackSourcesProvider);
    if (resolver == null) return;
    setState(() {
      _liveProbes[ruleId] = RuleProbeResult(
        ruleId: ruleId,
        ruleName: ruleName,
        state: RuleProbeState.searching,
        message: '验证通过，重新检索中...',
      );
    });
    final result = await resolver.probeRule(subject, ruleId);
    if (!mounted) return;
    setState(() => _liveProbes[ruleId] = result);
  }

  void _playEpisode(AnimeSubject subject, int episodeNumber) {
    BaseNavigator.push<void>(
      context,
      PlayerPage(
        subjectId: subject.subjectId,
        initialEpisode: episodeNumber,
        initialRuleId: _selectedRuleId,
        initialRuleName: _selectedRuleName,
      ),
    );
  }

  Future<void> _loadMoreComments(int currentCount) async {
    if (_loadingMoreComments) return;
    final online = ref.read(onlineCatalogProvider);
    if (online == null) return;
    setState(() => _loadingMoreComments = true);
    try {
      final page = await online.loadComments(
        widget.subjectId,
        offset: currentCount,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        _extraComments = page.items;
        _extraTotal = page.total;
        _extraHasMore = page.hasMore;
      });
    } on Object {
      if (mounted) {
        showKonekoBanner(context, '加载更多评论失败，请稍后重试', level: BannerLevel.error);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingMoreComments = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(catalogUpdatesProvider);
    final catalog = ref.watch(catalogRepositoryProvider);
    final library = ref.watch(libraryProvider);
    final history = ref.watch(historyProvider);

    final load = ref.watch(loadCatalogSubjectProvider(widget.subjectId));
    final commentsAsync = ref.watch(subjectCommentsProvider(widget.subjectId));
    final subject = catalog.getSubjectById(widget.subjectId);
    if (subject == null) {
      return KonekoScaffold(
        title: '番剧详情',
        showBack: true,
        body: Center(
          child: load.isLoading
              ? const ActivityIndicator()
              : TextButton(
                  onPressed: () => ref.invalidate(
                    loadCatalogSubjectProvider(widget.subjectId),
                  ),
                  child: const Text('番剧资料暂不可用，点此重试'),
                ),
        ),
      );
    }

    final hasLiveResolver = ref.watch(playbackSourcesProvider) != null;
    if (hasLiveResolver) {
      _ensureProbed(subject);
    }

    final entry = library
        .where((e) => e.subjectId == subject.subjectId)
        .firstOrNull;
    final hist = history
        .where((h) => h.subjectId == subject.subjectId)
        .firstOrNull;

    final currentEp =
        hist?.lastEpisode ??
        ((entry?.watchedEpisodes ?? 0) > 0 ? entry!.watchedEpisodes : 1);
    final hasHistory = hist != null || (entry?.watchedEpisodes ?? 0) > 0;
    final episodes = catalog.getEpisodes(
      subject.subjectId,
      watchedCount: entry?.watchedEpisodes ?? 0,
      currentEp: currentEp,
    );
    final enabledRules = ref
        .watch(rulesProvider)
        .where((rule) => rule.enabled)
        .toList();
    final mockProbes = hasLiveResolver
        ? const <RuleSourceProbe>[]
        : catalog.probeSources(subject.subjectId);
    final related = subject.relatedIds
        .map(catalog.getSubjectById)
        .whereType<AnimeSubject>()
        .toList();

    final commentCount =
        _extraTotal ??
        commentsAsync.value?.total ??
        catalog.getComments(subject.subjectId).length;
    final commentsTabLabel = commentCount > 0
        ? '评论吐槽 ($commentCount)'
        : '评论吐槽';

    return KonekoScaffold(
      title: '番剧详情',
      showBack: true,
      actions: [
        IconButtonData(
          glyph: KonekoGlyphs.play,
          tooltip: '播放第 $currentEp 话',
          onPressed: () => _playEpisode(subject, currentEp),
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          final heroCard = _HeroCard(
            subject: subject,
            entry: entry,
            currentEp: currentEp,
            hasHistory: hasHistory,
            onPlay: () => _playEpisode(subject, currentEp),
            onStatusChanged: (status) {
              ref
                  .read(libraryProvider.notifier)
                  .setStatus(subject.subjectId, status);
              showKonekoBanner(
                context,
                '已将《${subject.title}》标记为「${status.label}」',
                level: BannerLevel.success,
              );
            },
          );
          final episodeCard = _EpisodeMatrixCard(
            episodes: episodes,
            onSelect: (ep) => _playEpisode(subject, ep.episodeNumber),
          );
          final sourcesCard = _RuleSourcesCard(
            hasLiveResolver: hasLiveResolver,
            enabledRules: enabledRules,
            liveProbes: _liveProbes,
            mockProbes: mockProbes,
            selectedRuleId: _selectedRuleId,
            selectedRuleName: _selectedRuleName,
            onRefresh: () => unawaited(_probeAllEnabledRules(subject)),
            onManage: () async {
              await BaseNavigator.push<void>(
                context,
                const RulesPage(showBack: true),
              );
              if (mounted && hasLiveResolver) {
                unawaited(_probeAllEnabledRules(subject));
              }
            },
            onVerify: (ruleId, ruleName, verifyUrl) =>
                unawaited(_verifyRule(subject, ruleId, ruleName, verifyUrl)),
            onToggleSelect: (ruleId, ruleName) {
              if (_selectedRuleId == ruleId) {
                setState(() {
                  _selectedRuleId = '';
                  _selectedRuleName = '';
                });
                showKonekoBanner(context, '已取消指定播放源，将自动沿用上次线路');
              } else {
                setState(() {
                  _selectedRuleId = ruleId;
                  _selectedRuleName = ruleName;
                });
                showKonekoBanner(context, '已指定播放源：$ruleName（再次点击可取消）');
              }
            },
          );
          final relatedCard = related.isEmpty
              ? null
              : _RelatedSeriesCard(
                  subjects: related,
                  onOpen: (s) => BaseNavigator.push<void>(
                    context,
                    SubjectDetailPage(subjectId: s.subjectId),
                  ),
                );

          final commentsCard = _CommentsSectionCard(
            commentsAsync: commentsAsync,
            overrideItems: _extraComments,
            overrideTotal: _extraTotal,
            overrideHasMore: _extraComments != null ? _extraHasMore : null,
            loadingMore: _loadingMoreComments,
            onRefresh: () {
              setState(() {
                _extraComments = null;
                _extraTotal = null;
                _extraHasMore = false;
              });
              ref.invalidate(subjectCommentsProvider(widget.subjectId));
            },
            onLoadMore: (count) => _loadMoreComments(count),
          );

          final sectionSwitcher = KonekoSegmentedBar<_DetailSection>(
            segments: [
              const (_DetailSection.overview, '选集与播放源'),
              (_DetailSection.comments, commentsTabLabel),
            ],
            value: _section,
            onChanged: (value) => setState(() => _section = value),
          );

          return CustomScrollView(
            scrollCacheExtent: const ScrollCacheExtent.pixels(600),
            slivers: [
              const KonekoScrollStart(),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  6,
                  16,
                  28 + MediaQuery.paddingOf(context).bottom,
                ),
                sliver: SliverToBoxAdapter(
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 12,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                spacing: 16,
                                children: [
                                  heroCard,
                                  sectionSwitcher,
                                  if (_section == _DetailSection.overview) ...[
                                    episodeCard,
                                    ?relatedCard,
                                  ] else
                                    commentsCard,
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 7,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                spacing: 16,
                                children: [sourcesCard],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 14,
                          children: [
                            heroCard,
                            sectionSwitcher,
                            if (_section == _DetailSection.overview) ...[
                              episodeCard,
                              sourcesCard,
                              ?relatedCard,
                            ] else
                              commentsCard,
                          ],
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

class _HeroCard extends StatefulWidget {
  const _HeroCard({
    required this.subject,
    required this.entry,
    required this.currentEp,
    required this.hasHistory,
    required this.onPlay,
    required this.onStatusChanged,
  });

  final AnimeSubject subject;
  final CollectionEntry? entry;
  final int currentEp;
  final bool hasHistory;
  final VoidCallback onPlay;
  final ValueChanged<CollectionStatus> onStatusChanged;

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  bool _summaryExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final subject = widget.subject;
    final summary = subject.summary.trim();
    final summaryStyle = AppTextStyle.subheadline
        .of(context)
        .copyWith(color: colorScheme.onSurfaceVariant, height: 1.55);

    return KonekoCard(
      corner: 30,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 104,
                height: 148,
                child: KonekoPosterArt(
                  subject: subject,
                  borderRadius: AppRadius.all(18),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 148),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subject.title,
                            style: AppTextStyle.title3
                                .of(context, emphasized: true)
                                .copyWith(
                                  color: colorScheme.onSurface,
                                  height: 1.26,
                                ),
                          ),
                          if (subject.originalTitle.trim().isNotEmpty &&
                              subject.originalTitle.trim() !=
                                  subject.title.trim()) ...[
                            const SizedBox(height: 5),
                            Text(
                              subject.originalTitle,
                              style: AppTextStyle.footnote
                                  .of(context)
                                  .copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    height: 1.32,
                                  ),
                            ),
                          ],
                        ],
                      ),
                      if (subject.score > 0 || subject.rank > 0) ...[
                        const SizedBox(height: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 6,
                          children: [
                            if (subject.score > 0)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 7,
                                children: [
                                  KonekoStarRating(
                                    score: subject.score,
                                    starSize: 16,
                                    spacing: 2,
                                  ),
                                  Text(
                                    subject.score.toStringAsFixed(1),
                                    style: AppTextStyle.headline
                                        .of(context, emphasized: true)
                                        .copyWith(
                                          color: colorScheme.onSurface,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                  ),
                                ],
                              ),
                            if (subject.rank > 0)
                              KonekoChip(
                                label: 'Bangumi Rank #${subject.rank}',
                                height: 22,
                                fontSize: 11,
                                backgroundColor: colorScheme.primary.withValues(
                                  alpha: 0.12,
                                ),
                                foregroundColor: colorScheme.primary,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (subject.year > 0 ||
              subject.studio.trim().isNotEmpty ||
              subject.totalEpisodes > 0) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (subject.year > 0)
                  KonekoChip(
                    label: subject.seasonLabel.isNotEmpty
                        ? subject.seasonLabel
                        : '${subject.year} 年',
                  ),
                if (subject.studio.trim().isNotEmpty)
                  KonekoChip(label: subject.studio.trim()),
                if (subject.totalEpisodes > 0)
                  KonekoChip(label: '共 ${subject.totalEpisodes} 话'),
              ],
            ),
          ],
          const SizedBox(height: 16),
          PressSurface(
            fill: colorScheme.primary,
            shape: AppShape.full,
            clipsChild: true,
            onPressed: widget.onPlay,
            child: SizedBox(
              height: 46,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 8,
                children: [
                  GlyphIcon(
                    KonekoGlyphs.play,
                    size: 16,
                    color: colorScheme.onPrimary,
                  ),
                  Text(
                    widget.hasHistory
                        ? '继续播放 · 第 ${widget.currentEp} 话'
                        : '立即播放 · 第 ${widget.currentEp} 话',
                    style: AppTextStyle.callout
                        .of(context, emphasized: true)
                        .copyWith(color: colorScheme.onPrimary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            spacing: 8,
            children: [
              for (final status in const [
                CollectionStatus.watching,
                CollectionStatus.wish,
                CollectionStatus.watched,
                CollectionStatus.onHold,
              ])
                Expanded(
                  child: KonekoChip(
                    label: status.label,
                    height: 34,
                    fontSize: 12.5,
                    selected: widget.entry?.status == status,
                    onPressed: () => widget.onStatusChanged(status),
                  ),
                ),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 14),
            KonekoBlock(
              corner: 18,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final painter = TextPainter(
                    text: TextSpan(text: summary, style: summaryStyle),
                    maxLines: 3,
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                  )..layout(maxWidth: constraints.maxWidth);
                  final overflows = painter.didExceedMaxLines;
                  painter.dispose();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: Text(
                          summary,
                          maxLines: _summaryExpanded ? null : 3,
                          overflow: _summaryExpanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: summaryStyle,
                        ),
                      ),
                      if (overflows) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: KonekoChip(
                            label: _summaryExpanded ? '收起简介' : '展开全部简介',
                            height: 26,
                            fontSize: 11.5,
                            backgroundColor: colorScheme.primary.withValues(
                              alpha: 0.12,
                            ),
                            foregroundColor: colorScheme.primary,
                            trailing: Transform.rotate(
                              angle: _summaryExpanded ? 3.14159 : 0,
                              child: GlyphIcon(
                                Glyphs.chevronDown,
                                size: 12,
                                color: colorScheme.primary,
                              ),
                            ),
                            onPressed: () => setState(
                              () => _summaryExpanded = !_summaryExpanded,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
          if (subject.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in subject.tags.take(8))
                  KonekoChip(label: tag, height: 24, fontSize: 11),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EpisodeMatrixCard extends StatefulWidget {
  const _EpisodeMatrixCard({required this.episodes, required this.onSelect});

  final List<EpisodeItem> episodes;
  final ValueChanged<EpisodeItem> onSelect;

  @override
  State<_EpisodeMatrixCard> createState() => _EpisodeMatrixCardState();
}

class _EpisodeMatrixCardState extends State<_EpisodeMatrixCard> {
  static const int _pageSize = 24;
  int _pageIndex = 0;

  @override
  void didUpdateWidget(covariant _EpisodeMatrixCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final totalPages = (widget.episodes.length / _pageSize).ceil();
    if (totalPages > 0 && _pageIndex >= totalPages) {
      _pageIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final episodes = widget.episodes;
    final totalPages = (episodes.length / _pageSize).ceil();
    final safePage = totalPages == 0 ? 0 : _pageIndex.clamp(0, totalPages - 1);
    final start = safePage * _pageSize;
    final visible = episodes.skip(start).take(_pageSize).toList();

    return KonekoCard(
      corner: 30,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '选集',
                  style: AppTextStyle.headline
                      .of(context, emphasized: true)
                      .copyWith(color: colorScheme.onSurface),
                ),
              ),
              Text(
                '共 ${episodes.length} 话',
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          if (totalPages > 1) ...[
            const SizedBox(height: 10),
            KonekoAutoScrollChipBar(
              height: 32,
              chipHeight: 28,
              fontSize: 11.5,
              elevated: false,
              padding: EdgeInsets.zero,
              unselectedColor: SurfaceLevel.block.colorOf(colorScheme),
              labels: [
                for (var idx = 0; idx < totalPages; idx++)
                  '${idx * _pageSize + 1}-${((idx + 1) * _pageSize).clamp(1, episodes.length)}',
              ],
              selectedIndex: safePage,
              onSelected: (idx) => setState(() => _pageIndex = idx),
            ),
          ],
          const SizedBox(height: 12),
          if (episodes.isEmpty) const Text('Bangumi 暂无剧集资料，仍可在播放器内选集。'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final ep in visible) _episodeCell(context, ep)],
          ),
        ],
      ),
    );
  }

  Widget _episodeCell(BuildContext context, EpisodeItem ep) {
    final colorScheme = context.colorScheme;
    final (bg, fg, label) = switch (ep.state) {
      EpisodeWatchState.current => (
        colorScheme.primary,
        colorScheme.onPrimary,
        '${ep.episodeNumber}',
      ),
      EpisodeWatchState.watched => (
        colorScheme.primary.withValues(alpha: 0.14),
        colorScheme.primary,
        '${ep.episodeNumber}',
      ),
      EpisodeWatchState.aired => (
        SurfaceLevel.block.colorOf(colorScheme),
        colorScheme.onSurface,
        '${ep.episodeNumber}',
      ),
      EpisodeWatchState.unaired => (
        SurfaceLevel.block.colorOf(colorScheme).withValues(alpha: 0.45),
        colorScheme.onSurfaceVariant.withValues(alpha: 0.48),
        '${ep.episodeNumber}',
      ),
    };
    return SizedBox(
      width: 58,
      height: 40,
      child: PressSurface(
        fill: bg,
        shape: AppShape.md,
        clipsChild: true,
        onPressed: ep.state == EpisodeWatchState.unaired
            ? null
            : () => widget.onSelect(ep),
        child: Center(
          child: Text(
            label,
            style: AppTextStyle.footnote
                .of(context, emphasized: true)
                .copyWith(
                  color: fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ),
      ),
    );
  }
}

class _CommentsSectionCard extends StatelessWidget {
  const _CommentsSectionCard({
    required this.commentsAsync,
    required this.overrideItems,
    required this.overrideTotal,
    required this.overrideHasMore,
    required this.loadingMore,
    required this.onRefresh,
    required this.onLoadMore,
  });

  final AsyncValue<SubjectCommentsPage> commentsAsync;
  final List<SubjectComment>? overrideItems;
  final int? overrideTotal;
  final bool? overrideHasMore;
  final bool loadingMore;
  final VoidCallback onRefresh;
  final ValueChanged<int> onLoadMore;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final basePage = commentsAsync.value;
    final items = overrideItems ?? basePage?.items ?? const <SubjectComment>[];
    final total = overrideTotal ?? basePage?.total ?? items.length;
    final hasMore = overrideHasMore ?? basePage?.hasMore ?? false;

    return KonekoCard(
      corner: 30,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  total > 0 ? 'Bangumi 吐槽箱 ($total)' : 'Bangumi 吐槽箱',
                  style: AppTextStyle.headline
                      .of(context, emphasized: true)
                      .copyWith(color: colorScheme.onSurface),
                ),
              ),
              KonekoChip(
                label: '刷新',
                height: 28,
                fontSize: 12,
                leading: GlyphIcon(
                  KonekoGlyphs.refresh,
                  size: 13,
                  color: colorScheme.primary,
                ),
                onPressed: onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (commentsAsync.isLoading && items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: ActivityIndicator()),
            )
          else if (commentsAsync.hasError && items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  spacing: 8,
                  children: [
                    Text(
                      '评论加载失败，请检查网络后重试',
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    KonekoChip(
                      label: '重新加载',
                      height: 32,
                      fontSize: 12.5,
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      onPressed: onRefresh,
                    ),
                  ],
                ),
              ),
            )
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '暂时还没有吐槽评论',
                  style: AppTextStyle.subheadline
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                for (final comment in items) _CommentTile(comment: comment),
              ],
            ),
            if (hasMore) ...[
              const SizedBox(height: 14),
              Center(
                child: KonekoChip(
                  label: loadingMore ? '正在加载...' : '加载更多评论',
                  height: 36,
                  fontSize: 13,
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.14),
                  foregroundColor: colorScheme.primary,
                  onPressed: loadingMore ? null : () => onLoadMore(items.length),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _CommentTile extends StatefulWidget {
  const _CommentTile({required this.comment});

  final SubjectComment comment;

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final c = widget.comment;
    final isLong =
        c.content.length > 140 || '\n'.allMatches(c.content).length >= 3;

    return KonekoBlock(
      corner: 18,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KonekoAvatar(
                name: c.userName,
                avatarUrl: c.avatarUrl,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.subheadline
                          .of(context, emphasized: true)
                          .copyWith(color: colorScheme.onSurface),
                    ),
                    Text(
                      formatRelativeTime(c.updatedAt),
                      style: AppTextStyle.caption2
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (c.rate > 0)
                KonekoChip(
                  label: '${c.rate}',
                  height: 22,
                  fontSize: 11,
                  leading: const GlyphIcon(
                    KonekoGlyphs.star,
                    size: 11,
                    color: Color(0xFFE09F24),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            c.content,
            maxLines: _expanded ? null : 4,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: colorScheme.onSurface, height: 1.5),
          ),
          if (isLong) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: PressSurface(
                fill: Colors.transparent,
                shape: AppShape.full,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded ? '收起' : '展开全文',
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(color: colorScheme.primary),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RuleSourcesCard extends StatelessWidget {
  const _RuleSourcesCard({
    required this.hasLiveResolver,
    required this.enabledRules,
    required this.liveProbes,
    required this.mockProbes,
    required this.selectedRuleId,
    required this.selectedRuleName,
    required this.onRefresh,
    required this.onManage,
    required this.onVerify,
    required this.onToggleSelect,
  });

  final bool hasLiveResolver;
  final List<RulePluginMeta> enabledRules;
  final Map<String, RuleProbeResult> liveProbes;
  final List<RuleSourceProbe> mockProbes;
  final String selectedRuleId;
  final String selectedRuleName;
  final VoidCallback onRefresh;
  final VoidCallback onManage;
  final void Function(String ruleId, String ruleName, Uri verifyUrl) onVerify;
  final void Function(String ruleId, String ruleName) onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final hasAny = hasLiveResolver
        ? enabledRules.isNotEmpty
        : mockProbes.isNotEmpty;

    return KonekoCard(
      corner: 30,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            spacing: 6,
            children: [
              Expanded(
                child: Text(
                  '播放源',
                  style: AppTextStyle.headline
                      .of(context, emphasized: true)
                      .copyWith(color: colorScheme.onSurface),
                ),
              ),
              if (hasLiveResolver && enabledRules.isNotEmpty)
                KonekoChip(
                  label: '重新检测',
                  height: 28,
                  fontSize: 12,
                  leading: GlyphIcon(
                    KonekoGlyphs.refresh,
                    size: 12,
                    color: colorScheme.primary,
                  ),
                  onPressed: onRefresh,
                ),
              KonekoChip(
                label: '管理规则',
                height: 28,
                fontSize: 12,
                onPressed: onManage,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            selectedRuleId.isNotEmpty
                ? '已指定「$selectedRuleName」，再次点击取消'
                : '点击可指定播放源，再次点击取消',
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (!hasAny)
            TextButton(onPressed: onManage, child: const Text('添加播放规则'))
          else if (hasLiveResolver)
            Column(
              spacing: 8,
              children: [
                for (final rule in enabledRules)
                  _buildLiveRuleTile(context, rule),
              ],
            )
          else
            Column(
              spacing: 8,
              children: [
                for (final probe in mockProbes)
                  _buildMockProbeTile(context, probe),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLiveRuleTile(BuildContext context, RulePluginMeta rule) {
    final colorScheme = context.colorScheme;
    final probe = liveProbes[rule.id];
    final state = probe?.state ?? RuleProbeState.searching;
    final selected = rule.id == selectedRuleId;

    final (badgeText, badgeBg, badgeFg) = switch (state) {
      RuleProbeState.searching => (
        '检测中',
        SurfaceLevel.card.colorOf(colorScheme),
        colorScheme.onSurfaceVariant,
      ),
      RuleProbeState.found => (
        '可用 · ${probe!.hits.length} 条',
        colorScheme.successContainer,
        colorScheme.onSuccessContainer,
      ),
      RuleProbeState.noResult => (
        '无结果',
        SurfaceLevel.card.colorOf(colorScheme),
        colorScheme.onSurfaceVariant,
      ),
      RuleProbeState.captchaRequired => (
        '需验证',
        colorScheme.warningContainer,
        colorScheme.onWarningContainer,
      ),
      RuleProbeState.error => (
        '不可用',
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
    };

    final subtitle = switch (state) {
      RuleProbeState.searching => '检测中...',
      RuleProbeState.found =>
        probe != null && probe.hits.isNotEmpty
            ? probe.hits.first.title
            : '可用',
      RuleProbeState.noResult => '未收录',
      RuleProbeState.captchaRequired => '需要验证',
      RuleProbeState.error => probe?.message ?? '不可用',
    };

    return KonekoBlock(
      selected: selected,
      onPressed: () {
        if (state == RuleProbeState.captchaRequired &&
            probe?.verifyUrl != null) {
          onVerify(rule.id, rule.name, probe!.verifyUrl!);
        } else {
          onToggleSelect(rule.id, rule.name);
        }
      },
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  spacing: 6,
                  children: [
                    Flexible(
                      child: Text(
                        rule.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.subheadline
                            .of(context, emphasized: true)
                            .copyWith(color: colorScheme.onSurface),
                      ),
                    ),
                    if (selected)
                      KonekoChip(
                        label: '已指定',
                        height: 20,
                        fontSize: 10,
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (state == RuleProbeState.captchaRequired &&
              probe?.verifyUrl != null)
            KonekoChip(
              label: '去验证',
              height: 26,
              fontSize: 11.5,
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              onPressed: () => onVerify(rule.id, rule.name, probe!.verifyUrl!),
            )
          else
            KonekoChip(
              label: badgeText,
              height: 24,
              fontSize: 11,
              backgroundColor: badgeBg,
              foregroundColor: badgeFg,
            ),
        ],
      ),
    );
  }

  Widget _buildMockProbeTile(BuildContext context, RuleSourceProbe probe) {
    final colorScheme = context.colorScheme;
    final selected = probe.ruleId == selectedRuleId;
    return KonekoBlock(
      selected: selected,
      onPressed: () => onToggleSelect(probe.ruleId, probe.ruleName),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  spacing: 6,
                  children: [
                    Flexible(
                      child: Text(
                        probe.ruleName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.subheadline
                            .of(context, emphasized: true)
                            .copyWith(color: colorScheme.onSurface),
                      ),
                    ),
                    if (selected)
                      KonekoChip(
                        label: '已指定',
                        height: 20,
                        fontSize: 10,
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  probe.availableEpisodes > 0
                      ? '${probe.lineLabel} · ${probe.availableEpisodes} 话'
                      : probe.lineLabel,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (probe.latencyMs > 0)
            KonekoChip(
              label: '${probe.latencyMs} ms',
              height: 24,
              fontSize: 11,
              backgroundColor: probe.latencyMs < 130
                  ? colorScheme.successContainer
                  : colorScheme.warningContainer,
              foregroundColor: probe.latencyMs < 130
                  ? colorScheme.onSuccessContainer
                  : colorScheme.onWarningContainer,
            ),
        ],
      ),
    );
  }
}

class _RelatedSeriesCard extends StatelessWidget {
  const _RelatedSeriesCard({required this.subjects, required this.onOpen});

  final List<AnimeSubject> subjects;
  final ValueChanged<AnimeSubject> onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return KonekoCard(
      corner: 30,
      clip: true,
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              '关联系列',
              style: AppTextStyle.headline
                  .of(context, emphasized: true)
                  .copyWith(color: colorScheme.onSurface),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 238,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 22),
              itemCount: subjects.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, index) {
                final s = subjects[index];
                return SizedBox(
                  width: 122,
                  child: UnifiedAnimeCard(
                    subject: s,
                    corner: 18,
                    onTap: () => onOpen(s),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
