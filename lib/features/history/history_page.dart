import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/common/feature_feedback.dart';
import 'package:koneko/features/detail/subject_detail_page.dart';
import 'package:koneko/features/player/player_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

enum _HistoryFilter { all, today, week }

/// Watch history page: keeps one clean card per anime across rule switches.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key, this.showBack = false, this.bottomPadding = 0});

  final bool showBack;
  final double bottomPadding;

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  _HistoryFilter _filter = _HistoryFilter.all;
  int? _expandedSubjectId;

  Future<void> _import() async {
    final tracker = ref.read(trackingSyncProvider);
    if (tracker == null) return;
    try {
      final picked = await FilePicker.pickFile();
      final path = picked?.path;
      if (path == null) return;
      final file = File(path);
      if (await file.length() > 64 * 1024 * 1024) {
        throw const FormatException('单个备份文件不能超过 64 MB');
      }
      final count = await tracker.importKazumi(await file.readAsBytes());
      if (mounted) {
        showKonekoBanner(
          context,
          '已导入 $count 条观看历史',
          level: BannerLevel.success,
        );
      }
    } on Object catch (error) {
      if (mounted) {
        showKonekoBanner(
          context,
          featureError(error, '备份读取失败'),
          level: BannerLevel.error,
        );
      }
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: Builder(
        builder: (dialog) => AlertDialog(
          title: '清空观看历史？',
          destructive: true,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('清空'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    ref.read(historyProvider.notifier).clearAll();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    ref.watch(catalogUpdatesProvider);
    final catalog = ref.watch(catalogRepositoryProvider);
    final entries = ref.watch(historyProvider);

    final visible = entries.where((entry) {
      final diff = DateTime.now().difference(entry.updatedAt);
      return switch (_filter) {
        _HistoryFilter.all => true,
        _HistoryFilter.today => diff.inHours <= 24,
        _HistoryFilter.week => diff.inDays <= 7,
      };
    }).toList();

    return KonekoScaffold(
      title: '观看历史',
      showBack: widget.showBack,
      actions: [
        IconButtonData(
          glyph: KonekoGlyphs.importFile,
          tooltip: '导入 Kazumi 备份',
          onPressed: ref.watch(trackingSyncProvider) == null ? null : _import,
        ),
        IconButtonData(
          glyph: KonekoGlyphs.trash,
          tooltip: '清空历史',
          onPressed: entries.isEmpty ? null : _confirmClear,
        ),
      ],
      body: CustomScrollView(
        scrollCacheExtent: const ScrollCacheExtent.pixels(600),
        slivers: [
          const KonekoScrollStart(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SegmentedControl<_HistoryFilter>(
                segments: const [
                  (_HistoryFilter.all, '全部'),
                  (_HistoryFilter.today, '今天'),
                  (_HistoryFilter.week, '近 7 天'),
                ],
                value: _filter,
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
          ),
          if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  '暂无历史记录',
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
                4,
                16,
                24 + widget.bottomPadding,
              ),
              sliver: SliverList.separated(
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = visible[index];
                  final subject = catalog.getSubjectById(item.subjectId);
                  if (subject == null) return const SizedBox.shrink();
                  final expanded = _expandedSubjectId == item.subjectId;
                  return _MergedHistoryCard(
                    subject: subject,
                    entry: item,
                    expanded: expanded,
                    onToggleExpand: () => setState(() {
                      _expandedSubjectId = expanded ? null : item.subjectId;
                    }),
                    onOpenDetail: () => BaseNavigator.push<void>(
                      context,
                      SubjectDetailPage(subjectId: subject.subjectId),
                    ),
                    onResume: (ruleId, ruleName, ep) =>
                        BaseNavigator.push<void>(
                          context,
                          PlayerPage(
                            subjectId: subject.subjectId,
                            initialEpisode: ep,
                            initialRuleId: ruleId,
                            initialRuleName: ruleName,
                          ),
                        ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _MergedHistoryCard extends StatelessWidget {
  const _MergedHistoryCard({
    required this.subject,
    required this.entry,
    required this.expanded,
    required this.onToggleExpand,
    required this.onOpenDetail,
    required this.onResume,
  });

  final AnimeSubject subject;
  final MergedHistoryEntry entry;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onOpenDetail;
  final void Function(String ruleId, String ruleName, int episode) onResume;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final pct = (entry.progressRatio * 100).round();
    return KonekoCard(
      corner: 26,
      padding: const EdgeInsets.all(14),
      onPressed: onOpenDetail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 60,
                height: 84,
                child: KonekoPosterArt(
                  subject: subject,
                  borderRadius: AppRadius.all(14),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subject.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.callout
                                .of(context, emphasized: true)
                                .copyWith(color: colorScheme.onSurface),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Protected non-truncated timestamp
                        Text(
                          formatRelativeTime(entry.updatedAt),
                          maxLines: 1,
                          style: AppTextStyle.caption1
                              .of(context)
                              .copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '第 ${entry.lastEpisode} 话 · ${formatDurationShort(entry.lastPositionSeconds)} / ${formatDurationShort(entry.lastDurationSeconds)} ($pct%)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        KonekoChip(
                          label: entry.lastRuleName,
                          height: 24,
                          fontSize: 11,
                        ),
                        if (entry.mergedSourceCount > 1)
                          KonekoChip(
                            label: '${entry.mergedSourceCount} 个播放源',
                            height: 24,
                            fontSize: 11,
                            leading: GlyphIcon(
                              KonekoGlyphs.layers,
                              size: 11,
                              color: colorScheme.primary,
                            ),
                            backgroundColor: colorScheme.primary.withValues(
                              alpha: 0.14,
                            ),
                            foregroundColor: colorScheme.primary,
                            onPressed: onToggleExpand,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              KonekoCircleButton(
                size: 38,
                iconSize: 16,
                glyph: KonekoGlyphs.play,
                fillColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                tooltip: '继续播放',
                onPressed: () => onResume(
                  entry.lastRuleId,
                  entry.lastRuleName,
                  entry.lastEpisode,
                ),
              ),
            ],
          ),
          if (expanded && entry.sourceRecords.length > 1) ...[
            const SizedBox(height: 10),
            KonekoBlock(
              corner: 16,
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  Text(
                    '其他播放源进度（点击即可切换续播）',
                    style: AppTextStyle.caption1
                        .of(context, emphasized: true)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  for (final rec in entry.sourceRecords)
                    PressSurface(
                      fill: SurfaceLevel.card.colorOf(colorScheme),
                      shape: AppShape.md,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      onPressed: () =>
                          onResume(rec.ruleId, rec.ruleName, rec.episodeNumber),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              rec.ruleName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.footnote
                                  .of(context, emphasized: true)
                                  .copyWith(color: colorScheme.onSurface),
                            ),
                          ),
                          Text(
                            '第 ${rec.episodeNumber} 话 · ${formatDurationShort(rec.positionSeconds)}',
                            style: AppTextStyle.caption1
                                .of(context)
                                .copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
