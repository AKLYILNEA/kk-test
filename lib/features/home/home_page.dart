import 'dart:async';
import 'dart:ui' show ImageFilter;

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
    final featured = allTrending.take(8).toList();

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
                    padding: const EdgeInsets.only(top: 4, bottom: 10),
                    child: _AnimekoTrendingCarousel(
                      subjects: featured,
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
                        : Text(
                            loading.hasError ? '加载失败，请稍后重试' : '暂无番剧',
                          ),
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

/// Animeko-style silky horizontal hot-anime showcase carousel with smooth
/// scale/parallax transitions, blurred backdrop artwork, and expanding dots.
class _AnimekoTrendingCarousel extends StatefulWidget {
  const _AnimekoTrendingCarousel({
    required this.subjects,
    required this.onSelect,
  });

  final List<AnimeSubject> subjects;
  final ValueChanged<AnimeSubject> onSelect;

  @override
  State<_AnimekoTrendingCarousel> createState() =>
      _AnimekoTrendingCarouselState();
}

class _AnimekoTrendingCarouselState extends State<_AnimekoTrendingCarousel> {
  late final PageController _controller = PageController(
    viewportFraction: 0.90,
  );
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
    final safePage = _page.clamp(0, items.length - 1).toInt();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 186,
          child: PageView.builder(
            controller: _controller,
            clipBehavior: Clip.none,
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            onPageChanged: (index) => setState(() => _page = index),
            itemBuilder: (context, index) {
              final subject = items[index];
              return AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  var distance = (index - safePage).abs().toDouble();
                  if (_controller.position.haveDimensions) {
                    final current =
                        _controller.page ?? _controller.initialPage.toDouble();
                    distance = (index - current).abs();
                  }
                  final scale = (1.0 - distance * 0.055).clamp(0.92, 1.0);
                  final opacity = (1.0 - distance * 0.18).clamp(0.78, 1.0);
                  return Transform.scale(
                    scale: scale,
                    alignment: Alignment.center,
                    child: Opacity(opacity: opacity, child: child),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 6,
                  ),
                  child: _FeaturedAnimeSlide(
                    subject: subject,
                    rankIndex: index + 1,
                    onTap: () => widget.onSelect(subject),
                  ),
                ),
              );
            },
          ),
        ),
        if (items.length > 1) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 5,
            children: [
              for (var i = 0; i < items.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  width: i == safePage ? 18 : 6,
                  height: 6,
                  decoration: ShapeDecoration(
                    color: i == safePage
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.28),
                    shape: AppShape.full,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FeaturedAnimeSlide extends StatelessWidget {
  const _FeaturedAnimeSlide({
    required this.subject,
    required this.rankIndex,
    required this.onTap,
  });

  final AnimeSubject subject;
  final int rankIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final shape = SuperellipseBorder(borderRadius: AppRadius.all(24));

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: konekoCardShadows(colorScheme),
      ),
      child: PressSurface(
        fill: SurfaceLevel.card.colorOf(colorScheme),
        shape: shape,
        clipsChild: true,
        onPressed: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Soft blurred cover backdrop
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Transform.scale(
                scale: 1.15,
                child: KonekoPosterArt(subject: subject),
              ),
            ),
            // Cinematic dark scrim for crisp readability
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.42),
                    Colors.black.withValues(alpha: 0.76),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Crisp foreground mini-poster
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: SuperellipseBorder(
                        borderRadius: AppRadius.all(14),
                      ),
                      shadows: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: 96,
                      height: 136,
                      child: KonekoPosterArt(
                        subject: subject,
                        borderRadius: AppRadius.all(14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            KonekoChip(
                              label: '热门 #$rankIndex',
                              height: 22,
                              fontSize: 10.5,
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                            ),
                            if (subject.score > 0)
                              KonekoChip(
                                label: subject.score.toStringAsFixed(1),
                                height: 22,
                                fontSize: 10.5,
                                leading: const GlyphIcon(
                                  KonekoGlyphs.star,
                                  size: 10.5,
                                  color: Color(0xFFFFC145),
                                ),
                                backgroundColor: Colors.black.withValues(
                                  alpha: 0.45,
                                ),
                                foregroundColor: Colors.white,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subject.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.headline
                              .of(context, emphasized: true)
                              .copyWith(
                                color: Colors.white,
                                fontSize: 16,
                                height: 1.24,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subjectMetaCaption(subject),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.caption1
                              .of(context)
                              .copyWith(
                                color: Colors.white.withValues(alpha: 0.78),
                              ),
                        ),
                        if (subject.tags.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 5,
                            runSpacing: 4,
                            children: [
                              for (final tag in subject.tags.take(3))
                                KonekoChip(
                                  label: tag,
                                  height: 20,
                                  fontSize: 10,
                                  backgroundColor: Colors.white.withValues(
                                    alpha: 0.16,
                                  ),
                                  foregroundColor: Colors.white.withValues(
                                    alpha: 0.92,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
