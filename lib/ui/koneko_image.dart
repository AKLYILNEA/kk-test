import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:koneko/ui/koneko_polygon.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:prism_ui/shapes/shapes.dart' as shapes;

/// Fixed quantized decode width for all anime posters so every page (Home,
/// Schedule, Library, History, Detail, Related) hits the EXACT SAME entry in
/// Flutter's synchronous [ImageCache] with zero re-decoding or flashing.
const int kPosterCacheWidth = 420;
const int kAvatarCacheWidth = 96;

/// Normalizes Bangumi & external cover URLs exactly like Kazumi:
/// upgrades protocol-relative or `http://` URLs to `https://`.
String normalizeKonekoImageUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('//')) return 'https:$trimmed';
  if (trimmed.startsWith('http://')) {
    return 'https://${trimmed.substring('http://'.length)}';
  }
  return trimmed;
}

/// Disk- and memory-cached network image with synchronous Frame-0 memory hits.
///
/// Uses [CachedNetworkImageProvider] wrapped in [ResizeImage.resizeIfNeeded]
/// directly on Flutter's [Image] widget (with `gaplessPlayback: true`) instead
/// of `CachedNetworkImage`'s async `FutureBuilder` wrapper, eliminating the
/// placeholder flash when navigating or scrolling across pages.
class KonekoNetworkImage extends StatelessWidget {
  const KonekoNetworkImage({
    super.key,
    required this.url,
    required this.placeholder,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  final String url;
  final Widget placeholder;
  final BoxFit fit;
  final int? memCacheWidth;
  final int? memCacheHeight;

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeKonekoImageUrl(url);
    if (normalized.isEmpty || !normalized.startsWith('http')) {
      return placeholder;
    }
    final provider = ResizeImage.resizeIfNeeded(
      memCacheWidth,
      memCacheHeight,
      CachedNetworkImageProvider(normalized),
    );
    return Image(
      image: provider,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return placeholder;
      },
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

/// Expressive polygon cached avatar for Bangumi profiles, comments, and cast.
/// Defaults to [KonekoPolygons.cookie9Sided] to align with Kazumi's M3
/// expressive polygon language inside pure FlClash cards.
class KonekoAvatar extends StatelessWidget {
  const KonekoAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.size = 38,
    this.polygon,
    this.backgroundColor,
    this.foregroundColor,
    this.borderSide = BorderSide.none,
  });

  final String name;
  final String? avatarUrl;
  final double size;
  final shapes.RoundedPolygon? polygon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final BorderSide borderSide;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final initial = name.trim().isNotEmpty ? name.trim().substring(0, 1) : '?';
    final fallback = ColoredBox(
      color: backgroundColor ?? colorScheme.primary.withValues(alpha: 0.14),
      child: Center(
        child: Text(
          initial,
          style: AppTextStyle.subheadline
              .of(context, emphasized: true)
              .copyWith(
                fontSize: (size * 0.40).clamp(12.0, 24.0),
                color: foregroundColor ?? colorScheme.primary,
              ),
        ),
      ),
    );
    final url = avatarUrl == null ? '' : normalizeKonekoImageUrl(avatarUrl!);
    final border = KonekoPolygonBorder(
      polygon ?? KonekoPolygons.cookie9Sided,
      side: borderSide,
    );

    return DecoratedBox(
      decoration: ShapeDecoration(shape: border),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: border),
        child: SizedBox.square(
          dimension: size,
          child: url.isEmpty || !url.startsWith('http')
              ? fallback
              : KonekoNetworkImage(
                  url: url,
                  placeholder: fallback,
                  memCacheWidth: kAvatarCacheWidth,
                ),
        ),
      ),
    );
  }
}
