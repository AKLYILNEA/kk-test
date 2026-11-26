import 'package:flutter/foundation.dart' show clampDouble, listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/hct/hct.dart';
import 'package:prism_ui/prism_ui.dart';

const _trackHeight = 20.0;
const _thumbRadius = 14.0;
const _thumbRingWidth = 3.0;
const _padCorner = AppCorner.sm;

enum _PaletteMode { grid, spectrum, sliders }

/// Ported 1:1 from FlClash's iOS-style HCT Color Palette (Grid / Spectrum / Sliders).
class Palette extends StatefulWidget {
  const Palette({super.key, required this.controller});

  final ValueNotifier<Color> controller;

  @override
  State<Palette> createState() => _PaletteState();
}

class _PaletteState extends State<Palette> {
  var _mode = _PaletteMode.grid;
  late HSVColor _hsv = HSVColor.fromColor(widget.controller.value);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncHsv);
  }

  @override
  void didUpdateWidget(Palette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncHsv);
      widget.controller.addListener(_syncHsv);
      _syncHsv();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncHsv);
    super.dispose();
  }

  void _syncHsv() {
    if (_hsv.toColor() != widget.controller.value) {
      setState(() => _hsv = HSVColor.fromColor(widget.controller.value));
    }
  }

  void _pick(Color color) => widget.controller.value = color;

  void _pickHsv(HSVColor hsv) {
    setState(() => _hsv = hsv);
    widget.controller.value = hsv.toColor();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedControl<_PaletteMode>(
          segments: const [
            (_PaletteMode.grid, '网格'),
            (_PaletteMode.spectrum, '色谱'),
            (_PaletteMode.sliders, '滑块'),
          ],
          value: _mode,
          onChanged: (mode) => setState(() => _mode = mode),
        ),
        const SizedBox(height: 16),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: ValueListenableBuilder(
            valueListenable: widget.controller,
            builder: (_, color, _) => switch (_mode) {
              _PaletteMode.grid => _ColorGrid(color: color, onPicked: _pick),
              _PaletteMode.spectrum => _Spectrum(color: color, onPicked: _pick),
              _PaletteMode.sliders => _HsvSliders(hsv: _hsv, onChanged: _pickHsv),
            },
          ),
        ),
      ],
    );
  }
}

class _ColorGrid extends StatelessWidget {
  const _ColorGrid({required this.color, required this.onPicked});

  static const _hues = [
    230.0, 262.0, 285.0, 310.0, 340.0, 20.0,
    40.0, 60.0, 80.0, 100.0, 120.0, 145.0,
  ];
  static const _tones = [25.0, 33.0, 41.0, 49.0, 57.0, 65.0, 73.0, 81.0, 89.0];

  static final List<List<Color>> _rows = [
    [
      for (var column = 0; column < _hues.length; column++)
        Color(Hct.from(0, 0, 100 - column * 100 / (_hues.length - 1)).toInt()),
    ],
    for (final tone in _tones)
      [for (final hue in _hues) Color(Hct.from(hue, 200, tone).toInt())],
  ];

  final Color color;
  final ValueChanged<Color> onPicked;

  @override
  Widget build(BuildContext context) {
    final columns = _hues.length;
    final rows = _rows.length;
    return AspectRatio(
      aspectRatio: columns / rows,
      child: _PickArea(
        onPicked: (position, size) {
          final column = (position.dx / size.width * columns).floor();
          final row = (position.dy / size.height * rows).floor();
          onPicked(_rows[row.clamp(0, rows - 1)][column.clamp(0, columns - 1)]);
        },
        child: CustomPaint(
          painter: _GridPainter(rows: _rows, selected: color),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.rows, required this.selected});

  final List<List<Color>> rows;
  final Color selected;

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / rows.first.length;
    final cellHeight = size.height / rows.length;
    canvas.save();
    canvas.clipRSuperellipse(
      RSuperellipse.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(_padCorner),
      ),
    );
    final paint = Paint()..isAntiAlias = false;
    Rect? selectedCell;
    for (var row = 0; row < rows.length; row++) {
      for (var column = 0; column < rows[row].length; column++) {
        final cell = Rect.fromLTWH(
          column * cellWidth,
          row * cellHeight,
          cellWidth,
          cellHeight,
        );
        final c = rows[row][column];
        canvas.drawRect(cell, paint..color = c);
        if (c == selected) selectedCell = cell;
      }
    }
    if (selectedCell != null) {
      final light =
          ThemeData.estimateBrightnessForColor(selected) == Brightness.dark;
      canvas.drawRSuperellipse(
        RSuperellipse.fromRectAndRadius(
          selectedCell.deflate(_thumbRingWidth / 2),
          const Radius.circular(AppCorner.xs),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _thumbRingWidth
          ..color = light ? Colors.white : Colors.black,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.selected != selected || oldDelegate.rows != rows;
}

class _Spectrum extends StatefulWidget {
  const _Spectrum({required this.color, required this.onPicked});

  final Color color;
  final ValueChanged<Color> onPicked;

  @override
  State<_Spectrum> createState() => _SpectrumState();
}

class _SpectrumState extends State<_Spectrum> {
  ({Offset position, Color color})? _picked;

  Offset _positionOf(Color color) {
    final picked = _picked;
    if (picked != null && picked.color == color) return picked.position;
    final hsl = HSLColor.fromColor(color);
    return Offset(hsl.hue / 360, 1 - hsl.lightness);
  }

  void _handlePicked(Offset position, Size size) {
    final fraction = Offset(
      position.dx / size.width,
      position.dy / size.height,
    );
    final c = HSLColor.fromAHSL(
      1,
      clampDouble(fraction.dx * 360, 0, 359.99),
      1,
      1 - fraction.dy,
    ).toColor();
    _picked = (position: fraction, color: c);
    widget.onPicked(c);
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 6 / 5,
      child: _PickArea(
        onPicked: _handlePicked,
        child: CustomPaint(
          painter: _SpectrumPainter(
            color: widget.color,
            position: _positionOf(widget.color),
          ),
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  const _SpectrumPainter({required this.color, required this.position});

  static final _hues = [
    for (var hue = 0; hue <= 360; hue += 60)
      HSLColor.fromAHSL(1, hue % 360, 1, 0.5).toColor(),
  ];

  final Color color;
  final Offset position;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RSuperellipse.fromRectAndRadius(
      rect,
      const Radius.circular(_padCorner),
    );
    canvas.drawRSuperellipse(
      shape,
      Paint()..shader = LinearGradient(colors: _hues).createShader(rect),
    );
    canvas.drawRSuperellipse(
      shape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            Color(0x00FFFFFF),
            Color(0x00000000),
            Colors.black,
          ],
          stops: [0, 0.5, 0.5, 1],
        ).createShader(rect),
    );
    _paintColorThumb(
      canvas,
      Offset(position.dx * size.width, position.dy * size.height),
      _thumbRadius,
      color,
    );
  }

  @override
  bool shouldRepaint(_SpectrumPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.position != position;
}

class _HsvSliders extends StatelessWidget {
  const _HsvSliders({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  static final _hueStops = [
    for (var hue = 0; hue <= 360; hue += 60)
      HSVColor.fromAHSV(1, hue % 360, 1, 1).toColor(),
  ];

  @override
  Widget build(BuildContext context) {
    final pure = HSVColor.fromAHSV(1, hsv.hue, 1, hsv.value).toColor();
    final unsaturated = HSVColor.fromAHSV(1, hsv.hue, 0, hsv.value).toColor();
    final bright = HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, 1).toColor();
    return Column(
      spacing: 14,
      children: [
        _GradientSlider(
          label: '色相',
          valueLabel: '${hsv.hue.round()}°',
          value: hsv.hue / 360,
          colors: _hueStops,
          thumbColor: HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
          onChanged: (v) => onChanged(hsv.withHue(clampDouble(v * 360, 0, 359.99))),
        ),
        _GradientSlider(
          label: '饱和度',
          valueLabel: '${(hsv.saturation * 100).round()}%',
          value: hsv.saturation,
          colors: [unsaturated, pure],
          thumbColor: hsv.toColor(),
          onChanged: (v) => onChanged(hsv.withSaturation(v)),
        ),
        _GradientSlider(
          label: '亮度',
          valueLabel: '${(hsv.value * 100).round()}%',
          value: hsv.value,
          colors: [Colors.black, bright],
          thumbColor: hsv.toColor(),
          onChanged: (v) => onChanged(hsv.withValue(v)),
        ),
      ],
    );
  }
}

class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.colors,
    required this.thumbColor,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final List<Color> colors;
  final Color thumbColor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: AppTextStyle.footnote.of(context, emphasized: true).copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              valueLabel,
              style: AppTextStyle.footnote.of(context, emphasized: true).copyWith(
                color: colorScheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        SizedBox(
          height: _thumbRadius * 2 + 4,
          child: _PickArea(
            onPicked: (pos, size) {
              final usable = (size.width - _thumbRadius * 2).clamp(1.0, double.infinity);
              final t = ((pos.dx - _thumbRadius) / usable).clamp(0.0, 1.0);
              onChanged(t);
            },
            child: CustomPaint(
              painter: _SliderTrackPainter(
                colors: colors,
                value: value,
                thumbColor: thumbColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SliderTrackPainter extends CustomPainter {
  const _SliderTrackPainter({
    required this.colors,
    required this.value,
    required this.thumbColor,
  });

  final List<Color> colors;
  final double value;
  final Color thumbColor;

  @override
  void paint(Canvas canvas, Size size) {
    final trackRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width,
      height: _trackHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, const Radius.circular(_trackHeight / 2)),
      Paint()..shader = LinearGradient(colors: colors).createShader(trackRect),
    );
    final usable = (size.width - _thumbRadius * 2).clamp(0.0, double.infinity);
    final cx = _thumbRadius + usable * value.clamp(0.0, 1.0);
    _paintColorThumb(
      canvas,
      Offset(cx, size.height / 2),
      _thumbRadius,
      thumbColor,
    );
  }

  @override
  bool shouldRepaint(_SliderTrackPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.thumbColor != thumbColor ||
      !listEquals(oldDelegate.colors, colors);
}

void _paintColorThumb(Canvas canvas, Offset center, double radius, Color color) {
  canvas.drawCircle(
    center + const Offset(0, 2),
    radius,
    Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
  );
  canvas.drawCircle(center, radius, Paint()..color = color);
  canvas.drawCircle(
    center,
    radius - _thumbRingWidth / 2,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _thumbRingWidth
      ..color = Colors.white,
  );
}

class _ImmediatePanGestureRecognizer extends PanGestureRecognizer {
  _ImmediatePanGestureRecognizer({super.debugOwner});

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _PickArea extends StatelessWidget {
  const _PickArea({required this.onPicked, required this.child});

  final void Function(Offset position, Size size) onPicked;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final size = constraints.biggest;
        void emit(Offset local) {
          onPicked(
            Offset(
              clampDouble(local.dx, 0, size.width),
              clampDouble(local.dy, 0, size.height),
            ),
            size,
          );
        }

        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            _ImmediatePanGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  _ImmediatePanGestureRecognizer
                >(
                  () => _ImmediatePanGestureRecognizer(debugOwner: this),
                  (instance) {
                    instance
                      ..onDown = (d) => emit(d.localPosition)
                      ..onUpdate = (d) => emit(d.localPosition);
                  },
                ),
          },
          child: child,
        );
      },
    );
  }
}

/// Hex input field synced with [Palette].
class HexColorField extends StatefulWidget {
  const HexColorField({
    super.key,
    required this.color,
    required this.onChanged,
  });

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  State<HexColorField> createState() => _HexColorFieldState();
}

class _HexColorFieldState extends State<HexColorField> {
  late final TextEditingController _controller = TextEditingController(
    text: _hexOf(widget.color),
  );

  static String _hexOf(Color c) =>
      (c.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0');

  @override
  void didUpdateWidget(HexColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _hexOf(widget.color);
    if (_controller.text.toUpperCase() != next) {
      _controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Text(
          'HEX 色值',
          style: AppTextStyle.caption1.of(context, emphasized: true).copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        TextField(
          controller: _controller,
          maxLines: 1,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
            LengthLimitingTextInputFormatter(6),
          ],
          style: AppTextStyle.callout.of(context, emphasized: true).copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: SurfaceLevel.block.colorOf(colorScheme),
            prefixText: '#',
            border: AppShape.input.copyWith(borderSide: BorderSide.none),
            enabledBorder: AppShape.input.copyWith(borderSide: BorderSide.none),
            focusedBorder: AppShape.input.copyWith(
              borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onChanged: (raw) {
            if (raw.length == 6) {
              final parsed = int.tryParse(raw, radix: 16);
              if (parsed != null) {
                widget.onChanged(Color(0xFF000000 | parsed));
              }
            }
          },
        ),
      ],
    );
  }
}
