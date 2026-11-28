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
      body: ArrivalCacheExtentBuilder(
        builder: (context, cacheExtent) => CustomScrollView(
          scrollCacheExtent: cacheExtent,
          slivers: [
            const KonekoScrollStart(),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                4,
                16,
                32 + MediaQuery.paddingOf(context).bottom,
              ),
              sliver: SliverList.builder(
                itemCount: 5,
                itemBuilder: (context, index) => switch (index) {
                  0 => const _DanmakuPreviewSection(),
                  1 => const _DanmakuAreaSection(),
                  2 => const _DanmakuStyleSection(),
                  3 => const _DanmakuDisplaySection(),
                  _ => const _DanmakuSourceSection(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DanmakuPreviewSection extends ConsumerWidget {
  const _DanmakuPreviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(danmakuSettingsProvider);
    return RepaintBoundary(child: _DanmakuPreviewCard(settings: settings));
  }
}

class _DanmakuAreaSection extends ConsumerWidget {
  const _DanmakuAreaSection();

  static const _weightOptions = <int>[2, 3, 4, 5, 6, 7];
  static const _speedOptions = <double>[5, 7, 9, 11, 14];

  static String _areaLabel(double ratio) {
    for (final (preset, label) in DanmakuSettingsPage._areaPresets) {
      if ((ratio - preset).abs() < 0.02) return label;
    }
    return '${(ratio * 100).round()}%';
  }

  static String _speedLabel(double seconds) => switch (seconds.round()) {
    <= 5 => '极快 (5 秒)',
    <= 7 => '较快 (7 秒)',
    <= 9 => '标准 (9 秒)',
    <= 11 => '舒适 (11 秒)',
    _ => '慢速 (${seconds.round()} 秒)',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (area, fontWeight, duration) = ref.watch(
      danmakuSettingsProvider.select(
        (s) => (s.area, s.fontWeight, s.duration),
      ),
    );
    final notifier = ref.read(danmakuSettingsProvider.notifier);
    final matchedArea = DanmakuSettingsPage._areaPresets
        .map((e) => e.$1)
        .firstWhere((v) => (area - v).abs() < 0.02, orElse: () => 0.50);
    final matchedWeight = _weightOptions.contains(fontWeight)
        ? fontWeight
        : fontWeight.clamp(2, 7);
    final matchedSpeed = _speedOptions.reduce(
      (a, b) => (duration - a).abs() <= (duration - b).abs() ? a : b,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ListHeader(title: '常用预设'),
        KonekoGroup(
          items: [
            KonekoOptionsItem<double>(
              title: const Text('显示区域'),
              options: [for (final (ratio, _) in DanmakuSettingsPage._areaPresets) ratio],
              value: matchedArea,
              textBuilder: _areaLabel,
              onChanged: (v) => notifier.update((s) => s.copyWith(area: v)),
            ),
            KonekoOptionsItem<int>(
              title: const Text('弹幕字重'),
              options: _weightOptions,
              value: matchedWeight,
              textBuilder: DanmakuSettingsPage._weightLabel,
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(fontWeight: v)),
            ),
            KonekoOptionsItem<double>(
              title: const Text('滚动速度'),
              options: _speedOptions,
              value: matchedSpeed,
              textBuilder: _speedLabel,
              onChanged: (v) => notifier.update((s) => s.copyWith(duration: v)),
            ),
          ],
        ),
      ],
    );
  }
}

class _DanmakuStyleSection extends ConsumerWidget {
  const _DanmakuStyleSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (
      area,
      fontSize,
      strokeEnabled,
      strokeWidth,
      opacity,
      lineHeight,
    ) = ref.watch(
      danmakuSettingsProvider.select(
        (s) => (
          s.area,
          s.fontSize,
          s.strokeEnabled,
          s.strokeWidth,
          s.opacity,
          s.lineHeight,
        ),
      ),
    );
    final notifier = ref.read(danmakuSettingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ListHeader(title: '精细微调'),
        KonekoCard(
          corner: 24,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              _SliderRow(
                label: '区域占比',
                valueText: '${(area * 100).round()}%',
                value: area,
                min: 0.125,
                max: 1.0,
                onChanged: (v) {
                  final snapped = (v * 8).round() / 8;
                  notifier.update((s) => s.copyWith(area: snapped));
                },
              ),
              _SliderRow(
                label: '字号',
                valueText: '${fontSize.round()} px',
                value: fontSize,
                min: 10,
                max: 36,
                onChanged: (v) => notifier.update(
                  (s) => s.copyWith(fontSize: v.roundToDouble()),
                ),
              ),
              _SliderRow(
                label: '描边',
                valueText: strokeEnabled ? strokeWidth.toStringAsFixed(1) : '关',
                value: strokeWidth,
                min: 0.2,
                max: 3.0,
                onChanged: strokeEnabled
                    ? (v) => notifier.update(
                        (s) => s.copyWith(
                          strokeWidth: double.parse(v.toStringAsFixed(1)),
                        ),
                      )
                    : null,
              ),
              _SliderRow(
                label: '透明度',
                valueText: '${(opacity * 100).round()}%',
                value: opacity,
                min: 0.1,
                max: 1.0,
                onChanged: (v) => notifier.update(
                  (s) =>
                      s.copyWith(opacity: double.parse(v.toStringAsFixed(2))),
                ),
              ),
              _SliderRow(
                label: '行距',
                valueText: lineHeight.toStringAsFixed(1),
                value: lineHeight,
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
      ],
    );
  }
}

class _DanmakuDisplaySection extends ConsumerWidget {
  const _DanmakuDisplaySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (
      showScroll,
      showTop,
      showBottom,
      strokeEnabled,
      colorful,
      massiveMode,
    ) = ref.watch(
      danmakuSettingsProvider.select(
        (s) => (
          s.showScroll,
          s.showTop,
          s.showBottom,
          s.strokeEnabled,
          s.colorful,
          s.massiveMode,
        ),
      ),
    );
    final notifier = ref.read(danmakuSettingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ListHeader(title: '显示'),
        KonekoGroup(
          items: [
            DecorationListItem(
              title: const Text('滚动弹幕'),
              trailing: Switch(
                value: showScroll,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(showScroll: v)),
              ),
              onPressed: () =>
                  notifier.update((s) => s.copyWith(showScroll: !s.showScroll)),
            ),
            DecorationListItem(
              title: const Text('顶部弹幕'),
              trailing: Switch(
                value: showTop,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(showTop: v)),
              ),
              onPressed: () =>
                  notifier.update((s) => s.copyWith(showTop: !s.showTop)),
            ),
            DecorationListItem(
              title: const Text('底部弹幕'),
              trailing: Switch(
                value: showBottom,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(showBottom: v)),
              ),
              onPressed: () =>
                  notifier.update((s) => s.copyWith(showBottom: !s.showBottom)),
            ),
            DecorationListItem(
              title: const Text('描边'),
              trailing: Switch(
                value: strokeEnabled,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(strokeEnabled: v)),
              ),
              onPressed: () => notifier.update(
                (s) => s.copyWith(strokeEnabled: !s.strokeEnabled),
              ),
            ),
            DecorationListItem(
              title: const Text('彩色弹幕'),
              trailing: Switch(
                value: colorful,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(colorful: v)),
              ),
              onPressed: () =>
                  notifier.update((s) => s.copyWith(colorful: !s.colorful)),
            ),
            DecorationListItem(
              title: const Text('海量模式'),
              trailing: Switch(
                value: massiveMode,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(massiveMode: v)),
              ),
              onPressed: () => notifier.update(
                (s) => s.copyWith(massiveMode: !s.massiveMode),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DanmakuSourceSection extends ConsumerWidget {
  const _DanmakuSourceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (sourceBilibili, sourceGamer, sourceDandan) = ref.watch(
      danmakuSettingsProvider.select(
        (s) => (s.sourceBilibili, s.sourceGamer, s.sourceDandan),
      ),
    );
    final notifier = ref.read(danmakuSettingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ListHeader(title: '来源'),
        KonekoGroup(
          items: [
            DecorationListItem(
              title: const Text('B站'),
              trailing: Switch(
                value: sourceBilibili,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(sourceBilibili: v)),
              ),
              onPressed: () => notifier.update(
                (s) => s.copyWith(sourceBilibili: !s.sourceBilibili),
              ),
            ),
            DecorationListItem(
              title: const Text('巴哈姆特'),
              trailing: Switch(
                value: sourceGamer,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(sourceGamer: v)),
              ),
              onPressed: () => notifier.update(
                (s) => s.copyWith(sourceGamer: !s.sourceGamer),
              ),
            ),
            DecorationListItem(
              title: const Text('弹弹Play'),
              trailing: Switch(
                value: sourceDandan,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(sourceDandan: v)),
              ),
              onPressed: () => notifier.update(
                (s) => s.copyWith(sourceDandan: !s.sourceDandan),
              ),
            ),
          ],
        ),
      ],
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
