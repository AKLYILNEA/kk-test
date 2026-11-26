import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
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
  progress('观看进度');

  const _LibrarySort(this.label);
  final String label;
}

/// Pure FlClash responsive Library page with Kazumi sync parity
/// (Bangumi + WebDAV) and explicit Status Picker Sheet.
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key, this.bottomPadding = 0});

  final double bottomPadding;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  CollectionStatus? _filter = CollectionStatus.watching;
  bool _showSearch = false;
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

  Future<void> _runSync(
    Future<int> Function() action,
    String label,
  ) async {
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
    final hasBangumi = (secrets?.bangumiToken.trim().isNotEmpty ?? false);
    final hasWebDav = (secrets?.webdavUrl.trim().isNotEmpty ?? false);

    await showKonekoSheet<void>(
      context: context,
      title: '追番管理与同步',
      subtitle: '排序方式、Bangumi 与 WebDAV 云端同步',
      detents: const [0.64, 0.86],
      bodyBuilder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final colorScheme = sheetContext.colorScheme;
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                const ListHeader(title: '排序方式'),
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
                const ListHeader(title: '同步服务（对齐 Kazumi）'),
                generateGroup([
                  DecorationListItem(
                    leading: const GlyphIcon(KonekoGlyphs.sync),
                    title: const Text('同步 Bangumi 收藏与进度'),
                    subtitle: Text(
                      hasBangumi ? '已配置访问令牌，点击立即双向同步' : '尚未配置 Access Token，点击去设置',
                    ),
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
                              unawaited(_runSync(sync.syncBangumi, 'Bangumi'));
                            }
                          },
                  ),
                  DecorationListItem(
                    leading: const GlyphIcon(KonekoGlyphs.cloud),
                    title: const Text('同步 WebDAV 云端备份'),
                    subtitle: Text(
                      hasWebDav
                          ? '已配置服务器，兼容 Kazumi 备份格式'
                          : '尚未配置 WebDAV 服务器，点击去设置',
                    ),
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
                    title: const Text('账号与同步设置'),
                    subtitle: const Text('管理 Bangumi Token、WebDAV 与屏蔽词'),
                    trailing: const GlyphIcon(Glyphs.chevronForward),
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      BaseNavigator.push<void>(
                        context,
                        const ServiceSettingsPage(),
                      );
                    },
                  ),
                ]),
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
    final history = ref.watch(historyProvider);

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
      case _LibrarySort.progress:
        filtered.sort((a, b) => b.watchedEpisodes.compareTo(a.watchedEpisodes));
    }

    return KonekoScaffold(
      title: '追番',
      actions: [
        IconButtonData(
          glyph: Glyphs.search,
          tooltip: '搜索追番库',
          onPressed: () => setState(() {
            _showSearch = !_showSearch;
            if (!_showSearch) _query = '';
          }),
        ),
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
          final columns = width >= 1080
              ? 3
              : width >= 700
              ? 2
              : 1;

          return CustomScrollView(
            scrollCacheExtent: const ScrollCacheExtent.pixels(600),
            slivers: [
              const KonekoScrollStart(),
              if (_showSearch)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: SearchField(
                      fill: SurfaceLevel.card.colorOf(colorScheme),
                      hintText: '筛选追番库...',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 40,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    scrollDirection: Axis.horizontal,
                    itemCount: _tabs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, index) {
                      final (status, label) = _tabs[index];
                      final selected = status == _filter;
                      return KonekoChip(
                        label: '$label  ${countOf(status)}',
                        height: 36,
                        fontSize: 13,
                        selected: selected,
                        backgroundColor: selected
                            ? colorScheme.primary
                            : SurfaceLevel.card.colorOf(colorScheme),
                        onPressed: () => setState(() => _filter = status),
                      );
                    },
                  ),
                ),
              ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      '该分类下暂无番剧',
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
                    14,
                    16,
                    24 + widget.bottomPadding,
                  ),
                  sliver: columns == 1
                      ? SliverList.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final entry = filtered[index];
                            final subject = catalog.getSubjectById(
                              entry.subjectId,
                            )!;
                            final hist = history
                                .where((h) => h.subjectId == entry.subjectId)
                                .firstOrNull;
                            return _FlClashWatchCard(
                              subject: subject,
                              entry: entry,
                              history: hist,
                              onOpenDetail: () => _openDetail(subject),
                              onQuickPlay: () => _openPlayer(
                                subject,
                                hist?.lastEpisode ??
                                    (entry.watchedEpisodes > 0
                                        ? entry.watchedEpisodes
                                        : 1),
                                hist?.lastRuleId ?? '',
                                hist?.lastRuleName ?? '',
                              ),
                              onPickStatus: () => _pickStatus(subject, entry),
                            );
                          },
                        )
                      : SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                mainAxisExtent: 186,
                              ),
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final entry = filtered[index];
                            final subject = catalog.getSubjectById(
                              entry.subjectId,
                            )!;
                            final hist = history
                                .where((h) => h.subjectId == entry.subjectId)
                                .firstOrNull;
                            return _FlClashWatchCard(
                              subject: subject,
                              entry: entry,
                              history: hist,
                              onOpenDetail: () => _openDetail(subject),
                              onQuickPlay: () => _openPlayer(
                                subject,
                                hist?.lastEpisode ??
                                    (entry.watchedEpisodes > 0
                                        ? entry.watchedEpisodes
                                        : 1),
                                hist?.lastRuleId ?? '',
                                hist?.lastRuleName ?? '',
                              ),
                              onPickStatus: () => _pickStatus(subject, entry),
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

  void _openDetail(AnimeSubject subject) {
    BaseNavigator.push<void>(
      context,
      SubjectDetailPage(subjectId: subject.subjectId),
    );
  }

  void _openPlayer(
    AnimeSubject subject,
    int episode,
    String ruleId,
    String ruleName,
  ) {
    BaseNavigator.push<void>(
      context,
      PlayerPage(
        subjectId: subject.subjectId,
        initialEpisode: episode,
        initialRuleId: ruleId,
        initialRuleName: ruleName,
      ),
    );
  }
}

class _FlClashWatchCard extends StatelessWidget {
  const _FlClashWatchCard({
    required this.subject,
    required this.entry,
    required this.history,
    required this.onOpenDetail,
    required this.onQuickPlay,
    required this.onPickStatus,
  });

  final AnimeSubject subject;
  final CollectionEntry entry;
  final MergedHistoryEntry? history;
  final VoidCallback onOpenDetail;
  final VoidCallback onQuickPlay;
  final VoidCallback onPickStatus;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final total = subject.totalEpisodes > 0 ? subject.totalEpisodes : 12;
    final ratio = (entry.watchedEpisodes / total).clamp(0.0, 1.0);
    final pct = (ratio * 100).round();

    final String progressText;
    if (entry.watchedEpisodes <= 0) {
      progressText = subject.airedEpisodes > 0
          ? '尚未开始 · 更新至第 ${subject.airedEpisodes} 话'
          : '尚未开始观看';
    } else if (entry.watchedEpisodes >= total) {
      progressText = '已看完 · 共 $total 话';
    } else {
      progressText = '看到 第 ${entry.watchedEpisodes} 话 · 共 $total 话';
    }

    return KonekoCard(
      corner: 26,
      padding: const EdgeInsets.all(14),
      onPressed: onOpenDetail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                height: 90,
                child: KonekoPosterArt(
                  subject: subject,
                  borderRadius: AppRadius.all(16),
                  overlayBadges: [
                    if (subject.score > 0)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: KonekoChip(
                          label: subject.score.toStringAsFixed(1),
                          height: 18,
                          fontSize: 9.5,
                          backgroundColor: Colors.black.withValues(alpha: 0.62),
                          foregroundColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.callout
                          .of(context, emphasized: true)
                          .copyWith(color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subject.originalTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption1
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        KonekoChip(
                          label: entry.status.label,
                          height: 24,
                          fontSize: 11,
                          backgroundColor: colorScheme.primary.withValues(
                            alpha: 0.14,
                          ),
                          foregroundColor: colorScheme.primary,
                          trailing: GlyphIcon(
                            Glyphs.chevronDown,
                            size: 12,
                            color: colorScheme.primary,
                          ),
                          onPressed: onPickStatus,
                        ),
                        if (subject.isCompleted && subject.year > 0)
                          KonekoChip(
                            label: '${subject.year} 年',
                            height: 24,
                            fontSize: 11,
                          )
                        else if (subject.airedEpisodes > 0)
                          KonekoChip(
                            label: '更至 ${subject.airedEpisodes} 话',
                            height: 24,
                            fontSize: 11,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          KonekoBlock(
            corner: 18,
            padding: const EdgeInsets.fromLTRB(12, 8, 9, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              progressText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.caption1
                                  .of(context, emphasized: true)
                                  .copyWith(
                                    color: entry.watchedEpisodes > 0
                                        ? colorScheme.onSurface
                                        : colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$pct%',
                            style: AppTextStyle.caption1
                                .of(context, emphasized: true)
                                .copyWith(
                                  color: entry.watchedEpisodes > 0
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: AppRadius.full,
                        child: Container(
                          height: 4.5,
                          color: colorScheme.primary.withValues(alpha: 0.12),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: ratio,
                            child: Container(color: colorScheme.primary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                KonekoCircleButton(
                  size: 34,
                  iconSize: 15,
                  glyph: KonekoGlyphs.play,
                  fillColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  tooltip: '续播',
                  onPressed: onQuickPlay,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
