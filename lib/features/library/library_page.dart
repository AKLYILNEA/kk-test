import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/feature_feedback.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/detail/subject_detail_page.dart';
import 'package:koneko/features/my/service_settings_page.dart';
import 'package:koneko/features/player/player_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_sheet.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

enum _LibrarySort {
  recent('最近更新'),
  score('评分优先'),
  title('标题排序');

  const _LibrarySort(this.label);
  final String label;
}

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key, this.bottomPadding = 0});

  final double bottomPadding;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  int _selectedTabIndex = 0;
  _LibrarySort _sort = _LibrarySort.recent;
  String _query = '';
  bool _syncing = false;

  static const _tabs = <(CollectionStatus?, String)>[
    (CollectionStatus.watching, '在看'),
    (CollectionStatus.wish, '想看'),
    (CollectionStatus.watched, '看过'),
    (CollectionStatus.onHold, '搁置'),
    (CollectionStatus.dropped, '抛弃'),
    (null, '全部'),
  ];

  CollectionStatus? get _filter => _tabs[_selectedTabIndex].$1;

  Future<void> _pickStatus(AnimeSubject subject, CollectionEntry entry) async {
    final choice = await showKonekoStatusSheet(
      context: context,
      subjectTitle: subject.title,
      currentStatus: entry.status,
    );
    if (!mounted || choice == null) return;
    if (choice.remove) {
      ref.read(libraryProvider.notifier).removeSubject(entry.subjectId);
      showKonekoBanner(context, '已将「${subject.title}」移出追番');
    } else if (choice.status case final status?) {
      if (status != entry.status) {
        ref.read(libraryProvider.notifier).setStatus(entry.subjectId, status);
        showKonekoBanner(
          context,
          '「${subject.title}」已移至「${status.label}」',
          level: BannerLevel.success,
        );
      }
    }
  }

  Future<void> _runSync(Future<int> Function() action, String label) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final count = await action();
      if (!mounted) return;
      showKonekoBanner(
        context,
        '$label 同步完成（共 $count 条记录）',
        level: BannerLevel.success,
      );
    } on Object catch (error) {
      if (mounted) {
        showKonekoBanner(
          context,
          featureError(error, '$label 同步失败，请检查账号配置与网络'),
          level: BannerLevel.error,
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _openManageSheet() async {
    final sync = ref.read(trackingSyncProvider);
    final secrets = await ref.read(secretsProvider)?.read();
    if (!mounted) return;
    final hasBangumi = secrets?.bangumiToken.trim().isNotEmpty ?? false;
    final hasWebDav = secrets?.webdavUrl.trim().isNotEmpty ?? false;

    await showKonekoSheet<void>(
      context: context,
      title: '追番设置',
      detents: const [0.64, 0.86],
      bodyBuilder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final colorScheme = sheetContext.colorScheme;
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                const ListHeader(title: '排序'),
                KonekoCard(
                  corner: 22,
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in _LibrarySort.values)
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
                const ListHeader(title: '同步'),
                KonekoGroup(
                  items: [
                    DecorationListItem(
                      leading: const GlyphIcon(KonekoGlyphs.sync),
                      title: const Text('Bangumi 同步'),
                      subtitle: Text(hasBangumi ? '点击同步' : '未配置'),
                      trailing: _syncing
                          ? const ActivityIndicator()
                          : const GlyphIcon(Glyphs.chevronForward),
                      onPressed: _syncing
                          ? null
                          : () {
                              Navigator.of(sheetContext).pop();
                              if (!hasBangumi || sync == null) {
                                BaseNavigator.push<void>(
                                  context,
                                  const ServiceSettingsPage(),
                                );
                              } else {
                                unawaited(
                                  _runSync(sync.syncBangumi, 'Bangumi'),
                                );
                              }
                            },
                    ),
                    DecorationListItem(
                      leading: const GlyphIcon(KonekoGlyphs.cloud),
                      title: const Text('WebDAV 同步'),
                      subtitle: Text(hasWebDav ? '点击同步' : '未配置'),
                      trailing: _syncing
                          ? const ActivityIndicator()
                          : const GlyphIcon(Glyphs.chevronForward),
                      onPressed: _syncing
                          ? null
                          : () {
                              Navigator.of(sheetContext).pop();
                              if (!hasWebDav || sync == null) {
                                BaseNavigator.push<void>(
                                  context,
                                  const ServiceSettingsPage(),
                                );
                              } else {
                                unawaited(_runSync(sync.syncWebDav, 'WebDAV'));
                              }
                            },
                    ),
                    DecorationListItem(
                      leading: const GlyphIcon(KonekoGlyphs.user),
                      title: const Text('同步设置'),
                      trailing: const GlyphIcon(Glyphs.chevronForward),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        BaseNavigator.push<void>(
                          context,
                          const ServiceSettingsPage(),
                        );
                      },
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    ref.watch(catalogUpdatesProvider);
    final catalog = ref.watch(catalogRepositoryProvider);
    final entries = ref.watch(libraryProvider);
    final history = {
      for (final item in ref.watch(historyProvider)) item.subjectId: item,
    };

    int countOf(CollectionStatus? status) => status == null
        ? entries.length
        : entries.where((e) => e.status == status).length;

    final filtered = entries.where((entry) {
      if (_filter != null && entry.status != _filter) return false;
      final subject = catalog.getSubjectById(entry.subjectId);
      if (subject == null) return false;
      if (_query.trim().isEmpty) return true;
      final q = _query.trim().toLowerCase();
      return subject.title.toLowerCase().contains(q) ||
          subject.originalTitle.toLowerCase().contains(q);
    }).toList();

    switch (_sort) {
      case _LibrarySort.recent:
        filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case _LibrarySort.score:
        filtered.sort((a, b) {
          final sa = catalog.getSubjectById(a.subjectId)?.score ?? 0;
          final sb = catalog.getSubjectById(b.subjectId)?.score ?? 0;
          return sb.compareTo(sa);
        });
      case _LibrarySort.title:
        filtered.sort((a, b) {
          final ta = catalog.getSubjectById(a.subjectId)?.title ?? '';
          final tb = catalog.getSubjectById(b.subjectId)?.title ?? '';
          return ta.compareTo(tb);
        });
    }

    return KonekoScaffold(
      title: '追番',
      searchConfig: KonekoSearchConfig(
        tooltip: '搜索追番库',
        hintText: '搜索追过的番剧...',
        onChanged: (v) => setState(() => _query = v),
      ),
      actions: [
        IconButtonData(
          glyph: KonekoGlyphs.tune,
          tooltip: '排序与同步设置',
          isLoading: _syncing,
          onPressed: _openManageSheet,
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns = width >= 1150
              ? 6
              : width >= 930
              ? 5
              : width >= 680
              ? 4
              : width >= 470
              ? 3
              : 2;
          const spacing = 12.0;
          final cardWidth = (width - 28 - spacing * (columns - 1)) / columns;
          final scale = MediaQuery.textScalerOf(context);
          final titleHeight = scale.scale(AppTextStyle.footnote.size) * 1.25;
          final metaHeight = scale.scale(AppTextStyle.caption1.size) * 1.25;
          final footerHeight = 24 + titleHeight * 2 + metaHeight;

          return CustomScrollView(
            scrollCacheExtent: const ScrollCacheExtent.pixels(600),
            slivers: [
              const KonekoScrollStart(),
              SliverToBoxAdapter(
                child: KonekoAutoScrollChipBar(
                  height: 46,
                  chipHeight: 34,
                  fontSize: 13,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  labels: [
                    for (final (status, label) in _tabs)
                      '$label  ${countOf(status)}',
                  ],
                  selectedIndex: _selectedTabIndex,
                  onSelected: (index) =>
                      setState(() => _selectedTabIndex = index),
                ),
              ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      _query.trim().isNotEmpty ? '没有匹配的追番记录' : '该分类下暂无番剧',
                      style: AppTextStyle.subheadline
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    12,
                    14,
                    24 + widget.bottomPadding,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: 16,
                      mainAxisExtent: cardWidth * 1.32 + footerHeight,
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final entry = filtered[index];
                      final subject = catalog.getSubjectById(entry.subjectId)!;
                      final watched = history[entry.subjectId];
                      return _LibraryPosterCard(
                        subject: subject,
                        entry: entry,
                        history: watched,
                        showStatus: _filter == null,
                        footerHeight: footerHeight,
                        onStatusTap: () => _pickStatus(subject, entry),
                        onResume:
                            watched != null &&
                                entry.status == CollectionStatus.watching
                            ? () => BaseNavigator.push<void>(
                                context,
                                PlayerPage(
                                  subjectId: subject.subjectId,
                                  initialEpisode: watched.lastEpisode,
                                  initialRuleId: watched.lastRuleId,
                                  initialRuleName: watched.lastRuleName,
                                ),
                              )
                            : null,
                        onTap: () => BaseNavigator.push<void>(
                          context,
                          SubjectDetailPage(subjectId: subject.subjectId),
                        ),
                      );
                    }, childCount: filtered.length),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LibraryPosterCard extends StatelessWidget {
  const _LibraryPosterCard({
    required this.subject,
    required this.entry,
    required this.history,
    required this.showStatus,
    required this.footerHeight,
    required this.onStatusTap,
    required this.onResume,
    required this.onTap,
  });

  final AnimeSubject subject;
  final CollectionEntry entry;
  final MergedHistoryEntry? history;
  final bool showStatus;
  final double footerHeight;
  final VoidCallback onStatusTap;
  final VoidCallback? onResume;
  final VoidCallback onTap;

  String get _subtitle {
    if (entry.status == CollectionStatus.watched) return '已看完';
    if (history case final watched?
        when entry.status == CollectionStatus.watching ||
            entry.status == CollectionStatus.onHold) {
      final percent = (watched.progressRatio * 100).round();
      return percent > 0
          ? '第 ${watched.lastEpisode} 话 · $percent%'
          : '看到第 ${watched.lastEpisode} 话';
    }
    if (entry.watchedEpisodes > 0) {
      return subject.totalEpisodes > 0
          ? '已看 ${entry.watchedEpisodes}/${subject.totalEpisodes} 话'
          : '已看 ${entry.watchedEpisodes} 话';
    }
    return [
      if (subject.year > 0) '${subject.year}',
      if (subject.score > 0) '${subject.score.toStringAsFixed(1)} 分',
      if (subject.year <= 0 && subject.score <= 0) entry.status.label,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return KonekoCard(
      corner: 18,
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: KonekoPosterArt(
              subject: subject,
              overlayBadges: [
                Positioned(
                  top: 7,
                  right: 7,
                  child: TonalButtonTheme(
                    size: TonalButtonSize.section,
                    child: ElasticPress(
                      child: AppBarActionButton(
                        data: IconButtonData(
                          glyph: Glyphs.more,
                          tooltip: '修改「${subject.title}」的追番状态',
                          onPressed: onStatusTap,
                        ),
                      ),
                    ),
                  ),
                ),
                if (showStatus)
                  Positioned(
                    top: 10,
                    left: 9,
                    child: KonekoChip(
                      label: entry.status.label,
                      height: 24,
                      fontSize: 11,
                      backgroundColor: colors.surface.withValues(alpha: 0.9),
                      foregroundColor: colors.onSurface,
                      onPressed: onStatusTap,
                    ),
                  ),
                if (onResume != null)
                  Positioned(
                    bottom: 9,
                    right: 9,
                    child: Semantics(
                      button: true,
                      label: '继续播放 ${subject.title}',
                      child: PressSurface(
                        fill: colors.primary,
                        shape: AppShape.full,
                        onPressed: onResume,
                        child: SizedBox.square(
                          dimension: 40,
                          child: Center(
                            child: GlyphIcon(
                              KonekoGlyphs.play,
                              color: colors.onPrimary,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: footerHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    subject.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.footnote
                        .of(context, emphasized: true)
                        .copyWith(color: colors.onSurface, height: 1.25),
                  ),
                  Text(
                    _subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: colors.onSurfaceVariant, height: 1.25),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
