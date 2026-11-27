import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/player/player_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

class OfflinePage extends ConsumerWidget {
  const OfflinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(offlineLibraryProvider);
    final entries =
        ref.watch(offlineUpdatesProvider).value ??
        library?.entries ??
        const <OfflineEpisode>[];
    return KonekoScaffold(
      title: '离线缓存',
      showBack: true,
      body: ArrivalCacheExtentBuilder(
        builder: (context, cacheExtent) => PrismListView(
          scrollCacheExtent: cacheExtent,
          padding: EdgeInsets.fromLTRB(
            16,
            context.contentTopPadding,
            16,
            28 + context.bottomInset,
          ),
          gap: 8,
          estimatedItemExtent: 68,
          itemCount: entries.isEmpty ? 1 : entries.length,
          itemBuilder: (context, index) {
            if (entries.isEmpty) return const KonekoCard(child: Text('暂无离线缓存'));
            final entry = entries[index];
            return KonekoCard(
              key: ValueKey(entry.id),
              padding: const EdgeInsets.all(12),
              child: Row(
                spacing: 8,
                children: [
                  GlyphIcon(
                    entry.state == OfflineState.ready
                        ? KonekoGlyphs.play
                        : KonekoGlyphs.importFile,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.subjectTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.headline.of(context),
                        ),
                        Text(
                          '第 ${entry.number} 话 · ${_status(entry)}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: context.listSubtitleStyle,
                        ),
                      ],
                    ),
                  ),
                  if (entry.state == OfflineState.ready)
                    IconButton(
                      tooltip: '播放缓存',
                      icon: const GlyphIcon(KonekoGlyphs.play),
                      onPressed: () => BaseNavigator.push<void>(
                        context,
                        PlayerPage(
                          subjectId: entry.subjectId,
                          initialEpisode: entry.number,
                          initialRuleId: entry.ruleId,
                          initialRuleName: entry.ruleName,
                          offline: entry,
                        ),
                        rootNavigator: true,
                      ),
                    ),
                  IconButton(
                    tooltip: entry.state == OfflineState.downloading
                        ? '取消缓存'
                        : '移除缓存',
                    icon: const GlyphIcon(KonekoGlyphs.trash),
                    onPressed: () async {
                      try {
                        await library?.remove(entry.id);
                      } on Object {
                        if (context.mounted) {
                          showKonekoBanner(
                            context,
                            '无法移除缓存',
                            level: BannerLevel.error,
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _status(OfflineEpisode entry) => switch (entry.state) {
    OfflineState.ready => '可离线播放 · ${entry.ruleName}',
    OfflineState.downloading =>
      entry.progress == null ? '下载中' : '下载 ${(entry.progress! * 100).round()}%',
    OfflineState.failed => entry.error ?? '下载失败',
  };
}
