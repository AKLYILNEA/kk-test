import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/feature_feedback.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/detail/subject_detail_page.dart';
import 'package:koneko/features/player/player_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

enum _HistoryFilter { all, today, week }

/// Watch history page: keeps one clean card per anime displaying the latest
/// watched source, episode, progress capsule and FlClash capsule play buttons.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key, this.showBack = false, this.bottomPadding = 0});

  final bool showBack;
  final double bottomPadding;

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  _HistoryFilter _filter = _HistoryFilter.all;

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
              child: KonekoSegmentedBar<_HistoryFilter>(
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
                  return _HistoryCard(
                    subject: subject,
                    entry: item,
                    onOpenDetail: () => BaseNavigator.push<void>(
                      context,
                      SubjectDetailPage(subjectId: subject.subjectId),
                    ),
                    onResume: () => BaseNavigator.push<void>(
                      context,
                      PlayerPage(
                        subjectId: subject.subjectId,
                        initialEpisode: item.lastEpisode,
                        initialRuleId: item.lastRuleId,
                        initialRuleName: item.lastRuleName,
                      ),
                    ),
                    onPlayNext: () => BaseNavigator.push<void>(
                      context,
                      PlayerPage(
                        subjectId: subject.subjectId,
                        initialEpisode: item.lastEpisode + 1,
                        initialRuleId: item.lastRuleId,
                        initialRuleName: item.lastRuleName,
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

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.subject,
    required this.entry,
    required this.onOpenDetail,
    required this.onResume,
    required this.onPlayNext,
  });

  final AnimeSubject subject;
  final MergedHistoryEntry entry;
  final VoidCallback onOpenDetail;
  final VoidCallback onResume;
  final VoidCallback onPlayNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final ratio = entry.progressRatio.clamp(0.0, 1.0);
    final pct = (ratio * 100).round();
    final isFinished = ratio >= 0.94;
    final hasNext =
        subject.totalEpisodes <= 0 || entry.lastEpisode < subject.totalEpisodes;
    final ruleName = entry.lastRuleName.trim();
    final posText = formatDurationShort(entry.lastPositionSeconds);
    final durText = entry.lastDurationSeconds > 0
        ? formatDurationShort(entry.lastDurationSeconds)
        : '';

    return KonekoCard(
      corner: 26,
      padding: const EdgeInsets.all(14),
      onPressed: onOpenDetail,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            height: 108,
            child: KonekoPosterArt(
              subject: subject,
              borderRadius: AppRadius.all(16),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 108),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                          Text(
                            formatRelativeTime(entry.updatedAt),
                            maxLines: 1,
                            style: AppTextStyle.caption1
                                .of(context)
                                .copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            '第 ${entry.lastEpisode} 话',
                            style: AppTextStyle.footnote
                                .of(context, emphasized: true)
                                .copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                          if (ruleName.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '· $ruleName',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyle.caption1
                                    .of(context)
                                    .copyWith(
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.8),
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Kazumi-inspired progress capsule in pure FlClash surface palette
                      ClipRSuperellipse(
                        borderRadius: AppRadius.all(10),
                        child: SizedBox(
                          height: 22,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ColoredBox(
                                color: SurfaceLevel.block.colorOf(colorScheme),
                              ),
                              if (ratio > 0)
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: FractionallySizedBox(
                                    widthFactor: isFinished ? 1.0 : ratio,
                                    heightFactor: 1.0,
                                    child: DecoratedBox(
                                      decoration: ShapeDecoration(
                                        color: colorScheme.primary.withValues(
                                          alpha: 0.18,
                                        ),
                                        shape: SuperellipseBorder(
                                          borderRadius: AppRadius.all(10),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        durText.isNotEmpty
                                            ? '$posText / $durText'
                                            : '看到 $posText',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyle.caption2
                                            .of(context, emphasized: true)
                                            .copyWith(
                                              color: colorScheme.onSurface,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isFinished ? '已看完' : '$pct%',
                                      style: AppTextStyle.caption2
                                          .of(context, emphasized: true)
                                          .copyWith(
                                            color: colorScheme.primary,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // FlClash capsule action buttons echoing SubjectDetailPage's Play CTA
                  Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: PressSurface(
                          fill: colorScheme.primary,
                          shape: AppShape.full,
                          clipsChild: true,
                          onPressed: onResume,
                          child: SizedBox(
                            height: 34,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              spacing: 5,
                              children: [
                                GlyphIcon(
                                  KonekoGlyphs.play,
                                  size: 13,
                                  color: colorScheme.onPrimary,
                                ),
                                Text(
                                  isFinished ? '重新播放' : '继续播放',
                                  style: AppTextStyle.caption1
                                      .of(context, emphasized: true)
                                      .copyWith(
                                        fontSize: 12.5,
                                        color: colorScheme.onPrimary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (hasNext)
                        PressSurface(
                          fill: colorScheme.primary.withValues(alpha: 0.13),
                          shape: AppShape.full,
                          clipsChild: true,
                          onPressed: onPlayNext,
                          child: SizedBox(
                            height: 34,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 4,
                                children: [
                                  GlyphIcon(
                                    KonekoGlyphs.skipNext,
                                    size: 14,
                                    color: colorScheme.primary,
                                  ),
                                  Text(
                                    '下一话',
                                    style: AppTextStyle.caption1
                                        .of(context, emphasized: true)
                                        .copyWith(
                                          fontSize: 12.5,
                                          color: colorScheme.primary,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
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
