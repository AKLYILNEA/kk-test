import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/font_manager.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/theme/font_family_page.dart';
import 'package:koneko/features/theme/theme_preview.dart';
import 'package:koneko/ui/koneko_danmaku_sheet.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko/ui/palette.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

String _colorStyleLabel(ColorStyle style) => switch (style) {
  ColorStyle.soft => '柔和',
  ColorStyle.vivid => '鲜艳',
  ColorStyle.tinted => '轻快',
  ColorStyle.monochrome => '中性',
};

String _colorHex(int color) =>
    '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

bool _intListEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 1:1 FlClash ThemeView with shadowless interactive live preview, pure-black
/// OLED toggle, HCT swatch deck with context-menu edit/delete, right-anchored
/// silky popup picker for ColorStyle, dock/floating navigation bar style,
/// tab animation, liquid glass, font & danmaku, and text scaling.
class ThemePage extends ConsumerStatefulWidget {
  const ThemePage({super.key, this.showBack = true, this.bottomPadding = 0});

  final bool showBack;
  final double bottomPadding;

  @override
  ConsumerState<ThemePage> createState() => _ThemePageState();
}

class _ThemePageState extends ConsumerState<ThemePage> {
  void _openCustomColorSheet(Color initial, ValueChanged<int> onConfirmed) {
    showSheet<void>(
      context: context,
      props: const SheetProps(detents: [0.9]),
      builder: (_) =>
          _CustomColorSheet(initialColor: initial, onConfirmed: onConfirmed),
    );
  }

  Widget _buildSection(BuildContext context, int index) => switch (index) {
    0 => const ThemeLivePreview(),
    1 => const _ThemeModeSection(),
    2 => const _PureBlackSection(),
    3 => _ThemeColorSection(onOpenCustomColor: _openCustomColorSheet),
    4 => const _NavigationBarSection(),
    5 => const _TabAnimationSection(),
    6 => const _LiquidGlassSection(),
    7 => const _FontAndDanmakuSection(),
    _ => const _TextScaleSection(),
  };

  @override
  Widget build(BuildContext context) {
    return KonekoScaffold(
      title: '外观主题',
      showBack: widget.showBack,
      body: ArrivalCacheExtentBuilder(
        builder: (context, cacheExtent) => CustomScrollView(
          scrollCacheExtent: cacheExtent,
          slivers: [
            const KonekoScrollStart(),
            SliverPadding(
              padding: EdgeInsets.only(
                top: 4,
                bottom:
                    32 +
                    MediaQuery.paddingOf(context).bottom +
                    widget.bottomPadding,
              ),
              sliver: SliverList.builder(
                itemCount: 9,
                itemBuilder: (context, index) => Padding(
                  padding: EdgeInsets.only(bottom: index == 8 ? 0 : 16),
                  child: _buildSection(context, index),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeModeSection extends ConsumerWidget {
  const _ThemeModeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (themeMode, pureBlack, primaryColor, colorStyle, floatingBar, glass) =
        ref.watch(
          themeSettingsProvider.select(
            (s) => (
              s.themeMode,
              s.pureBlack,
              s.primaryColor,
              s.colorStyle,
              s.floatingNavigationBar,
              s.liquidGlass != LiquidGlassMode.none,
            ),
          ),
        );
    final notifier = ref.read(themeSettingsProvider.notifier);
    final lightMini = MiniScreen(
      colorScheme: buildKonekoColorScheme(
        brightness: Brightness.light,
        primaryColor: primaryColor,
        colorStyle: colorStyle,
      ),
      floatingBar: floatingBar,
      liquidGlass: glass,
    );
    final darkMini = MiniScreen(
      colorScheme: buildKonekoColorScheme(
        brightness: Brightness.dark,
        primaryColor: primaryColor,
        colorStyle: colorStyle,
        pureBlack: pureBlack,
      ),
      floatingBar: floatingBar,
      liquidGlass: glass,
    );

    return PreviewChoiceGroup<ThemeMode>(
      info: const Info(label: '主题模式', glyph: KonekoGlyphs.sun),
      value: themeMode,
      choices: [
        PreviewChoice(
          value: ThemeMode.system,
          label: '跟随系统',
          pictogram: MiniScreenThumb(
            screen: MiniSplitScreen(light: lightMini, dark: darkMini),
          ),
        ),
        PreviewChoice(
          value: ThemeMode.light,
          label: '浅色',
          pictogram: MiniScreenThumb(screen: lightMini),
        ),
        PreviewChoice(
          value: ThemeMode.dark,
          label: '深色',
          pictogram: MiniScreenThumb(screen: darkMini),
        ),
      ],
      onChanged: (mode) => notifier.update((s) => s.copyWith(themeMode: mode)),
    );
  }
}

class _PureBlackSection extends ConsumerWidget {
  const _PureBlackSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (pureBlack, primaryColor, colorStyle, floatingBar, glass) = ref.watch(
      themeSettingsProvider.select(
        (s) => (
          s.pureBlack,
          s.primaryColor,
          s.colorStyle,
          s.floatingNavigationBar,
          s.liquidGlass != LiquidGlassMode.none,
        ),
      ),
    );
    final notifier = ref.read(themeSettingsProvider.notifier);
    Widget preview(bool isPureBlack) => MiniScreenThumb(
      screen: MiniScreen(
        colorScheme: buildKonekoColorScheme(
          brightness: Brightness.dark,
          primaryColor: primaryColor,
          colorStyle: colorStyle,
          pureBlack: isPureBlack,
        ),
        floatingBar: floatingBar,
        liquidGlass: glass,
      ),
    );

    return PreviewChoiceGroup<bool>(
      info: const Info(label: '纯黑模式', glyph: KonekoGlyphs.pureBlack),
      value: pureBlack,
      choices: [
        PreviewChoice(value: false, label: '标准', pictogram: preview(false)),
        PreviewChoice(value: true, label: '纯黑', pictogram: preview(true)),
      ],
      onChanged: (value) => notifier.update((s) => s.copyWith(pureBlack: value)),
    );
  }
}

class _ThemeColorSection extends ConsumerWidget {
  const _ThemeColorSection({required this.onOpenCustomColor});

  final void Function(Color initial, ValueChanged<int> onConfirmed)
  onOpenCustomColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (primaryColor, primaryColors, colorStyle) = ref.watch(
      themeSettingsProvider.select(
        (s) => (s.primaryColor, s.primaryColors, s.colorStyle),
      ),
    );
    final isDefault =
        primaryColor == kDefaultPrimaryColor &&
        _intListEquals(primaryColors, kDefaultPrimaryColors) &&
        colorStyle == ColorStyle.soft;
    final notifier = ref.read(themeSettingsProvider.notifier);

    void handleEdit(int oldColor) {
      onOpenCustomColor(Color(oldColor), (edited) {
        notifier.update((s) {
          final index = s.primaryColors.indexOf(oldColor);
          if (edited == oldColor || index == -1) return s;
          final list = List<int>.from(s.primaryColors);
          if (list.contains(edited)) {
            list.removeAt(index);
          } else {
            list[index] = edited;
          }
          return s.copyWith(
            primaryColors: list,
            primaryColor: s.primaryColor == oldColor ? edited : s.primaryColor,
          );
        });
      });
    }

    void handleDelete(int color) {
      notifier.update((s) {
        final list = List<int>.from(s.primaryColors)..remove(color);
        var current = s.primaryColor;
        if (current == color) {
          current = list.contains(kDefaultPrimaryColor)
              ? kDefaultPrimaryColor
              : null;
        }
        return s.copyWith(
          primaryColors: list.isEmpty ? kDefaultPrimaryColors : list,
          primaryColor: current,
        );
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoHeader(
          info: const Info(label: '主题色', glyph: KonekoGlyphs.palette),
          actions: [
            if (!isDefault)
              _ResetButton(
                onPressed: () => notifier.update(
                  (s) => s.copyWith(
                    primaryColor: kDefaultPrimaryColor,
                    primaryColors: kDefaultPrimaryColors,
                    colorStyle: ColorStyle.soft,
                  ),
                ),
              ),
          ],
        ),
        Padding(
          padding: context.listInsets.page(top: infoSectionContentGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              _ColorSwatches(
                colors: [null, ...primaryColors],
                selected: primaryColor,
                onSelect: (c) =>
                    notifier.update((s) => s.copyWith(primaryColor: c)),
                onEdit: handleEdit,
                onDelete: handleDelete,
                onAdd: () {
                  final init = Color(primaryColor ?? kDefaultPrimaryColor);
                  onOpenCustomColor(init, (picked) {
                    notifier.update(
                      (s) => s.copyWith(
                        primaryColors: s.primaryColors.contains(picked)
                            ? s.primaryColors
                            : [...s.primaryColors, picked],
                        primaryColor: picked,
                      ),
                    );
                  });
                },
              ),
              generateGroup([
                KonekoOptionsItem<ColorStyle>(
                  title: const Text('色彩风格'),
                  options: ColorStyle.values,
                  value: colorStyle,
                  textBuilder: _colorStyleLabel,
                  onChanged: (style) =>
                      notifier.update((s) => s.copyWith(colorStyle: style)),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavigationBarSection extends ConsumerWidget {
  const _NavigationBarSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final (floatingBar, glass) = ref.watch(
      themeSettingsProvider.select(
        (s) => (
          s.floatingNavigationBar,
          s.liquidGlass != LiquidGlassMode.none,
        ),
      ),
    );
    final notifier = ref.read(themeSettingsProvider.notifier);

    return PreviewChoiceGroup<bool>(
      info: const Info(label: '导航栏样式', glyph: KonekoGlyphs.dock),
      value: floatingBar,
      choices: [
        PreviewChoice(
          value: true,
          label: '悬浮',
          pictogram: MiniScreenThumb(
            screen: MiniScreen(
              colorScheme: colorScheme,
              floatingBar: true,
              liquidGlass: glass,
            ),
          ),
        ),
        PreviewChoice(
          value: false,
          label: '贴底',
          pictogram: MiniScreenThumb(
            screen: MiniScreen(colorScheme: colorScheme, floatingBar: false),
          ),
        ),
      ],
      onChanged: (value) =>
          notifier.update((s) => s.copyWith(floatingNavigationBar: value)),
    );
  }
}

class _TabAnimationSection extends ConsumerWidget {
  const _TabAnimationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final (tabAnimation, floatingBar, liquidGlass) = ref.watch(
      themeSettingsProvider.select(
        (s) => (
          s.tabAnimation,
          s.floatingNavigationBar,
          s.liquidGlass != LiquidGlassMode.none,
        ),
      ),
    );
    final notifier = ref.read(themeSettingsProvider.notifier);
    Widget switching(TabAnimationMode mode) => MiniScreenThumb(
      screen: MiniScreen(
        colorScheme: colorScheme,
        floatingBar: floatingBar,
        liquidGlass: liquidGlass,
        selected: 1,
        previous: 0,
        progress: 0.55,
        tabAnimation: mode,
      ),
    );

    return PreviewChoiceGroup<TabAnimationMode>(
      info: const Info(label: '切换动画', glyph: KonekoGlyphs.motion),
      value: tabAnimation,
      choices: [
        PreviewChoice(
          value: TabAnimationMode.slide,
          label: '滑动',
          pictogram: switching(TabAnimationMode.slide),
        ),
        PreviewChoice(
          value: TabAnimationMode.fade,
          label: '淡入',
          pictogram: switching(TabAnimationMode.fade),
        ),
      ],
      onChanged: (v) => notifier.update((s) => s.copyWith(tabAnimation: v)),
    );
  }
}

class _LiquidGlassSection extends ConsumerWidget {
  const _LiquidGlassSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final liquidGlass = ref.watch(
      themeSettingsProvider.select((s) => s.liquidGlass),
    );
    final notifier = ref.read(themeSettingsProvider.notifier);
    // Floating over the schedule list page whose rows run under the bar so the
    // glass refraction reads clearly in the thumbnails (1:1 FlClash).
    Widget preview(bool glass) => MiniScreenThumb(
      screen: MiniScreen(
        colorScheme: colorScheme,
        floatingBar: true,
        liquidGlass: glass,
        selected: 1,
      ),
    );

    return PreviewChoiceGroup<LiquidGlassMode>(
      info: const Info(label: '液态玻璃', glyph: KonekoGlyphs.glass),
      value: liquidGlass,
      choices: [
        PreviewChoice(
          value: LiquidGlassMode.none,
          label: '关闭',
          pictogram: preview(false),
        ),
        PreviewChoice(
          value: LiquidGlassMode.standard,
          label: '标准',
          pictogram: preview(true),
        ),
        PreviewChoice(
          value: LiquidGlassMode.ultra,
          label: '极致',
          pictogram: preview(true),
        ),
      ],
      onChanged: (v) => notifier.update((s) => s.copyWith(liquidGlass: v)),
    );
  }
}

class _FontAndDanmakuSection extends StatelessWidget {
  const _FontAndDanmakuSection();

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final cardColor = context.raisedSurfaceLevel.colorOf(colorScheme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const InfoHeader(
          info: Info(label: '字体与弹幕', glyph: KonekoGlyphs.font),
        ),
        Padding(
          padding: context.listInsets.page(top: infoSectionContentGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              ValueListenableBuilder<String?>(
                valueListenable: FontManager.fontFamilyNotifier,
                builder: (context, family, _) {
                  final name = FontManager.selectedName ?? '系统默认';
                  return PressSurface(
                    fill: cardColor,
                    shape: AppShape.lg,
                    childFills: true,
                    clipsChild: true,
                    onPressed: () => BaseNavigator.push<void>(
                      context,
                      const FontFamilyPage(),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                      child: Row(
                        spacing: 12,
                        children: [
                          Text(
                            'Aa',
                            style: AppTextStyle.headline
                                .of(context)
                                .copyWith(fontFamily: family),
                          ),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.subheadline
                                  .of(context)
                                  .copyWith(
                                    fontFamily: family,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                          GlyphIcon(
                            Glyphs.chevronForward,
                            size: 20,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              generateGroup([
                DecorationListItem(
                  leading: GlyphIcon(
                    KonekoGlyphs.danmaku,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('弹幕设置'),
                  subtitle: const Text('区域、样式与来源'),
                  trailing: const GlyphIcon(Glyphs.chevronForward),
                  onPressed: () => openKonekoDanmakuSettingsPage(context),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _TextScaleSection extends ConsumerStatefulWidget {
  const _TextScaleSection();

  @override
  ConsumerState<_TextScaleSection> createState() => _TextScaleSectionState();
}

class _TextScaleSectionState extends ConsumerState<_TextScaleSection> {
  double? _draft;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final (customEnabled, savedScale) = ref.watch(
      themeSettingsProvider.select(
        (s) => (s.customTextScaleEnabled, s.textScale),
      ),
    );
    final notifier = ref.read(themeSettingsProvider.notifier);
    final sysScale = systemTextScaleOf(
      context,
    ).clamp(kMinTextScale, kMaxTextScale).toDouble();
    final scale = _draft ?? (customEnabled ? savedScale : sysScale);
    final percent = '${(scale * 100).round()}%';
    final level = context.raisedSurfaceLevel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoHeader(
          info: const Info(label: '字号缩放', glyph: KonekoGlyphs.textSize),
          actions: [
            if (customEnabled && savedScale != 1.0)
              _ResetButton(
                onPressed: () {
                  setState(() => _draft = null);
                  notifier.update((s) => s.copyWith(textScale: 1.0));
                },
              ),
          ],
        ),
        Padding(
          padding: context.listInsets.page(top: infoSectionContentGap),
          child: Column(
            spacing: 8,
            children: [
              SegmentedControl<bool>(
                segments: const [(false, '跟随系统'), (true, '自定义')],
                value: customEnabled,
                onChanged: (enable) {
                  setState(() => _draft = null);
                  notifier.update(
                    (s) => s.copyWith(customTextScaleEnabled: enable),
                  );
                },
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                decoration: ShapeDecoration(
                  color: level.colorOf(colorScheme),
                  shape: AppShape.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 12,
                      children: [
                        Expanded(
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topLeft,
                            child: MediaQuery(
                              data: MediaQuery.of(
                                context,
                              ).copyWith(textScaler: TextScaler.linear(scale)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 4,
                                children: [
                                  Text(
                                    'Aa',
                                    style: AppTextStyle.title3.of(context),
                                  ),
                                  Text(
                                    '拖动滑块预览文字大小',
                                    style: AppTextStyle.subheadline
                                        .of(context)
                                        .copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: ShapeDecoration(
                            color: level.next.colorOf(colorScheme),
                            shape: AppShape.full,
                          ),
                          child: Text(
                            percent,
                            style: AppTextStyle.subheadline
                                .of(context, emphasized: true)
                                .copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    MediaQuery.withNoTextScaling(
                      child: Row(
                        spacing: 12,
                        children: [
                          ExcludeSemantics(
                            child: Text(
                              'A',
                              style: AppTextStyle.footnote
                                  .of(context)
                                  .copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              min: kMinTextScale,
                              max: kMaxTextScale,
                              value: scale,
                              label: percent,
                              onChanged: customEnabled
                                  ? (v) => setState(() => _draft = v)
                                  : null,
                              onChangeEnd: (v) {
                                setState(() => _draft = null);
                                notifier.update(
                                  (s) => s.copyWith(textScale: v),
                                );
                              },
                            ),
                          ),
                          ExcludeSemantics(
                            child: Text(
                              'A',
                              style: AppTextStyle.title2
                                  .of(context)
                                  .copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TonalButtonTheme(
      size: TonalButtonSize.section,
      child: ElasticPress(
        child: IconButton(
          tooltip: '重置',
          onPressed: onPressed,
          icon: const GlyphIcon(KonekoGlyphs.reset),
        ),
      ),
    );
  }
}

class _ColorSwatches extends StatelessWidget {
  const _ColorSwatches({
    required this.colors,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onAdd,
  });

  static const double _minGap = 6;
  static const double _inset = 16 - (_ColorSwatch.size - _ColorSwatch.dot) / 2;

  final List<int?> colors;
  final int? selected;
  final ValueChanged<int?> onSelect;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onDelete;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final level = context.raisedSurfaceLevel;
    const systemColor = Color(kDefaultPrimaryColor);

    return Container(
      padding: const EdgeInsets.all(_inset),
      decoration: ShapeDecoration(
        color: level.colorOf(colorScheme),
        shape: AppShape.xl,
      ),
      child: SurfaceScope(
        level: level,
        child: LayoutBuilder(
          builder: (_, constraints) {
            const cell = _ColorSwatch.size;
            final width = constraints.maxWidth;
            final columns = max(
              1,
              ((width + _minGap) / (cell + _minGap)).floor(),
            );
            final gap = columns > 1
                ? ((width - columns * cell) / (columns - 1)).floorToDouble()
                : 0.0;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final color in colors)
                  _ColorSwatch(
                    color: color == null ? null : Color(color),
                    systemColor: systemColor,
                    isSelected: color == selected,
                    label: color == null ? '跟随系统' : _colorHex(color),
                    onPressed: () => onSelect(color),
                    menuItems: color == null
                        ? null
                        : [
                            PopupMenuItem(
                              glyph: KonekoGlyphs.edit,
                              label: '编辑',
                              onPressed: () => onEdit(color),
                            ),
                            PopupMenuItem(
                              danger: true,
                              glyph: KonekoGlyphs.trash,
                              label: '删除',
                              onPressed: () => onDelete(color),
                            ),
                          ],
                  ),
                _AddColorButton(onPressed: onAdd),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.systemColor,
    required this.isSelected,
    required this.label,
    required this.onPressed,
    this.menuItems,
  });

  static const double size = 44;
  static const double dot = 32;
  static const double _ring = 2.5;
  static const _duration = Duration(milliseconds: 200);
  static const double _badge = 20;

  final Color? color;
  final Color systemColor;
  final bool isSelected;
  final String label;
  final VoidCallback onPressed;
  final List<PopupMenuItem>? menuItems;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? systemColor;
    final selected = isSelected;
    final check = ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final swatch = SizedBox.square(
      dimension: size,
      child: PressSurface(
        fill: Colors.transparent,
        shape: AppShape.circle,
        ringStandsOff: selected,
        selected: selected,
        childFills: true,
        onPressed: onPressed,
        child: Semantics(
          label: label,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: _duration,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: AppShape.circle.copyWith(
                      side: BorderSide(color: fill, width: _ring),
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              SizedBox.square(
                dimension: dot,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: fill,
                    shape: AppShape.circle,
                  ),
                ),
              ),
              if (color == null)
                const Positioned(
                  right: 0,
                  bottom: 0,
                  child: _EyedropperBadge(size: _badge),
                ),
              AnimatedScale(
                scale: selected ? 1 : 0,
                duration: _duration,
                curve: Curves.easeOutBack,
                child: GlyphIcon(
                  Glyphs.check,
                  size: 18,
                  fill: 1,
                  color: check,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final menuItems = this.menuItems;
    if (menuItems == null) return swatch;
    return ContextMenuRegion(menuItems: menuItems, child: swatch);
  }
}

class _EyedropperBadge extends StatelessWidget {
  const _EyedropperBadge({required this.size});

  static const double _gap = 2;

  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(_gap),
      decoration: ShapeDecoration(
        color: context.surfaceLevel.colorOf(colorScheme),
        shape: AppShape.circle,
      ),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: context.raisedSurfaceLevel.colorOf(colorScheme),
          shape: AppShape.circle,
        ),
        child: Center(
          child: GlyphIcon(
            KonekoGlyphs.eyedropper,
            size: size - _gap * 2 - 4,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _AddColorButton extends StatelessWidget {
  const _AddColorButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Tooltip(
      message: '添加自定义颜色',
      child: SizedBox.square(
        dimension: _ColorSwatch.size,
        child: PressSurface(
          fill: Colors.transparent,
          shape: AppShape.circle,
          childFills: true,
          onPressed: onPressed,
          child: Center(
            child: Container(
              width: _ColorSwatch.dot,
              height: _ColorSwatch.dot,
              decoration: ShapeDecoration(
                color: context.raisedSurfaceLevel.colorOf(colorScheme),
                shape: AppShape.circle,
              ),
              child: GlyphIcon(
                KonekoGlyphs.add,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomColorSheet extends ConsumerStatefulWidget {
  const _CustomColorSheet({
    required this.initialColor,
    required this.onConfirmed,
  });

  final Color initialColor;
  final ValueChanged<int> onConfirmed;

  @override
  ConsumerState<_CustomColorSheet> createState() => _CustomColorSheetState();
}

class _CustomColorSheetState extends ConsumerState<_CustomColorSheet> {
  late final ValueNotifier<Color> _controller = ValueNotifier<Color>(
    widget.initialColor,
  );

  void _confirm() {
    final color = _controller.value.toARGB32();
    final onConfirmed = widget.onConfirmed;
    final route = ModalRoute.of(context);
    if (route != null) {
      unawaited(route.completed.whenComplete(() => onConfirmed(color)));
    } else {
      onConfirmed(color);
    }
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(themeSettingsProvider);
    final gestureInsets = MediaQuery.systemGestureInsetsOf(context);
    final level = context.raisedSurfaceLevel;

    return KonekoScaffold(
      title: '自定义颜色',
      showBack: true,
      actions: [
        IconButtonData(
          glyph: Glyphs.check,
          tooltip: '确认',
          onPressed: _confirm,
        ),
      ],
      body: CustomScrollView(
        slivers: [
          const KonekoScrollStart(),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              max(16, gestureInsets.left),
              4,
              max(16, gestureInsets.right),
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverList.list(
              children: [
                ValueListenableBuilder<Color>(
                  valueListenable: _controller,
                  builder: (_, color, _) {
                    Widget screen(Brightness brightness) => ExcludeSemantics(
                      child: SizedBox(
                        width: 72,
                        height: 96,
                        child: ClipRSuperellipse(
                          borderRadius: AppRadius.md,
                          child: FittedBox(
                            child: SizedBox(
                              width: 96,
                              height: 128,
                              child: MiniScreen(
                                colorScheme: buildKonekoColorScheme(
                                  brightness: brightness,
                                  primaryColor: null,
                                  colorStyle: settings.colorStyle,
                                  pureBlack: settings.pureBlack,
                                  overrideColor: color,
                                ),
                                floatingBar: settings.floatingNavigationBar,
                                liquidGlass:
                                    settings.liquidGlass !=
                                    LiquidGlassMode.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: ShapeDecoration(
                        color: level.colorOf(context.colorScheme),
                        shape: AppShape.xl,
                      ),
                      child: SurfaceScope(
                        level: level,
                        child: Row(
                          spacing: 12,
                          children: [
                            screen(Brightness.light),
                            screen(Brightness.dark),
                            Expanded(
                              child: HexColorField(
                                color: color,
                                onChanged: (c) => _controller.value = c,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Palette(controller: _controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
