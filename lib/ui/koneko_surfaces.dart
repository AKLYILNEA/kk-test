import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_image.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

final _cardShadowCache = <(bool, int), List<BoxShadow>>{};
final _pillShadowCache = <(bool, int), List<BoxShadow>>{};

/// Apple/FlClash-style soft layered elevation shadow (no heavy Material borders).
List<BoxShadow> konekoCardShadows(ColorScheme colorScheme) {
  final isDark = colorScheme.brightness == Brightness.dark;
  final shadow = colorScheme.shadow;
  return _cardShadowCache.putIfAbsent((isDark, shadow.toARGB32()), () {
    if (_cardShadowCache.length >= 16) _cardShadowCache.clear();
    return List<BoxShadow>.unmodifiable([
      BoxShadow(
        color: shadow.withValues(alpha: isDark ? 0.24 : 0.055),
        blurRadius: isDark ? 20 : 18,
        offset: const Offset(0, 6),
      ),
      BoxShadow(
        color: shadow.withValues(alpha: isDark ? 0.14 : 0.03),
        blurRadius: 3,
        offset: const Offset(0, 1),
      ),
    ]);
  });
}

/// Matching softer elevation shadow for page-level pills, chip bars & segmented controls.
List<BoxShadow> konekoPillShadows(ColorScheme colorScheme) {
  final isDark = colorScheme.brightness == Brightness.dark;
  final shadow = colorScheme.shadow;
  return _pillShadowCache.putIfAbsent((isDark, shadow.toARGB32()), () {
    if (_pillShadowCache.length >= 16) _pillShadowCache.clear();
    return List<BoxShadow>.unmodifiable([
      BoxShadow(
        color: shadow.withValues(alpha: isDark ? 0.22 : 0.055),
        blurRadius: isDark ? 14 : 12,
        offset: const Offset(0, 4),
      ),
      BoxShadow(
        color: shadow.withValues(alpha: isDark ? 0.12 : 0.028),
        blurRadius: 2.5,
        offset: const Offset(0, 1),
      ),
    ]);
  });
}

void showKonekoBanner(
  BuildContext context,
  String message, {
  BannerLevel level = BannerLevel.info,
}) {
  BannerHost.maybeOf(context)?.show(message, level: level);
}

/// Pure FlClash / prism_ui borderless elevated card (`SurfaceLevel.card`).
class KonekoCard extends StatelessWidget {
  const KonekoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.corner = 26,
    this.onPressed,
    this.color,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double corner;
  final VoidCallback? onPressed;
  final Color? color;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final fill = color ?? SurfaceLevel.card.colorOf(colorScheme);
    final shape = SuperellipseBorder(borderRadius: AppRadius.all(corner));
    final content = SurfaceScope(
      level: SurfaceLevel.card,
      child: Padding(padding: padding, child: child),
    );
    if (onPressed != null) {
      return DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          shadows: konekoCardShadows(colorScheme),
        ),
        child: PressSurface(
          fill: fill,
          shape: shape,
          clipsChild: true,
          onPressed: onPressed,
          child: content,
        ),
      );
    }
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: fill,
        shape: shape,
        shadows: konekoCardShadows(colorScheme),
      ),
      child: clip
          ? ClipPath(
              clipper: ShapeBorderClipper(shape: shape),
              child: content,
            )
          : content,
    );
  }
}

/// Inner surface tile (`SurfaceLevel.block`) inside a [KonekoCard].
class KonekoBlock extends StatelessWidget {
  const KonekoBlock({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.corner = 18,
    this.onPressed,
    this.selected = false,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double corner;
  final VoidCallback? onPressed;
  final bool selected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final fill =
        color ??
        (selected
            ? colorScheme.primary.withValues(alpha: 0.14)
            : SurfaceLevel.block.colorOf(colorScheme));
    final shape = SuperellipseBorder(borderRadius: AppRadius.all(corner));
    final inner = SurfaceScope(
      level: SurfaceLevel.block,
      child: Padding(padding: padding, child: child),
    );
    if (onPressed != null) {
      return PressSurface(
        fill: fill,
        shape: shape,
        clipsChild: true,
        selected: selected,
        onPressed: onPressed,
        child: inner,
      );
    }
    return DecoratedBox(
      decoration: ShapeDecoration(color: fill, shape: shape),
      child: inner,
    );
  }
}

/// Elevated wrapper around `prism_ui`'s [generateGroup] so grouped list sections
/// share the exact same soft FlClash drop shadows as [KonekoCard].
class KonekoGroup extends StatelessWidget {
  const KonekoGroup({super.key, required this.items});

  final Iterable<Widget> items;

  @override
  Widget build(BuildContext context) {
    final list = items.toList();
    if (list.isEmpty) return const SizedBox.shrink();
    final colorScheme = context.colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: AppShape.xl,
        shadows: konekoCardShadows(colorScheme),
      ),
      child: generateGroup(list),
    );
  }
}

/// Elevated replacement for `prism_ui`'s [generateSection] with soft card shadows.
class KonekoSection extends StatelessWidget {
  const KonekoSection({
    super.key,
    this.title,
    this.caption,
    required this.items,
    this.actions = const [],
    this.footer,
  });

  final String? title;
  final String? caption;
  final Iterable<Widget> items;
  final List<IconButtonData> actions;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final list = items.toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          ListHeader(title: title!, caption: caption, actions: actions)
        else
          const ListSectionGap(),
        KonekoGroup(items: list),
        if (footer != null) ListFooter(text: footer!),
      ],
    );
  }
}

/// Kazumi-style 5-star fractional painted rating indicator mapping a 0..10
/// Bangumi score onto 5 partially-filled gold stars.
class KonekoStarRating extends StatelessWidget {
  const KonekoStarRating({
    super.key,
    required this.score,
    this.starSize = 15,
    this.spacing = 2,
  });

  /// Bangumi score on a 0..10 scale.
  final double score;
  final double starSize;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final fillStars = (score / 2.0).clamp(0.0, 5.0);
    return CustomPaint(
      size: Size(starSize * 5 + spacing * 4, starSize),
      painter: _StarRatingPainter(
        fillStars: fillStars,
        starSize: starSize,
        spacing: spacing,
        activeColor: const Color(0xFFFFB423),
        inactiveColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.22),
      ),
    );
  }
}

class _StarRatingPainter extends CustomPainter {
  const _StarRatingPainter({
    required this.fillStars,
    required this.starSize,
    required this.spacing,
    required this.activeColor,
    required this.inactiveColor,
  });

  final double fillStars;
  final double starSize;
  final double spacing;
  final Color activeColor;
  final Color inactiveColor;

  static final Map<(double, double), List<Path>> _pathCache = {};
  static final Paint _paint = Paint()..isAntiAlias = true;

  static List<Path> _pathsFor(double starSize, double spacing) {
    return _pathCache.putIfAbsent((starSize, spacing), () {
      if (_pathCache.length >= 16) _pathCache.clear();
      final outerR = starSize * 0.48;
      final innerR = outerR * 0.44;
      final cy = starSize / 2;
      return List<Path>.unmodifiable([
        for (var i = 0; i < 5; i++)
          () {
            final cx = i * (starSize + spacing) + starSize / 2;
            final path = Path();
            for (var v = 0; v < 10; v++) {
              final angle = -math.pi / 2 + v * math.pi / 5;
              final r = v.isEven ? outerR : innerR;
              final pt = Offset(
                cx + math.cos(angle) * r,
                cy + math.sin(angle) * r,
              );
              if (v == 0) {
                path.moveTo(pt.dx, pt.dy);
              } else {
                path.lineTo(pt.dx, pt.dy);
              }
            }
            path.close();
            return path;
          }(),
      ]);
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paths = _pathsFor(starSize, spacing);
    _paint.color = inactiveColor;
    for (var i = 0; i < 5; i++) {
      canvas.drawPath(paths[i], _paint);
    }

    _paint.color = activeColor;
    for (var i = 0; i < 5; i++) {
      final starFill = (fillStars - i).clamp(0.0, 1.0);
      if (starFill <= 0) continue;
      if (starFill >= 1.0) {
        canvas.drawPath(paths[i], _paint);
      } else {
        final left = i * (starSize + spacing);
        canvas.save();
        canvas.clipRect(
          Rect.fromLTWH(left, 0, starSize * starFill, size.height),
        );
        canvas.drawPath(paths[i], _paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_StarRatingPainter oldDelegate) =>
      oldDelegate.fillStars != fillStars ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.inactiveColor != inactiveColor ||
      oldDelegate.starSize != starSize;
}

/// Full-bleed poster card designed for the Library grid: eliminates mismatched
/// white footer boxes and awkward empty whitespace on short titles by laying
/// crisp white typography over a soft bottom gradient scrim inside a uniform
/// elevated superellipse poster.
class KonekoPosterCard extends StatelessWidget {
  const KonekoPosterCard({
    super.key,
    required this.subject,
    required this.onTap,
    this.statusBadgeLabel,
    this.onStatusTap,
    this.corner = 18,
  });

  final AnimeSubject subject;
  final VoidCallback onTap;
  final String? statusBadgeLabel;
  final VoidCallback? onStatusTap;
  final double corner;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final shape = SuperellipseBorder(borderRadius: AppRadius.all(corner));
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: konekoCardShadows(colorScheme),
      ),
      child: PressSurface(
        fill: SurfaceLevel.card.colorOf(colorScheme),
        shape: shape,
        clipsChild: true,
        onPressed: onTap,
        child: KonekoPosterArt(
          subject: subject,
          overlayBadges: [
            // Smooth bottom scrim for crisp title legibility regardless of cover art
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.46, 0.76, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.42),
                        Colors.black.withValues(alpha: 0.84),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (subject.score > 0)
              Positioned(
                top: 7,
                left: 7,
                child: KonekoChip(
                  label: subject.score.toStringAsFixed(1),
                  height: 20,
                  fontSize: 10,
                  leading: const GlyphIcon(
                    KonekoGlyphs.star,
                    size: 10,
                    color: Color(0xFFFFC145),
                  ),
                  backgroundColor: Colors.black.withValues(alpha: 0.56),
                  foregroundColor: Colors.white,
                ),
              ),
            if (statusBadgeLabel != null)
              Positioned(
                top: 7,
                right: 7,
                child: KonekoChip(
                  label: statusBadgeLabel!,
                  height: 21,
                  fontSize: 10,
                  backgroundColor: Colors.black.withValues(alpha: 0.62),
                  foregroundColor: Colors.white,
                  trailing: onStatusTap != null
                      ? const GlyphIcon(
                          Glyphs.chevronDown,
                          size: 9.5,
                          color: Colors.white,
                        )
                      : null,
                  onPressed: onStatusTap,
                ),
              ),
            Positioned(
              left: 9,
              right: 9,
              bottom: 8,
              child: IgnorePointer(
                child: Text(
                  subject.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(
                        fontSize: 12.5,
                        height: 1.24,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.55),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Elevated wrapper for page-level [SegmentedControl] so sliders share the
/// exact same soft shadow language as cards and top chip bars.
class KonekoSegmentedBar<T extends Object> extends StatelessWidget {
  const KonekoSegmentedBar({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String)> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: AppShape.full,
        shadows: konekoPillShadows(colorScheme),
      ),
      child: SegmentedControl<T>(
        segments: segments,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// Full-pill capsule chip with locked vertical optical alignment.
/// Set [elevated] to `true` when sitting directly on `SurfaceLevel.page` so
/// top-level pills share the unified FlClash soft shadow language.
class KonekoChip extends StatelessWidget {
  const KonekoChip({
    super.key,
    required this.label,
    this.leading,
    this.trailing,
    this.backgroundColor,
    this.foregroundColor,
    this.height = 24,
    this.fontSize = 11.5,
    this.onPressed,
    this.selected = false,
    this.elevated = false,
  });

  final String label;
  final Widget? leading;
  final Widget? trailing;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double height;
  final double fontSize;
  final VoidCallback? onPressed;
  final bool selected;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final bg =
        backgroundColor ??
        (selected
            ? colorScheme.primary
            : SurfaceLevel.block.colorOf(colorScheme));
    final fg =
        foregroundColor ??
        (selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant);

    final row = Padding(
      padding: EdgeInsets.symmetric(horizontal: height >= 30 ? 12 : 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 4)],
          Flexible(
            child: EmojiText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1
                  .of(context, emphasized: true)
                  .copyWith(
                    fontSize: fontSize,
                    height: 1.0,
                    leadingDistribution: TextLeadingDistribution.even,
                    color: fg,
                  ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );

    if (onPressed != null) {
      final surface = PressSurface(
        fill: bg,
        shape: AppShape.full,
        clipsChild: true,
        selected: selected,
        onPressed: onPressed,
        child: Center(widthFactor: 1.0, child: row),
      );
      return SizedBox(
        height: height,
        child: elevated
            ? DecoratedBox(
                decoration: ShapeDecoration(
                  shape: AppShape.full,
                  shadows: konekoPillShadows(colorScheme),
                ),
                child: surface,
              )
            : surface,
      );
    }

    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: bg,
          shape: AppShape.full,
          shadows: elevated ? konekoPillShadows(colorScheme) : null,
        ),
        child: Center(widthFactor: 1.0, child: row),
      ),
    );
  }
}

/// Floating circular bar action button matching FlClash's top bar buttons.
class KonekoCircleButton extends StatelessWidget {
  const KonekoCircleButton({
    super.key,
    required this.onPressed,
    required this.glyph,
    this.size = 40,
    this.iconSize = 19,
    this.fillColor,
    this.foregroundColor,
    this.tooltip,
  });

  final VoidCallback? onPressed;
  final Glyph glyph;
  final double size;
  final double iconSize;
  final Color? fillColor;
  final Color? foregroundColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final fill = fillColor ?? SurfaceLevel.card.colorOf(colorScheme);
    final fg = foregroundColor ?? colorScheme.onSurface;
    final button = SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: AppShape.circle,
          shadows: konekoCardShadows(colorScheme),
        ),
        child: PressSurface(
          fill: fill,
          shape: AppShape.circle,
          clipsChild: true,
          onPressed: onPressed,
          child: Center(
            child: GlyphIcon(glyph, size: iconSize, color: fg),
          ),
        ),
      ),
    );
    final child = ElasticPress(enabled: onPressed != null, child: button);
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: child);
    }
    return child;
  }
}

/// A cached network cover with a clean Kazumi/Bilibili-style little-TV placeholder.
/// Uses a single fixed decode width ([kPosterCacheWidth]) across all pages so
/// Flutter's synchronous memory cache hits instantly without re-loading.
class KonekoPosterArt extends StatelessWidget {
  const KonekoPosterArt({
    super.key,
    required this.subject,
    this.borderRadius = BorderRadius.zero,
    this.overlayBadges = const [],
  });

  final AnimeSubject subject;
  final BorderRadius borderRadius;
  final List<Widget> overlayBadges;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final fallback = ColoredBox(
      color: SurfaceLevel.block.colorOf(colorScheme),
      child: CustomPaint(
        painter: _BiliTvPlaceholderPainter(
          iconColor: colorScheme.onSurfaceVariant.withValues(
            alpha: isDark ? 0.28 : 0.24,
          ),
          screenColor: SurfaceLevel.card.colorOf(colorScheme),
        ),
        child: const SizedBox.expand(),
      ),
    );
    final url = subject.coverUrl;
    final art = url == null || url.isEmpty
        ? fallback
        : KonekoNetworkImage(
            url: url,
            placeholder: fallback,
            memCacheWidth: kPosterCacheWidth,
          );
    final content = overlayBadges.isEmpty
        ? art
        : Stack(fit: StackFit.expand, children: [art, ...overlayBadges]);
    if (borderRadius == BorderRadius.zero) {
      return content;
    }
    return ClipRSuperellipse(borderRadius: borderRadius, child: content);
  }
}

/// Clean vector recreation of Kazumi / Bilibili's iconic little-TV (`-ω-`)
/// loading placeholder that adapts naturally to light and dark surfaces.
class _BiliTvPlaceholderPainter extends CustomPainter {
  const _BiliTvPlaceholderPainter({
    required this.iconColor,
    required this.screenColor,
  });

  final Color iconColor;
  final Color screenColor;

  @override
  void paint(Canvas canvas, Size size) {
    final base = math.min(size.width, size.height);
    if (base <= 0) return;

    final tvWidth = (base * 0.44).clamp(26.0, 74.0);
    final tvHeight = tvWidth * 0.74;
    final cx = size.width / 2;
    final cy = size.height / 2 + tvHeight * 0.05;
    final stroke = (tvWidth * 0.095).clamp(2.4, 6.2);

    final bodyRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: tvWidth,
      height: tvHeight,
    );
    final bodyRadius = Radius.circular(tvWidth * 0.18);

    final strokePaint = Paint()
      ..color = iconColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = iconColor
      ..style = PaintingStyle.fill;

    // Two tilted antennae on top
    final topY = bodyRect.top;
    canvas.drawLine(
      Offset(cx - tvWidth * 0.08, topY),
      Offset(cx - tvWidth * 0.24, topY - tvHeight * 0.23),
      strokePaint..strokeWidth = stroke * 0.82,
    );
    canvas.drawLine(
      Offset(cx + tvWidth * 0.08, topY),
      Offset(cx + tvWidth * 0.24, topY - tvHeight * 0.23),
      strokePaint,
    );

    // Two small rounded feet at bottom
    final footRadius = stroke * 0.56;
    canvas.drawCircle(
      Offset(cx - tvWidth * 0.26, bodyRect.bottom + footRadius * 0.42),
      footRadius,
      fillPaint,
    );
    canvas.drawCircle(
      Offset(cx + tvWidth * 0.26, bodyRect.bottom + footRadius * 0.42),
      footRadius,
      fillPaint,
    );

    // Outer TV chassis + inner screen
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, bodyRadius),
      Paint()..color = screenColor,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, bodyRadius),
      strokePaint..strokeWidth = stroke,
    );

    // Relaxed slanted bar eyes (`-  -`)
    final eyeY = cy - tvHeight * 0.06;
    final eyeW = tvWidth * 0.17;
    final eyeH = stroke * 0.72;
    for (final sign in const [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(cx + sign * tvWidth * 0.21, eyeY);
      canvas.rotate(sign * 0.16);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: eyeW, height: eyeH),
          Radius.circular(eyeH * 0.35),
        ),
        fillPaint,
      );
      canvas.restore();
    }

    // Cute little `ω` mouth
    final mouthY = cy + tvHeight * 0.15;
    final mouthSpan = tvWidth * 0.11;
    final mouthDrop = tvHeight * 0.10;
    final mouthPath = Path()
      ..moveTo(cx - mouthSpan, mouthY - mouthDrop * 0.25)
      ..quadraticBezierTo(
        cx - mouthSpan * 0.5,
        mouthY + mouthDrop,
        cx,
        mouthY - mouthDrop * 0.1,
      )
      ..quadraticBezierTo(
        cx + mouthSpan * 0.5,
        mouthY + mouthDrop,
        cx + mouthSpan,
        mouthY - mouthDrop * 0.25,
      );
    canvas.drawPath(
      mouthPath,
      Paint()
        ..color = iconColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.62
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_BiliTvPlaceholderPainter oldDelegate) =>
      oldDelegate.iconColor != iconColor ||
      oldDelegate.screenColor != screenColor;
}

/// Builds a concise metadata line for cards without ever showing "更至第 0 话".
String subjectMetaCaption(AnimeSubject subject) {
  final primaryTag = subject.tags.isNotEmpty ? subject.tags.first : '';
  final parts = <String>[
    if (subject.airedEpisodes > 0)
      '更至第 ${subject.airedEpisodes} 话'
    else if (subject.totalEpisodes > 0)
      '共 ${subject.totalEpisodes} 话'
    else if (subject.seasonLabel.isNotEmpty)
      subject.seasonLabel
    else if (subject.year > 0)
      '${subject.year} 年',
    if (primaryTag.isNotEmpty) primaryTag,
  ];
  return parts.isEmpty ? '动画' : parts.join(' · ');
}

/// Horizontal chip bar that smoothly scrolls the active item toward the center
/// on initial build and whenever [selectedIndex] changes (matching Kazumi).
class KonekoAutoScrollChipBar extends StatefulWidget {
  const KonekoAutoScrollChipBar({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.height = 48,
    this.chipHeight = 36,
    this.fontSize = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    this.unselectedColor,
    this.elevated = true,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double height;
  final double chipHeight;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final Color? unselectedColor;
  final bool elevated;

  @override
  State<KonekoAutoScrollChipBar> createState() =>
      _KonekoAutoScrollChipBarState();
}

class _KonekoAutoScrollChipBarState extends State<KonekoAutoScrollChipBar> {
  late List<GlobalKey> _keys = List.generate(
    widget.labels.length,
    (_) => GlobalKey(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelected(animated: false);
    });
  }

  @override
  void didUpdateWidget(covariant KonekoAutoScrollChipBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.labels.length != widget.labels.length) {
      _keys = List.generate(widget.labels.length, (_) => GlobalKey());
    }
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelected(animated: true);
      });
    }
  }

  void _scrollToSelected({required bool animated}) {
    if (!mounted) return;
    final idx = widget.selectedIndex;
    if (idx < 0 || idx >= _keys.length) return;
    final ctx = _keys[idx].currentContext;
    if (ctx == null) return;
    final scrollable = Scrollable.maybeOf(ctx, axis: Axis.horizontal);
    final target = ctx.findRenderObject();
    if (scrollable == null || target == null) return;
    unawaited(
      scrollable.position.ensureVisible(
        target,
        alignment: 0.5,
        duration: animated
            ? context.motionDuration(const Duration(milliseconds: 260))
            : Duration.zero,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final idleColor =
        widget.unselectedColor ?? SurfaceLevel.card.colorOf(colorScheme);
    return SizedBox(
      height: widget.height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: widget.padding,
        child: Row(
          spacing: 8,
          children: [
            for (var i = 0; i < widget.labels.length; i++)
              KeyedSubtree(
                key: _keys[i],
                child: KonekoChip(
                  label: widget.labels[i],
                  height: widget.chipHeight,
                  fontSize: widget.fontSize,
                  selected: i == widget.selectedIndex,
                  elevated: widget.elevated,
                  backgroundColor: i == widget.selectedIndex
                      ? colorScheme.primary
                      : idleColor,
                  onPressed: () => widget.onSelected(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Unified Anime Card (pure FlClash elevated design):
/// Full-bleed poster cover fused together with a locked-height text footer
/// inside ONE borderless elevated superellipse card so every card in a row
/// aligns pixel-perfectly regardless of 1-line vs 2-line title length.
class UnifiedAnimeCard extends StatelessWidget {
  const UnifiedAnimeCard({
    super.key,
    required this.subject,
    required this.onTap,
    this.isTracking = false,
    this.showTopRank = false,
    this.statusBadgeLabel,
    this.statusGlyph,
    this.statusColor,
    this.statusTooltip,
    this.onStatusTap,
    this.showMetaLine = true,
    this.compact = false,
    this.corner = 22,
  });

  final AnimeSubject subject;
  final VoidCallback onTap;
  final bool isTracking;
  final bool showTopRank;
  final String? statusBadgeLabel;
  final Glyph? statusGlyph;
  final Color? statusColor;
  final String? statusTooltip;
  final VoidCallback? onStatusTap;
  final bool showMetaLine;
  final bool compact;
  final double corner;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final shape = SuperellipseBorder(borderRadius: AppRadius.all(corner));
    final textScale = MediaQuery.textScalerOf(
      context,
    ).scale(1.0).clamp(1.0, 1.35);

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: konekoCardShadows(colorScheme),
      ),
      child: PressSurface(
        fill: SurfaceLevel.card.colorOf(colorScheme),
        shape: shape,
        clipsChild: true,
        onPressed: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: KonekoPosterArt(
                subject: subject,
                overlayBadges: [
                  if (showTopRank && subject.rank > 0 && subject.rank <= 3)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: KonekoChip(
                        label: 'TOP ${subject.rank}',
                        height: 22,
                        fontSize: 10.5,
                        backgroundColor: colorScheme.primary.withValues(
                          alpha: 0.92,
                        ),
                        foregroundColor: colorScheme.onPrimary,
                      ),
                    ),
                  if (statusGlyph != null)
                    Positioned(
                      top: compact ? 6 : 7,
                      right: compact ? 6 : 7,
                      child: Semantics(
                        button: onStatusTap != null,
                        label: statusTooltip ?? '修改追番状态',
                        child: Tooltip(
                          message: statusTooltip ?? '修改追番状态',
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              shape: CircleBorder(
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.28),
                                  width: 1,
                                ),
                              ),
                              shadows: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.24),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: SizedBox.square(
                              dimension: compact ? 26 : 28,
                              child: PressSurface(
                                fill: statusColor ?? colorScheme.primary,
                                shape: AppShape.full,
                                clipsChild: true,
                                onPressed: onStatusTap,
                                child: Center(
                                  child: GlyphIcon(
                                    statusGlyph!,
                                    fill: 1,
                                    size: compact ? 14 : 15,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (statusBadgeLabel != null)
                    Positioned(
                      top: 7,
                      right: 7,
                      child: KonekoChip(
                        label: statusBadgeLabel!,
                        height: 22,
                        fontSize: 10.5,
                        backgroundColor: Colors.black.withValues(alpha: 0.62),
                        foregroundColor: Colors.white,
                        trailing: onStatusTap != null
                            ? const GlyphIcon(
                                Glyphs.chevronDown,
                                size: 10,
                                color: Colors.white,
                              )
                            : null,
                        onPressed: onStatusTap,
                      ),
                    )
                  else if (isTracking)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: KonekoChip(
                        label: '在追',
                        height: 22,
                        fontSize: 10.5,
                        leading: GlyphIcon(
                          KonekoGlyphs.heart,
                          fill: 1,
                          size: 11,
                          color: colorScheme.onPrimary,
                        ),
                        backgroundColor: const Color(0xE0E84C7F),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  if (subject.score > 0)
                    Positioned(
                      right: compact ? 6 : 8,
                      bottom: compact ? 6 : 8,
                      child: KonekoChip(
                        label: subject.score.toStringAsFixed(1),
                        height: compact ? 19 : 22,
                        fontSize: compact ? 10 : 11,
                        leading: GlyphIcon(
                          KonekoGlyphs.star,
                          size: compact ? 10 : 11,
                          color: const Color(0xFFFFC145),
                        ),
                        backgroundColor: Colors.black.withValues(alpha: 0.58),
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
            if (showMetaLine)
              Padding(
                padding: compact
                    ? const EdgeInsets.fromLTRB(8, 7, 8, 8)
                    : const EdgeInsets.fromLTRB(10, 9, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.subheadline
                          .of(context, emphasized: true)
                          .copyWith(
                            color: colorScheme.onSurface,
                            fontSize: compact ? 12.5 : 14,
                          ),
                    ),
                    SizedBox(height: compact ? 2 : 4),
                    Text(
                      subjectMetaCaption(subject),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption1
                          .of(context)
                          .copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: compact ? 10.5 : null,
                          ),
                    ),
                  ],
                ),
              )
            else
              // Locked uniform 2-line footer height so every card in the Library
              // grid aligns its cover bottom and white block pixel-perfectly.
              SizedBox(
                height: (48 * textScale).roundToDouble(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      subject.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.subheadline
                          .of(context, emphasized: true)
                          .copyWith(
                            color: colorScheme.onSurface,
                            fontSize: 12.5,
                            height: 1.25,
                          ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Unified semantic glyph for each collection status across Library cards,
/// SubjectDetailPage status chips, and the status picker sheet.
Glyph konekoStatusGlyph(CollectionStatus status, {bool forBadge = false}) =>
    switch (status) {
      CollectionStatus.watching => KonekoGlyphs.heart,
      CollectionStatus.wish => KonekoGlyphs.bookmark,
      CollectionStatus.watched =>
        forBadge ? KonekoGlyphs.checkBold : KonekoGlyphs.checkCircle,
      CollectionStatus.onHold => KonekoGlyphs.hourglass,
      CollectionStatus.dropped => KonekoGlyphs.heartBroken,
    };

/// Unified semantic accent color for each collection status.
Color konekoStatusColor(CollectionStatus status) => switch (status) {
  CollectionStatus.watching => const Color(0xFFE84C7F),
  CollectionStatus.wish => const Color(0xFFF09336),
  CollectionStatus.watched => const Color(0xFF2DA970),
  CollectionStatus.onHold => const Color(0xFF5485C2),
  CollectionStatus.dropped => const Color(0xFF7A8094),
};
