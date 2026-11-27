import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/about/about_page.dart';
import 'package:koneko/features/history/history_page.dart';
import 'package:koneko/features/my/offline_page.dart';
import 'package:koneko/features/my/service_settings_page.dart';
import 'package:koneko/features/rules/rules_page.dart';
import 'package:koneko/features/theme/theme_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

/// My / Settings Hub Page with Bangumi profile card and clean grouped entries.
class MyPage extends ConsumerWidget {
  const MyPage({super.key, this.bottomPadding = 0});

  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final rules = ref.watch(rulesProvider);
    final history = ref.watch(historyProvider);
    final library = ref.watch(libraryProvider);
    final profile = ref.watch(bangumiProfileProvider).value;
    final offlineEntries =
        ref.watch(offlineUpdatesProvider).value ??
        ref.watch(offlineLibraryProvider)?.entries ??
        const <OfflineEpisode>[];
    final enabledRules = rules.where((r) => r.enabled).length;

    final displayName = (profile?.nickname.trim().isNotEmpty ?? false)
        ? profile!.nickname
        : 'Bangumi';
    final bangumiIdText = profile != null
        ? (profile.username.isNotEmpty
              ? '@${profile.username}${profile.id > 0 ? ' · ID ${profile.id}' : ''}'
              : 'ID ${profile.id}')
        : '未绑定 Bangumi ID';

    return KonekoScaffold(
      title: '我的',
      body: CustomScrollView(
        slivers: [
          const KonekoScrollStart(),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 28 + bottomPadding),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Bangumi Profile Card
                KonekoCard(
                  corner: 28,
                  padding: const EdgeInsets.all(16),
                  onPressed: () => BaseNavigator.push<void>(
                    context,
                    const ServiceSettingsPage(),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: ShapeDecoration(
                          color: const Color(0xFFF09199).withValues(alpha: 0.2),
                          shape: AppShape.circle,
                        ),
                        child: Center(
                          child: EmojiText(
                            '🐱',
                            style: AppTextStyle.title2.of(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 2,
                          children: [
                            Row(
                              spacing: 6,
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyle.headline
                                        .of(context, emphasized: true)
                                        .copyWith(color: colorScheme.onSurface),
                                  ),
                                ),
                                KonekoChip(
                                  label: 'Bangumi',
                                  height: 20,
                                  fontSize: 10.5,
                                  backgroundColor: const Color(
                                    0xFFF09199,
                                  ).withValues(alpha: 0.18),
                                  foregroundColor: const Color(0xFFD95B6A),
                                ),
                              ],
                            ),
                            Text(
                              bangumiIdText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.footnote
                                  .of(context)
                                  .copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            Text(
                              '追番 ${library.length} · 历史 ${history.length}',
                              maxLines: 1,
                              style: AppTextStyle.caption2
                                  .of(context)
                                  .copyWith(
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.78),
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const GlyphIcon(Glyphs.chevronForward),
                    ],
                  ),
                ),

                KonekoSection(
                  title: '常用',
                  items: [
                    DecorationListItem(
                      leading: GlyphIcon(
                        KonekoGlyphs.history,
                        color: colorScheme.primary,
                      ),
                      title: const Text('观看历史'),
                      subtitle: history.isEmpty
                          ? null
                          : Text('${history.length} 部'),
                      trailing: const GlyphIcon(Glyphs.chevronForward),
                      onPressed: () => BaseNavigator.push<void>(
                        context,
                        const HistoryPage(showBack: true),
                      ),
                    ),
                    DecorationListItem(
                      leading: GlyphIcon(
                        KonekoGlyphs.puzzle,
                        color: colorScheme.primary,
                      ),
                      title: const Text('规则管理'),
                      subtitle: Text('$enabledRules / ${rules.length}'),
                      trailing: const GlyphIcon(Glyphs.chevronForward),
                      onPressed: () => BaseNavigator.push<void>(
                        context,
                        const RulesPage(showBack: true),
                      ),
                    ),
                    DecorationListItem(
                      leading: GlyphIcon(
                        KonekoGlyphs.cloud,
                        color: colorScheme.primary,
                      ),
                      title: const Text('同步设置'),
                      subtitle: const Text('Bangumi / WebDAV'),
                      trailing: const GlyphIcon(Glyphs.chevronForward),
                      onPressed: () => BaseNavigator.push<void>(
                        context,
                        const ServiceSettingsPage(),
                      ),
                    ),
                    DecorationListItem(
                      leading: GlyphIcon(
                        KonekoGlyphs.importFile,
                        color: colorScheme.primary,
                      ),
                      title: const Text('离线缓存'),
                      subtitle: Text(
                        offlineEntries.isEmpty
                            ? '管理本地下载剧集'
                            : '已缓存 ${offlineEntries.length} 话',
                      ),
                      trailing: const GlyphIcon(Glyphs.chevronForward),
                      onPressed: () => BaseNavigator.push<void>(
                        context,
                        const OfflinePage(),
                      ),
                    ),
                    DecorationListItem(
                      leading: GlyphIcon(
                        KonekoGlyphs.palette,
                        color: colorScheme.primary,
                      ),
                      title: const Text('外观主题'),
                      subtitle: const Text('主题色、字体与弹幕'),
                      trailing: const GlyphIcon(Glyphs.chevronForward),
                      onPressed: () =>
                          BaseNavigator.push<void>(context, const ThemePage()),
                    ),
                  ],
                ),

                KonekoSection(
                  title: '关于',
                  items: [
                    DecorationListItem(
                      leading: GlyphIcon(
                        KonekoGlyphs.info,
                        color: colorScheme.primary,
                      ),
                      title: const Text('关于 Koneko'),
                      subtitle: const Text('v$kAppVersion'),
                      trailing: const GlyphIcon(Glyphs.chevronForward),
                      onPressed: () => BaseNavigator.push<void>(
                        context,
                        const AboutPage(showBack: true),
                      ),
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
