import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/catalog_page_refresh.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/detail/subject_detail_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_sheet.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

/// Discover & Condition Search Page (Kazumi filter parity in pure FlClash Sheet style,
/// intentionally without image-recognition search).
class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key, this.showBack = true, this.bottomPadding = 0});

  final bool showBack;
  final double bottomPadding;

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage>
    with
        RouteMotionHoldMixin<DiscoverPage>,
        CatalogPageRefreshMixin<DiscoverPage> {
  static const _hotQueries = [
    '葬送的芙莉莲',
    '败犬女主太多了',
    '胆大党',
    '药屋少女的呢喃',
    '孤独摇滚',
    '间谍过家家',
    '迷宫饭',
    '进击的巨人',
    '辉夜大小姐',
    '紫罗兰永恒花园',
    '命运石之门',
    '物语系列',
  ];
  static const _quickTags = [
    '奇幻',
    '日常',
    '恋爱',
    '科幻',
    '校园',
    '喜剧',
    '治愈',
    '悬疑',
    '动作',
    '冒险',
    '音乐',
    '美食',
    '催泪',
    '推理',
    '智斗',
    '热血',
    '搞笑',
    '黑暗',
    '致郁',
    '后宫',
    '轻百合',
    '百合',
    '运动',
    '机战',
    '赛博朋克',
    '时间穿越',
    '异世界',
    '乐队',
    '原创',
    '漫画改',
    '轻小说改',
    '游戏改',
    '剧场版',
    'OVA',
    '泡面番',
    '京阿尼',
    'MAPPA',
    'WIT STUDIO',
    'CloverWorks',
    'A-1 Pictures',
    '骨头社',
    'SHAFT',
  ];
  static const _sortOptions = <(String, String)>[
    ('heat', '热度优先'),
    ('score', '评分优先'),
    ('rank', '排名优先'),
    ('match', '匹配度'),
  ];
  static const _scoreThresholds = <(double?, String)>[
    (null, '不限'),
    (6.0, '6.0+'),
    (7.0, '7.0+'),
    (7.5, '7.5+'),
    (8.0, '8.0+'),
    (8.5, '8.5+'),
  ];

  final TextEditingController _controller = TextEditingController();
  SearchFilter _filter = const SearchFilter();
  bool _hideWatched = false;
  bool _hideDropped = false;

  List<AnimeSubject>? _remoteResults;
  bool _searching = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _searchError;
  int _requestId = 0;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool get _hasQueryOrFilter =>
      _filter.keyword.trim().isNotEmpty || _filter.hasActiveFilters;

  String _sortLabel(String sort) => _sortOptions
      .firstWhere((e) => e.$1 == sort, orElse: () => ('heat', '热度优先'))
      .$2;

  void _onKeywordChanged(String value) {
    final next = _filter.copyWith(keyword: value);
    setState(() => _filter = next);
    _debounce?.cancel();
    if (!next.hasActiveFilters && value.trim().isEmpty) {
      setState(() {
        _remoteResults = null;
        _searchError = null;
        _searching = false;
        _hasMore = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_executeSearch(next));
    });
  }

  void _applyQuery(String q) {
    _controller.value = TextEditingValue(
      text: q,
      selection: TextSelection.collapsed(offset: q.length),
    );
    final next = _filter.copyWith(keyword: q);
    setState(() => _filter = next);
    unawaited(_executeSearch(next));
  }

  Future<void> _executeSearch(
    SearchFilter filter, {
    bool append = false,
  }) async {
    final online = ref.read(onlineCatalogProvider);
    if (online == null) {
      setState(() {
        _remoteResults = null;
        _searching = false;
        _loadingMore = false;
        _hasMore = false;
        _searchError = null;
      });
      return;
    }

    final token = ++_requestId;
    final offset = append ? (_remoteResults?.length ?? 0) : 0;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _searching = true;
        _searchError = null;
      }
    });

    try {
      final page = await online.searchFiltered(
        filter,
        offset: offset,
        limit: 30,
      );
      if (!mounted || token != _requestId) return;
      setState(() {
        if (append) {
          final merged = <int, AnimeSubject>{
            for (final item in _remoteResults ?? const <AnimeSubject>[])
              item.subjectId: item,
            for (final item in page) item.subjectId: item,
          };
          _remoteResults = merged.values.toList();
        } else {
          _remoteResults = page;
        }
        _hasMore = page.length >= 30;
        _searching = false;
        _loadingMore = false;
      });
    } on Object {
      if (!mounted || token != _requestId) return;
      setState(() {
        _searching = false;
        _loadingMore = false;
        if (!append) {
          _searchError = '条件搜索失败，请检查网络后重试';
        }
      });
      if (append && mounted) {
        showKonekoBanner(context, '加载更多结果失败', level: BannerLevel.error);
      }
    }
  }

  Future<void> _openFilterSheet() async {
    var draft = _filter;
    var draftHideWatched = _hideWatched;
    var draftHideDropped = _hideDropped;
    final now = DateTime.now();
    final recentSeasons = <AnimeSeason>[];
    var y = now.year;
    var q = ((now.month - 1) ~/ 3) + 1;
    for (var i = 0; i < 8; i++) {
      recentSeasons.add(AnimeSeason(year: y, quarter: q));
      q--;
      if (q < 1) {
        q = 4;
        y--;
      }
    }
    final recentYears = List<int>.generate(10, (i) => now.year - i);

    final applied = await showKonekoSheet<bool>(
      context: context,
      title: '按条件搜索',
      detents: const [0.78, 0.94],
      bodyBuilder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final colorScheme = sheetContext.colorScheme;
            Future<void> openCustomTagDialog() async {
              final value = await showFloatingDialog<String>(
                context: sheetContext,
                child: const InputDialog(
                  title: '添加自定义标签',
                  value: '',
                  hintText: '例如：京阿尼、剧场版、科幻',
                ),
              );
              final tag = value?.trim() ?? '';
              if (tag.isEmpty || draft.tags.contains(tag)) return;
              draft = draft.copyWith(tags: [...draft.tags, tag]);
              setSheetState(() {});
            }

            final allTags = <String>{..._quickTags, ...draft.tags};

            return ArrivalCacheExtentBuilder(
              builder: (context, cacheExtent) => ListView.builder(
                scrollCacheExtent: cacheExtent,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                itemCount: 5,
                itemBuilder: (context, index) => switch (index) {
                  0 => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ListHeader(title: '排序方式'),
                      KonekoCard(
                        corner: 22,
                        padding: const EdgeInsets.all(14),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final (value, label) in _sortOptions)
                              KonekoChip(
                                label: label,
                                height: 34,
                                fontSize: 13,
                                selected: draft.sort == value,
                                backgroundColor: draft.sort == value
                                    ? colorScheme.primary
                                    : SurfaceLevel.block.colorOf(colorScheme),
                                onPressed: () {
                                  draft = draft.copyWith(sort: value);
                                  setSheetState(() {});
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  1 => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListHeader(
                        title: '题材标签',
                        caption: draft.tags.isEmpty
                            ? '可多选'
                            : '已选：${draft.tags.join('、')}',
                      ),
                      KonekoCard(
                        corner: 22,
                        padding: const EdgeInsets.all(14),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in allTags)
                              KonekoChip(
                                label: tag,
                                height: 32,
                                fontSize: 12.5,
                                selected: draft.tags.contains(tag),
                                backgroundColor: draft.tags.contains(tag)
                                    ? colorScheme.primary
                                    : SurfaceLevel.block.colorOf(colorScheme),
                                onPressed: () {
                                  final nextTags = draft.tags.contains(tag)
                                      ? draft.tags
                                            .where((t) => t != tag)
                                            .toList()
                                      : [...draft.tags, tag];
                                  draft = draft.copyWith(tags: nextTags);
                                  setSheetState(() {});
                                },
                              ),
                            KonekoChip(
                              label: '自定义标签',
                              height: 32,
                              fontSize: 12.5,
                              leading: GlyphIcon(
                                KonekoGlyphs.add,
                                size: 13,
                                color: colorScheme.primary,
                              ),
                              backgroundColor: colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              foregroundColor: colorScheme.primary,
                              onPressed: () => unawaited(openCustomTagDialog()),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  2 => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ListHeader(title: '放送季度与年份'),
                      KonekoCard(
                        corner: 22,
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 10,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                KonekoChip(
                                  label: '不限时间',
                                  height: 32,
                                  fontSize: 12.5,
                                  selected:
                                      draft.season == null &&
                                      draft.year == null,
                                  backgroundColor:
                                      draft.season == null && draft.year == null
                                      ? colorScheme.primary
                                      : SurfaceLevel.block.colorOf(colorScheme),
                                  onPressed: () {
                                    draft = draft.copyWith(
                                      season: null,
                                      year: null,
                                    );
                                    setSheetState(() {});
                                  },
                                ),
                                for (final s in recentSeasons)
                                  KonekoChip(
                                    label: s.shortLabel,
                                    height: 32,
                                    fontSize: 12.5,
                                    selected: draft.season == s,
                                    backgroundColor: draft.season == s
                                        ? colorScheme.primary
                                        : SurfaceLevel.block.colorOf(
                                            colorScheme,
                                          ),
                                    onPressed: () {
                                      draft = draft.copyWith(
                                        season: draft.season == s ? null : s,
                                        year: null,
                                      );
                                      setSheetState(() {});
                                    },
                                  ),
                              ],
                            ),
                            Text(
                              '按年份',
                              style: AppTextStyle.caption1
                                  .of(sheetContext, emphasized: true)
                                  .copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final year in recentYears)
                                  KonekoChip(
                                    label: '$year',
                                    height: 30,
                                    fontSize: 12,
                                    selected: draft.year == year,
                                    backgroundColor: draft.year == year
                                        ? colorScheme.primary
                                        : SurfaceLevel.block.colorOf(
                                            colorScheme,
                                          ),
                                    onPressed: () {
                                      draft = draft.copyWith(
                                        year: draft.year == year ? null : year,
                                        season: null,
                                      );
                                      setSheetState(() {});
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  3 => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ListHeader(title: '星期与最低评分'),
                      KonekoCard(
                        corner: 22,
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 12,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (var day = 1; day <= 7; day++)
                                  KonekoChip(
                                    label: '周${'一二三四五六日'[day - 1]}',
                                    height: 30,
                                    fontSize: 12,
                                    selected: draft.weekdays.contains(day),
                                    backgroundColor:
                                        draft.weekdays.contains(day)
                                        ? colorScheme.primary
                                        : SurfaceLevel.block.colorOf(
                                            colorScheme,
                                          ),
                                    onPressed: () {
                                      final next = draft.weekdays.toSet();
                                      if (!next.add(day)) next.remove(day);
                                      draft = draft.copyWith(
                                        weekdays: next.toList()..sort(),
                                      );
                                      setSheetState(() {});
                                    },
                                  ),
                              ],
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final (score, label) in _scoreThresholds)
                                  KonekoChip(
                                    label: score == null
                                        ? '评分不限'
                                        : '评分 $label',
                                    height: 30,
                                    fontSize: 12,
                                    selected: draft.minScore == score,
                                    backgroundColor: draft.minScore == score
                                        ? colorScheme.primary
                                        : SurfaceLevel.block.colorOf(
                                            colorScheme,
                                          ),
                                    onPressed: () {
                                      draft = draft.copyWith(minScore: score);
                                      setSheetState(() {});
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  _ => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ListHeader(title: '收藏状态过滤'),
                      KonekoGroup(
                        items: [
                          DecorationListItem(
                            title: const Text('隐藏看过的番剧'),
                            trailing: Switch(
                              value: draftHideWatched,
                              onChanged: (value) {
                                draftHideWatched = value;
                                setSheetState(() {});
                              },
                            ),
                            onPressed: () {
                              draftHideWatched = !draftHideWatched;
                              setSheetState(() {});
                            },
                          ),
                          DecorationListItem(
                            title: const Text('隐藏抛弃的番剧'),
                            trailing: Switch(
                              value: draftHideDropped,
                              onChanged: (value) {
                                draftHideDropped = value;
                                setSheetState(() {});
                              },
                            ),
                            onPressed: () {
                              draftHideDropped = !draftHideDropped;
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                },
              ),
            );
          },
        );
      },
      footerBuilder: (sheetContext) => Row(
        spacing: 12,
        children: [
          TextButton(
            onPressed: () {
              draft = SearchFilter(keyword: draft.keyword);
              draftHideWatched = false;
              draftHideDropped = false;
              Navigator.of(sheetContext).pop(true);
            },
            child: const Text('重置条件'),
          ),
          Expanded(
            child: FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              child: const Text('应用筛选'),
            ),
          ),
        ],
      ),
    );

    if (!mounted || applied != true) return;
    setState(() {
      _filter = draft;
      _hideWatched = draftHideWatched;
      _hideDropped = draftHideDropped;
    });
    if (_hasQueryOrFilter) {
      await _executeSearch(draft);
    } else {
      setState(() {
        _remoteResults = null;
        _searchError = null;
        _hasMore = false;
      });
    }
  }

  List<AnimeSubject> _localFallback(CatalogRepository catalog) {
    final base = catalog.search(_filter.keyword);
    final filtered = base.where((s) {
      if (_filter.tags.isNotEmpty &&
          !_filter.tags.every((t) => s.tags.any((st) => st.contains(t)))) {
        return false;
      }
      if (_filter.year != null && s.year != _filter.year) return false;
      if (_filter.season != null && s.year != _filter.season!.year) {
        return false;
      }
      if (_filter.minScore != null && s.score < _filter.minScore!) {
        return false;
      }
      if (_filter.weekdays.isNotEmpty &&
          !_filter.weekdays.contains(s.weekday)) {
        return false;
      }
      return true;
    }).toList();
    if (_filter.sort == 'score') {
      filtered.sort((a, b) => b.score.compareTo(a.score));
    } else if (_filter.sort == 'rank') {
      filtered.sort((a, b) => a.rank.compareTo(b.rank));
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final catalog = ref.watch(catalogRepositoryProvider);
    final library = ref.watch(libraryProvider);
    final statusMap = <int, CollectionStatus>{
      for (final e in library) e.subjectId: e.status,
    };
    final trackingIds = {
      for (final e in library)
        if (e.status == CollectionStatus.watching) e.subjectId,
    };

    final rawList = _hasQueryOrFilter
        ? (_remoteResults ?? _localFallback(catalog))
        : catalog.getTrending();
    final results = rawList.where((s) {
      final status = statusMap[s.subjectId];
      if (_hideWatched && status == CollectionStatus.watched) return false;
      if (_hideDropped && status == CollectionStatus.dropped) return false;
      return true;
    }).toList();

    final filterCount =
        _filter.activeFilterCount +
        (_hideWatched ? 1 : 0) +
        (_hideDropped ? 1 : 0);

    return KonekoScaffold(
      title: '发现搜索',
      showBack: widget.showBack,
      loading: _searching,
      actions: [
        IconButtonData(
          glyph: KonekoGlyphs.tune,
          tooltip: filterCount > 0 ? '按条件筛选（已选 $filterCount 项）' : '按条件筛选',
          onPressed: _openFilterSheet,
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
              scrollCacheExtent: cacheExtent,
              slivers: [
                const KonekoScrollStart(),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        shape: AppShape.full,
                        shadows: konekoPillShadows(colorScheme),
                      ),
                      child: SearchField(
                        controller: _controller,
                        fill: SurfaceLevel.card.colorOf(colorScheme),
                        hintText: '搜索 Bangumi 番名或原名…',
                        onChanged: _onKeywordChanged,
                      ),
                    ),
                  ),
                ),
                // Condition search bar & active filter summary (Kazumi parity in FlClash style)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        KonekoChip(
                          label: filterCount > 0
                              ? '按条件查找 · 已选 $filterCount 项'
                              : '按条件查找',
                          height: 32,
                          fontSize: 12.5,
                          elevated: true,
                          selected: filterCount > 0,
                          backgroundColor: filterCount > 0
                              ? colorScheme.primary
                              : SurfaceLevel.card.colorOf(colorScheme),
                          leading: GlyphIcon(
                            KonekoGlyphs.tune,
                            size: 13,
                            color: filterCount > 0
                                ? colorScheme.onPrimary
                                : colorScheme.primary,
                          ),
                          onPressed: _openFilterSheet,
                        ),
                        if (_filter.sort != 'heat')
                          KonekoChip(
                            label: _sortLabel(_filter.sort),
                            height: 32,
                            fontSize: 12,
                            elevated: true,
                            backgroundColor: SurfaceLevel.card.colorOf(
                              colorScheme,
                            ),
                            onPressed: _openFilterSheet,
                          ),
                        for (final tag in _filter.tags)
                          KonekoChip(
                            label: tag,
                            height: 32,
                            fontSize: 12,
                            elevated: true,
                            backgroundColor: SurfaceLevel.card.colorOf(
                              colorScheme,
                            ),
                            foregroundColor: colorScheme.primary,
                            onPressed: _openFilterSheet,
                          ),
                        if (_filter.season case final season?)
                          KonekoChip(
                            label: season.shortLabel,
                            height: 32,
                            fontSize: 12,
                            elevated: true,
                            backgroundColor: SurfaceLevel.card.colorOf(
                              colorScheme,
                            ),
                            onPressed: _openFilterSheet,
                          )
                        else if (_filter.year case final year?)
                          KonekoChip(
                            label: '$year 年',
                            height: 32,
                            fontSize: 12,
                            elevated: true,
                            backgroundColor: SurfaceLevel.card.colorOf(
                              colorScheme,
                            ),
                            onPressed: _openFilterSheet,
                          ),
                        if (_filter.minScore case final minScore?)
                          KonekoChip(
                            label: '评分 ${minScore.toStringAsFixed(1)}+',
                            height: 32,
                            fontSize: 12,
                            elevated: true,
                            backgroundColor: SurfaceLevel.card.colorOf(
                              colorScheme,
                            ),
                            onPressed: _openFilterSheet,
                          ),
                        if (filterCount > 0)
                          KonekoChip(
                            label: '清空条件',
                            height: 32,
                            fontSize: 12,
                            elevated: true,
                            backgroundColor: SurfaceLevel.card.colorOf(
                              colorScheme,
                            ),
                            onPressed: () {
                              final reset = SearchFilter(
                                keyword: _filter.keyword,
                              );
                              setState(() {
                                _filter = reset;
                                _hideWatched = false;
                                _hideDropped = false;
                              });
                              if (_hasQueryOrFilter) {
                                unawaited(_executeSearch(reset));
                              } else {
                                setState(() {
                                  _remoteResults = null;
                                  _hasMore = false;
                                });
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                if (!_hasQueryOrFilter)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 8,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final hot in _hotQueries)
                                KonekoChip(
                                  label: '# $hot',
                                  height: 28,
                                  fontSize: 12,
                                  elevated: true,
                                  backgroundColor: SurfaceLevel.card.colorOf(
                                    colorScheme,
                                  ),
                                  onPressed: () => _applyQuery(hot),
                                ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final tag in const [
                                '奇幻',
                                '恋爱',
                                '日常',
                                '校园',
                                '科幻',
                                '悬疑',
                                '治愈',
                                '喜剧',
                                '动作',
                                '催泪',
                                '剧场版',
                                '京阿尼',
                              ])
                                KonekoChip(
                                  label: tag,
                                  height: 28,
                                  fontSize: 12,
                                  elevated: true,
                                  backgroundColor: SurfaceLevel.card.colorOf(
                                    colorScheme,
                                  ),
                                  foregroundColor: colorScheme.primary,
                                  onPressed: () {
                                    final next = _filter.copyWith(tags: [tag]);
                                    setState(() => _filter = next);
                                    unawaited(_executeSearch(next));
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_searching)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: ActivityIndicator.page()),
                  )
                else if (_searchError != null && results.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: TextButton(
                        onPressed: () => unawaited(_executeSearch(_filter)),
                        child: Text(_searchError!),
                      ),
                    ),
                  )
                else if (results.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        _hasQueryOrFilter ? '未找到符合条件的番剧' : '输入番名或点击「按条件查找」开始探索',
                        style: AppTextStyle.subheadline
                            .of(context)
                            .copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      _hasMore ? 12 : 24 + widget.bottomPadding,
                    ),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 14,
                        childAspectRatio: 0.56,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final subject = results[index];
                        return UnifiedAnimeCard(
                          subject: subject,
                          isTracking: trackingIds.contains(subject.subjectId),
                          onTap: () => BaseNavigator.push<void>(
                            context,
                            SubjectDetailPage(subjectId: subject.subjectId),
                          ),
                        );
                      }, childCount: results.length),
                    ),
                  ),
                  if (_hasMore)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          4,
                          16,
                          24 + widget.bottomPadding,
                        ),
                        child: Center(
                          child: KonekoChip(
                            label: _loadingMore ? '正在加载...' : '加载更多结果',
                            height: 36,
                            fontSize: 13,
                            backgroundColor: colorScheme.primary.withValues(
                              alpha: 0.14,
                            ),
                            foregroundColor: colorScheme.primary,
                            onPressed: _loadingMore
                                ? null
                                : () => unawaited(
                                    _executeSearch(_filter, append: true),
                                  ),
                          ),
                        ),
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
