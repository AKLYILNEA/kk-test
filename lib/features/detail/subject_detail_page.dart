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
import 'package:koneko/ui/koneko_polygon.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_skeleton.dart';
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
  Map<String, RuleProbeResult>? _pendingProbes;
  Timer? _probeFlushTimer;
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
    _probeFlushTimer?.cancel();
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
    _probeFlushTimer?.cancel();
    final initial = {
      for (final rule in enabledRules)
        rule.id: RuleProbeResult(
          ruleId: rule.id,
          ruleName: rule.name,
          state: RuleProbeState.searching,
          message: '正在检测可用性...',
        ),
    };
    _pendingProbes = Map<String, RuleProbeResult>.of(initial);
    _liveProbes.value = initial;

    void flushProbes() {
      _probeFlushTimer?.cancel();
      _probeFlushTimer = null;
      final snapshot = _pendingProbes;
      if (!mounted ||
          gen != _probeGeneration ||
          snapshot == null ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      _liveProbes.value = Map<String, RuleProbeResult>.unmodifiable(snapshot);
    }

    await Future.wait(
      enabledRules.map((rule) async {
        final result = await resolver.probeRule(subject, rule.id);
        if (!mounted ||
            gen != _probeGeneration ||
            !(ModalRoute.of(context)?.isCurrent ?? true)) {
          return;
        }
        (_pendingProbes ??= Map<String, RuleProbeResult>.of(
          _liveProbes.value,
        ))[rule.id] = result;
        _probeFlushTimer ??= Timer(
          const Duration(milliseconds: 80),
          flushProbes,
        );
      }),
    );
    flushProbes();
  }

  Future<void> _verifyRule(
    AnimeSubject subject,
    String ruleId,
    String ruleName,
    Uri verifyUrl, {
    RuleVerifyHint? verifyHint,
  }) async {
    final verified = await showRuleVerifySheet(
      context: context,
      ruleId: ruleId,
      ruleName: ruleName,
      verifyUrl: verifyUrl,
      verifyHint: verifyHint,
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
      rootNavigator: true,
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
            expectedCount: subject.totalEpisodes,
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
              ready: _sectionsReady,
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
              onVerify: (ruleId, ruleName, verifyUrl, verifyHint) => unawaited(
                _verifyRule(
                  subject,
                  ruleId,
                  ruleName,
                  verifyUrl,
                  verifyHint: verifyHint,
                ),
              ),
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
    final subjectLoad = loadCatalogSubjectProvider(id);
    final detailLoad = _sectionsReady
        ? ref.watch(subjectLoad)
        : const AsyncLoading<void>();
    final detailPending = !_sectionsReady || detailLoad.isLoading;
    // Read the latest catalog subject synchronously once settled (and when
    // detailLoad completes) so `summary` and `detailPending` always flip on
    // the exact same frame—preventing the synopsis block from collapsing to
    // 0px for one frame before expanding back down.
    final subject = _sectionsReady
        ? (ref.read(catalogRepositoryProvider).getSubjectById(id) ?? _subject)
        : _subject;
    if (subject != null) _subject = subject;
    if (subject == null) {
      final load = _sectionsReady ? detailLoad : ref.watch(subjectLoad);
      return KonekoScaffold(
        title: '番剧详情',
        showBack: true,
        body: load.isLoading
            ? _SubjectDetailSkeletonView(animate: routeSettled)
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: KonekoCard(
                    corner: 24,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    onPressed: () => ref.invalidate(subjectLoad),
                    child: const Text(
                      '番剧资料暂不可用，点此重试',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
      );
    }
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
              detailPending,
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
                detailPending: detailPending,
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

          return TickerMode(
            enabled: routeSettled,
            child: KonekoSkeletonScope(
              animate: routeSettled,
              child: ArrivalCacheExtentBuilder(
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
              ),
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
    required this.detailPending,
    required this.onPlay,
    required this.onStatusChanged,
  });

  final AnimeSubject subject;
  final CollectionEntry? entry;
  final int currentEp;
  final bool hasHistory;
  final bool detailPending;
  final VoidCallback onPlay;
  final ValueChanged<CollectionStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final summary = subject.summary.trim();
    // Kazumi-style unified top Hero skeleton: when entering a subject whose
    // full Bangumi detail (summary) hasn't arrived yet, hold the rating, meta
    // row, and synopsis as placeholders together and reveal in one smooth fade.
    final deferHeroMeta = detailPending && summary.isEmpty;
    final hasRating = !deferHeroMeta && (subject.score > 0 || subject.rank > 0);
    final showRatingSkeleton = deferHeroMeta || (!hasRating && detailPending);
    final hasMeta =
        !deferHeroMeta &&
        (subject.year > 0 ||
            subject.studio.trim().isNotEmpty ||
            subject.totalEpisodes > 0);
    final showMetaSkeleton = deferHeroMeta || (!hasMeta && detailPending);
    final showSummarySkeleton = summary.isEmpty && detailPending;

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
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 46,
                        child: Align(
                          alignment: AlignmentDirectional.bottomStart,
                          child: KonekoSkeletonFade(
                            child: hasRating
                                ? Column(
                                    key: const ValueKey('hero-rating-live'),
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    spacing: 4,
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
                                                    color:
                                                        colorScheme.onSurface,
                                                    fontFeatures: const [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                  ),
                                            ),
                                          ],
                                        ),
                                      if (subject.rank > 0)
                                        _BangumiRankLine(rank: subject.rank),
                                    ],
                                  )
                                : showRatingSkeleton
                                ? const KonekoSkeletonPulse(
                                    key: ValueKey('hero-rating-skeleton'),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      spacing: 6,
                                      children: [
                                        KonekoSkeletonBox(
                                          width: 124,
                                          height: 18,
                                          corner: 7,
                                        ),
                                        KonekoSkeletonBox(
                                          width: 108,
                                          height: 16,
                                          corner: 6,
                                        ),
                                      ],
                                    ),
                                  )
                                : Text(
                                    '暂无评分',
                                    key: const ValueKey('hero-rating-empty'),
                                    style: AppTextStyle.caption1
                                        .of(context)
                                        .copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 24,
            child: KonekoSkeletonFade(
              child: hasMeta
                  ? SingleChildScrollView(
                      key: const ValueKey('hero-meta-live'),
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        spacing: 6,
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
                    )
                  : showMetaSkeleton
                  ? const KonekoSkeletonPulse(
                      key: ValueKey('hero-meta-skeleton'),
                      child: Row(
                        spacing: 6,
                        children: [
                          KonekoSkeletonBox(width: 68, height: 24, corner: 12),
                          KonekoSkeletonBox(width: 88, height: 24, corner: 12),
                          KonekoSkeletonBox(width: 60, height: 24, corner: 12),
                        ],
                      ),
                    )
                  : Align(
                      key: const ValueKey('hero-meta-empty'),
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        '动画',
                        style: AppTextStyle.caption1
                            .of(context)
                            .copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
            ),
          ),
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
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: KonekoSkeletonFade(
              child: summary.isNotEmpty
                  ? SubjectSynopsis(
                      key: const ValueKey('hero-synopsis-live'),
                      summary: summary,
                    )
                  : showSummarySkeleton
                  ? const _SynopsisSkeletonBlock(
                      key: ValueKey('hero-synopsis-skeleton'),
                    )
                  : KonekoBlock(
                      key: const ValueKey('hero-synopsis-empty'),
                      corner: 18,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: SizedBox(
                        width: double.infinity,
                        height: kSynopsisCollapsedHeight,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '暂无剧情简介',
                            style: AppTextStyle.caption1
                                .of(context)
                                .copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BangumiRankLine extends StatelessWidget {
  const _BangumiRankLine({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Bangumi 排名',
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 5),
          Text(
            '#$rank',
            style: AppTextStyle.subheadline
                .of(context, emphasized: true)
                .copyWith(
                  color: colorScheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeMatrixCard extends StatefulWidget {
  const _EpisodeMatrixCard({
    required this.episodes,
    required this.onSelect,
    this.expectedCount = 0,
    this.isLoading = false,
    this.onRetry,
  });

  final List<EpisodeItem> episodes;
  final ValueChanged<EpisodeItem> onSelect;
  final int expectedCount;
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

    return KonekoCard(
      corner: 30,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '选集',
                    style: AppTextStyle.headline
                        .of(context, emphasized: true)
                        .copyWith(color: colorScheme.onSurface),
                  ),
                ),
                if (totalPages > 1)
                  KonekoPopupTrigger<int>(
                    options: [for (var idx = 0; idx < totalPages; idx++) idx],
                    value: safePage,
                    textBuilder: (idx) =>
                        '${idx * _pageSize + 1}-${((idx + 1) * _pageSize).clamp(1, episodes.length)} 话',
                    onChanged: (idx) {
                      _revealLiveCard();
                      setState(() => _pageIndex = idx);
                    },
                  )
                else if (episodes.isNotEmpty)
                  Text(
                    '共 ${episodes.length} 话',
                    style: AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  )
                else if (widget.isLoading)
                  const KonekoSkeletonBox(width: 52, height: 14, corner: 7),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSize(
            duration: context.motionDuration(const Duration(milliseconds: 220)),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: KonekoSkeletonFade(
              child: episodes.isNotEmpty
                  ? Listener(
                      key: const ValueKey('episodes-live'),
                      onPointerDown: (_) => _revealLiveCard(),
                      child: SnapshotWidget(
                        key: const ValueKey('episode-arrival-snapshot'),
                        controller: _arrivalSnapshot,
                        mode: SnapshotMode.permissive,
                        autoresize: true,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final ep in visible)
                              _episodeCell(context, ep),
                          ],
                        ),
                      ),
                    )
                  : widget.isLoading
                  ? _EpisodeGridSkeleton(
                      key: const ValueKey('episodes-skeleton'),
                      count: widget.expectedCount > 0
                          ? widget.expectedCount.clamp(1, 24)
                          : 12,
                    )
                  : Row(
                      key: const ValueKey('episodes-empty'),
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
            ),
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

    final showSkeleton = commentsAsync.isLoading && items.isEmpty;
    final Widget? status;
    if (showSkeleton) {
      status = null;
    } else if (commentsAsync.hasError && items.isEmpty) {
      status = KonekoEmptyState(
        glyph: KonekoGlyphs.comment,
        shape: KonekoPolygons.softBurst,
        title: '评论加载失败，请检查网络后重试',
        compact: true,
        actions: [
          KonekoRefreshChip(
            label: '重新加载',
            prominent: true,
            onPressed: onRefresh,
          ),
        ],
      );
    } else if (items.isEmpty) {
      status = const KonekoEmptyState(
        glyph: KonekoGlyphs.comment,
        shape: KonekoPolygons.flower,
        title: '暂时还没有吐槽评论',
        compact: true,
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
                    KonekoRefreshChip(
                      label: '刷新',
                      loading: commentsAsync.isLoading,
                      onPressed: onRefresh,
                    ),
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              if (showSkeleton)
                SliverPrismList(
                  key: const ValueKey('comments-loading-skeleton'),
                  itemCount: 4,
                  gap: 10,
                  estimatedItemExtent: 112,
                  itemBuilder: (_, index) =>
                      _CommentSkeletonTile(compact: index.isOdd),
                )
              else if (status != null)
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
    required this.ready,
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

  final bool ready;
  final bool hasLiveResolver;
  final List<RulePluginMeta> enabledRules;
  final Map<String, RuleProbeResult> liveProbes;
  final List<RuleSourceProbe> mockProbes;
  final String selectedRuleId;
  final String selectedRuleName;
  final VoidCallback onRefresh;
  final VoidCallback onManage;
  final void Function(
    String ruleId,
    String ruleName,
    Uri verifyUrl,
    RuleVerifyHint? verifyHint,
  )
  onVerify;
  final void Function(String ruleId, String ruleName) onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final hasAny = hasLiveResolver
        ? enabledRules.isNotEmpty
        : mockProbes.isNotEmpty;
    final anySearching =
        hasLiveResolver &&
        enabledRules.any(
          (rule) => liveProbes[rule.id]?.state == RuleProbeState.searching,
        );

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
                KonekoRefreshChip(
                  label: '重新检测',
                  loadingLabel: '检测中',
                  loading: anySearching,
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
          else if (hasLiveResolver && !ready)
            KonekoSkeletonPulse(
              child: Column(
                spacing: 8,
                children: [
                  for (var i = 0; i < enabledRules.length.clamp(1, 6); i++)
                    const _SourceSkeletonTile(),
                ],
              ),
            )
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

    return KonekoSourceSurface(
      selected: selected,
      elevated: false,
      onPressed: () {
        if (state == RuleProbeState.captchaRequired &&
            probe?.verifyUrl != null) {
          onVerify(rule.id, rule.name, probe!.verifyUrl!, probe.verifyHint);
        } else {
          onToggleSelect(rule.id, rule.name);
        }
      },
      child: Row(
        spacing: 10,
        children: [
          if (selected) const KonekoSourceCheckBadge(),
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
                            .copyWith(
                              color: selected
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                      ),
                    ),
                    if (selected)
                      KonekoChip(
                        label: '已指定',
                        height: 20,
                        fontSize: 10,
                        backgroundColor: colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        foregroundColor: colorScheme.primary,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                if (state == RuleProbeState.searching)
                  const SizedBox(
                    height: 16,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: KonekoSkeletonBox(
                        width: 96,
                        height: 11,
                        corner: 5,
                      ),
                    ),
                  )
                else
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
              onPressed: () => onVerify(
                rule.id,
                rule.name,
                probe!.verifyUrl!,
                probe.verifyHint,
              ),
            )
          else if (state == RuleProbeState.searching)
            const KonekoSkeletonBox(width: 56, height: 24, corner: 12)
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
    return KonekoSourceSurface(
      selected: selected,
      elevated: false,
      onPressed: () => onToggleSelect(probe.ruleId, probe.ruleName),
      child: Row(
        spacing: 10,
        children: [
          if (selected) const KonekoSourceCheckBadge(),
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
                            .copyWith(
                              color: selected
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                      ),
                    ),
                    if (selected)
                      KonekoChip(
                        label: '已指定',
                        height: 20,
                        fontSize: 10,
                        backgroundColor: colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        foregroundColor: colorScheme.primary,
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

class _SynopsisSkeletonBlock extends StatelessWidget {
  const _SynopsisSkeletonBlock({super.key});

  @override
  Widget build(BuildContext context) {
    return const KonekoSkeletonPulse(
      child: KonekoBlock(
        corner: 18,
        padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: SizedBox(
          height: kSynopsisCollapsedHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KonekoSkeletonBox(width: double.infinity, height: 14, corner: 6),
              SizedBox(height: 10),
              FractionallySizedBox(
                widthFactor: 0.92,
                child: KonekoSkeletonBox(height: 14, corner: 6),
              ),
              SizedBox(height: 10),
              FractionallySizedBox(
                widthFactor: 0.64,
                child: KonekoSkeletonBox(height: 14, corner: 6),
              ),
              Spacer(),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: KonekoSkeletonBox(width: 52, height: 14, corner: 7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodeGridSkeleton extends StatelessWidget {
  const _EpisodeGridSkeleton({super.key, this.count = 12});

  final int count;

  @override
  Widget build(BuildContext context) {
    return KonekoSkeletonPulse(
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < count; i++)
            const KonekoSkeletonBox(width: 58, height: 40, corner: 12),
        ],
      ),
    );
  }
}

class _CommentSkeletonTile extends StatelessWidget {
  const _CommentSkeletonTile({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return KonekoSkeletonPulse(
      child: KonekoBlock(
        corner: 18,
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                KonekoSkeletonBox(width: 34, height: 34, circle: true),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 5,
                    children: [
                      KonekoSkeletonBox(width: 104, height: 14, corner: 6),
                      KonekoSkeletonBox(width: 64, height: 10, corner: 5),
                    ],
                  ),
                ),
                KonekoSkeletonBox(width: 38, height: 22, corner: 11),
              ],
            ),
            const SizedBox(height: 10),
            const KonekoSkeletonBox(
              width: double.infinity,
              height: 13,
              corner: 5,
            ),
            const SizedBox(height: 7),
            FractionallySizedBox(
              widthFactor: compact ? 0.68 : 0.90,
              child: const KonekoSkeletonBox(height: 13, corner: 5),
            ),
            if (!compact) ...[
              const SizedBox(height: 7),
              const FractionallySizedBox(
                widthFactor: 0.54,
                child: KonekoSkeletonBox(height: 13, corner: 5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SubjectDetailSkeletonView extends StatelessWidget {
  const _SubjectDetailSkeletonView({required this.animate});

  final bool animate;

  @override
  Widget build(BuildContext context) {
    final bottomPad = 28 + MediaQuery.paddingOf(context).bottom;
    return KonekoSkeletonScope(
      animate: animate,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          const episodesCard = KonekoCard(
            corner: 30,
            padding: EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    KonekoSkeletonBox(width: 44, height: 18, corner: 7),
                    Spacer(),
                    KonekoSkeletonBox(width: 52, height: 14, corner: 7),
                  ],
                ),
                SizedBox(height: 14),
                _EpisodeGridSkeleton(count: 12),
              ],
            ),
          );
          const sourcesCard = KonekoCard(
            corner: 30,
            padding: EdgeInsets.all(18),
            child: KonekoSkeletonPulse(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KonekoSkeletonBox(width: 62, height: 18, corner: 7),
                  SizedBox(height: 6),
                  KonekoSkeletonBox(width: 148, height: 12, corner: 5),
                  SizedBox(height: 12),
                  Column(
                    spacing: 8,
                    children: [
                      _SourceSkeletonTile(),
                      _SourceSkeletonTile(),
                      _SourceSkeletonTile(),
                    ],
                  ),
                ],
              ),
            ),
          );

          return CustomScrollView(
            key: const ValueKey('detail-full-skeleton'),
            physics: const NeverScrollableScrollPhysics(),
            slivers: [
              const KonekoScrollStart(),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 6, 16, bottomPad),
                sliver: SliverList.list(
                  children: [
                    const KonekoSkeletonPulse(
                      child: KonekoCard(
                        corner: 30,
                        padding: EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                KonekoSkeletonBox(
                                  width: 104,
                                  height: 148,
                                  corner: 18,
                                ),
                                SizedBox(width: 16),
                                Expanded(
                                  child: SizedBox(
                                    height: 148,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          spacing: 8,
                                          children: [
                                            KonekoSkeletonBox(
                                              width: double.infinity,
                                              height: 22,
                                              corner: 8,
                                            ),
                                            FractionallySizedBox(
                                              widthFactor: 0.62,
                                              child: KonekoSkeletonBox(
                                                height: 20,
                                                corner: 8,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          spacing: 6,
                                          children: [
                                            KonekoSkeletonBox(
                                              width: 124,
                                              height: 18,
                                              corner: 7,
                                            ),
                                            KonekoSkeletonBox(
                                              width: 108,
                                              height: 16,
                                              corner: 6,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                KonekoSkeletonBox(
                                  width: 68,
                                  height: 26,
                                  corner: 13,
                                ),
                                KonekoSkeletonBox(
                                  width: 88,
                                  height: 26,
                                  corner: 13,
                                ),
                                KonekoSkeletonBox(
                                  width: 60,
                                  height: 26,
                                  corner: 13,
                                ),
                              ],
                            ),
                            SizedBox(height: 16),
                            KonekoSkeletonBox(
                              width: double.infinity,
                              height: 46,
                              corner: 23,
                            ),
                            SizedBox(height: 10),
                            Row(
                              spacing: 8,
                              children: [
                                Expanded(
                                  child: KonekoSkeletonBox(
                                    height: 34,
                                    corner: 17,
                                  ),
                                ),
                                Expanded(
                                  child: KonekoSkeletonBox(
                                    height: 34,
                                    corner: 17,
                                  ),
                                ),
                                Expanded(
                                  child: KonekoSkeletonBox(
                                    height: 34,
                                    corner: 17,
                                  ),
                                ),
                                Expanded(
                                  child: KonekoSkeletonBox(
                                    height: 34,
                                    corner: 17,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 14),
                            _SynopsisSkeletonBlock(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const KonekoSkeletonBox(
                      width: double.infinity,
                      height: 42,
                      corner: 21,
                    ),
                    const SizedBox(height: 14),
                    if (isWide)
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 16,
                        children: [
                          Expanded(flex: 12, child: episodesCard),
                          Expanded(flex: 7, child: sourcesCard),
                        ],
                      )
                    else ...const [
                      episodesCard,
                      SizedBox(height: 14),
                      sourcesCard,
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SourceSkeletonTile extends StatelessWidget {
  const _SourceSkeletonTile();

  @override
  Widget build(BuildContext context) {
    return const KonekoBlock(
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                KonekoSkeletonBox(width: 112, height: 15, corner: 6),
                KonekoSkeletonBox(width: 84, height: 11, corner: 5),
              ],
            ),
          ),
          KonekoSkeletonBox(width: 56, height: 24, corner: 12),
        ],
      ),
    );
  }
}
