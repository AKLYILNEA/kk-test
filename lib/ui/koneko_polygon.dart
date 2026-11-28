import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:prism_ui/shapes/shapes.dart' as shapes;

/// Material 3 Expressive rounded-polygon vocabulary matching Kazumi's
/// `material_new_shapes` aesthetic, built natively on `prism_ui`'s
/// [shapes.RoundedPolygon] engine with zero extra dependencies.
abstract final class KonekoPolygons {
  static shapes.PointTransformer _rotated(double radians) {
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return (x, y) => (cos * x - sin * y, sin * x + cos * y);
  }

  /// 8-point rounded sunburst (Kazumi watch stats, Bangumi highlights, ratings).
  static final shapes.RoundedPolygon sunny = shapes.RoundedPolygon.star(
    numVerticesPerRadius: 8,
    innerRadius: 0.80,
    rounding: const shapes.CornerRounding(radius: 0.16),
    innerRounding: const shapes.CornerRounding(radius: 0.16),
  ).transformed(_rotated(-math.pi / 8)).normalized();

  /// 4-sided scalloped cookie (Kazumi default empty/state badge & offline).
  static final shapes.RoundedPolygon cookie4Sided = shapes.RoundedPolygon.star(
    numVerticesPerRadius: 4,
    innerRadius: 0.72,
    rounding: const shapes.CornerRounding(radius: 0.42),
    innerRounding: const shapes.CornerRounding(radius: 0.42),
  ).transformed(_rotated(math.pi / 4)).normalized();

  /// 6-sided scalloped cookie (history, collections, status seals).
  static final shapes.RoundedPolygon cookie6Sided =
      shapes.MaterialShapes.cookie6Sided;

  /// 9-sided scalloped seal (Bangumi avatars, sync badges, verified checkmarks).
  static final shapes.RoundedPolygon cookie9Sided =
      shapes.MaterialShapes.cookie9Sided;

  /// 12-sided scalloped medal (Bangumi hero watermark, premium seals).
  static final shapes.RoundedPolygon cookie12Sided =
      shapes.MaterialShapes.cookie12Sided;

  /// 4-leaf clover (Kazumi rules tile & plugin cards).
  static final shapes.RoundedPolygon clover4Leaf =
      shapes.MaterialShapes.clover4Leaf;

  /// 8-petal soft blossom (theme, appearance, danmaku, comments).
  static final shapes.RoundedPolygon flower = shapes.RoundedPolygon.star(
    numVerticesPerRadius: 8,
    innerRadius: 0.72,
    rounding: const shapes.CornerRounding(radius: 0.44),
    innerRounding: const shapes.CornerRounding(radius: 0.10),
  ).transformed(_rotated(-math.pi / 8)).normalized();

  /// 10-point soft burst (about, updates, featured badges).
  static final shapes.RoundedPolygon softBurst = shapes.RoundedPolygon.star(
    numVerticesPerRadius: 10,
    innerRadius: 0.78,
    rounding: const shapes.CornerRounding(radius: 0.24),
    innerRounding: const shapes.CornerRounding(radius: 0.24),
  ).transformed(_rotated(-math.pi / 10)).normalized();

  /// Soft rounded pentagon (search, filter, schedule).
  static final shapes.RoundedPolygon pentagon =
      shapes.RoundedPolygon.fromVerticesNum(
        5,
        rounding: const shapes.CornerRounding(radius: 0.34),
      ).transformed(_rotated(-math.pi / 2)).normalized();

  /// Soft rounded hexagon (player tools, tags, metadata).
  static final shapes.RoundedPolygon hexagon =
      shapes.RoundedPolygon.fromVerticesNum(
        6,
        rounding: const shapes.CornerRounding(radius: 0.30),
      ).transformed(_rotated(-math.pi / 2)).normalized();

  /// 8-sided rounded gem (playback, media controls).
  static final shapes.RoundedPolygon gem =
      shapes.RoundedPolygon.fromVerticesNum(
        8,
        rounding: const shapes.CornerRounding(radius: 0.26),
      ).transformed(_rotated(math.pi / 8)).normalized();
}

/// First-class [OutlinedBorder] backed by a [shapes.RoundedPolygon] with
/// zero-allocation normalized path caching so polygons compose natively with
/// FlClash's [DecoratedBox], [ShapeDecoration], [PressSurface], and shadows.
class KonekoPolygonBorder extends OutlinedBorder {
  const KonekoPolygonBorder(this.polygon, {super.side = BorderSide.none});

  final shapes.RoundedPolygon polygon;

  static final Expando<Path> _unitPaths = Expando<Path>('konekoPolygonPaths');

  static Path _unitPathOf(shapes.RoundedPolygon polygon) =>
      _unitPaths[polygon] ??= polygon.toPath();

  Path _scaledPath(Rect rect) {
    final unit = _unitPathOf(polygon);
    final matrix = Matrix4.translationValues(rect.left, rect.top, 0)
      ..multiply(Matrix4.diagonal3Values(rect.width, rect.height, 1));
    return unit.transform(matrix.storage);
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _scaledPath(rect.deflate(side.strokeInset));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _scaledPath(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    final path = _scaledPath(rect.deflate(side.strokeInset / 2));
    canvas.drawPath(path, side.toPaint());
  }

  @override
  OutlinedBorder copyWith({BorderSide? side}) =>
      KonekoPolygonBorder(polygon, side: side ?? this.side);

  @override
  ShapeBorder scale(double t) =>
      KonekoPolygonBorder(polygon, side: side.scale(t));

  @override
  bool operator ==(Object other) =>
      other is KonekoPolygonBorder &&
      identical(other.polygon, polygon) &&
      other.side == side;

  @override
  int get hashCode => Object.hash(identityHashCode(polygon), side);
}

/// Pure FlClash (`prism_ui`) counterpart of Kazumi's `StateIconBadge`:
/// places a [GlyphIcon] (or custom [child]) inside a crisp expressive
/// [shapes.RoundedPolygon] with tonal or solid fill, optional shadow, and
/// optional press interaction.
class KonekoPolygonBadge extends StatelessWidget {
  const KonekoPolygonBadge({
    super.key,
    this.glyph,
    this.child,
    this.shape,
    this.size = 38,
    this.iconSize,
    this.backgroundColor,
    this.foregroundColor,
    this.borderSide = BorderSide.none,
    this.shadows,
    this.fill = 0,
    this.onPressed,
  }) : assert(glyph != null || child != null);

  final Glyph? glyph;
  final Widget? child;
  final shapes.RoundedPolygon? shape;
  final double size;
  final double? iconSize;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final BorderSide borderSide;
  final List<BoxShadow>? shadows;
  final double fill;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final polygon = shape ?? KonekoPolygons.cookie4Sided;
    final bg = backgroundColor ?? colorScheme.primary.withValues(alpha: 0.13);
    final fg = foregroundColor ?? colorScheme.primary;
    final border = KonekoPolygonBorder(polygon, side: borderSide);
    final resolvedIconSize = iconSize ?? (size * 0.48).clamp(13.0, 36.0);

    final inner = SizedBox.square(
      dimension: size,
      child: Center(
        child:
            child ??
            GlyphIcon(glyph!, size: resolvedIconSize, color: fg, fill: fill),
      ),
    );

    if (onPressed != null) {
      final pressable = PressSurface(
        fill: bg,
        shape: border,
        clipsChild: true,
        onPressed: onPressed,
        child: inner,
      );
      if (shadows != null && shadows!.isNotEmpty) {
        return DecoratedBox(
          decoration: ShapeDecoration(shape: border, shadows: shadows),
          child: pressable,
        );
      }
      return pressable;
    }

    return DecoratedBox(
      decoration: ShapeDecoration(color: bg, shape: border, shadows: shadows),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: border),
        child: inner,
      ),
    );
  }
}

/// Kazumi-inspired expressive empty / error state built with FlClash typography,
/// elevated polygon icon badge, and optional action buttons.
class KonekoEmptyState extends StatelessWidget {
  const KonekoEmptyState({
    super.key,
    required this.glyph,
    required this.title,
    this.subtitle,
    this.shape,
    this.accentColor,
    this.actions = const [],
    this.compact = false,
  });

  final Glyph glyph;
  final String title;
  final String? subtitle;
  final shapes.RoundedPolygon? shape;
  final Color? accentColor;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final accent = accentColor ?? colorScheme.primary;
    final badgeSize = compact ? 56.0 : 76.0;
    final iconSize = compact ? 24.0 : 32.0;

    return Center(
      child: Padding(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 20)
            : const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              KonekoPolygonBadge(
                glyph: glyph,
                shape: shape ?? KonekoPolygons.cookie4Sided,
                size: badgeSize,
                iconSize: iconSize,
                backgroundColor: accent.withValues(alpha: 0.13),
                foregroundColor: accent,
                shadows: konekoPillShadows(colorScheme),
              ),
              SizedBox(height: compact ? 12 : 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style:
                    (compact
                            ? AppTextStyle.subheadline
                            : AppTextStyle.headline)
                        .of(context, emphasized: true)
                        .copyWith(color: colorScheme.onSurface),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
              if (actions.isNotEmpty) ...[
                SizedBox(height: compact ? 14 : 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
