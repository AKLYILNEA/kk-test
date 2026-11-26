import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_sheet.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

/// Opens Kazumi-parity Danmaku appearance, area (including half-screen 50%),
/// typography weight/stroke, speed & aggregated source settings in a pure
/// FlClash modal Sheet. Changes apply live to active playback immediately.
Future<void> showKonekoDanmakuSettingsSheet(BuildContext context) {
  return showKonekoSheet<void>(
    context: context,
    title: '弹幕设置',
    subtitle: '弹弹Play 已聚合 B站 / 巴哈姆特 / 弹弹Play 多平台弹幕',
    detents: const [0.76, 0.94],
    bodyBuilder: (sheetContext) => const _DanmakuSettingsSheetBody(),
  );
}

class _DanmakuSettingsSheetBody extends ConsumerWidget {
  const _DanmakuSettingsSheetBody();

  static const _areaPresets = <(double, String)>[
    (0.25, '1/4 屏'),
    (0.50, '半屏 50%'),
    (0.75, '3/4 屏'),
    (1.00, '全屏'),
  ];

  static String _weightLabel(int weight) => switch (weight) {
    <= 2 => '极细 ($weight)',
    3 => '细体 (3)',
    4 => '常规 (4)',
    5 => '中等 (5)',
    6 => '半粗 (6)',
    _ => '粗体 ($weight)',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final settings = ref.watch(danmakuSettingsProvider);
    final notifier = ref.read(danmakuSettingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        const ListHeader(title: '显示区域'),
        KonekoCard(
          corner: 24,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (ratio, label) in _areaPresets)
                    KonekoChip(
                      label: label,
                      height: 32,
                      fontSize: 12.5,
                      selected: (settings.area - ratio).abs() < 0.02,
                      backgroundColor: (settings.area - ratio).abs() < 0.02
                          ? colorScheme.primary
                          : SurfaceLevel.block.colorOf(colorScheme),
                      onPressed: () =>
                          notifier.update((s) => s.copyWith(area: ratio)),
                    ),
                ],
              ),
              _SliderRow(
                label: '自定义显示区域',
                valueText: '${(settings.area * 100).round()}%',
                value: settings.area,
                min: 0.125,
                max: 1.0,
                divisions: 7,
                onChanged: (v) => notifier.update((s) => s.copyWith(area: v)),
              ),
            ],
          ),
        ),
        const ListHeader(title: '字体、粗细与样式'),
        KonekoCard(
          corner: 24,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              _SliderRow(
                label: '字体大小',
                valueText: '${settings.fontSize.round()} px',
                value: settings.fontSize,
                min: 10,
                max: 36,
                divisions: 26,
                onChanged: (v) => notifier.update(
                  (s) => s.copyWith(fontSize: v.roundToDouble()),
                ),
              ),
              _SliderRow(
                label: '字体字重（粗细）',
                valueText: _weightLabel(settings.fontWeight),
                value: settings.fontWeight.toDouble(),
                min: 1,
                max: 9,
                divisions: 8,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(fontWeight: v.round())),
              ),
              _SliderRow(
                label: '描边粗细',
                valueText: settings.strokeEnabled
                    ? settings.strokeWidth.toStringAsFixed(1)
                    : '已关闭',
                value: settings.strokeWidth,
                min: 0.2,
                max: 3.0,
                divisions: 28,
                onChanged: settings.strokeEnabled
                    ? (v) => notifier.update(
                        (s) => s.copyWith(
                          strokeWidth: double.parse(v.toStringAsFixed(1)),
                        ),
                      )
                    : null,
              ),
              _SliderRow(
                label: '不透明度',
                valueText: '${(settings.opacity * 100).round()}%',
                value: settings.opacity,
                min: 0.1,
                max: 1.0,
                divisions: 18,
                onChanged: (v) => notifier.update(
                  (s) => s.copyWith(
                    opacity: double.parse(v.toStringAsFixed(2)),
                  ),
                ),
              ),
              _SliderRow(
                label: '停留时间（越大越慢）',
                valueText: '${settings.duration.round()} 秒',
                value: settings.duration,
                min: 3,
                max: 16,
                divisions: 13,
                onChanged: (v) => notifier.update(
                  (s) => s.copyWith(duration: v.roundToDouble()),
                ),
              ),
              _SliderRow(
                label: '行间距',
                valueText: settings.lineHeight.toStringAsFixed(1),
                value: settings.lineHeight,
                min: 0.8,
                max: 2.2,
                divisions: 14,
                onChanged: (v) => notifier.update(
                  (s) => s.copyWith(
                    lineHeight: double.parse(v.toStringAsFixed(1)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const ListHeader(title: '弹幕类型与绘制'),
        KonekoGroup(
          items: [
            DecorationListItem(
              title: const Text('滚动弹幕'),
              trailing: Switch(
                value: settings.showScroll,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(showScroll: v)),
              ),
              onPressed: () => notifier.update(
                (s) => s.copyWith(showScroll: !s.showScroll),
              ),
            ),
            DecorationListItem(
              title: const Text('顶部弹幕'),
              trailing: Switch(
                value: settings.showTop,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(showTop: v)),
              ),
              onPressed: () =>
                  notifier.update((s) => s.copyWith(showTop: !s.showTop)),
            ),
            DecorationListItem(
              title: const Text('底部弹幕'),
              trailing: Switch(
                value: settings.showBottom,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(showBottom: v)),
              ),
              onPressed: () => notifier.update(
                (s) => s.copyWith(showBottom: !s.showBottom),
              ),
            ),
            DecorationListItem(
              title: const Text('弹幕描边'),
              trailing: Switch(
                value: settings.strokeEnabled,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(strokeEnabled: v)),
              ),
              onPressed: () => notifier.update(
                (s) => s.copyWith(strokeEnabled: !s.strokeEnabled),
              ),
            ),
            DecorationListItem(
              title: const Text('彩色弹幕'),
              subtitle: const Text('关闭后统一以纯白显示'),
              trailing: Switch(
                value: settings.colorful,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(colorful: v)),
              ),
              onPressed: () =>
                  notifier.update((s) => s.copyWith(colorful: !s.colorful)),
            ),
            DecorationListItem(
              title: const Text('海量弹幕模式'),
              subtitle: const Text('高密度弹幕时允许叠加绘制'),
              trailing: Switch(
                value: settings.massiveMode,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(massiveMode: v)),
              ),
              onPressed: () => notifier.update(
                (s) => s.copyWith(massiveMode: !s.massiveMode),
              ),
            ),
          ],
        ),
        const ListHeader(
          title: '弹幕来源过滤（对齐 Kazumi）',
          caption: '与 Kazumi 一致，通过弹弹Play 聚合接口同步拉取多站弹幕',
        ),
        KonekoGroup(
          items: [
            DecorationListItem(
              title: const Text('BiliBili（B站）'),
              trailing: Switch(
                value: settings.sourceBilibili,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(sourceBilibili: v)),
              ),
              onPressed: () => notifier.update(
                (s) => s.copyWith(sourceBilibili: !s.sourceBilibili),
              ),
            ),
            DecorationListItem(
              title: const Text('Gamer（巴哈姆特动画疯）'),
              trailing: Switch(
                value: settings.sourceGamer,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(sourceGamer: v)),
              ),
              onPressed: () => notifier.update(
                (s) => s.copyWith(sourceGamer: !s.sourceGamer),
              ),
            ),
            DecorationListItem(
              title: const Text('弹弹Play 及其他来源'),
              trailing: Switch(
                value: settings.sourceDandan,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(sourceDandan: v)),
              ),
              onPressed: () => notifier.update(
                (s) => s.copyWith(sourceDandan: !s.sourceDandan),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        KonekoCard(
          corner: 20,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          onPressed: () {
            notifier.reset();
            showKonekoBanner(context, '已恢复默认弹幕设置');
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 8,
            children: [
              GlyphIcon(
                KonekoGlyphs.reset,
                size: 16,
                color: colorScheme.primary,
              ),
              Text(
                '恢复默认弹幕设置',
                style: AppTextStyle.subheadline
                    .of(context, emphasized: true)
                    .copyWith(color: colorScheme.primary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyle.footnote
                    .of(context, emphasized: true)
                    .copyWith(color: colorScheme.onSurface),
              ),
            ),
            Text(
              valueText,
              style: AppTextStyle.caption1
                  .of(context, emphasized: true)
                  .copyWith(
                    color: colorScheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
