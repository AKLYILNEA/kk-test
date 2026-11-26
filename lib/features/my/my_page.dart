import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/font_manager.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/about/about_page.dart';
import 'package:koneko/features/history/history_page.dart';
import 'package:koneko/features/my/offline_page.dart';
import 'package:koneko/features/my/service_settings_page.dart';
import 'package:koneko/features/rules/rules_page.dart';
import 'package:koneko/features/theme/font_family_page.dart';
import 'package:koneko/features/theme/theme_page.dart';
import 'package:koneko/ui/koneko_danmaku_sheet.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

/// 07A · My / Settings Hub Page using prism_ui grouped cards (`generateSection`).
class MyPage extends ConsumerWidget {
  const MyPage({super.key, this.bottomPadding = 0});

  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final rules = ref.watch(rulesProvider);
    final history = ref.watch(historyProvider);
    final library = ref.watch(libraryProvider);
    final enabledRules = rules.where((r) => r.enabled).length;

    return KonekoScaffold(
      title: '我的',
      body: CustomScrollView(
        slivers: [
          const KonekoScrollStart(),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 28 + bottomPadding),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Profile & Sync summary card
                KonekoCard(
                  corner: 28,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: ShapeDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.14),
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
                          children: [
                            Text(
                              'Koneko',
                              style: AppTextStyle.headline
                                  .of(context, emphasized: true)
                                  .copyWith(color: colorScheme.onSurface),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '追番 ${library.length} 部 · 观看历史 ${history.length} 部',
                              style: AppTextStyle.caption1
                                  .of(context)
                                  .copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      KonekoChip(
                        label: 'v$kAppVersion',
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                      ),
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
                        KonekoGlyphs.danmaku,
                        color: colorScheme.primary,
                      ),
                      title: const Text('弹幕设置'),
                      trailing: const GlyphIcon(Glyphs.chevronForward),
                      onPressed: () => openKonekoDanmakuSettingsPage(context),
                    ),
                    DecorationListItem(
                      leading: GlyphIcon(
                        KonekoGlyphs.cloud,
                        color: colorScheme.primary,
                      ),
                      title: const Text('同步与服务'),
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
                      trailing: const GlyphIcon(Glyphs.chevronForward),
                      onPressed: () => BaseNavigator.push<void>(
                        context,
                        const OfflinePage(),
                      ),
                    ),
                  ],
                ),

                KonekoSection(
                  title: '外观',
                  items: [
                    DecorationListItem(
                      leading: GlyphIcon(
                        KonekoGlyphs.palette,
                        color: colorScheme.primary,
                      ),
                      title: const Text('外观主题'),
                      trailing: const GlyphIcon(Glyphs.chevronForward),
                      onPressed: () =>
                          BaseNavigator.push<void>(context, const ThemePage()),
                    ),
                    ValueListenableBuilder<String?>(
                      valueListenable: FontManager.fontFamilyNotifier,
                      builder: (context, _, _) {
                        return DecorationListItem(
                          leading: GlyphIcon(
                            KonekoGlyphs.font,
                            color: colorScheme.primary,
                          ),
                          title: const Text('字体'),
                          subtitle: Text(
                            FontManager.selectedName ?? '系统默认',
                          ),
                          trailing: const GlyphIcon(Glyphs.chevronForward),
                          onPressed: () => BaseNavigator.push<void>(
                            context,
                            const FontFamilyPage(),
                          ),
                        );
                      },
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
