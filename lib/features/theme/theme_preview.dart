import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/providers.dart';
import 'package:prism_ui/prism_ui.dart';

class PreviewChoice<T> {
  const PreviewChoice({
    required this.value,
    required this.label,
    required this.pictogram,
  });

  final T value;
  final String label;
  final Widget pictogram;
}

/// Ported 1:1 from FlClash's [PreviewChoiceGroup].
class PreviewChoiceGroup<T> extends StatelessWidget {
  const PreviewChoiceGroup({
    super.key,
    required this.info,
    required this.choices,
    required this.value,
    required this.onChanged,
  });

  final Info info;
  final List<PreviewChoice<T>> choices;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoHeader(info: info),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: generateGroup([
            for (final choice in choices)
              DecorationListItem(
                leading: ExcludeSemantics(child: choice.pictogram),
                title: Text(choice.label),
                isSelected: choice.value == value,
                trailing: choice.value == value ? const SelectionCheck() : null,
                onPressed: () => onChanged(choice.value),
              ),
          ]),
        ),
      ],
    );
  }
}

class MiniScreenThumb extends StatelessWidget {
  const MiniScreenThumb({super.key, required this.screen});

  static const Size _screenSize = Size(96, 128);
  static const double _shownHeight = 66;
  static const double _height = 30;

  final Widget screen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      width: _height * _screenSize.width / _shownHeight,
      child: ClipRSuperellipse(
        borderRadius: AppRadius.sm,
        child: FittedBox(
          child: SizedBox(
            width: _screenSize.width,
            height: _shownHeight,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.bottomCenter,
                minHeight: _screenSize.height,
                maxHeight: _screenSize.height,
                child: screen,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorSchemeTween extends Tween<ColorScheme> {
  _ColorSchemeTween({super.end});

  @override
  ColorScheme lerp(double t) => ColorScheme.lerp(begin!, end!, t);
}

/// Interactive live mini-phone preview of Koneko's theme settings (FlClash style).
class ThemeLivePreview extends ConsumerStatefulWidget {
  const ThemeLivePreview({super.key});

  @override
  ConsumerState<ThemeLivePreview> createState() => _ThemeLivePreviewState();
}

class _ThemeLivePreviewState extends ConsumerState<ThemeLivePreview>
    with SingleTickerProviderStateMixin {
  static const double _phoneWidth = 168;
  static const _duration = Duration(milliseconds: 300);

  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final CurvedAnimation _slideCurve = CurvedAnimation(
    parent: _slide,
    curve: Curves.easeOut,
  );
  int _selected = 0;
  int? _previous;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      themeSettingsProvider.select((s) => s.tabAnimation),
      (_, _) => _select((_selected + 1) % MiniScreen.destinationCount),
    );
  }

  Future<void> _select(int index) async {
    if (index == _selected) return;
    final anim = ref.read(themeSettingsProvider).tabAnimation;
    final fade = anim == TabAnimationMode.fade;
    _slide.duration = fade
        ? const Duration(milliseconds: 220)
        : const Duration(milliseconds: 300);
    _slideCurve.curve = fade ? Curves.easeOutCubic : Curves.easeOut;
    setState(() {
      _previous = _selected;
      _selected = index;
    });
    await _slide.forward(from: 0).orCancel.catchError((_) {});
    if (mounted && _selected == index) {
      setState(() => _previous = null);
    }
  }

  @override
  void dispose() {
    _slideCurve.dispose();
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(themeSettingsProvider);
    final brightness = switch (settings.themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    final scheme = buildKonekoColorScheme(
      brightness: brightness,
      primaryColor: settings.primaryColor,
      colorStyle: settings.colorStyle,
      pureBlack: settings.pureBlack,
    );
    final liquidGlass = settings.liquidGlass != LiquidGlassMode.none;
    final corner = AppCorner.fit(_phoneWidth);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 22),
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(context.colorScheme),
        shape: AppShape.xxl,
      ),
      child: SizedBox(
        width: _phoneWidth,
        child: AspectRatio(
          aspectRatio: 9 / 17,
          child: ClipRSuperellipse(
            borderRadius: AppRadius.all(corner),
            child: TweenAnimationBuilder<ColorScheme>(
              tween: _ColorSchemeTween(end: scheme),
              duration: _duration,
              builder: (_, animatedScheme, _) => AnimatedSwitcher(
                duration: _duration,
                child: AnimatedBuilder(
                  key: ValueKey((settings.floatingNavigationBar, liquidGlass)),
                  animation: _slideCurve,
                  builder: (_, _) => MiniScreen(
                    colorScheme: animatedScheme,
                    floatingBar: settings.floatingNavigationBar,
                    liquidGlass: liquidGlass,
                    selected: _selected,
                    previous: _previous,
                    progress: _previous == null ? 1 : _slideCurve.value,
                    tabAnimation: settings.tabAnimation,
                    onSelect: _select,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MiniScreen extends StatelessWidget {
  const MiniScreen({
    super.key,
    required this.colorScheme,
    required this.floatingBar,
    this.liquidGlass = false,
    this.selected = 0,
    this.previous,
    this.progress = 1,
    this.tabAnimation = TabAnimationMode.slide,
    this.onSelect,
  });

  static const int destinationCount = 4;

  final ColorScheme colorScheme;
  final bool floatingBar;
  final bool liquidGlass;
  final int selected;
  final int? previous;
  final double progress;
  final TabAnimationMode tabAnimation;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final sketch = SizedBox.expand(
      child: CustomPaint(
        painter: _MiniScreenPainter(
          colorScheme: colorScheme,
          floatingBar: floatingBar,
          liquidGlass: liquidGlass,
          selected: selected,
          previous: previous,
          progress: progress,
          tabAnimation: tabAnimation,
        ),
      ),
    );
    final onSelect = this.onSelect;
    if (onSelect == null) return sketch;
    return LayoutBuilder(
      builder: (_, constraints) {
        final g = _MiniGeometry(constraints.biggest, floatingBar: floatingBar);
        return Stack(
          children: [
            sketch,
            Positioned.fromRect(
              rect: g.bar,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < destinationCount; i++)
                    Expanded(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onSelect(i),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class MiniSplitScreen extends StatelessWidget {
  const MiniSplitScreen({super.key, required this.light, required this.dark});

  final Widget light;
  final Widget dark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        light,
        ClipPath(clipper: _DiagonalClipper(), child: dark),
      ],
    );
  }
}

class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * 0.7, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * 0.3, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_DiagonalClipper oldClipper) => false;
}

class _MiniGeometry {
  _MiniGeometry(this.size, {required bool floatingBar})
    : unit = size.width / 20 {
    margin = unit * 1.5;
    final barHeight = floatingBar ? unit * 3.2 : unit * 3.6;
    pageBottom = floatingBar ? 0 : barHeight;
    bar = floatingBar
        ? Rect.fromLTWH(
            margin,
            size.height - margin - barHeight,
            size.width - margin * 2,
            barHeight,
          )
        : Rect.fromLTWH(0, size.height - barHeight, size.width, barHeight);
  }

  final Size size;
  final double unit;
  late final double margin;
  late final double pageBottom;
  late final Rect bar;
}

class _MiniScreenPainter extends CustomPainter {
  const _MiniScreenPainter({
    required this.colorScheme,
    required this.floatingBar,
    required this.liquidGlass,
    required this.selected,
    required this.previous,
    required this.progress,
    required this.tabAnimation,
  });

  final ColorScheme colorScheme;
  final bool floatingBar;
  final bool liquidGlass;
  final int selected;
  final int? previous;
  final double progress;
  final TabAnimationMode tabAnimation;

  bool get _glass => floatingBar && liquidGlass;

  static void _fill(
    Canvas canvas,
    Rect rect,
    Color color,
    ShapeBorder shape, {
    List<BoxShadow>? shadows,
    MaskFilter? blur,
  }) {
    if (blur != null) {
      shape.paintInterior(
        canvas,
        rect,
        Paint()
          ..color = color
          ..maskFilter = blur,
      );
      return;
    }
    ShapeDecoration(color: color, shape: shape, shadows: shadows)
        .createBoxPainter(() {})
        .paint(canvas, rect.topLeft, ImageConfiguration(size: rect.size));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _MiniGeometry(size, floatingBar: floatingBar);
    _paintPages(canvas, geometry);
    final unit = geometry.unit;
    final dock = SurfaceLevel.floatingOf(colorScheme).colorOf(colorScheme);
    final shadow = BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.12),
      blurRadius: unit,
      offset: Offset(0, unit * 0.3),
    );
    if (_glass) {
      final path = AppShape.full.getOuterPath(geometry.bar);
      final style = LiquidGlassStyle.pill(colorScheme);
      canvas
        ..save()
        ..clipPath(path);
      _paintPages(
        canvas,
        geometry,
        blur: MaskFilter.blur(BlurStyle.normal, unit * 0.4),
      );
      canvas
        ..drawPath(path, Paint()..color = style.tint)
        ..restore();
    } else if (floatingBar) {
      _fill(canvas, geometry.bar, dock, AppShape.full, shadows: [shadow]);
    } else {
      canvas.drawRect(geometry.bar, Paint()..color = dock);
    }
    _paintDestinations(canvas, geometry.bar, unit);
  }

  void _paintPages(Canvas canvas, _MiniGeometry geometry, {MaskFilter? blur}) {
    final size = geometry.size;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = SurfaceLevel.page.colorOf(colorScheme),
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size, doAntiAlias: false);
    final prev = previous;
    if (prev == null) {
      _paintPage(canvas, geometry, selected, 0, blur: blur);
    } else if (tabAnimation == TabAnimationMode.fade) {
      _paintPage(canvas, geometry, prev, 0, opacity: 1 - progress, blur: blur);
      _paintPage(canvas, geometry, selected, 0, opacity: progress, blur: blur);
    } else {
      final dir = prev > selected ? -1 : 1;
      _paintPage(canvas, geometry, prev, -dir * size.width * progress, blur: blur);
      _paintPage(
        canvas,
        geometry,
        selected,
        dir * size.width * (1 - progress),
        blur: blur,
      );
    }
    canvas.restore();
  }

  void _paintPage(
    Canvas canvas,
    _MiniGeometry g,
    int index,
    double offset, {
    double opacity = 1,
    MaskFilter? blur,
  }) {
    final alpha = (opacity * 255).round().clamp(0, 255);
    if (alpha == 0) return;
    final u = g.unit;
    final m = g.margin;
    final content = Rect.fromLTRB(
      offset + m,
      m,
      offset + g.size.width - m,
      g.size.height - g.pageBottom,
    );
    if (alpha < 255) {
      canvas.saveLayer(null, Paint()..color = Color.fromARGB(alpha, 0, 0, 0));
    } else {
      canvas.save();
    }
    canvas.clipRect(content, doAntiAlias: false);
    final card = SurfaceLevel.card.colorOf(colorScheme);
    final block = SurfaceLevel.block.colorOf(colorScheme);
    final text = colorScheme.onSurface.withValues(alpha: 0.72);
    final line = colorScheme.onSurfaceVariant.withValues(alpha: 0.38);
    Rect r(double x, double y, double w, double h) => Rect.fromLTWH(
      content.left + x * u,
      content.top + y * u,
      w * u,
      h * u,
    );
    final w = content.width / u;
    _fill(canvas, r(0, 0.5, 6.5, 1.1), text, AppShape.full, blur: blur);
    _fill(canvas, r(w - 2, 0.1, 2, 2), card, AppShape.circle, blur: blur);
    if (index % 4 == 0) {
      // Home: top deck + 2-col unified anime cards
      _fill(canvas, r(0, 2.8, w, 5.2), card, AppShape.md, blur: blur);
      _fill(canvas, r(w - 3.6, 4.1, 2.6, 2.6), colorScheme.primary, AppShape.circle, blur: blur);
      _fill(canvas, r(1.0, 3.8, 5.5, 0.9), text, AppShape.full, blur: blur);
      _fill(canvas, r(1.0, 5.2, 4.0, 0.7), line, AppShape.full, blur: blur);
      final cw = (w - 0.8) / 2;
      for (var row = 0; row < 2; row++) {
        for (var col = 0; col < 2; col++) {
          final x = col * (cw + 0.8);
          final y = 9.0 + row * 9.6;
          _fill(canvas, r(x, y, cw, 8.8), card, AppShape.md, blur: blur);
          _fill(canvas, r(x, y, cw, 5.8), block, AppShape.md, blur: blur);
          _fill(canvas, r(x + 0.7, y + 6.5, cw - 1.6, 0.8), text, AppShape.full, blur: blur);
        }
      }
    } else {
      // Library / Schedule / My cards
      for (var i = 0; i < 4; i++) {
        final y = 2.8 + i * 6.4;
        _fill(canvas, r(0, y, w, 5.6), card, AppShape.md, blur: blur);
        _fill(canvas, r(0.8, y + 0.8, 2.8, 4.0), block, AppShape.sm, blur: blur);
        _fill(canvas, r(4.4, y + 1.1, 7.2, 0.9), text, AppShape.full, blur: blur);
        _fill(canvas, r(4.4, y + 2.6, 5.0, 0.7), line, AppShape.full, blur: blur);
        _fill(
          canvas,
          r(4.4, y + 4.1, w - 5.4, 0.55),
          i == 0 ? colorScheme.primary : block,
          AppShape.full,
          blur: blur,
        );
      }
    }
    canvas.restore();
  }

  void _paintDestinations(Canvas canvas, Rect bar, double unit) {
    final cell = bar.width / MiniScreen.destinationCount;
    final dark = colorScheme.brightness == Brightness.dark;
    final indicator = _glass
        ? colorScheme.onSurface.withValues(alpha: dark ? 0.14 : 0.08)
        : SurfaceLevel.floatingOf(colorScheme).next.colorOf(colorScheme);
    for (var i = 0; i < MiniScreen.destinationCount; i++) {
      final center = Offset(bar.left + cell * i + cell / 2, bar.center.dy);
      final iconCenter = center.translate(0, -unit * 0.4);
      final isSelected = i == selected;
      if (isSelected) {
        _fill(
          canvas,
          floatingBar
              ? Rect.fromCenter(
                  center: center,
                  width: cell - unit * 0.5,
                  height: bar.height - unit * 0.5,
                )
              : Rect.fromCenter(
                  center: iconCenter,
                  width: unit * 2.8,
                  height: unit * 1.5,
                ),
          indicator,
          AppShape.full,
        );
      }
      final ink = isSelected
          ? colorScheme.primary
          : colorScheme.onSurfaceVariant;
      _fill(
        canvas,
        Rect.fromCircle(center: iconCenter, radius: unit * 0.45),
        ink,
        AppShape.circle,
      );
      _fill(
        canvas,
        Rect.fromCenter(
          center: center.translate(0, unit * 0.8),
          width: unit * 1.7,
          height: unit * 0.35,
        ),
        isSelected ? ink : ink.withValues(alpha: 0.6),
        AppShape.full,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniScreenPainter oldDelegate) =>
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.floatingBar != floatingBar ||
      oldDelegate.liquidGlass != liquidGlass ||
      oldDelegate.selected != selected ||
      oldDelegate.previous != previous ||
      oldDelegate.progress != progress ||
      oldDelegate.tabAnimation != tabAnimation;
}
