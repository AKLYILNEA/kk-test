import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/catalog_page_refresh.dart';
import 'package:koneko/common/feature_feedback.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/detail/subject_detail_page.dart';
import 'package:koneko/features/my/service_settings_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_sheet.dart';
import 'package:koneko/ui/koneko_skeleton.dart';
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

class _LibraryPageState extends ConsumerState<LibraryPage>
    with
        SingleTickerProviderStateMixin,
        RouteMotionHoldMixin<LibraryPage>,
        CatalogPageRefreshMixin<LibraryPage>,
        TabEntranceMixin<LibraryPage> {
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
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                const ListHeader(title: '显示'),
                KonekoGroup(
                  items: [
                    KonekoOptionsItem<_LibrarySort>(
                      leading: const GlyphIcon(KonekoGlyphs.tune),
                      title: const Text('排序方式'),
                      options: _LibrarySort.values,
                      value: _sort,
                      textBuilder: (option) => option.label,
                      onChanged: (option) {
                        setState(() => _sort = option);
                        setSheetState(() {});
                      },
                    ),
                  ],
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
                                final syncPrefs = ref.read(
                                  syncSettingsProvider,
                                );
                                unawaited(
                                  _runSync(
                                    () => sync.syncBangumi(
                                      priority: syncPrefs.bangumiPriority,
                                    ),
                                    'Bangumi',
                                  ),
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
                                final syncPrefs = ref.read(
                                  syncSettingsProvider,
                                );
                                unawaited(
                                  _runSync(
                                    () => sync.syncWebDav(
                                      syncHistory: syncPrefs.webdavSyncHistory,
                                      syncCollect: syncPrefs.webdavSyncCollect,
                                    ),
                                    'WebDAV',
                                  ),
                                );
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
    final catalog = ref.watch(catalogRepositoryProvider);
    final entries = ref.watch(libraryProvider);
    final trackedLoad = ref.watch(loadTrackedSubjectsProvider);
    final loadingSubjects = trackedLoad.isLoading || _syncing;

    int countOf(CollectionStatus? status) => status == null
        ? entries.length
        : entries.where((e) => e.status == status).length;

    final tabEntries = entries
        .where((entry) => _filter == null || entry.status == _filter)
        .toList();
    final q = _query.trim().toLowerCase();
    final filtered = tabEntries.where((entry) {
      final subject = catalog.getSubjectById(entry.subjectId);
      if (subject == null) {
        return q.isEmpty;
      }
      if (q.isEmpty) return true;
      return subject.title.toLowerCase().contains(q) ||
          subject.originalTitle.toLowerCase().contains(q);
    }).toList();

    switch (_sort) {
      case _LibrarySort.recent:
        filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case _LibrarySort.score:
        filtered.sort((a, b) {
          final sa = catalog.getSubjectById(a.subjectId)?.score ?? -1;
          final sb = catalog.getSubjectById(b.subjectId)?.score ?? -1;
          return sb.compareTo(sa);
        });
      case _LibrarySort.title:
        filtered.sort((a, b) {
          final ta = catalog.getSubjectById(a.subjectId)?.title ?? '\uffff';
          final tb = catalog.getSubjectById(b.subjectId)?.title ?? '\uffff';
          return ta.compareTo(tb);
        });
    }

    final showEntranceSkeleton =
        !tabEntered || (_syncing && tabEntries.isEmpty);

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
      body: KonekoSkeletonScope(
        animate: tabEntered && PageActivityScope.isActiveOf(context),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 1120
                ? 6
                : width >= 860
                ? 5
                : width >= 600
                ? 4
                : 3;

            return CustomScrollView(
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
                if (showEntranceSkeleton)
                  SliverPadding(
                    key: const ValueKey('library-loading-skeleton'),
                    padding: EdgeInsets.fromLTRB(
                      12,
                      10,
                      12,
                      24 + widget.bottomPadding,
                    ),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.56,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, _) => const _LibraryCardSkeleton(),
                        childCount: tabEntries.isNotEmpty
                            ? tabEntries.length.clamp(3, columns * 3)
                            : columns * 2,
                      ),
                    ),
                  )
                else if (filtered.isEmpty)
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
                      12,
                      10,
                      12,
                      24 + widget.bottomPadding,
                    ),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.56,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final entry = filtered[index];
                        final subject = catalog.getSubjectById(entry.subjectId);
                        if (subject == null) {
                          if (loadingSubjects) {
                            return _LibraryCardSkeleton(
                              key: ValueKey('library-slot-${entry.subjectId}'),
                            );
                          }
                          return _LibraryFallbackCard(
                            key: ValueKey('library-fallback-${entry.subjectId}'),
                            entry: entry,
                            onTap: () => BaseNavigator.push<void>(
                              context,
                              SubjectDetailPage(subjectId: entry.subjectId),
                            ),
                          );
                        }
                        return RepaintBoundary(
                          child: UnifiedAnimeCard(
                            subject: subject,
                            corner: 16,
                            compact: true,
                            statusGlyph: konekoStatusGlyph(
                              entry.status,
                              forBadge: true,
                            ),
                            statusColor: konekoStatusColor(entry.status),
                            statusTooltip: '修改「${subject.title}」的追番状态',
                            onStatusTap: () => _pickStatus(subject, entry),
                            onTap: () => BaseNavigator.push<void>(
                              context,
                              SubjectDetailPage(subjectId: subject.subjectId),
                            ),
                          ),
                        );
                      }, childCount: filtered.length),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LibraryFallbackCard extends StatelessWidget {
  const _LibraryFallbackCard({
    super.key,
    required this.entry,
    required this.onTap,
  });

  final CollectionEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final shape = SuperellipseBorder(borderRadius: AppRadius.all(16));
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
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 8,
            children: [
              GlyphIcon(
                KonekoGlyphs.heart,
                size: 22,
                color: konekoStatusColor(entry.status),
              ),
              Text(
                '条目 #${entry.subjectId}',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.caption1
                    .of(context, emphasized: true)
                    .copyWith(color: colorScheme.onSurface),
              ),
              Text(
                '点击加载详情',
                style: AppTextStyle.caption2
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryCardSkeleton extends StatelessWidget {
  const _LibraryCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const KonekoSkeletonPulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: KonekoSkeletonBox(height: double.infinity, corner: 16),
          ),
          SizedBox(height: 7),
          KonekoSkeletonBox(height: 13, corner: 5),
          SizedBox(height: 5),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: 0.62,
              child: KonekoSkeletonBox(height: 11, corner: 5),
            ),
          ),
        ],
      ),
    );
  }
}
