import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    ref.watch(catalogUpdatesProvider);
    final catalog = ref.watch(catalogRepositoryProvider);
    final loading = ref.watch(loadHomeCatalogProvider);
    final library = ref.watch(libraryProvider);

    final allTrending = catalog.getTrending();
    final subjects = catalog.getTrending(tag: _selectedTag);
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
            BaseNavigator.push<void>(context, const HistoryPage(showBack: true));
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

          return CustomScrollView(
            controller: _scrollController,
            scrollCacheExtent: const ScrollCacheExtent.pixels(900),
            slivers: [
              const KonekoScrollStart(),
              if (featured.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 10),
                    child: _AnimekoHeroCarousel(
                      subjects: featured,
                      availableWidth: width,
                      onSelect: _openDetail,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
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
              if (subjects.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: loading.isLoading || _loadingMore
                        ? const ActivityIndicator()
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
                      return UnifiedAnimeCard(
                        subject: subject,
                        isTracking: trackingIds.contains(subject.subjectId),
                        showTopRank: _selectedTag == '全部',
                        onTap: () => _openDetail(subject),
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

class _AnimekoHeroCarouselState extends State<_AnimekoHeroCarousel> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
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
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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

    List<({int index, double left, double width, double expansion})> layoutFor(
      double page,
    ) {
      final lastIndex = items.length - 1;
      final endShift = items.length >= 2
          ? (page - (lastIndex - 1)).clamp(0.0, 1.0) * (peekWidth + gap)
          : 0.0;
      var cursor = horizontalMargin - page * (peekWidth + gap) + endShift;
      final rects =
          <({int index, double left, double width, double expansion})>[];
      for (var i = 0; i < items.length; i++) {
        final t = (1.0 - (i - page).abs()).clamp(0.0, 1.0);
        final w = lerpDouble(peekWidth, heroWidth, t)!;
        if (cursor + w >= -24 && cursor <= viewportWidth + 24) {
          rects.add((index: i, left: cursor, width: w, expansion: t));
        }
        cursor += w + gap;
      }
      return rects;
    }

    double currentPage() {
      if (_controller.hasClients && _controller.position.haveDimensions) {
        return (_controller.page ?? _page.toDouble()).clamp(
          0.0,
          (items.length - 1).toDouble(),
        );
      }
      return _page.clamp(0, items.length - 1).toDouble();
    }

    void handleTapAt(double dx) {
      final page = currentPage();
      final slots = layoutFor(page);
      for (final slot in slots) {
        if (dx >= slot.left && dx <= slot.left + slot.width) {
          if (slot.index == page.round()) {
            widget.onSelect(items[slot.index]);
          } else {
            unawaited(
              _controller.animateToPage(
                slot.index,
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
              ),
            );
          }
          return;
        }
      }
    }

    return SizedBox(
      height: cardHeight + 12,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final slots = layoutFor(currentPage());
              return Stack(
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
                      ),
                    ),
                ],
              );
            },
          ),
          // Transparent native PageView provides silky 120fps physics & snapping.
          Positioned.fill(
            child: PageView.builder(
              controller: _controller,
              physics: const BouncingScrollPhysics(),
              itemCount: items.length,
              onPageChanged: (index) => setState(() => _page = index),
              itemBuilder: (_, _) => GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (details) => handleTapAt(details.localPosition.dx),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
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
