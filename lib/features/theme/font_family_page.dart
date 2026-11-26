import 'package:flutter/widgets.dart';
import 'package:koneko/common/font_manager.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

/// 07C · 1:1 FlClash Custom Font Management Page (import TTF/OTF, instant hot-swap).
class FontFamilyPage extends StatefulWidget {
  const FontFamilyPage({super.key});

  @override
  State<FontFamilyPage> createState() => _FontFamilyPageState();
}

class _FontFamilyPageState extends State<FontFamilyPage> {
  Future<void> _handleImport() async {
    final ok = await FontManager.importAndSelect();
    if (!mounted) return;
    if (ok) {
      setState(() {});
      showKonekoBanner(
        context,
        '已导入并秒切字体：${FontManager.selectedName ?? ""}',
        level: BannerLevel.success,
      );
    }
  }

  Future<void> _handleDelete(CustomFont font) async {
    await FontManager.delete(font);
    if (!mounted) return;
    setState(() {});
    showKonekoBanner(context, '已删除字体：${font.name}');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Surface(
      color: SurfaceLevel.page.colorOf(colorScheme),
      child: SafeArea(
        bottom: false,
        child: ValueListenableBuilder<String?>(
          valueListenable: FontManager.fontFamilyNotifier,
          builder: (context, activeFamily, _) {
            final fonts = FontManager.fonts;
            final selected = FontManager.selectedFont;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: KonekoPageHeader(
                    title: '字体管理',
                    subtitle: '导入本地 .ttf / .otf · 选后全界面秒切',
                    showBack: true,
                    actions: [
                      KonekoChip(
                        label: '导入字体',
                        height: 36,
                        fontSize: 13,
                        leading: GlyphIcon(
                          KonekoGlyphs.add,
                          size: 15,
                          color: colorScheme.onPrimary,
                        ),
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        onPressed: _handleImport,
                      ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    28 + MediaQuery.paddingOf(context).bottom,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Live sample preview card
                      KonekoCard(
                        corner: 26,
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 6,
                          children: [
                            Row(
                              children: [
                                KonekoChip(
                                  label: selected == null ? '当前：系统默认' : '当前：${selected.name}',
                                  backgroundColor:
                                      colorScheme.primary.withValues(alpha: 0.14),
                                  foregroundColor: colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                const KonekoChip(label: 'Twemoji 🐱✨'),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '星海旅人：北境编年史 2026',
                              style: AppTextStyle.title2
                                  .of(context, emphasized: true)
                                  .copyWith(fontFamily: activeFamily),
                            ),
                            Text(
                              'Hoshiumi no Tabibito · 0123456789 · 切换后零重启秒级生效 🎬🌸',
                              style: AppTextStyle.subheadline.of(context).copyWith(
                                fontFamily: activeFamily,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),

                      generateSection(
                        title: '默认字体',
                        items: [
                          DecorationListItem(
                            title: const Text('系统默认'),
                            subtitle: const Text('跟随设备系统字体 + Twemoji'),
                            isSelected: selected == null,
                            trailing: selected == null
                                ? const SelectionCheck()
                                : null,
                            onPressed: () async {
                              await FontManager.selectDefault();
                              if (mounted) setState(() {});
                            },
                          ),
                        ],
                      ),

                      generateSection(
                        title: '已导入字体 (${fonts.length})',
                        footer: fonts.isEmpty
                            ? '点击右上角「导入字体」选择设备中的 .ttf 或 .otf 文件，导入后支持实时预览与一键秒切。'
                            : '点击任意字体即可零重启切换全局排版；点击右侧垃圾桶图标可移除。',
                        items: [
                          if (fonts.isEmpty)
                            DecorationListItem(
                              leading: GlyphIcon(
                                KonekoGlyphs.addCircle,
                                color: colorScheme.primary,
                              ),
                              title: const Text('立即导入本地 TTF / OTF 字体'),
                              subtitle: const Text('与 FlClash 一致，自动修正静态粗体字重'),
                              onPressed: _handleImport,
                            )
                          else
                            for (final font in fonts)
                              DecorationListItem(
                                title: Text(
                                  font.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: FontManager.familyOf(font),
                                  ),
                                ),
                                subtitle: Text(
                                  '示例：星海旅人 AaBb 0123',
                                  style: TextStyle(
                                    fontFamily: FontManager.familyOf(font),
                                  ),
                                ),
                                isSelected: selected?.path == font.path,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  spacing: 8,
                                  children: [
                                    if (selected?.path == font.path)
                                      const SelectionCheck(),
                                    KonekoCircleButton(
                                      size: 32,
                                      iconSize: 15,
                                      glyph: KonekoGlyphs.trash,
                                      tooltip: '删除字体',
                                      onPressed: () => _handleDelete(font),
                                    ),
                                  ],
                                ),
                                onPressed: () async {
                                  await FontManager.select(font);
                                  if (mounted) setState(() {});
                                },
                              ),
                        ],
                      ),
                    ]),
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
