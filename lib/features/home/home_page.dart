import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/catalog_page_refresh.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/detail/subject_detail_page.dart';
import 'package:koneko/features/discover/discover_page.dart';
import 'package:koneko/features/history/history_page.dart';
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

class _HomePageState extends ConsumerState<HomePage>
    with RouteMotionHoldMixin<HomePage>, CatalogPageRefreshMixin<HomePage> {
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

  final ScrollController _scrollController = ScrollController();
  String _selectedTag = '全部';
  bool _loadingMore = false;
  final Map<String, bool> _exhausted = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 480) {
      unawaited(_loadMore(_selectedTag));
    }
  }

  Future<void> _loadMore(String tag) async {
    if (_loadingMore || _exhausted[tag] == true) return;
    final online = ref.read(onlineCatalogProvider);
    if (online == null) return;
    setState(() => _loadingMore = true);
    try {
      final hasMore = await online.loadMoreTrending(tag: tag);
      if (mounted) {
        setState(() {
          _loadingMore = false;
          if (!hasMore) _exhausted[tag] = true;
        });
      }
    } on Object {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _selectTag(String tag) {
    setState(() => _selectedTag = tag);
    final items = ref.read(catalogRepositoryProvider).getTrending(tag: tag);
    if (tag != '全部' && items.length < 18 && _exhausted[tag] != true) {
      unawaited(_loadMore(tag));
    }
  }

  void _openDetail(AnimeSubject subject) {
    BaseNavigator.push<void>(
      context,
      SubjectDetailPage(subjectId: subject.subjectId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogRepositoryProvider);
    final loading = ref.watch(loadHomeCatalogProvider);
    final library = ref.watch(libraryProvider);

    final allTrending = catalog.getTrending();
    final subjects = _selectedTag == '全部'
        ? allTrending
        : catalog.getTrending(tag: _selectedTag);
    final trackingIds = {
      for (final e in library)
        if (e.status == CollectionStatus.watching) e.subjectId,
    };
    final featured = allTrending.take(10).toList();

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
          glyph: KonekoGlyphs.history,
          tooltip: '观看历史',
          onPressed: () {
            BaseNavigator.push<void>(
              context,
              const HistoryPage(showBack: true),
            );
          },
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

          return ArrivalCacheExtentBuilder(
            builder: (context, cacheExtent) => CustomScrollView(
              controller: _scrollController,
              scrollCacheExtent: cacheExtent,
              slivers: [
                const KonekoScrollStart(),
                if (featured.isNotEmpty)
                  SliverToBoxAdapter(
                    child: RepaintBoundary(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 10),
                        child: _AnimekoHeroCarousel(
                          subjects: featured,
                          availableWidth: width,
                          onSelect: _openDetail,
                        ),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child: KonekoAutoScrollChipBar(
                      height: 46,
                      chipHeight: 34,
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      labels: _tags,
                      selectedIndex: _tags
                          .indexOf(_selectedTag)
                          .clamp(0, _tags.length - 1)
                          .toInt(),
                      onSelected: (index) => _selectTag(_tags[index]),
                    ),
                  ),
                ),
                if (subjects.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: loading.isLoading || _loadingMore
                          ? const ActivityIndicator.page()
                          : Text(loading.hasError ? '加载失败，请稍后重试' : '暂无番剧'),
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      _loadingMore ? 12 : 24 + widget.bottomPadding,
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
                        return RepaintBoundary(
                          child: UnifiedAnimeCard(
                            subject: subject,
                            isTracking: trackingIds.contains(subject.subjectId),
                            showTopRank: _selectedTag == '全部',
                            onTap: () => _openDetail(subject),
                          ),
                        );
                      }, childCount: subjects.length),
                    ),
                  ),
                  if (_loadingMore)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          0,
                          8,
                          0,
                          28 + widget.bottomPadding,
                        ),
                        child: const Center(child: ActivityIndicator()),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Authentic Animeko-style "最高热度" horizontal multi-browse hero carousel:
/// - Mobile: full-bleed rounded hero artwork card (~78% width) paired with a
///   peeking vertical slice (~18% width) that smoothly morphs & expands into
///   the active hero card as you swipe, with crisp white bottom-left title.
/// - Wide / Desktop: clean horizontal gallery of wide full-bleed artwork cards.
class _AnimekoHeroCarousel extends StatefulWidget {
  const _AnimekoHeroCarousel({
    required this.subjects,
    required this.availableWidth,
    required this.onSelect,
  });

  final List<AnimeSubject> subjects;
  final double availableWidth;
  final ValueChanged<AnimeSubject> onSelect;

  @override
  State<_AnimekoHeroCarousel> createState() => _AnimekoHeroCarouselState();
}

class _AnimekoHeroCarouselState extends State<_AnimekoHeroCarousel>
    with SingleTickerProviderStateMixin {
  static const _autoPlayInterval = Duration(seconds: 5);

  late final AnimationController _snapController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..addListener(_onSnapTick);
  final ScrollController _wideController = ScrollController();
  Timer? _autoPlayTimer;
  double _page = 0.0;
  double _snapFrom = 0.0;
  double _snapTo = 0.0;
  Curve _snapCurve = Curves.easeOutCubic;
  bool _userDragging = false;
  bool _visible = false;
  Animation<double>? _secondaryAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final secondary = route?.secondaryAnimation;
    if (!identical(secondary, _secondaryAnimation)) {
      _secondaryAnimation?.removeStatusListener(_handleSecondaryStatus);
      _secondaryAnimation = secondary
        ?..addStatusListener(_handleSecondaryStatus);
    }
    _syncVisibility();
  }

  void _handleSecondaryStatus(AnimationStatus _) => _syncVisibility();

  void _syncVisibility() {
    if (!mounted) return;
    final routeCovered =
        _secondaryAnimation != null && !_secondaryAnimation!.isDismissed;
    final visible =
        TickerMode.valuesOf(context).enabled &&
        PageActivityScope.isActiveOf(context) &&
        (ModalRoute.isCurrentOf(context) ?? true) &&
        !routeCovered;
    if (_visible == visible) return;
    _visible = visible;
    if (!visible) _snapController.stop();
    _restartAutoPlay();
  }

  @override
  void didUpdateWidget(covariant _AnimekoHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subjects.length != widget.subjects.length) {
      if (widget.subjects.isNotEmpty && _page > widget.subjects.length - 1) {
        _page = 0.0;
      }
      _restartAutoPlay();
    }
  }

  void _restartAutoPlay() {
    _autoPlayTimer?.cancel();
    if (!_visible || widget.subjects.length <= 1) return;
    _autoPlayTimer = Timer.periodic(_autoPlayInterval, (_) => _autoAdvance());
  }

  void _autoAdvance() {
    if (!mounted || _userDragging || widget.subjects.length <= 1) return;
    final isWide = widget.availableWidth >= 640;
    if (isWide) {
      if (!_wideController.hasClients) return;
      final maxExtent = _wideController.position.maxScrollExtent;
      if (maxExtent <= 0) return;
      final current = _wideController.offset;
      final next = current >= maxExtent - 16
          ? 0.0
          : (current + 280.0).clamp(0.0, maxExtent);
      unawaited(
        _wideController.animateTo(
          next,
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeInOutCubic,
        ),
      );
      return;
    }
    final nextIndex = (_page.round() + 1) % widget.subjects.length;
    _animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
    );
  }

  void _onSnapTick() {
    final t = _snapCurve.transform(_snapController.value);
    setState(() {
      _page = lerpDouble(_snapFrom, _snapTo, t)!;
    });
  }

  void _animateToPage(
    int target, {
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeOutCubic,
  }) {
    final clamped = target.clamp(0, widget.subjects.length - 1).toDouble();
    _snapFrom = _page;
    _snapTo = clamped;
    _snapCurve = curve;
    _snapController.duration = duration;
    _snapController.forward(from: 0);
  }

  @override
  void dispose() {
    _secondaryAnimation?.removeStatusListener(_handleSecondaryStatus);
    _autoPlayTimer?.cancel();
    _wideController.dispose();
    _snapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final items = widget.subjects;
    final isWide = widget.availableWidth >= 640;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            '最高热度',
            style: AppTextStyle.title3
                .of(context, emphasized: true)
                .copyWith(color: colorScheme.onSurface),
          ),
        ),
        if (isWide)
          SizedBox(
            height: 184,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification &&
                    notification.dragDetails != null) {
                  _userDragging = true;
                  _autoPlayTimer?.cancel();
                } else if (notification is ScrollEndNotification &&
                    _userDragging) {
                  _userDragging = false;
                  _restartAutoPlay();
                }
                return false;
              },
              child: ListView.separated(
                controller: _wideController,
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final subject = items[index];
                  return SizedBox(
                    width: 268,
                    child: _AnimekoArtworkCard(
                      subject: subject,
                      titleOpacity: 1.0,
                      corner: 24,
                      onTap: () => widget.onSelect(subject),
                    ),
                  );
                },
              ),
            ),
          )
        else
          _buildMobileMultiBrowse(context, items),
      ],
    );
  }

  Widget _buildMobileMultiBrowse(
    BuildContext context,
    List<AnimeSubject> items,
  ) {
    const horizontalMargin = 16.0;
    const gap = 10.0;
    const cardHeight = 212.0;
    final viewportWidth = widget.availableWidth;
    final usable = (viewportWidth - horizontalMargin * 2).clamp(160.0, 640.0);
    final single = items.length <= 1;
    final heroWidth = single ? usable : usable * 0.78;
    final peekWidth = single ? 0.0 : usable - heroWidth - gap;
    final maxPage = (items.length - 1).toDouble();
    final page = _page.clamp(0.0, maxPage);

    final lastIndex = items.length - 1;
    final endShift = items.length >= 2
        ? (page - (lastIndex - 1)).clamp(0.0, 1.0) * (peekWidth + gap)
        : 0.0;
    var cursor = horizontalMargin - page * (peekWidth + gap) + endShift;
    final slots =
        <({int index, double left, double width, double expansion})>[];
    for (var i = 0; i < items.length; i++) {
      final t = (1.0 - (i - page).abs()).clamp(0.0, 1.0);
      final w = lerpDouble(peekWidth, heroWidth, t)!;
      if (cursor + w >= -24 && cursor <= viewportWidth + 24) {
        slots.add((index: i, left: cursor, width: w, expansion: t));
      }
      cursor += w + gap;
    }

    final dragSpan = heroWidth.clamp(160.0, 360.0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: single
          ? null
          : (_) {
              _userDragging = true;
              _autoPlayTimer?.cancel();
              if (_snapController.isAnimating) {
                _snapController.stop();
              }
            },
      onHorizontalDragUpdate: single
          ? null
          : (details) {
              setState(() {
                var next = _page - details.delta.dx / dragSpan;
                if (next < 0) {
                  next = next * 0.35;
                } else if (next > maxPage) {
                  next = maxPage + (next - maxPage) * 0.35;
                }
                _page = next.clamp(-0.2, maxPage + 0.2);
              });
            },
      onHorizontalDragEnd: single
          ? null
          : (details) {
              _userDragging = false;
              final vx = details.primaryVelocity ?? 0;
              int target;
              if (vx < -240) {
                target = _page.ceil();
              } else if (vx > 240) {
                target = _page.floor();
              } else {
                target = _page.round();
              }
              _animateToPage(target);
              _restartAutoPlay();
            },
      onHorizontalDragCancel: single
          ? null
          : () {
              _userDragging = false;
              _animateToPage(_page.round());
              _restartAutoPlay();
            },
      child: SizedBox(
        height: cardHeight + 12,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final slot in slots)
              Positioned(
                left: slot.left,
                top: 4,
                width: slot.width,
                height: cardHeight,
                child: _AnimekoArtworkCard(
                  subject: items[slot.index],
                  titleOpacity: ((slot.expansion - 0.35) / 0.65).clamp(
                    0.0,
                    1.0,
                  ),
                  corner: 26,
                  onTap: () {
                    if (slot.index == page.round()) {
                      widget.onSelect(items[slot.index]);
                    } else {
                      _animateToPage(slot.index);
                      _restartAutoPlay();
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AnimekoArtworkCard extends StatelessWidget {
  const _AnimekoArtworkCard({
    required this.subject,
    required this.titleOpacity,
    required this.corner,
    this.onTap,
  });

  final AnimeSubject subject;
  final double titleOpacity;
  final double corner;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final shape = SuperellipseBorder(borderRadius: AppRadius.all(corner));

    final artwork = Stack(
      fit: StackFit.expand,
      children: [
        KonekoPosterArt(subject: subject),
        // Subtle bottom-only gradient scrim matching Animeko's clean hero style
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.46, 1.0],
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.72),
              ],
            ),
          ),
        ),
        if (titleOpacity > 0.02)
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Opacity(
              opacity: titleOpacity,
              child: Text(
                subject.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.headline
                    .of(context, emphasized: true)
                    .copyWith(
                      color: Colors.white,
                      fontSize: 16.5,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 8,
                        ),
                      ],
                    ),
              ),
            ),
          ),
      ],
    );

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: konekoCardShadows(colorScheme),
      ),
      child: onTap != null
          ? PressSurface(
              fill: SurfaceLevel.card.colorOf(colorScheme),
              shape: shape,
              clipsChild: true,
              onPressed: onTap,
              child: artwork,
            )
          : ClipRSuperellipse(
              borderRadius: AppRadius.all(corner),
              child: artwork,
            ),
    );
  }
}
