import 'package:flutter/widgets.dart';
import 'package:koneko/common/font_manager.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
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
        '已切换字体：${FontManager.selectedName ?? ""}',
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
    return KonekoScaffold(
      title: '字体管理',
      showBack: true,
      actions: [
        IconButtonData(
          glyph: KonekoGlyphs.addCircle,
          tooltip: '导入字体',
          onPressed: _handleImport,
        ),
      ],
      body: ArrivalCacheExtentBuilder(
        builder: (context, cacheExtent) => ValueListenableBuilder<String?>(
          valueListenable: FontManager.fontFamilyNotifier,
          builder: (context, activeFamily, _) {
            final fonts = FontManager.fonts;
            final selected = FontManager.selectedFont;
            return CustomScrollView(
              scrollCacheExtent: cacheExtent,
              slivers: [
                const KonekoScrollStart(),
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
                      RepaintBoundary(
                        child: KonekoCard(
                          corner: 26,
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 6,
                            children: [
                              KonekoChip(
                                label: selected == null
                                    ? '当前：系统默认'
                                    : '当前：${selected.name}',
                                backgroundColor: colorScheme.primary.withValues(
                                  alpha: 0.14,
                                ),
                                foregroundColor: colorScheme.primary,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '星海旅人：北境编年史 2026',
                                style: AppTextStyle.title2
                                    .of(context, emphasized: true)
                                    .copyWith(fontFamily: activeFamily),
                              ),
                              Text(
                                'AaBbCc 0123456789',
                                style: AppTextStyle.subheadline
                                    .of(context)
                                    .copyWith(
                                      fontFamily: activeFamily,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    KonekoSection(
                      title: '默认',
                      items: [
                        DecorationListItem(
                          title: const Text('系统默认'),
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

                    KonekoSection(
                      title: '已导入 (${fonts.length})',
                      items: [
                        if (fonts.isEmpty)
                          DecorationListItem(
                            leading: GlyphIcon(
                              KonekoGlyphs.addCircle,
                              color: colorScheme.primary,
                            ),
                            title: const Text('导入字体'),
                            subtitle: const Text('支持 .ttf / .otf'),
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
