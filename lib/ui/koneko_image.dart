import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

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

/// Disk- and memory-cached network image aligned 1:1 with Kazumi's `NetworkImgLayer`.
/// Uses `CachedNetworkImage`'s default cache manager without custom headers so
/// Bangumi CDN (`lain.bgm.tv`) never rejects requests with 403/timeout.
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
    return CachedNetworkImage(
      imageUrl: normalized,
      fit: fit,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      fadeInDuration: const Duration(milliseconds: 120),
      fadeOutDuration: const Duration(milliseconds: 120),
      useOldImageOnUrlChange: true,
      filterQuality: FilterQuality.medium,
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

/// Circular cached avatar for Bangumi comments and profiles.
class KonekoAvatar extends StatelessWidget {
  const KonekoAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.size = 38,
  });

  final String name;
  final String? avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final initial = name.trim().isNotEmpty ? name.trim().substring(0, 1) : '?';
    final fallback = ColoredBox(
      color: colorScheme.primary.withValues(alpha: 0.14),
      child: Center(
        child: Text(
          initial,
          style: AppTextStyle.subheadline
              .of(context, emphasized: true)
              .copyWith(color: colorScheme.primary),
        ),
      ),
    );
    final url = avatarUrl == null ? '' : normalizeKonekoImageUrl(avatarUrl!);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodePx = (size * dpr).round().clamp(48, 160);

    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: url.isEmpty || !url.startsWith('http')
            ? fallback
            : KonekoNetworkImage(
                url: url,
                placeholder: fallback,
                memCacheWidth: decodePx,
              ),
      ),
    );
  }
}
