import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
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

/// Elevated preview choice group matching Koneko's unified card shadow language.
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
          child: KonekoGroup(
            items: [
              for (final choice in choices)
                DecorationListItem(
                  leading: ExcludeSemantics(child: choice.pictogram),
                  title: Text(choice.label),
                  isSelected: choice.value == value,
                  trailing: choice.value == value
                      ? const SelectionCheck()
                      : null,
                  onPressed: () => onChanged(choice.value),
                ),
            ],
          ),
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

/// Interactive live mini-phone preview of Koneko's theme settings with distinct
/// layouts for all 4 destinations (推荐 / 时间表 / 追番 / 我的).
class ThemeLivePreview extends ConsumerStatefulWidget {
  const ThemeLivePreview({super.key});

  @override
  ConsumerState<ThemeLivePreview> createState() => _ThemeLivePreviewState();
}

class _ThemeLivePreviewState extends ConsumerState<ThemeLivePreview>
    with SingleTickerProviderStateMixin {
  static const double _phoneWidth = 172;
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
    final outerScheme = context.colorScheme;
    final brightness = switch (settings.themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    final scheme = buildKonekoColorScheme(
      brightness: brightness,
      primaryColor: settings.primaryColor,
      colorStyle: settings.colorStyle,
    );
    final liquidGlass = settings.liquidGlass != LiquidGlassMode.none;
    final corner = AppCorner.fit(_phoneWidth);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 22),
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: SurfaceLevel.card.colorOf(outerScheme),
        shape: AppShape.xxl,
        shadows: konekoCardShadows(outerScheme),
      ),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: SuperellipseBorder(
            borderRadius: AppRadius.all(corner),
            side: BorderSide(
              color: outerScheme.outlineVariant.withValues(alpha: 0.24),
              width: 1,
            ),
          ),
          shadows: [
            BoxShadow(
              color: outerScheme.shadow.withValues(alpha: 0.14),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
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
                    key: ValueKey(liquidGlass),
                    animation: _slideCurve,
                    builder: (_, _) => MiniScreen(
                      colorScheme: animatedScheme,
                      floatingBar: true,
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
    margin = unit * 1.4;
    final barHeight = floatingBar ? unit * 3.1 : unit * 3.5;
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
      color: colorScheme.shadow.withValues(alpha: 0.14),
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
    final dark = colorScheme.brightness == Brightness.dark;
    // Distinct slightly-contrasted page backdrop so mini cards stand out clearly
    final pageBg = dark
        ? Color.lerp(SurfaceLevel.page.colorOf(colorScheme), Colors.black, 0.25)!
        : SurfaceLevel.page.colorOf(colorScheme);
    canvas.drawRect(Offset.zero & size, Paint()..color = pageBg);
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
      _paintPage(
        canvas,
        geometry,
        prev,
        -dir * size.width * progress,
        blur: blur,
      );
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

    final dark = colorScheme.brightness == Brightness.dark;
    final card = SurfaceLevel.card.colorOf(colorScheme);
    final text = colorScheme.onSurface.withValues(alpha: 0.78);
    final line = colorScheme.onSurfaceVariant.withValues(alpha: 0.44);
    final cardShadows = blur != null
        ? null
        : [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: dark ? 0.32 : 0.10),
              blurRadius: u * 0.85,
              offset: Offset(0, u * 0.25),
            ),
          ];

    // Distinct tinted anime poster art tones so covers pop cleanly in light & dark mode
    final posters = <Color>[
      colorScheme.primary.withValues(alpha: dark ? 0.45 : 0.34),
      colorScheme.tertiary.withValues(alpha: dark ? 0.45 : 0.34),
      colorScheme.secondary.withValues(alpha: dark ? 0.48 : 0.36),
      Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.5)!
          .withValues(alpha: dark ? 0.45 : 0.34),
    ];

    Rect r(double x, double y, double w, double h) => Rect.fromLTWH(
      content.left + x * u,
      content.top + y * u,
      w * u,
      h * u,
    );
    final w = content.width / u;

    // Header title + right action circle
    _fill(canvas, r(0, 0.5, 5.4, 1.15), text, AppShape.full, blur: blur);
    _fill(
      canvas,
      r(w - 2.0, 0.1, 2.0, 2.0),
      card,
      AppShape.circle,
      shadows: cardShadows,
      blur: blur,
    );

    switch (index % 4) {
      case 0:
        // Page 0 · 推荐: Animeko featured showcase banner + tag strip + 2-col anime grid
        _fill(
          canvas,
          r(0, 2.7, w, 6.2),
          colorScheme.primary.withValues(alpha: dark ? 0.42 : 0.26),
          AppShape.md,
          shadows: cardShadows,
          blur: blur,
        );
        _fill(
          canvas,
          r(0.8, 3.4, 3.4, 4.8),
          colorScheme.primary.withValues(alpha: dark ? 0.72 : 0.55),
          AppShape.sm,
          blur: blur,
        );
        _fill(canvas, r(5.0, 3.8, 3.0, 0.8), colorScheme.primary, AppShape.full, blur: blur);
        _fill(canvas, r(5.0, 5.2, 8.6, 0.9), text, AppShape.full, blur: blur);
        _fill(canvas, r(5.0, 6.6, 6.0, 0.7), line, AppShape.full, blur: blur);
        // Carousel indicator dots
        _fill(canvas, r(w / 2 - 1.8, 9.3, 1.6, 0.45), colorScheme.primary, AppShape.full, blur: blur);
        _fill(canvas, r(w / 2 + 0.3, 9.3, 0.5, 0.45), line, AppShape.full, blur: blur);
        _fill(canvas, r(w / 2 + 1.2, 9.3, 0.5, 0.45), line, AppShape.full, blur: blur);
        // Tag pills
        for (var i = 0; i < 4; i++) {
          _fill(
            canvas,
            r(i * 4.2, 10.4, 3.5, 1.3),
            i == 0 ? colorScheme.primary : card,
            AppShape.full,
            shadows: i == 0 ? null : cardShadows,
            blur: blur,
          );
        }
        // 2-col elevated anime cards with distinct tinted covers
        final cw = (w - 0.9) / 2;
        for (var row = 0; row < 2; row++) {
          for (var col = 0; col < 2; col++) {
            final x = col * (cw + 0.9);
            final y = 12.5 + row * 9.8;
            final posterColor = posters[(row * 2 + col) % posters.length];
            _fill(
              canvas,
              r(x, y, cw, 9.0),
              card,
              AppShape.md,
              shadows: cardShadows,
              blur: blur,
            );
            _fill(canvas, r(x, y, cw, 6.1), posterColor, AppShape.md, blur: blur);
            _fill(canvas, r(x + 0.7, y + 6.8, cw - 1.6, 0.75), text, AppShape.full, blur: blur);
            _fill(canvas, r(x + 0.7, y + 7.9, cw * 0.55, 0.55), line, AppShape.full, blur: blur);
          }
        }
      case 1:
        // Page 1 · 时间表: Weekday selector strip + horizontal airing schedule cards
        for (var i = 0; i < 5; i++) {
          _fill(
            canvas,
            r(i * 3.45, 2.7, 2.9, 1.45),
            i == 1 ? colorScheme.primary : card,
            AppShape.full,
            shadows: i == 1 ? null : cardShadows,
            blur: blur,
          );
        }
        for (var i = 0; i < 4; i++) {
          final y = 5.0 + i * 5.8;
          _fill(
            canvas,
            r(0, y, w, 5.0),
            card,
            AppShape.md,
            shadows: cardShadows,
            blur: blur,
          );
          _fill(
            canvas,
            r(0.7, y + 0.7, 2.7, 3.6),
            posters[i % posters.length],
            AppShape.sm,
            blur: blur,
          );
          _fill(canvas, r(4.1, y + 1.0, 7.6, 0.85), text, AppShape.full, blur: blur);
          _fill(canvas, r(4.1, y + 2.35, 5.2, 0.65), line, AppShape.full, blur: blur);
          _fill(
            canvas,
            r(w - 3.3, y + 3.1, 2.5, 1.1),
            colorScheme.primary.withValues(alpha: 0.22),
            AppShape.full,
            blur: blur,
          );
        }
      case 2:
        // Page 2 · 追番: Status filter chips + 3-col compact poster grid with top-right status icons
        for (var i = 0; i < 4; i++) {
          _fill(
            canvas,
            r(i * 4.2, 2.7, 3.6, 1.35),
            i == 0 ? colorScheme.primary : card,
            AppShape.full,
            shadows: i == 0 ? null : cardShadows,
            blur: blur,
          );
        }
        final cw3 = (w - 1.4) / 3;
        final statusColors = [
          colorScheme.primary,
          const Color(0xFFE07A5F),
          const Color(0xFF2E9E6B),
        ];
        for (var row = 0; row < 3; row++) {
          for (var col = 0; col < 3; col++) {
            final x = col * (cw3 + 0.7);
            final y = 4.9 + row * 8.1;
            _fill(
              canvas,
              r(x, y, cw3, 7.3),
              card,
              AppShape.sm,
              shadows: cardShadows,
              blur: blur,
            );
            _fill(
              canvas,
              r(x, y, cw3, 5.0),
              posters[(row * 3 + col) % posters.length],
              AppShape.sm,
              blur: blur,
            );
            // Top-right circular status icon dot
            _fill(
              canvas,
              r(x + cw3 - 1.35, y + 0.4, 0.95, 0.95),
              statusColors[(row + col) % statusColors.length],
              AppShape.circle,
              blur: blur,
            );
            _fill(
              canvas,
              r(x + 0.5, y + 5.6, cw3 - 1.0, 0.65),
              text,
              AppShape.full,
              blur: blur,
            );
          }
        }
      default:
        // Page 3 · 我的: Bangumi profile card + grouped settings rows + About card
        _fill(
          canvas,
          r(0, 2.7, w, 4.8),
          card,
          AppShape.md,
          shadows: cardShadows,
          blur: blur,
        );
        _fill(
          canvas,
          r(1.0, 3.7, 2.8, 2.8),
          const Color(0xFFF09199).withValues(alpha: 0.45),
          AppShape.circle,
          blur: blur,
        );
        _fill(canvas, r(4.6, 4.0, 5.4, 0.9), text, AppShape.full, blur: blur);
        _fill(canvas, r(4.6, 5.4, 7.2, 0.65), line, AppShape.full, blur: blur);
        // Grouped settings list card
        _fill(
          canvas,
          r(0, 8.6, w, 13.6),
          card,
          AppShape.md,
          shadows: cardShadows,
          blur: blur,
        );
        for (var i = 0; i < 5; i++) {
          final rowY = 9.4 + i * 2.55;
          _fill(
            canvas,
            r(1.0, rowY, 1.4, 1.4),
            colorScheme.primary.withValues(alpha: 0.72),
            AppShape.sm,
            blur: blur,
          );
          _fill(
            canvas,
            r(3.2, rowY + 0.3, 6.4 - (i % 2) * 1.4, 0.8),
            text,
            AppShape.full,
            blur: blur,
          );
          _fill(
            canvas,
            r(w - 1.6, rowY + 0.35, 0.6, 0.6),
            line,
            AppShape.circle,
            blur: blur,
          );
        }
        // Bottom About mini card
        _fill(
          canvas,
          r(0, 23.2, w, 3.2),
          card,
          AppShape.md,
          shadows: cardShadows,
          blur: blur,
        );
        _fill(canvas, r(1.0, 24.1, 1.4, 1.4), colorScheme.primary, AppShape.circle, blur: blur);
        _fill(canvas, r(3.2, 24.4, 5.0, 0.8), text, AppShape.full, blur: blur);
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
