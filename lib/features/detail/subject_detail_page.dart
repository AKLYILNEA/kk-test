import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/detail/subject_metadata_tabs.dart';
import 'package:koneko/features/detail/subject_synopsis.dart';
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
import 'package:prism_ui/route_scope.dart';

enum _DetailSection { play, characters, relations, comments }

class SubjectDetailPage extends ConsumerStatefulWidget {
  const SubjectDetailPage({super.key, required this.subjectId});

  final int subjectId;

  @override
  ConsumerState<SubjectDetailPage> createState() => _SubjectDetailPageState();
}

class _SubjectDetailPageState extends ConsumerState<SubjectDetailPage>
    with
        RouteMotionHoldMixin<SubjectDetailPage>,
        RouteSettledMixin<SubjectDetailPage> {
  final _selectedRule = ValueNotifier<(String, String)>(('', ''));
  _DetailSection _section = _DetailSection.play;
  AnimeSubject? _subject;
  bool _sectionsReady = false;
  bool _peopleVisited = false;
  final _scroll = ScrollController(keepScrollOffset: false);
  final _liveProbes = ValueNotifier<Map<String, RuleProbeResult>>(const {});
  late final _sourceChanges = Listenable.merge([_selectedRule, _liveProbes]);
  int _probeGeneration = 0;
  int? _probedSubjectId;

  // Pagination state for Bangumi comments beyond the first page.
  List<SubjectComment>? _extraComments;
  int? _extraTotal;
  bool _extraHasMore = false;
  bool _loadingMoreComments = false;

  @override
  void initState() {
    super.initState();
    final subject = catalogSubjectProvider(widget.subjectId);
    _subject = ref.read(subject);
    ref.listenManual(subject, (_, _) {
      showFirstContent(() {
        final latest = ref.read(subject);
        if (!identical(_subject, latest)) setState(() => _subject = latest);
      });
    });
  }

  @override
  void didSettleRoute() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _sectionsReady = true;
        _subject = ref.read(catalogSubjectProvider(widget.subjectId));
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _probeGeneration++;
    _liveProbes.dispose();
    _selectedRule.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _ensureProbed(AnimeSubject subject) {
    if (!routeSettled ||
        _probedSubjectId == subject.subjectId ||
        ref.read(playbackSourcesProvider) == null) {
      return;
    }
    _probedSubjectId = subject.subjectId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_section != _DetailSection.play ||
          !(ModalRoute.isCurrentOf(context) ?? true)) {
        _probedSubjectId = null;
        return;
      }
      unawaited(_probeAllEnabledRules(subject));
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
      _liveProbes.value = const {};
      return;
    }

    final gen = ++_probeGeneration;
    _liveProbes.value = {
      for (final rule in enabledRules)
        rule.id: RuleProbeResult(
          ruleId: rule.id,
          ruleName: rule.name,
          state: RuleProbeState.searching,
          message: '正在检测可用性...',
        ),
    };

    await Future.wait(
      enabledRules.map((rule) async {
        final result = await resolver.probeRule(subject, rule.id);
        if (!mounted || gen != _probeGeneration) return;
        _liveProbes.value = {..._liveProbes.value, rule.id: result};
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
    _liveProbes.value = {
      ..._liveProbes.value,
      ruleId: RuleProbeResult(
        ruleId: ruleId,
        ruleName: ruleName,
        state: RuleProbeState.searching,
        message: '验证通过，重新检索中...',
      ),
    };
    final result = await resolver.probeRule(subject, ruleId);
    if (!mounted) return;
    _liveProbes.value = {..._liveProbes.value, ruleId: result};
  }

  void _playEpisode(AnimeSubject subject, int episodeNumber) {
    final (ruleId, ruleName) = _selectedRule.value;
    BaseNavigator.push<void>(
      context,
      PlayerPage(
        subjectId: subject.subjectId,
        initialEpisode: episodeNumber,
        initialRuleId: ruleId,
        initialRuleName: ruleName,
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

  Widget _playSliver(
    AnimeSubject subject, {
    required int watchedCount,
    required int currentEp,
    required bool isWide,
  }) {
    final episodes = Consumer(
      builder: (context, ref, _) {
        final catalog = ref.watch(catalogRepositoryProvider);
        final episodeProvider = loadCatalogEpisodesProvider(subject.subjectId);
        final load = _sectionsReady
            ? ref.watch(episodeProvider)
            : const AsyncLoading<void>();
        return MemoBuilder(
          inputs: [
            catalog,
            subject.subjectId,
            subject.totalEpisodes,
            subject.airedEpisodes,
            watchedCount,
            currentEp,
            load,
          ],
          builder: (context) => _EpisodeMatrixCard(
            episodes: catalog.getEpisodes(
              subject.subjectId,
              watchedCount: watchedCount,
              currentEp: currentEp,
            ),
            isLoading: load.isLoading,
            onRetry: () => ref.invalidate(episodeProvider),
            onSelect: (episode) => _playEpisode(subject, episode.episodeNumber),
          ),
        );
      },
    );
    final sources = Consumer(
      builder: (context, ref, _) {
        final hasLiveResolver = ref.watch(playbackSourcesProvider) != null;
        final enabledRules = ref
            .watch(rulesProvider)
            .where((rule) => rule.enabled)
            .toList();
        final mockProbes = hasLiveResolver
            ? const <RuleSourceProbe>[]
            : ref
                  .watch(catalogRepositoryProvider)
                  .probeSources(subject.subjectId);
        _ensureProbed(subject);
        return ListenableBuilder(
          listenable: _sourceChanges,
          builder: (context, _) {
            final (selectedId, selectedName) = _selectedRule.value;
            return _RuleSourcesCard(
              hasLiveResolver: hasLiveResolver,
              enabledRules: enabledRules,
              liveProbes: _liveProbes.value,
              mockProbes: mockProbes,
              selectedRuleId: selectedId,
              selectedRuleName: selectedName,
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
                if (_selectedRule.value.$1 == ruleId) {
                  _selectedRule.value = ('', '');
                  showKonekoBanner(context, '已取消指定播放源，将自动沿用上次线路');
                } else {
                  _selectedRule.value = (ruleId, ruleName);
                  showKonekoBanner(context, '已指定播放源：$ruleName（再次点击可取消）');
                }
              },
            );
          },
        );
      },
    );
    return isWide
        ? SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
                Expanded(flex: 12, child: episodes),
                Expanded(flex: 7, child: sources),
              ],
            ),
          )
        : SliverList.list(
            children: [episodes, const SizedBox(height: 14), sources],
          );
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.subjectId;
    final subject = _subject;
    final subjectLoad = loadCatalogSubjectProvider(id);
    if (subject == null) {
      final load = ref.watch(subjectLoad);
      return KonekoScaffold(
        title: '番剧详情',
        showBack: true,
        body: Center(
          child: load.isLoading
              ? const ActivityIndicator()
              : TextButton(
                  onPressed: () => ref.invalidate(subjectLoad),
                  child: const Text('番剧资料暂不可用，点此重试'),
                ),
        ),
      );
    }
    if (_sectionsReady) ref.listen(subjectLoad, (_, _) {});
    if (_peopleVisited) SubjectPeopleSliver.retain(ref, id);

    final entry = ref.watch(
      libraryProvider.select(
        (list) => list.firstWhereOrNull((item) => item.subjectId == id),
      ),
    );
    final hist = ref.watch(
      historyProvider.select(
        (list) => list.firstWhereOrNull((item) => item.subjectId == id),
      ),
    );
    final currentEp =
        hist?.lastEpisode ??
        ((entry?.watchedEpisodes ?? 0) > 0 ? entry!.watchedEpisodes : 1);
    final hasHistory = hist != null || (entry?.watchedEpisodes ?? 0) > 0;
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
          final heroCard = MemoBuilder(
            inputs: [
              subject.subjectId,
              subject.title,
              subject.coverUrl,
              subject.poster,
              subject.score,
              subject.rank,
              subject.year,
              subject.seasonLabel,
              subject.totalEpisodes,
              subject.studio,
              subject.summary,
              ...subject.tags,
              entry?.status,
              currentEp,
              hasHistory,
            ],
            builder: (context) => RepaintBoundary(
              child: _HeroCard(
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
              ),
            ),
          );
          final sectionSwitcher = KonekoSegmentedBar<_DetailSection>(
            segments: const [
              (_DetailSection.play, '播放'),
              (_DetailSection.characters, '角色'),
              (_DetailSection.relations, '关联'),
              (_DetailSection.comments, '评论'),
            ],
            value: _section,
            onChanged: (value) => setState(() {
              _section = value;
              if (value == _DetailSection.characters) _peopleVisited = true;
            }),
          );

          final bottomPad = 28 + MediaQuery.paddingOf(context).bottom;

          return ArrivalCacheExtentBuilder(
            builder: (context, cacheExtent) => CustomScrollView(
              controller: _scroll,
              scrollCacheExtent: cacheExtent,
              slivers: [
                const KonekoScrollStart(),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 14,
                      children: [heroCard, sectionSwitcher],
                    ),
                  ),
                ),
                ...switch (_section) {
                  _DetailSection.play => [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPad),
                      sliver: _playSliver(
                        subject,
                        watchedCount: entry?.watchedEpisodes ?? 0,
                        currentEp: currentEp,
                        isWide: isWide,
                      ),
                    ),
                  ],
                  _DetailSection.characters => [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPad),
                      sliver: SubjectPeopleSliver(subjectId: id),
                    ),
                  ],
                  _DetailSection.relations => [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPad),
                      sliver: SubjectRelationsSliver(
                        subjectId: subject.subjectId,
                        onOpenAnime: (id) => BaseNavigator.push<void>(
                          context,
                          SubjectDetailPage(subjectId: id),
                        ),
                      ),
                    ),
                  ],
                  _DetailSection.comments => [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPad),
                      sliver: Consumer(
                        builder: (context, ref, _) {
                          final commentsAsync = ref.watch(
                            subjectCommentsProvider(id),
                          );
                          return _CommentsSectionSliver(
                            commentsAsync: commentsAsync,
                            overrideItems: _extraComments,
                            overrideTotal: _extraTotal,
                            overrideHasMore: _extraComments != null
                                ? _extraHasMore
                                : null,
                            loadingMore: _loadingMoreComments,
                            onRefresh: () {
                              setState(() {
                                _extraComments = null;
                                _extraTotal = null;
                                _extraHasMore = false;
                              });
                              ref.invalidate(
                                subjectCommentsProvider(widget.subjectId),
                              );
                            },
                            onLoadMore: (count) => _loadMoreComments(count),
                          );
                        },
                      ),
                    ),
                  ],
                },
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final summary = subject.summary.trim();

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
            onPressed: onPlay,
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
                    hasHistory
                        ? '继续播放 · 第 $currentEp 话'
                        : '立即播放 · 第 $currentEp 话',
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
                    selected: entry?.status == status,
                    leading: GlyphIcon(
                      konekoStatusGlyph(status),
                      fill: entry?.status == status ? 1 : 0,
                      size: 13.5,
                      color: entry?.status == status
                          ? colorScheme.onPrimary
                          : konekoStatusColor(status),
                    ),
                    onPressed: () => onStatusChanged(status),
                  ),
                ),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 14),
            SubjectSynopsis(summary: summary),
          ],
        ],
      ),
    );
  }
}

class _EpisodeMatrixCard extends StatefulWidget {
  const _EpisodeMatrixCard({
    required this.episodes,
    required this.onSelect,
    this.isLoading = false,
    this.onRetry,
  });

  final List<EpisodeItem> episodes;
  final ValueChanged<EpisodeItem> onSelect;
  final bool isLoading;
  final VoidCallback? onRetry;

  @override
  State<_EpisodeMatrixCard> createState() => _EpisodeMatrixCardState();
}

class _EpisodeMatrixCardState extends State<_EpisodeMatrixCard> {
  static const int _pageSize = 24;
  int _pageIndex = 0;
  final _arrivalSnapshot = SnapshotController();
  Animation<double>? _arrival;
  bool _live = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = routeOf(context);
    final arrival = route is CardPageRoute<Object?> ? route.animation : null;
    if (!identical(arrival, _arrival)) {
      _arrival?.removeStatusListener(_updateSnapshot);
      _arrival = arrival?..addStatusListener(_updateSnapshot);
    }
    _updateSnapshot();
  }

  void _updateSnapshot([AnimationStatus? _]) {
    _arrivalSnapshot.allowSnapshotting =
        !_live &&
        widget.episodes.isNotEmpty &&
        _arrival?.status == AnimationStatus.forward;
  }

  void _revealLiveCard() {
    if (!_arrivalSnapshot.allowSnapshotting) return;
    _live = true;
    _updateSnapshot();
  }

  @override
  void dispose() {
    _arrival?.removeStatusListener(_updateSnapshot);
    _arrivalSnapshot.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _EpisodeMatrixCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.episodes, widget.episodes)) {
      _revealLiveCard();
    }
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

    return Listener(
      onPointerDown: (_) => _revealLiveCard(),
      child: SnapshotWidget(
        key: const ValueKey('episode-arrival-snapshot'),
        controller: _arrivalSnapshot,
        mode: SnapshotMode.permissive,
        autoresize: true,
        child: KonekoCard(
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
              if (episodes.isEmpty)
                widget.isLoading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: ActivityIndicator()),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Text(
                              '暂无剧集资料，可在播放器内选集',
                              style: AppTextStyle.footnote
                                  .of(context)
                                  .copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                          if (widget.onRetry != null)
                            KonekoChip(
                              label: '重试',
                              height: 28,
                              fontSize: 12,
                              onPressed: widget.onRetry,
                            ),
                        ],
                      ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final ep in visible) _episodeCell(context, ep)],
              ),
            ],
          ),
        ),
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

class _CommentsSectionSliver extends StatelessWidget {
  const _CommentsSectionSliver({
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

    final Widget? status;
    if (commentsAsync.isLoading && items.isEmpty) {
      status = const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: ActivityIndicator()),
      );
    } else if (commentsAsync.hasError && items.isEmpty) {
      status = Padding(
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
      );
    } else if (items.isEmpty) {
      status = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '暂时还没有吐槽评论',
            style: AppTextStyle.subheadline
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    } else {
      status = null;
    }

    return SurfaceScope(
      level: SurfaceLevel.card,
      child: DecoratedSliver(
        decoration: ShapeDecoration(
          color: SurfaceLevel.card.colorOf(colorScheme),
          shape: SuperellipseBorder(borderRadius: AppRadius.all(30)),
          shadows: konekoCardShadows(colorScheme),
        ),
        sliver: SliverPadding(
          padding: const EdgeInsets.all(18),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Row(
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
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              if (status != null)
                SliverToBoxAdapter(child: status)
              else ...[
                SliverPrismList(
                  itemCount: items.length,
                  gap: 10,
                  estimatedItemExtent: 112,
                  itemBuilder: (_, index) =>
                      _CommentTile(comment: items[index]),
                ),
                if (hasMore)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Center(
                        child: KonekoChip(
                          label: loadingMore ? '正在加载...' : '加载更多评论',
                          height: 36,
                          fontSize: 13,
                          backgroundColor: colorScheme.primary.withValues(
                            alpha: 0.14,
                          ),
                          foregroundColor: colorScheme.primary,
                          onPressed: loadingMore
                              ? null
                              : () => onLoadMore(items.length),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
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
              KonekoAvatar(name: c.userName, avatarUrl: c.avatarUrl, size: 34),
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
        probe != null && probe.hits.isNotEmpty ? probe.hits.first.title : '可用',
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
