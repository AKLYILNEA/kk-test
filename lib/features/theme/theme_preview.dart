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

/// 1:1 FlClash grouped choice section with compact mini-screen pictograms.
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

/// The foot of a [MiniScreen], where the options differ, drawn at the size of
/// an icon (1:1 FlClash [MiniScreenThumb], zero extra shadows).
class MiniScreenThumb extends StatelessWidget {
  const MiniScreenThumb({super.key, required this.screen});

  static const Size _screenSize = Size(96, 128);
  static const double _shownHeight = 66;
  static const double _height = 30;

  final Widget screen;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
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
      ),
    );
  }
}

class _ColorSchemeTween extends Tween<ColorScheme> {
  _ColorSchemeTween({super.end});

  @override
  ColorScheme lerp(double t) => ColorScheme.lerp(begin!, end!, t);
}

/// 1:1 FlClash interactive mini-phone preview: flat raised container, clean
/// shadowless superellipse frame, clickable bottom destinations (推荐 / 时间表
/// / 追番 / 我的) to preview theme mode, pure black, palette, dock style,
/// tab animation, and liquid glass in real time.
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
    final (
      themeMode,
      pureBlack,
      primaryColor,
      colorStyle,
      floatingBar,
      tabAnimation,
      liquidGlass,
    ) = ref.watch(
      themeSettingsProvider.select(
        (s) => (
          s.themeMode,
          s.pureBlack,
          s.primaryColor,
          s.colorStyle,
          s.floatingNavigationBar,
          s.tabAnimation,
          s.liquidGlass != LiquidGlassMode.none,
        ),
      ),
    );
    final brightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    final scheme = buildKonekoColorScheme(
      brightness: brightness,
      primaryColor: primaryColor,
      colorStyle: colorStyle,
      pureBlack: pureBlack,
    );
    final corner = AppCorner.fit(_phoneWidth);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 24),
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
            child: RepaintBoundary(
              child: TweenAnimationBuilder<ColorScheme>(
                tween: _ColorSchemeTween(end: scheme),
                duration: _duration,
                builder: (_, animatedScheme, _) => AnimatedSwitcher(
                  duration: _duration,
                  child: AnimatedBuilder(
                    key: ValueKey((floatingBar, liquidGlass)),
                    animation: _slideCurve,
                    builder: (_, _) => MiniScreen(
                      colorScheme: animatedScheme,
                      floatingBar: floatingBar,
                      liquidGlass: liquidGlass,
                      selected: _selected,
                      previous: _previous,
                      progress: _previous == null ? 1 : _slideCurve.value,
                      tabAnimation: tabAnimation,
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

enum _MiniPage { home, schedule, library, my }

/// A phone-shaped architectural sketch of Koneko's home destinations drawn in
/// [colorScheme], following FlClash's clean shadowless geometric sketch style.
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
        final geometry = _MiniGeometry(
          constraints.biggest,
          floatingBar: floatingBar,
        );
        return Stack(
          children: [
            sketch,
            Positioned.fromRect(
              rect: geometry.bar,
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

  static _MiniPage _pageOf(int index) =>
      _MiniPage.values[index % _MiniPage.values.length];

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
      _paintGlassBar(canvas, geometry, shadow);
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
    final previous = this.previous;
    if (previous == null) {
      _paintPage(canvas, geometry, selected, 0, blur: blur);
    } else if (tabAnimation == TabAnimationMode.fade) {
      _paintPage(
        canvas,
        geometry,
        previous,
        0,
        opacity: 1 - progress,
        blur: blur,
      );
      _paintPage(canvas, geometry, selected, 0, opacity: progress, blur: blur);
    } else {
      final direction = previous > selected ? -1 : 1;
      _paintPage(
        canvas,
        geometry,
        previous,
        -direction * size.width * progress,
        blur: blur,
      );
      _paintPage(
        canvas,
        geometry,
        selected,
        direction * size.width * (1 - progress),
        blur: blur,
      );
    }
    canvas.restore();
  }

  /// Authentic FlClash frosted glass dock: casts shadow strictly outside the
  /// pill, blurs the underlying page inside, overlays the glass tint, and
  /// strokes a diagonal specular rim.
  void _paintGlassBar(Canvas canvas, _MiniGeometry geometry, BoxShadow shadow) {
    final bar = geometry.bar;
    final unit = geometry.unit;
    final path = AppShape.full.getOuterPath(bar);
    final style = LiquidGlassStyle.pill(colorScheme);
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(bar.inflate(unit * 3))
          ..addPath(path, Offset.zero),
      );
    AppShape.full.paintInterior(
      canvas,
      bar.shift(shadow.offset),
      shadow.toPaint(),
    );
    canvas
      ..restore()
      ..save()
      ..clipPath(path);
    _paintPages(
      canvas,
      geometry,
      blur: MaskFilter.blur(BlurStyle.normal, unit * 0.4),
    );
    final rimWidth = unit * 0.15;
    canvas
      ..drawPath(path, Paint()..color = style.tint)
      ..drawPath(
        AppShape.full.getOuterPath(bar.deflate(rimWidth / 2)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rimWidth
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: style.rim),
              Colors.white.withValues(alpha: style.rim * 0.15),
              Colors.white.withValues(alpha: style.rim * 0.5),
            ],
          ).createShader(bar),
      )
      ..restore();
  }

  void _paintPage(
    Canvas canvas,
    _MiniGeometry geometry,
    int index,
    double offset, {
    double opacity = 1,
    MaskFilter? blur,
  }) {
    final alpha = (opacity * 255).round().clamp(0, 255);
    if (alpha == 0) return;
    final size = geometry.size;
    final margin = geometry.margin;
    final content = Rect.fromLTRB(
      offset + margin,
      margin,
      offset + size.width - margin,
      size.height - geometry.pageBottom,
    );
    if (alpha < 255) {
      canvas.saveLayer(null, Paint()..color = Color.fromARGB(alpha, 0, 0, 0));
    } else {
      canvas.save();
    }
    canvas.clipRect(content, doAntiAlias: false);
    _PageSketch(
      canvas,
      colorScheme,
      geometry.unit,
      content,
      blur: blur,
    ).paint(_pageOf(index));
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
      final icon = center.translate(0, -unit * 0.4);
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
                  center: icon,
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
        Rect.fromCircle(center: icon, radius: unit * 0.45),
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

/// Pure shadowless FlClash geometric page sketch laid out in 1/20th-width units.
class _PageSketch {
  _PageSketch(
    this.canvas,
    this.colorScheme,
    this.unit,
    this.content, {
    this.blur,
  }) : width = content.width / unit,
       card = SurfaceLevel.card.colorOf(colorScheme),
       inset = SurfaceLevel.inset.colorOf(colorScheme),
       text = colorScheme.onSurface.withValues(alpha: 0.72),
       line = colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
       faint = colorScheme.onSurfaceVariant.withValues(alpha: 0.16);

  static const double _gap = 0.65;

  final Canvas canvas;
  final ColorScheme colorScheme;
  final double unit;
  final Rect content;
  final MaskFilter? blur;
  final double width;
  final Color card;
  final Color inset;
  final Color text;
  final Color line;
  final Color faint;

  void paint(_MiniPage page) {
    switch (page) {
      case _MiniPage.home:
        _home(_header(actions: 1));
      case _MiniPage.schedule:
        _schedule(_header(actions: 1));
      case _MiniPage.library:
        _library(_header(actions: 2));
      case _MiniPage.my:
        _my(_header(actions: 0));
    }
  }

  Rect _rect(double x, double y, double w, double h) => Rect.fromLTWH(
    content.left + x * unit,
    content.top + y * unit,
    w * unit,
    h * unit,
  );

  ShapeBorder _shape(double extent) =>
      AppShape.all(AppCorner.fit(unit * extent));

  void _block(Rect rect, Color color, {double extent = 5}) {
    _MiniScreenPainter._fill(canvas, rect, color, _shape(extent), blur: blur);
  }

  void _pill(double x, double y, double w, double h, Color color) {
    _MiniScreenPainter._fill(
      canvas,
      _rect(x, y, w, h),
      color,
      AppShape.full,
      blur: blur,
    );
  }

  void _dot(double x, double y, double radius, Color color) {
    _MiniScreenPainter._fill(
      canvas,
      _rect(x - radius, y - radius, radius * 2, radius * 2),
      color,
      AppShape.circle,
      blur: blur,
    );
  }

  double _header({required int actions}) {
    _pill(0, 0.45, 6.2, 1.1, text);
    for (var i = 0; i < actions; i++) {
      final x = width - 1 - i * 2.4;
      _dot(x, 1, 1, card);
      _dot(x, 1, 0.3, line);
    }
    return 2.8;
  }

  void _home(double top) {
    var y = top;
    // Featured hero card with soft primary halo (1:1 FlClash dashboard hero feel)
    final hero = _rect(0, y, width, 6.6);
    final playX = width - 2.6;
    final playY = y + 3.3;
    _block(hero, card);
    canvas
      ..save()
      ..clipPath(_shape(5).getOuterPath(hero))
      ..drawCircle(
        _rect(playX, playY, 0, 0).topLeft,
        unit * 4.4,
        Paint()
          ..color = colorScheme.primary.withValues(alpha: 0.12)
          ..maskFilter = blur,
      )
      ..restore();
    _block(_rect(1.0, y + 0.9, 3.2, 4.8), inset, extent: 2.8);
    _pill(5.0, y + 1.2, 3.0, 0.65, colorScheme.primary.withValues(alpha: 0.24));
    _pill(5.0, y + 2.4, 5.4, 0.9, text);
    _pill(5.0, y + 3.8, 3.8, 0.65, line);
    _dot(playX, playY, 1.5, colorScheme.primary);
    _dot(playX, playY, 0.45, colorScheme.onPrimary);
    y += 6.6 + _gap;

    // Filter chip strip
    final chipW = (width - 1.5) / 4;
    for (var i = 0; i < 4; i++) {
      _pill(
        i * (chipW + 0.5),
        y + 0.1,
        chipW,
        1.45,
        i == 0 ? colorScheme.primary : card,
      );
    }
    y += 1.6 + _gap;

    // Clean 2-col anime poster grid (extends under dock so Liquid Glass shows through)
    final colW = (width - _gap) / 2;
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 2; col++) {
        final x = col * (colW + _gap);
        final cardRect = _rect(x, y, colW, 8.2);
        _block(cardRect, card, extent: 4.2);
        _block(
          _rect(x + 0.55, y + 0.55, colW - 1.1, 5.0),
          (row + col).isEven
              ? colorScheme.primary.withValues(alpha: 0.16)
              : inset,
          extent: 3.0,
        );
        _pill(x + 0.7, y + 6.1, colW - 2.2, 0.7, text);
        _pill(x + 0.7, y + 7.1, colW * 0.48, 0.5, faint);
      }
      y += 8.2 + _gap;
    }
  }

  void _schedule(double top) {
    var y = top;
    // Weekday segmented strip
    final segW = (width - 1.6) / 5;
    for (var i = 0; i < 5; i++) {
      _pill(
        i * (segW + 0.4),
        y,
        segW,
        1.5,
        i == 1 ? colorScheme.primary : card,
      );
    }
    y += 1.6 + _gap;

    // Dense schedule rows running cleanly under the dock (ideal for glass thumb)
    for (var i = 0; i < 8; i++) {
      _block(_rect(0, y, width, 3.0), card, extent: 3.6);
      _block(_rect(0.7, y + 0.5, 1.7, 2.0), inset, extent: 1.8);
      _pill(3.1, y + 0.75, 4.2 + (i % 3) * 1.1, 0.7, text);
      _pill(3.1, y + 1.8, 3.4, 0.5, faint);
      _pill(
        width - 3.6,
        y + 1.05,
        2.6,
        0.9,
        i == 0 ? colorScheme.primary.withValues(alpha: 0.2) : inset,
      );
      y += 3.0 + _gap;
    }
  }

  void _library(double top) {
    var y = top;
    final segW = (width - 1.2) / 3;
    for (var i = 0; i < 3; i++) {
      _pill(
        i * (segW + 0.6),
        y,
        segW,
        1.5,
        i == 0 ? colorScheme.primary : card,
      );
    }
    y += 1.6 + _gap;

    final colW = (width - _gap * 2) / 3;
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 3; col++) {
        final x = col * (colW + _gap);
        _block(_rect(x, y, colW, 6.4), card, extent: 3.4);
        _block(
          _rect(x + 0.4, y + 0.4, colW - 0.8, 4.1),
          (row * 3 + col) % 3 == 0
              ? colorScheme.primary.withValues(alpha: 0.18)
              : inset,
          extent: 2.2,
        );
        _dot(
          x + colW - 0.95,
          y + 0.95,
          0.35,
          col == 0 ? colorScheme.primary : line,
        );
        _pill(x + 0.45, y + 5.05, colW - 1.1, 0.6, line);
      }
      y += 6.4 + _gap;
    }
  }

  void _my(double top) {
    const rowHeight = 2.4;
    var y = top;
    // Profile header card
    _block(_rect(0, y, width, 4.0), card);
    _dot(2.0, y + 2.0, 1.1, colorScheme.primary.withValues(alpha: 0.22));
    _pill(3.8, y + 1.2, 4.6, 0.75, text);
    _pill(3.8, y + 2.3, 6.0, 0.55, faint);
    y += 4.0 + _gap * 1.6;

    // FlClash grouped settings sections with crisp hairline dividers
    for (final rows in [4, 5]) {
      _pill(0.8, y + 0.2, 2.2, 0.5, faint);
      y += 1.25;
      _block(_rect(0, y, width, rows * rowHeight), card);
      for (var i = 0; i < rows; i++) {
        final row = y + i * rowHeight;
        _dot(1.3, row + rowHeight / 2, 0.45, line);
        _pill(2.6, row + 0.85, 4 + (i * 3 + rows) % 4, 0.7, line);
        if (i < rows - 1) {
          canvas.drawRect(
            _rect(2.6, row + rowHeight - 0.03, width - 3.4, 0.06),
            Paint()
              ..color = faint
              ..maskFilter = blur,
          );
        }
      }
      y += rows * rowHeight + _gap * 2;
    }
  }
}
