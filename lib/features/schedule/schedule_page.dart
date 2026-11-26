import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/detail/subject_detail_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_sheet.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

enum _ScheduleSort {
  defaultOrder('默认顺序'),
  rating('评分优先'),
  popularity('热度排名');

  const _ScheduleSort(this.label);
  final String label;
}

class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({super.key, this.bottomPadding = 0});

  final double bottomPadding;

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  static const _weekdays = [
    (1, '月', '周一'),
    (2, '火', '周二'),
    (3, '水', '周三'),
    (4, '木', '周四'),
    (5, '金', '周五'),
    (6, '土', '周六'),
    (7, '日', '周日'),
  ];

  int _selectedDay = DateTime.now().weekday;
  AnimeSeason _season = AnimeSeason.current();
  _ScheduleSort _sort = _ScheduleSort.defaultOrder;
  bool _hideWatched = false;
  bool _hideDropped = false;
  bool _onlyWatching = false;

  Map<int, List<AnimeSubject>>? _seasonCalendar;
  bool _seasonLoading = false;
  String? _seasonError;
  int _seasonRequest = 0;

  int get _activeOptionCount {
    var count = 0;
    if (!_season.isCurrent) count++;
    if (_sort != _ScheduleSort.defaultOrder) count++;
    if (_hideWatched) count++;
    if (_hideDropped) count++;
    if (_onlyWatching) count++;
    return count;
  }

  Future<void> _selectSeason(AnimeSeason next) async {
    if (_season == next && _seasonError == null) return;
    final token = ++_seasonRequest;
    setState(() {
      _season = next;
      _seasonError = null;
      if (next.isCurrent) {
        _seasonCalendar = null;
        _seasonLoading = false;
      } else {
        _seasonCalendar = null;
        _seasonLoading = true;
      }
    });
    if (next.isCurrent) return;

    final online = ref.read(onlineCatalogProvider);
    if (online == null) {
      if (mounted && token == _seasonRequest) {
        setState(() => _seasonLoading = false);
      }
      return;
    }

    try {
      final result = await online.loadSeasonCalendar(next);
      if (!mounted || token != _seasonRequest) return;
      setState(() {
        _seasonCalendar = result;
        _seasonLoading = false;
      });
    } on Object {
      if (!mounted || token != _seasonRequest) return;
      setState(() {
        _seasonLoading = false;
        _seasonError = '${next.label} 加载失败，请重试';
      });
    }
  }

  Future<void> _openSettingsSheet() async {
    final now = DateTime.now();
    final years = List<int>.generate(16, (i) => now.year - i);

    await showKonekoSheet<void>(
      context: context,
      title: '放送时间表设置',
      subtitle: '当前查看：${_season.label}',
      detents: const [0.74, 0.92],
      actions: [
        if (!_season.isCurrent)
          IconButtonData(
            glyph: KonekoGlyphs.reset,
            tooltip: '回到本季',
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(_selectSeason(AnimeSeason.current()));
            },
          ),
      ],
      bodyBuilder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final colorScheme = sheetContext.colorScheme;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                // Sort section
                const ListHeader(title: '排序方式'),
                KonekoCard(
                  corner: 22,
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in _ScheduleSort.values)
                        KonekoChip(
                          label: option.label,
                          height: 34,
                          fontSize: 13,
                          selected: _sort == option,
                          backgroundColor: _sort == option
                              ? colorScheme.primary
                              : SurfaceLevel.block.colorOf(colorScheme),
                          onPressed: () {
                            setState(() => _sort = option);
                            setSheetState(() {});
                          },
                        ),
                    ],
                  ),
                ),

                // Visibility filter section (Kazumi parity)
                const ListHeader(title: '显示范围'),
                generateGroup([
                  DecorationListItem(
                    title: const Text('只看正在追的番剧'),
                    subtitle: const Text('仅显示追番状态为「在看」的条目'),
                    trailing: Switch(
                      value: _onlyWatching,
                      onChanged: (value) {
                        setState(() => _onlyWatching = value);
                        setSheetState(() {});
                      },
                    ),
                    onPressed: () {
                      setState(() => _onlyWatching = !_onlyWatching);
                      setSheetState(() {});
                    },
                  ),
                  DecorationListItem(
                    title: const Text('隐藏看过的番剧'),
                    trailing: Switch(
                      value: _hideWatched,
                      onChanged: (value) {
                        setState(() => _hideWatched = value);
                        setSheetState(() {});
                      },
                    ),
                    onPressed: () {
                      setState(() => _hideWatched = !_hideWatched);
                      setSheetState(() {});
                    },
                  ),
                  DecorationListItem(
                    title: const Text('隐藏抛弃的番剧'),
                    trailing: Switch(
                      value: _hideDropped,
                      onChanged: (value) {
                        setState(() => _hideDropped = value);
                        setSheetState(() {});
                      },
                    ),
                    onPressed: () {
                      setState(() => _hideDropped = !_hideDropped);
                      setSheetState(() {});
                    },
                  ),
                ]),

                // Year & Season Picker (Kazumi parity)
                ListHeader(
                  title: '切换年份与季度',
                  trailing: !_season.isCurrent
                      ? KonekoChip(
                          label: '回到本季',
                          height: 26,
                          fontSize: 11.5,
                          backgroundColor: colorScheme.primary.withValues(
                            alpha: 0.14,
                          ),
                          foregroundColor: colorScheme.primary,
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            unawaited(_selectSeason(AnimeSeason.current()));
                          },
                        )
                      : null,
                ),
                Column(
                  spacing: 10,
                  children: [
                    for (final year in years)
                      KonekoCard(
                        corner: 22,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 8,
                          children: [
                            Text(
                              '$year 年',
                              style: AppTextStyle.subheadline
                                  .of(sheetContext, emphasized: true)
                                  .copyWith(color: colorScheme.onSurface),
                            ),
                            Row(
                              spacing: 8,
                              children: [
                                for (var q = 1; q <= 4; q++)
                                  Expanded(
                                    child: Builder(
                                      builder: (_) {
                                        final target = AnimeSeason(
                                          year: year,
                                          quarter: q,
                                        );
                                        final selected = target == _season;
                                        final disabled = target.isAfter(now);
                                        return KonekoBlock(
                                          corner: 14,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          selected: selected,
                                          color: selected
                                              ? colorScheme.primary
                                              : disabled
                                              ? SurfaceLevel.block
                                                    .colorOf(colorScheme)
                                                    .withValues(alpha: 0.45)
                                              : SurfaceLevel.block.colorOf(
                                                  colorScheme,
                                                ),
                                          onPressed: disabled
                                              ? null
                                              : () {
                                                  Navigator.of(
                                                    sheetContext,
                                                  ).pop();
                                                  unawaited(
                                                    _selectSeason(target),
                                                  );
                                                },
                                          child: Center(
                                            child: Text(
                                              '${target.seasonName}季',
                                              style: AppTextStyle.footnote
                                                  .of(
                                                    sheetContext,
                                                    emphasized: selected,
                                                  )
                                                  .copyWith(
                                                    color: selected
                                                        ? colorScheme.onPrimary
                                                        : disabled
                                                        ? colorScheme
                                                              .onSurfaceVariant
                                                              .withValues(
                                                                alpha: 0.42,
                                                              )
                                                        : colorScheme.onSurface,
                                                  ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<AnimeSubject> _subjectsForDay(
    CatalogRepository catalog,
    int day,
    Map<int, CollectionStatus> statusMap,
  ) {
    final raw = _season.isCurrent
        ? catalog.getByWeekday(day)
        : (_seasonCalendar?[day] ?? const <AnimeSubject>[]);
    final filtered = raw.where((subject) {
      final status = statusMap[subject.subjectId];
      if (_onlyWatching && status != CollectionStatus.watching) return false;
      if (_hideWatched && status == CollectionStatus.watched) return false;
      if (_hideDropped && status == CollectionStatus.dropped) return false;
      return true;
    }).toList();

    switch (_sort) {
      case _ScheduleSort.defaultOrder:
        break;
      case _ScheduleSort.rating:
        filtered.sort((a, b) => b.score.compareTo(a.score));
      case _ScheduleSort.popularity:
        filtered.sort((a, b) {
          final ra = a.rank > 0 ? a.rank : 999999;
          final rb = b.rank > 0 ? b.rank : 999999;
          return ra.compareTo(rb);
        });
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    ref.watch(catalogUpdatesProvider);
    final catalog = ref.watch(catalogRepositoryProvider);
    final loading = ref.watch(loadHomeCatalogProvider);
    final library = ref.watch(libraryProvider);
    final statusMap = <int, CollectionStatus>{
      for (final e in library) e.subjectId: e.status,
    };

    final items = _subjectsForDay(catalog, _selectedDay, statusMap);
    final isLoading = _season.isCurrent ? loading.isLoading : _seasonLoading;
    final hasError = _season.isCurrent
        ? loading.hasError
        : _seasonError != null;
    final title = _season.isCurrent
        ? (ref.watch(onlineCatalogProvider)?.seasonTitle ?? _season.label)
        : _season.label;

    return KonekoScaffold(
      title: title,
      actions: [
        IconButtonData(
          glyph: KonekoGlyphs.tune,
          tooltip: _activeOptionCount > 0
              ? '放送设置（已启用 $_activeOptionCount 项）'
              : '放送设置与季度切换',
          onPressed: _openSettingsSheet,
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;
          return CustomScrollView(
            scrollCacheExtent: const ScrollCacheExtent.pixels(600),
            slivers: [
              const KonekoScrollStart(),
              SliverToBoxAdapter(
                child: KonekoAutoScrollChipBar(
                  height: 48,
                  chipHeight: 36,
                  fontSize: 13,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  labels: [
                    for (final (dayNum, jp, cn) in _weekdays)
                      '$jp · $cn  ${_subjectsForDay(catalog, dayNum, statusMap).length}',
                  ],
                  selectedIndex: (_selectedDay - 1).clamp(0, 6).toInt(),
                  onSelected: (index) =>
                      setState(() => _selectedDay = _weekdays[index].$1),
                ),
              ),
              if (_activeOptionCount > 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (!_season.isCurrent)
                          KonekoChip(
                            label: '${_season.shortLabel} · 回到本季',
                            height: 28,
                            fontSize: 12,
                            elevated: true,
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            onPressed: () =>
                                unawaited(_selectSeason(AnimeSeason.current())),
                          ),
                        if (_sort != _ScheduleSort.defaultOrder)
                          KonekoChip(
                            label: _sort.label,
                            height: 28,
                            fontSize: 12,
                            elevated: true,
                            backgroundColor: SurfaceLevel.card.colorOf(
                              colorScheme,
                            ),
                            onPressed: _openSettingsSheet,
                          ),
                        if (_onlyWatching)
                          KonekoChip(
                            label: '仅看在追',
                            height: 28,
                            fontSize: 12,
                            elevated: true,
                            backgroundColor: SurfaceLevel.card.colorOf(
                              colorScheme,
                            ),
                            onPressed: () =>
                                setState(() => _onlyWatching = false),
                          ),
                        if (_hideWatched)
                          KonekoChip(
                            label: '隐藏看过',
                            height: 28,
                            fontSize: 12,
                            elevated: true,
                            backgroundColor: SurfaceLevel.card.colorOf(
                              colorScheme,
                            ),
                            onPressed: () =>
                                setState(() => _hideWatched = false),
                          ),
                        if (_hideDropped)
                          KonekoChip(
                            label: '隐藏抛弃',
                            height: 28,
                            fontSize: 12,
                            elevated: true,
                            backgroundColor: SurfaceLevel.card.colorOf(
                              colorScheme,
                            ),
                            onPressed: () =>
                                setState(() => _hideDropped = false),
                          ),
                      ],
                    ),
                  ),
                ),
              if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: isLoading
                        ? const ActivityIndicator()
                        : hasError
                        ? TextButton(
                            onPressed: () {
                              if (_season.isCurrent) {
                                ref.invalidate(loadHomeCatalogProvider);
                              } else {
                                unawaited(_selectSeason(_season));
                              }
                            },
                            child: Text(_seasonError ?? '时间表加载失败，点此重试'),
                          )
                        : Text(
                            _activeOptionCount > 0
                                ? '当前筛选条件下暂无放送条目'
                                : '当天暂无放送条目',
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
                    12,
                    16,
                    24 + widget.bottomPadding,
                  ),
                  sliver: isWide
                      ? SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                mainAxisExtent: 124,
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _ScheduleCard(
                              subject: items[index],
                              isWatching:
                                  statusMap[items[index].subjectId] ==
                                  CollectionStatus.watching,
                              onTap: () => BaseNavigator.push<void>(
                                context,
                                SubjectDetailPage(
                                  subjectId: items[index].subjectId,
                                ),
                              ),
                            ),
                            childCount: items.length,
                          ),
                        )
                      : SliverList.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) => _ScheduleCard(
                            subject: items[index],
                            isWatching:
                                statusMap[items[index].subjectId] ==
                                CollectionStatus.watching,
                            onTap: () => BaseNavigator.push<void>(
                              context,
                              SubjectDetailPage(
                                subjectId: items[index].subjectId,
                              ),
                            ),
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

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.subject,
    required this.isWatching,
    required this.onTap,
  });

  final AnimeSubject subject;
  final bool isWatching;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final metaParts = <String>[
      if (subject.studio.isNotEmpty) subject.studio,
      if (subject.tags.isNotEmpty) subject.tags.take(3).join(' / '),
    ];
    return KonekoCard(
      corner: 26,
      padding: const EdgeInsets.all(12),
      onPressed: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 100,
            child: KonekoPosterArt(
              subject: subject,
              borderRadius: AppRadius.all(16),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  subject.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.headline
                      .of(context, emphasized: true)
                      .copyWith(color: colorScheme.onSurface),
                ),
                if (metaParts.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    metaParts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (subject.score > 0)
                      KonekoChip(
                        label: subject.score.toStringAsFixed(1),
                        height: 24,
                        fontSize: 11.5,
                        leading: const GlyphIcon(
                          KonekoGlyphs.star,
                          size: 11,
                          color: Color(0xFFE09F24),
                        ),
                      ),
                    if (subject.airedEpisodes > 0)
                      KonekoChip(
                        label: '更至 ${subject.airedEpisodes} 话',
                        height: 24,
                        fontSize: 11.5,
                      )
                    else if (subject.seasonLabel.isNotEmpty)
                      KonekoChip(
                        label: subject.seasonLabel,
                        height: 24,
                        fontSize: 11.5,
                      ),
                    if (isWatching)
                      KonekoChip(
                        label: '在追',
                        height: 24,
                        fontSize: 11.5,
                        backgroundColor: colorScheme.primary.withValues(
                          alpha: 0.14,
                        ),
                        foregroundColor: colorScheme.primary,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
