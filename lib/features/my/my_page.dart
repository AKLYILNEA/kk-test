import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/font_manager.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/about/about_page.dart';
import 'package:koneko/features/history/history_page.dart';
import 'package:koneko/features/theme/font_family_page.dart';
import 'package:koneko/features/theme/theme_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_icon.dart';
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

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: KonekoPageHeader(
              title: '我的',
              subtitle: 'Koneko UI-First · 纯净 FlClash / prism_ui 架构',
            ),
          ),
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
                          child: Text(
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
                              'Bangumi 离线演示账号',
                              style: AppTextStyle.headline
                                  .of(context, emphasized: true)
                                  .copyWith(color: colorScheme.onSurface),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '追番 ${library.length} 部 · 合并历史 ${history.length} 部 · Twemoji 默认',
                              style: AppTextStyle.caption1.of(context).copyWith(
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

                // Content & Kazumi Core Modules
                generateSection(
                  title: '番剧与规则引擎',
                  items: [
                    DecorationListItem(
                      leading: GlyphIcon(
                        KonekoGlyphs.history,
                        color: colorScheme.primary,
                      ),
                      title: const Text('合并历史记录'),
                      subtitle: Text('已按番剧合并 ${history.length} 组多源记录'),
                      trailing: const GlyphIcon(Glyphs.chevronForward),
                      onPressed: () => Navigator.of(context).push(
                        CardPageRoute<void>(
                          builder: (_) => const HistoryPage(showBack: true),
                        ),
                      ),
                    ),
                    DecorationListItem(
                      leading: GlyphIcon(
                        KonekoGlyphs.puzzle,
                        color: colorScheme.primary,
                      ),
                      title: const Text('Kazumi 规则管理'),
                      subtitle: Text('$enabledRules / ${rules.length} 条规则已启用'),
                      trailing: const GlyphIcon(Glyphs.chevronForward),
                      onPressed: () => Navigator.of(context).push(
                        CardPageRoute<void>(
                          builder: (_) => const RulesPage(showBack: true),
                        ),
                      ),
                    ),
                    DecorationListItem(
                      leading: GlyphIcon(
                        KonekoGlyphs.cloud,
                        color: colorScheme.primary,
                      ),
                      title: const Text('WebDAV 云端同步'),
                      subtitle: const Text('支持导入 Kazumi 备份并自动合并多源历史'),
                      trailing: KonekoChip(
                        label: '测试合并',
                        height: 26,
                        fontSize: 11.5,
                        backgroundColor:
                            colorScheme.primary.withValues(alpha: 0.14),
                        foregroundColor: colorScheme.primary,
                      ),
                      onPressed: () {
                        final count = ref
                            .read(historyProvider.notifier)
                            .importLegacyKazumiSample();
                        showKonekoBanner(
                          context,
                          '模拟 WebDAV 同步完成：已合并 $count 条 Kazumi 历史',
                          level: BannerLevel.success,
                        );
                      },
                    ),
                  ],
                ),

                // FlClash Theme & Instant Font Manager
                generateSection(
                  title: '外观与排版（FlClash 规范）',
                  items: [
                    DecorationListItem(
                      leading: GlyphIcon(
                        KonekoGlyphs.palette,
                        color: colorScheme.primary,
                      ),
                      title: const Text('外观主题'),
                      subtitle: const Text('实时预览 · HCT 调色盘 · 液态玻璃 · 深色模式'),
                      trailing: const GlyphIcon(Glyphs.chevronForward),
                      onPressed: () => Navigator.of(context).push(
                        CardPageRoute<void>(builder: (_) => const ThemePage()),
                      ),
                    ),
                    ValueListenableBuilder<String?>(
                      valueListenable: FontManager.fontFamilyNotifier,
                      builder: (context, _, _) {
                        return DecorationListItem(
                          leading: GlyphIcon(
                            KonekoGlyphs.font,
                            color: colorScheme.primary,
                          ),
                          title: const Text('字体管理（选后秒切）'),
                          subtitle: Text(
                            FontManager.selectedName ?? '系统默认（Emoji 固定 Twemoji）',
                          ),
                          trailing: const GlyphIcon(Glyphs.chevronForward),
                          onPressed: () => Navigator.of(context).push(
                            CardPageRoute<void>(
                              builder: (_) => const FontFamilyPage(),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                // About MIUIX
                generateSection(
                  title: '关于应用',
                  items: [
                    DecorationListItem(
                      leading: GlyphIcon(
                        KonekoGlyphs.info,
                        color: colorScheme.primary,
                      ),
                      title: const Text('关于 Koneko'),
                      subtitle: const Text('MIUIX 动态流体渐变关于页 · v$kAppVersion'),
                      trailing: const GlyphIcon(Glyphs.chevronForward),
                      onPressed: () => Navigator.of(context).push(
                        CardPageRoute<void>(
                          builder: (_) => const AboutPage(showBack: true),
                        ),
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

/// Dedicated Kazumi Rules Manager Page (accessible from Desktop Sidebar or MyPage).
class RulesPage extends ConsumerStatefulWidget {
  const RulesPage({
    super.key,
    this.showBack = false,
    this.bottomPadding = 0,
  });

  final bool showBack;
  final double bottomPadding;

  @override
  ConsumerState<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends ConsumerState<RulesPage> {
  bool _testing = false;

  Future<void> _testAll() async {
    if (_testing) return;
    setState(() => _testing = true);
    await ref.read(rulesProvider.notifier).testLatencies();
    if (!mounted) return;
    setState(() => _testing = false);
    showKonekoBanner(context, '规则测速完成', level: BannerLevel.success);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final rules = ref.watch(rulesProvider);

    return Surface(
      color: SurfaceLevel.page.colorOf(colorScheme),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: KonekoPageHeader(
                title: '规则管理',
                subtitle: '完全兼容 Kazumi JSON / XPath 规则格式',
                showBack: widget.showBack,
                actions: [
                  KonekoChip(
                    label: _testing ? '测速中...' : '全部测速',
                    height: 36,
                    fontSize: 12.5,
                    leading: KonekoIcon(
                      KonekoIcons.gauge,
                      size: 14,
                      color: colorScheme.onPrimary,
                    ),
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    onPressed: _testAll,
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                24 + widget.bottomPadding,
              ),
              sliver: SliverList.separated(
                itemCount: rules.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final rule = rules[index];
                  return KonekoCard(
                    corner: 24,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: ShapeDecoration(
                            color: rule.enabled
                                ? colorScheme.primary.withValues(alpha: 0.14)
                                : SurfaceLevel.block.colorOf(colorScheme),
                            shape: AppShape.md,
                          ),
                          child: Center(
                            child: KonekoIcon(
                              KonekoIcons.server,
                              size: 20,
                              color: rule.enabled
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
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
                                      rule.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyle.callout
                                          .of(context, emphasized: true)
                                          .copyWith(color: colorScheme.onSurface),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  KonekoChip(
                                    label: '${rule.latencyMs} ms',
                                    height: 22,
                                    fontSize: 10.5,
                                    backgroundColor: rule.latencyMs < 140
                                        ? colorScheme.successContainer
                                        : colorScheme.warningContainer,
                                    foregroundColor: rule.latencyMs < 140
                                        ? colorScheme.onSuccessContainer
                                        : colorScheme.onWarningContainer,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${rule.apiType} · v${rule.version} · ${rule.lastCheckedLabel}',
                                style: AppTextStyle.caption1.of(context).copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Switch(
                          value: rule.enabled,
                          onChanged: (v) =>
                              ref.read(rulesProvider.notifier).toggle(rule.id, v),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
