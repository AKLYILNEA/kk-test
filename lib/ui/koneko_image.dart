import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:prism_ui/prism_ui.dart';

/// Persistent disk cache manager dedicated to anime posters and user avatars.
/// Mirrors Kazumi's instant cover loading by retaining up to 1000 images for 30 days.
class KonekoImageCache {
  KonekoImageCache._();

  static const String cacheKey = 'koneko_cover_cache_v1';

  static final CacheManager instance = CacheManager(
    Config(
      cacheKey,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 1000,
    ),
  );

  static const Map<String, String> defaultHeaders = {
    'User-Agent':
        'AKLYILNEA/Koneko/0.0.4 (https://github.com/AKLYILNEA/kk-test)',
    'Referer': 'https://bgm.tv/',
  };
}

/// Disk- and memory-cached network image with DPR-aware downsampled decoding.
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
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: KonekoImageCache.instance,
      httpHeaders: KonekoImageCache.defaultHeaders,
      fit: fit,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      fadeInDuration: const Duration(milliseconds: 120),
      fadeOutDuration: const Duration(milliseconds: 80),
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
    final url = avatarUrl;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodePx = (size * dpr).round().clamp(48, 160);

    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: url == null || url.isEmpty || !url.startsWith('http')
            ? fallback
            : KonekoNetworkImage(
                url: url,
                placeholder: fallback,
                memCacheWidth: decodePx,
                memCacheHeight: decodePx,
              ),
      ),
    );
  }
}
