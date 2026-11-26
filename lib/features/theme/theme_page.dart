import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/font_manager.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/theme/font_family_page.dart';
import 'package:koneko/features/theme/theme_preview.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko/ui/palette.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

/// 07B · 1:1 FlClash ThemeView with interactive MiniScreen preview, HCT Palette,
/// instant custom Font Manager entry, and default Twemoji (no emoji switcher).
class ThemePage extends ConsumerStatefulWidget {
  const ThemePage({super.key, this.showBack = true, this.bottomPadding = 0});

  final bool showBack;
  final double bottomPadding;

  @override
  ConsumerState<ThemePage> createState() => _ThemePageState();
}

class _ThemePageState extends ConsumerState<ThemePage> {
  double? _draftScale;

  void _openCustomColorSheet(Color initial, ValueChanged<int> onConfirmed) {
    showSheet<void>(
      context: context,
      props: const SheetProps(detents: [0.9]),
      builder: (_) =>
          _CustomColorSheet(initialColor: initial, onConfirmed: onConfirmed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final settings = ref.watch(themeSettingsProvider);
    final notifier = ref.read(themeSettingsProvider.notifier);

    final lightScheme = buildKonekoColorScheme(
      brightness: Brightness.light,
      primaryColor: settings.primaryColor,
      colorStyle: settings.colorStyle,
      pureBlack: settings.pureBlack,
    );
    final darkScheme = buildKonekoColorScheme(
      brightness: Brightness.dark,
      primaryColor: settings.primaryColor,
      colorStyle: settings.colorStyle,
      pureBlack: settings.pureBlack,
    );
    final liquidGlass = settings.liquidGlass != LiquidGlassMode.none;

    final lightMini = MiniScreen(
      colorScheme: lightScheme,
      floatingBar: settings.floatingNavigationBar,
      liquidGlass: liquidGlass,
    );
    final darkMini = MiniScreen(
      colorScheme: darkScheme,
      floatingBar: settings.floatingNavigationBar,
      liquidGlass: liquidGlass,
    );

    final sysScale = systemTextScaleOf(
      context,
    ).clamp(kMinTextScale, kMaxTextScale).toDouble();
    final effectiveScale =
        _draftScale ??
        (settings.customTextScaleEnabled ? settings.textScale : sysScale);
    final scalePct = '${(effectiveScale * 100).round()}%';

    return KonekoScaffold(
      title: '外观主题',
      showBack: widget.showBack,
      body: Builder(
        builder: (context) => ListView(
          padding: EdgeInsets.only(
            top: context.contentTopPadding,
            bottom:
                32 +
                MediaQuery.paddingOf(context).bottom +
                widget.bottomPadding,
          ),
          children: [
            const ThemeLivePreview(),
            const SizedBox(height: 16),

            // Theme Mode
            PreviewChoiceGroup<ThemeMode>(
              info: const Info(label: '主题模式', glyph: KonekoGlyphs.sun),
              value: settings.themeMode,
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
              onChanged: (mode) =>
                  notifier.update((s) => s.copyWith(themeMode: mode)),
            ),
            const SizedBox(height: 16),

            // Pure Black
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: KonekoGroup(
                items: [
                  DecorationListItem(
                    leading: const GlyphIcon(KonekoGlyphs.pureBlack),
                    title: const Text('纯黑模式'),
                    trailing: Switch(
                      value: settings.pureBlack,
                      onChanged: (v) =>
                          notifier.update((s) => s.copyWith(pureBlack: v)),
                    ),
                    onPressed: () => notifier.update(
                      (s) => s.copyWith(pureBlack: !s.pureBlack),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Theme Color Swatches + Custom Palette + ColorStyle
            InfoHeader(
              info: const Info(label: '主题色', glyph: KonekoGlyphs.palette),
              actions: [
                KonekoCircleButton(
                  size: 32,
                  iconSize: 15,
                  glyph: KonekoGlyphs.reset,
                  tooltip: '重置配色',
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [
                  _ColorSwatches(
                    colors: [null, ...settings.primaryColors],
                    selected: settings.primaryColor,
                    onSelect: (c) =>
                        notifier.update((s) => s.copyWith(primaryColor: c)),
                    onAdd: () {
                      final init = Color(
                        settings.primaryColor ?? kDefaultPrimaryColor,
                      );
                      _openCustomColorSheet(init, (picked) {
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
                  SegmentedControl<ColorStyle>(
                    segments: const [
                      (ColorStyle.soft, '柔和'),
                      (ColorStyle.vivid, '鲜艳'),
                      (ColorStyle.tinted, '轻快'),
                      (ColorStyle.monochrome, '中性'),
                    ],
                    value: settings.colorStyle,
                    onChanged: (style) =>
                        notifier.update((s) => s.copyWith(colorStyle: style)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Navigation Bar Style
            PreviewChoiceGroup<bool>(
              info: const Info(label: '底栏样式', glyph: KonekoGlyphs.navBar),
              value: settings.floatingNavigationBar,
              choices: [
                PreviewChoice(
                  value: true,
                  label: '悬浮底栏',
                  pictogram: MiniScreenThumb(
                    screen: MiniScreen(
                      colorScheme: colorScheme,
                      floatingBar: true,
                      liquidGlass: liquidGlass,
                    ),
                  ),
                ),
                PreviewChoice(
                  value: false,
                  label: '经典底栏',
                  pictogram: MiniScreenThumb(
                    screen: MiniScreen(
                      colorScheme: colorScheme,
                      floatingBar: false,
                      liquidGlass: false,
                    ),
                  ),
                ),
              ],
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(floatingNavigationBar: v)),
            ),
            const SizedBox(height: 16),

            // Tab Animation
            PreviewChoiceGroup<TabAnimationMode>(
              info: const Info(label: '切换动画', glyph: KonekoGlyphs.motion),
              value: settings.tabAnimation,
              choices: [
                PreviewChoice(
                  value: TabAnimationMode.slide,
                  label: '滑动',
                  pictogram: MiniScreenThumb(
                    screen: MiniScreen(
                      colorScheme: colorScheme,
                      floatingBar: settings.floatingNavigationBar,
                      liquidGlass: liquidGlass,
                      selected: 1,
                      previous: 0,
                      progress: 0.55,
                      tabAnimation: TabAnimationMode.slide,
                    ),
                  ),
                ),
                PreviewChoice(
                  value: TabAnimationMode.fade,
                  label: '淡入',
                  pictogram: MiniScreenThumb(
                    screen: MiniScreen(
                      colorScheme: colorScheme,
                      floatingBar: settings.floatingNavigationBar,
                      liquidGlass: liquidGlass,
                      selected: 1,
                      previous: 0,
                      progress: 0.55,
                      tabAnimation: TabAnimationMode.fade,
                    ),
                  ),
                ),
              ],
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(tabAnimation: v)),
            ),
            const SizedBox(height: 16),

            // Liquid Glass Quality
            PreviewChoiceGroup<LiquidGlassMode>(
              info: const Info(label: '液态玻璃', glyph: KonekoGlyphs.glass),
              value: settings.liquidGlass,
              choices: [
                PreviewChoice(
                  value: LiquidGlassMode.none,
                  label: '关闭',
                  pictogram: MiniScreenThumb(
                    screen: MiniScreen(
                      colorScheme: colorScheme,
                      floatingBar: true,
                      liquidGlass: false,
                    ),
                  ),
                ),
                PreviewChoice(
                  value: LiquidGlassMode.standard,
                  label: '标准',
                  pictogram: MiniScreenThumb(
                    screen: MiniScreen(
                      colorScheme: colorScheme,
                      floatingBar: true,
                      liquidGlass: true,
                    ),
                  ),
                ),
                PreviewChoice(
                  value: LiquidGlassMode.ultra,
                  label: '极致',
                  pictogram: MiniScreenThumb(
                    screen: MiniScreen(
                      colorScheme: colorScheme,
                      floatingBar: true,
                      liquidGlass: true,
                    ),
                  ),
                ),
              ],
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(liquidGlass: v)),
            ),
            const SizedBox(height: 16),

            const InfoHeader(
              info: Info(label: '字体', glyph: KonekoGlyphs.font),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ValueListenableBuilder<String?>(
                valueListenable: FontManager.fontFamilyNotifier,
                builder: (context, family, _) {
                  final name = FontManager.selectedName ?? '系统默认';
                  return KonekoGroup(
                    items: [
                      DecorationListItem(
                        leading: Text(
                          'Aa',
                          style: AppTextStyle.headline
                              .of(context, emphasized: true)
                              .copyWith(
                                fontFamily: family,
                                color: colorScheme.primary,
                              ),
                        ),
                        title: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: family),
                        ),
                        trailing: const GlyphIcon(Glyphs.chevronForward),
                        onPressed: () => BaseNavigator.push<void>(
                          context,
                          const FontFamilyPage(),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Text Scale
            const InfoHeader(
              info: Info(label: '字号缩放', glyph: KonekoGlyphs.textSize),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                spacing: 8,
                children: [
                  SegmentedControl<bool>(
                    segments: const [(false, '跟随系统'), (true, '自定义')],
                    value: settings.customTextScaleEnabled,
                    onChanged: (enable) {
                      setState(() => _draftScale = null);
                      notifier.update(
                        (s) => s.copyWith(customTextScaleEnabled: enable),
                      );
                    },
                  ),
                  KonekoCard(
                    corner: 22,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: MediaQuery(
                                data: MediaQuery.of(context).copyWith(
                                  textScaler: TextScaler.linear(effectiveScale),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  spacing: 4,
                                  children: [
                                    Text(
                                      'Aa · 星海旅人 🎬',
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
                            const SizedBox(width: 8),
                            KonekoChip(label: scalePct),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          spacing: 10,
                          children: [
                            Text(
                              'A',
                              style: AppTextStyle.footnote
                                  .of(context)
                                  .copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            Expanded(
                              child: Slider(
                                min: kMinTextScale,
                                max: kMaxTextScale,
                                value: effectiveScale,
                                label: scalePct,
                                onChanged: settings.customTextScaleEnabled
                                    ? (v) => setState(() => _draftScale = v)
                                    : null,
                                onChangeEnd: (v) {
                                  setState(() => _draftScale = null);
                                  notifier.update(
                                    (s) => s.copyWith(textScale: v),
                                  );
                                },
                              ),
                            ),
                            Text(
                              'A',
                              style: AppTextStyle.title2
                                  .of(context)
                                  .copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
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
    );
  }
}

class _ColorSwatches extends StatelessWidget {
  const _ColorSwatches({
    required this.colors,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
  });

  final List<int?> colors;
  final int? selected;
  final ValueChanged<int?> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final level = context.raisedSurfaceLevel;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ShapeDecoration(
        color: level.colorOf(colorScheme),
        shape: AppShape.xl,
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final c in colors)
            _SwatchDot(
              color: Color(c ?? kDefaultPrimaryColor),
              isSystem: c == null,
              selected: c == selected,
              onTap: () => onSelect(c),
            ),
          PressSurface(
            fill: SurfaceLevel.block.colorOf(colorScheme),
            shape: AppShape.circle,
            onPressed: onAdd,
            child: SizedBox.square(
              dimension: 40,
              child: Center(
                child: GlyphIcon(
                  KonekoGlyphs.add,
                  size: 18,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwatchDot extends StatelessWidget {
  const _SwatchDot({
    required this.color,
    required this.isSystem,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool isSystem;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        padding: EdgeInsets.all(selected ? 3 : 0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: colorScheme.primary, width: 2.2)
              : null,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Center(
            child: selected
                ? const GlyphIcon(Glyphs.check, size: 16, color: Colors.white)
                : isSystem
                ? const Text(
                    '系',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  )
                : null,
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final settings = ref.watch(themeSettingsProvider);
    final gestureInsets = MediaQuery.systemGestureInsetsOf(context);

    return Surface(
      color: SurfaceLevel.page.colorOf(colorScheme),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            max(16, gestureInsets.left),
            12,
            max(16, gestureInsets.right),
            24,
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '自定义调色盘',
                    style: AppTextStyle.title2.of(context, emphasized: true),
                  ),
                ),
                KonekoChip(
                  label: '应用配色',
                  height: 36,
                  fontSize: 13,
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  onPressed: () {
                    widget.onConfirmed(_controller.value.toARGB32());
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<Color>(
              valueListenable: _controller,
              builder: (_, color, _) {
                Widget mini(Brightness b) => SizedBox(
                  width: 72,
                  height: 96,
                  child: ClipRSuperellipse(
                    borderRadius: AppRadius.md,
                    child: MiniScreen(
                      colorScheme: buildKonekoColorScheme(
                        brightness: b,
                        primaryColor: null,
                        colorStyle: settings.colorStyle,
                        pureBlack: settings.pureBlack,
                        overrideColor: color,
                      ),
                      floatingBar: settings.floatingNavigationBar,
                      liquidGlass: settings.liquidGlass != LiquidGlassMode.none,
                    ),
                  ),
                );
                return KonekoCard(
                  corner: 24,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    spacing: 12,
                    children: [
                      mini(Brightness.light),
                      mini(Brightness.dark),
                      Expanded(
                        child: HexColorField(
                          color: color,
                          onChanged: (c) => _controller.value = c,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Palette(controller: _controller),
          ],
        ),
      ),
    );
  }
}
