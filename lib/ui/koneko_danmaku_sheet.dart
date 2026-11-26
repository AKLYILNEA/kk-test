import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/prism_ui.dart';

/// Opens the full-page Kazumi-parity Danmaku Settings screen in pure FlClash style.
Future<void> openKonekoDanmakuSettingsPage(BuildContext context) {
  return BaseNavigator.push<void>(context, const DanmakuSettingsPage());
}

/// Full-page Danmaku appearance, area (including half-screen 50%), typography
/// weight/stroke, speed & aggregated source settings with live cinema preview.
class DanmakuSettingsPage extends ConsumerWidget {
  const DanmakuSettingsPage({super.key});

  static const _areaPresets = <(double, String)>[
    (0.25, '1/4 屏'),
    (0.50, '半屏'),
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

    return KonekoScaffold(
      title: '弹幕设置',
      showBack: true,
      actions: [
        IconButtonData(
          glyph: KonekoGlyphs.reset,
          tooltip: '恢复默认',
          onPressed: () {
            notifier.reset();
            showKonekoBanner(context, '已恢复默认弹幕设置');
          },
        ),
      ],
      body: CustomScrollView(
        slivers: [
          const KonekoScrollStart(),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              4,
              16,
              32 + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _DanmakuPreviewCard(settings: settings),
                const ListHeader(title: '显示区域'),
                KonekoCard(
                  corner: 24,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 10,
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
                              backgroundColor:
                                  (settings.area - ratio).abs() < 0.02
                                  ? colorScheme.primary
                                  : SurfaceLevel.block.colorOf(colorScheme),
                              onPressed: () => notifier.update(
                                (s) => s.copyWith(area: ratio),
                              ),
                            ),
                        ],
                      ),
                      _SliderRow(
                        label: '屏幕占比',
                        valueText: '${(settings.area * 100).round()}%',
                        value: settings.area,
                        min: 0.125,
                        max: 1.0,
                        onChanged: (v) {
                          final snapped = (v * 8).round() / 8;
                          notifier.update((s) => s.copyWith(area: snapped));
                        },
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
                    spacing: 10,
                    children: [
                      _SliderRow(
                        label: '字体大小',
                        valueText: '${settings.fontSize.round()} px',
                        value: settings.fontSize,
                        min: 10,
                        max: 36,
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
                        onChanged: (v) => notifier.update(
                          (s) => s.copyWith(fontWeight: v.round()),
                        ),
                      ),
                      _SliderRow(
                        label: '描边粗细',
                        valueText: settings.strokeEnabled
                            ? settings.strokeWidth.toStringAsFixed(1)
                            : '已关闭',
                        value: settings.strokeWidth,
                        min: 0.2,
                        max: 3.0,
                        onChanged: settings.strokeEnabled
                            ? (v) => notifier.update(
                                (s) => s.copyWith(
                                  strokeWidth: double.parse(
                                    v.toStringAsFixed(1),
                                  ),
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
                      onPressed: () => notifier.update(
                        (s) => s.copyWith(showTop: !s.showTop),
                      ),
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
                        onChanged: (v) => notifier.update(
                          (s) => s.copyWith(strokeEnabled: v),
                        ),
                      ),
                      onPressed: () => notifier.update(
                        (s) => s.copyWith(strokeEnabled: !s.strokeEnabled),
                      ),
                    ),
                    DecorationListItem(
                      title: const Text('彩色弹幕'),
                      trailing: Switch(
                        value: settings.colorful,
                        onChanged: (v) =>
                            notifier.update((s) => s.copyWith(colorful: v)),
                      ),
                      onPressed: () => notifier.update(
                        (s) => s.copyWith(colorful: !s.colorful),
                      ),
                    ),
                    DecorationListItem(
                      title: const Text('海量弹幕模式'),
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
                  title: '弹幕来源过滤',
                  caption: '弹弹Play 聚合接口自动拉取多站弹幕，可按需开关',
                ),
                KonekoGroup(
                  items: [
                    DecorationListItem(
                      title: const Text('BiliBili（B站）'),
                      trailing: Switch(
                        value: settings.sourceBilibili,
                        onChanged: (v) => notifier.update(
                          (s) => s.copyWith(sourceBilibili: v),
                        ),
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
                      title: const Text('弹弹Play 及其他'),
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
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _DanmakuPreviewCard extends StatelessWidget {
  const _DanmakuPreviewCard({required this.settings});

  final DanmakuSettings settings;

  FontWeight get _fontWeight =>
      FontWeight.values[(settings.fontWeight - 1).clamp(0, 8).toInt()];

  Widget _sampleText(String text, Color color) {
    final fillColor = (settings.colorful ? color : Colors.white).withValues(
      alpha: settings.opacity.clamp(0.1, 1.0),
    );
    final baseStyle = TextStyle(
      fontSize: settings.fontSize.clamp(10.0, 28.0),
      fontWeight: _fontWeight,
      height: settings.lineHeight.clamp(0.9, 1.8),
    );
    if (!settings.strokeEnabled) {
      return Text(text, maxLines: 1, style: baseStyle.copyWith(color: fillColor));
    }
    return Stack(
      children: [
        Text(
          text,
          maxLines: 1,
          style: baseStyle.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = settings.strokeWidth * 1.6
              ..color = Colors.black.withValues(
                alpha: (settings.opacity * 0.85).clamp(0.1, 0.9),
              ),
          ),
        ),
        Text(text, maxLines: 1, style: baseStyle.copyWith(color: fillColor)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return KonekoCard(
      corner: 24,
      padding: EdgeInsets.zero,
      clip: true,
      child: AspectRatio(
        aspectRatio: 16 / 8,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1D2233), Color(0xFF10131D)],
                ),
              ),
            ),
            // Visual area ratio overlay showing active danmaku region
            Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                widthFactor: 1.0,
                heightFactor: settings.area.clamp(0.125, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.14),
                    border: Border(
                      bottom: BorderSide(
                        color: colorScheme.primary.withValues(alpha: 0.55),
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (settings.showTop)
                    Center(
                      child: _sampleText('前方高能反应！', const Color(0xFFFFD54F)),
                    ),
                  if (settings.showScroll) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _sampleText(
                        '这段作画简直神回 23333',
                        Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _sampleText(
                        '爷青回，BGM 响起来了',
                        const Color(0xFF80DEEA),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (settings.showBottom)
                    Center(
                      child: _sampleText('感谢字幕组辛苦翻译', const Color(0xFFFFAB91)),
                    ),
                ],
              ),
            ),
            Positioned(
              right: 10,
              bottom: 8,
              child: KonekoChip(
                label: '显示区域 ${(settings.area * 100).round()}%',
                height: 22,
                fontSize: 10.5,
                backgroundColor: Colors.black.withValues(alpha: 0.52),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
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
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
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
          onChanged: onChanged,
        ),
      ],
    );
  }
}
