import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_polygon.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko/ui/miuix/miuix_bg_effect.dart';
import 'package:koneko/ui/miuix/miuix_frosted_card.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:prism_ui/shapes/shapes.dart' as shapes;
import 'package:url_launcher/url_launcher.dart';

/// 08 · 1:1 FlClash MIUIX About Page with dynamic fluid mesh shader,
/// chromatic cat-ear Logo & Title, floating pills, and frosted glass cards.
class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({
    super.key,
    this.showBack = false,
    this.bottomPadding = 0,
    this.dynamicBackground = true,
  });

  final bool showBack;
  final double bottomPadding;
  final bool dynamicBackground;

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage>
    with SingleTickerProviderStateMixin, RouteSettledMixin<AboutPage> {
  final GlobalKey _backdropKey = GlobalKey();
  final GlobalKey _heroKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0.0);
  late final MiuixBgEffectController _bgController = MiuixBgEffectController(
    vsync: this,
  );

  static const double _heroExtent = 280.0;
  bool _checkingUpdate = false;
  bool _heroHidden = false;
  bool _bgPlaying = false;
  double _bgPeriod = 8.0;
  Animation<double>? _routeAnimation;
  Animation<double>? _coverAnimation;

  @override
  void didSettleRoute() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_routeAnimation != route?.animation) {
      _routeAnimation?.removeStatusListener(_onRouteStatus);
      _routeAnimation = route?.animation;
      _routeAnimation?.addStatusListener(_onRouteStatus);
    }
    if (_coverAnimation != route?.secondaryAnimation) {
      _coverAnimation?.removeStatusListener(_onRouteStatus);
      _coverAnimation = route?.secondaryAnimation;
      _coverAnimation?.addStatusListener(_onRouteStatus);
    }
  }

  void _onRouteStatus(AnimationStatus status) {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _coverAnimation?.removeStatusListener(_onRouteStatus);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollOffset.dispose();
    _bgController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final next = math.max(0.0, _scrollController.offset);
    if ((next - _scrollOffset.value).abs() < 0.5) return;
    _scrollOffset.value = next;
    final hidden = next >= _heroExtent;
    if (hidden != _heroHidden) {
      _heroHidden = hidden;
      _bgController.sync(
        playing: _bgPlaying && !hidden,
        colorInterpPeriod: _bgPeriod,
      );
    }
  }

  double _progressFor(double offset) =>
      (_heroExtent <= 0 ? 0.0 : (offset / _heroExtent)).clamp(0.0, 1.0);

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final check = ref.read(checkForUpdateProvider);
      if (check == null) return;
      final result = await check(kAppVersion);
      if (!mounted) return;
      if (result == null) {
        showKonekoBanner(
          context,
          '当前已是最新版本 v$kAppVersion',
          level: BannerLevel.success,
        );
      } else {
        final open = await showFloatingDialog<bool>(
          context: context,
          child: Builder(
            builder: (dialog) => AlertDialog(
              title: '发现新版本 ${result.version}',
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('稍后'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('查看发布'),
                ),
              ],
            ),
          ),
        );
        if (mounted && open == true) await _openUrl(result.url.toString());
      }
    } on Object {
      if (mounted) {
        showKonekoBanner(context, '检查更新失败，请稍后重试', level: BannerLevel.error);
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Widget _linkRow({
    required Glyph glyph,
    required Color color,
    required String title,
    required String subtitle,
    required String url,
    shapes.RoundedPolygon? shape,
  }) {
    return DecorationListItem(
      leading: KonekoPolygonBadge(
        glyph: glyph,
        shape: shape ?? KonekoPolygons.cookie4Sided,
        size: 38,
        iconSize: 18,
        backgroundColor: color.withValues(alpha: 0.14),
        foregroundColor: color,
      ),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const GlyphIcon(KonekoGlyphs.externalLink, size: 18),
      onPressed: () => unawaited(_openUrl(url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final isWide = !context.isMobileView;
    final preset = MiuixBgConfig.of(isWide: isWide, isDark: isDark);
    final routeMoving =
        !routeSettled ||
        (_routeAnimation?.isAnimating ?? false) ||
        (_coverAnimation?.isAnimating ?? false);
    final pageColor = SurfaceLevel.page.colorOf(colorScheme);

    _bgPlaying =
        widget.dynamicBackground &&
        !context.disableAnimations &&
        PageActivityScope.isActiveOf(context) &&
        ModalRoute.isCurrentOf(context) != false &&
        !routeMoving;
    _bgPeriod = preset.colorInterpPeriod;
    _bgController.sync(
      playing: _bgPlaying && !_heroHidden,
      colorInterpPeriod: _bgPeriod,
    );

    final headlineStyle = AppTextStyle.title1
        .of(context, emphasized: true)
        .copyWith(fontSize: 36, fontWeight: FontWeight.w700, height: 1.28);

    Widget fadeScale(double p, Widget child) {
      final clamped = p.clamp(0.0, 1.0);
      return Opacity(
        opacity: 1.0 - clamped,
        child: Transform.scale(scale: 1.0 - clamped * 0.05, child: child),
      );
    }

    final logo = MiuixChromaticLogo(
      assetPath: 'assets/images/logo.svg',
      size: 98,
      backdropKey: _backdropKey,
      controller: _bgController,
      preset: preset,
    );
    final title = MiuixChromaticTitle(
      text: kAppName,
      style: headlineStyle,
      backdropKey: _backdropKey,
      controller: _bgController,
      preset: preset,
    );
    final badges = Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            KonekoChip(
              label: 'v$kAppVersion',
              height: 26,
              fontSize: 12,
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            KonekoChip(
              label: 'GPL-3.0',
              height: 26,
              fontSize: 12,
              backgroundColor: isDark
                  ? colorScheme.surfaceContainer.withValues(alpha: 0.72)
                  : const Color(0xB8FFFFFF),
              foregroundColor: colorScheme.onSurfaceVariant,
            ),
            KonekoChip(
              label: kPackageName,
              height: 26,
              fontSize: 11.5,
              backgroundColor: isDark
                  ? colorScheme.surfaceContainer.withValues(alpha: 0.72)
                  : const Color(0xB8FFFFFF),
              foregroundColor: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
        const SizedBox(height: 16),
        KonekoRefreshChip(
          label: '检查更新',
          loadingLabel: '正在检查更新…',
          loading: _checkingUpdate,
          height: 40,
          fontSize: 13.5,
          iconSize: 16,
          backgroundColor: isDark
              ? colorScheme.surfaceContainer.withValues(alpha: 0.75)
              : const Color(0xD8FFFFFF),
          foregroundColor: colorScheme.onSurface,
          onPressed: _checkUpdate,
        ),
      ],
    );

    return KonekoScaffold(
      title: '关于',
      showBack: widget.showBack,
      barBackgroundColor: Colors.transparent,
      leadingShadows: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
      body: ArrivalCacheExtentBuilder(
        builder: (context, cacheExtent) => Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: ValueListenableBuilder<double>(
                  valueListenable: _scrollOffset,
                  builder: (context, offset, _) => MiuixAboutBackdrop(
                    backdropKey: _backdropKey,
                    controller: _bgController,
                    preset: preset,
                    alpha: (1.0 - _progressFor(offset)).clamp(0.0, 1.0),
                  ),
                ),
              ),
            ),
            CustomScrollView(
              controller: _scrollController,
              scrollCacheExtent: cacheExtent,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const KonekoScrollStart(),
                SliverToBoxAdapter(
                  child: KeyedSubtree(
                    key: _heroKey,
                    child: ValueListenableBuilder<double>(
                      valueListenable: _scrollOffset,
                      builder: (context, offset, _) {
                        final progress = _progressFor(offset);
                        return Transform.translate(
                          offset: Offset(0, offset * 0.65),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                            child: Column(
                              children: [
                                fadeScale((progress - 0.35) / 0.15, logo),
                                fadeScale((progress - 0.20) / 0.15, title),
                                const SizedBox(height: 4),
                                fadeScale((progress - 0.05) / 0.15, badges),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        8,
                        16,
                        32 +
                            MediaQuery.paddingOf(context).bottom +
                            widget.bottomPadding,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          MiuixFrostedSection(
                            title: '开源致谢',
                            blurEnabled: !routeMoving,
                            items: [
                              _linkRow(
                                glyph: KonekoGlyphs.code,
                                color: colorScheme.primary,
                                title: '项目仓库',
                                subtitle: 'github.com/AKLYILNEA/kk-test',
                                url: kRepoUrl,
                              ),
                              _linkRow(
                                glyph: KonekoGlyphs.palette,
                                color: colorScheme.primary,
                                title: 'prism_ui',
                                subtitle: 'github.com/chen08209/prism_ui',
                                url: kPrismUiUrl,
                              ),
                              _linkRow(
                                glyph: KonekoGlyphs.cpu,
                                color: colorScheme.primary,
                                title: 'Kazumi',
                                subtitle: 'github.com/Predidit/Kazumi',
                                url: kKazumiUrl,
                              ),
                              _linkRow(
                                glyph: KonekoGlyphs.heart,
                                color: colorScheme.primary,
                                title: 'Animeko',
                                subtitle: 'github.com/open-ani/animeko',
                                url: kAnimekoUrl,
                              ),
                            ],
                          ),
                          MiuixFrostedSection(
                            title: '版本信息',
                            blurEnabled: !routeMoving,
                            items: const [
                              DecorationListItem(
                                title: Text('版本'),
                                subtitle: Text('v$kAppVersion'),
                              ),
                              DecorationListItem(
                                title: Text('平台'),
                                subtitle: Text('Android · Windows'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: context.contentTopPadding,
              child: IgnorePointer(
                child: ValueListenableBuilder<double>(
                  valueListenable: _scrollOffset,
                  builder: (context, offset, _) {
                    final barAlpha = ((_progressFor(offset) - 0.35) / 0.65)
                        .clamp(0.0, 1.0);
                    if (barAlpha <= 0.005) return const SizedBox.shrink();
                    return ColoredBox(
                      color: pageColor.withValues(alpha: barAlpha),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
