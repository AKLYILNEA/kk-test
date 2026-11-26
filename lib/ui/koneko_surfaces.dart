import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:koneko/ui/koneko_icon.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

/// Apple/FlClash-style soft layered elevation shadow (no heavy Material borders).
List<BoxShadow> konekoCardShadows(ColorScheme colorScheme) {
  final isDark = colorScheme.brightness == Brightness.dark;
  return [
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: isDark ? 0.24 : 0.055),
      blurRadius: isDark ? 20 : 18,
      offset: const Offset(0, 6),
    ),
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: isDark ? 0.14 : 0.03),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
  ];
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
    final fill = color ??
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

/// Full-pill capsule chip with locked vertical optical alignment (`StrutStyle`).
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final bg = backgroundColor ??
        (selected
            ? colorScheme.primary
            : SurfaceLevel.block.colorOf(colorScheme));
    final fg = foregroundColor ??
        (selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant);

    final row = Padding(
      padding: EdgeInsets.symmetric(horizontal: height >= 30 ? 12 : 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              strutStyle: StrutStyle(
                fontSize: fontSize,
                height: 1.0,
                forceStrutHeight: true,
                leadingDistribution: TextLeadingDistribution.even,
              ),
              style: AppTextStyle.caption1.of(context, emphasized: true).copyWith(
                fontSize: fontSize,
                height: 1.0,
                leadingDistribution: TextLeadingDistribution.even,
                color: fg,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            trailing!,
          ],
        ],
      ),
    );

    if (onPressed != null) {
      return SizedBox(
        height: height,
        child: PressSurface(
          fill: bg,
          shape: AppShape.full,
          clipsChild: true,
          selected: selected,
          onPressed: onPressed,
          child: Center(widthFactor: 1.0, child: row),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: ShapeDecoration(color: bg, shape: AppShape.full),
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
    this.glyph,
    this.icon,
    this.size = 40,
    this.iconSize = 19,
    this.fillColor,
    this.foregroundColor,
    this.tooltip,
  });

  final VoidCallback? onPressed;
  final Glyph? glyph;
  final IconData? icon;
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
    final child = SizedBox.square(
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
            child: glyph != null
                ? GlyphIcon(glyph!, size: iconSize, color: fg)
                : KonekoIcon(icon ?? KonekoIcons.sparkles, size: iconSize, color: fg),
          ),
        ),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: child);
    }
    return child;
  }
}

/// Clean FlClash top header bar with large title and circular action buttons.
class KonekoPageHeader extends StatelessWidget {
  const KonekoPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = false,
    this.onBack,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          if (showBack) ...[
            KonekoCircleButton(
              glyph: Glyphs.chevronBack,
              tooltip: '返回',
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.title1.of(context, emphasized: true).copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.footnote.of(context).copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: actions,
            ),
        ],
      ),
    );
  }
}

/// Crisp deterministic procedural poster art for offline UI-First MVP.
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
    final art = CustomPaint(
      painter: _PosterPainter(subject.poster),
      child: const SizedBox.expand(),
    );
    final content = overlayBadges.isEmpty
        ? art
        : Stack(
            fit: StackFit.expand,
            children: [
              art,
              ...overlayBadges,
            ],
          );
    if (borderRadius == BorderRadius.zero) {
      return content;
    }
    return ClipRSuperellipse(borderRadius: borderRadius, child: content);
  }
}

class _PosterPainter extends CustomPainter {
  const _PosterPainter(this.palette);

  final PosterPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final primary = Color(palette.primaryHex);
    final secondary = Color(palette.secondaryHex);
    final accent = Color(palette.accentHex);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, secondary],
        ).createShader(rect),
    );

    final cx = size.width * 0.56;
    final cy = size.height * 0.38;
    final r = math.min(size.width, size.height) * 0.34;

    switch (palette.motifIndex % 8) {
      case 0:
        canvas.drawCircle(
          Offset(cx, cy),
          r,
          Paint()..color = accent.withValues(alpha: 0.25),
        );
        canvas.drawCircle(
          Offset(cx + r * 0.35, cy - r * 0.25),
          r * 0.48,
          Paint()..color = accent.withValues(alpha: 0.72),
        );
        canvas.drawCircle(
          Offset(size.width * 0.24, size.height * 0.74),
          r * 0.85,
          Paint()..color = Colors.white.withValues(alpha: 0.1),
        );
      case 1:
        canvas.drawCircle(
          Offset(size.width * 0.5, size.height * 0.42),
          r * 0.9,
          Paint()..color = accent.withValues(alpha: 0.22),
        );
        canvas.drawLine(
          Offset(size.width * 0.24, size.height * 0.78),
          Offset(size.width * 0.76, size.height * 0.22),
          Paint()
            ..color = accent.withValues(alpha: 0.8)
            ..strokeWidth = size.width * 0.032
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(
          Offset(size.width * 0.68, size.height * 0.3),
          r * 0.26,
          Paint()..color = accent,
        );
      case 2:
        canvas.drawCircle(
          Offset(size.width * 0.5, size.height * 0.36),
          r * 0.72,
          Paint()..color = accent.withValues(alpha: 0.82),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(size.width * 0.5, size.height * 0.86),
            width: size.width * 1.15,
            height: size.height * 0.46,
          ),
          Paint()..color = primary.withValues(alpha: 0.58),
        );
      case 3:
        canvas.drawRSuperellipse(
          RSuperellipse.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(size.width * 0.5, size.height * 0.44),
              width: size.width * 0.54,
              height: size.height * 0.38,
            ),
            Radius.circular(size.width * 0.08),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.24),
        );
        canvas.drawCircle(
          Offset(size.width * 0.72, size.height * 0.22),
          r * 0.32,
          Paint()..color = accent.withValues(alpha: 0.85),
        );
      case 4:
        canvas.drawCircle(
          Offset(size.width * 0.5, size.height * 0.48),
          r * 0.86,
          Paint()..color = accent.withValues(alpha: 0.75),
        );
        canvas.drawCircle(
          Offset(size.width * 0.5, size.height * 0.48),
          r * 0.55,
          Paint()..color = primary.withValues(alpha: 0.36),
        );
      case 5:
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(
            Offset(size.width * 0.5, size.height * 0.45),
            r * (0.45 + i * 0.35),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2
              ..color = accent.withValues(alpha: 0.55 - i * 0.14),
          );
        }
        canvas.drawCircle(
          Offset(size.width * 0.5, size.height * 0.45),
          r * 0.22,
          Paint()..color = accent,
        );
      case 6:
        final path = Path()
          ..moveTo(size.width * 0.2, size.height * 0.34)
          ..lineTo(size.width * 0.8, size.height * 0.34)
          ..lineTo(size.width * 0.8, size.height * 0.66)
          ..lineTo(size.width * 0.2, size.height * 0.66)
          ..close();
        canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: 0.24));
        canvas.drawCircle(
          Offset(size.width * 0.5, size.height * 0.5),
          r * 0.26,
          Paint()..color = accent.withValues(alpha: 0.9),
        );
      default:
        final star = Path();
        final center = Offset(size.width * 0.5, size.height * 0.44);
        final outer = r * 0.82;
        final inner = r * 0.28;
        for (var i = 0; i < 8; i++) {
          final rad = i * math.pi / 4 - math.pi / 2;
          final dist = i.isEven ? outer : inner;
          final pt = Offset(
            center.dx + math.cos(rad) * dist,
            center.dy + math.sin(rad) * dist,
          );
          if (i == 0) {
            star.moveTo(pt.dx, pt.dy);
          } else {
            star.lineTo(pt.dx, pt.dy);
          }
        }
        star.close();
        canvas.drawPath(star, Paint()..color = accent.withValues(alpha: 0.85));
    }

    // Subtle bottom scrim for badge legibility.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.55, 1.0],
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.34),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_PosterPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

/// Unified Anime Card (user-approved v3 design):
/// Full-bleed poster cover fused together with the bottom text footer inside ONE
/// borderless elevated `22dp` superellipse card — no detached floating captions.
class UnifiedAnimeCard extends StatelessWidget {
  const UnifiedAnimeCard({
    super.key,
    required this.subject,
    required this.onTap,
    this.isTracking = false,
    this.showTopRank = false,
  });

  final AnimeSubject subject;
  final VoidCallback onTap;
  final bool isTracking;
  final bool showTopRank;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final shape = SuperellipseBorder(borderRadius: AppRadius.all(22));
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
            AspectRatio(
              aspectRatio: 0.72,
              child: KonekoPosterArt(
                subject: subject,
                overlayBadges: [
                  if (showTopRank && subject.rank <= 3)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: KonekoChip(
                        label: 'TOP ${subject.rank}',
                        height: 22,
                        fontSize: 10.5,
                        backgroundColor: colorScheme.primary.withValues(alpha: 0.92),
                        foregroundColor: colorScheme.onPrimary,
                      ),
                    ),
                  if (isTracking)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: KonekoChip(
                        label: '在追',
                        height: 22,
                        fontSize: 10.5,
                        leading: KonekoIcon(
                          KonekoIcons.heart,
                          size: 11,
                          color: colorScheme.onPrimary,
                        ),
                        backgroundColor: const Color(0xD9D64C7F),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: KonekoChip(
                      label: subject.score.toStringAsFixed(1),
                      height: 22,
                      fontSize: 11,
                      leading: const KonekoIcon(
                        KonekoIcons.star,
                        size: 11,
                        color: Color(0xFFFFC145),
                      ),
                      backgroundColor: Colors.black.withValues(alpha: 0.58),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.subheadline
                        .of(context, emphasized: true)
                        .copyWith(color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '更至第 ${subject.airedEpisodes} 话 · ${subject.tags.first}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.caption1.of(context).copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
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
    );
  }
}
