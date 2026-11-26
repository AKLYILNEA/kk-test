import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko/ui/miuix/miuix_bg_effect.dart';
import 'package:koneko/ui/miuix/miuix_frosted_card.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// 08 · 1:1 FlClash MIUIX About Page with dynamic fluid mesh shader,
/// chromatic cat-ear Logo & Title, floating pills, and frosted glass cards.
class AboutPage extends StatefulWidget {
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
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage>
    with SingleTickerProviderStateMixin {
  final GlobalKey _backdropKey = GlobalKey();
  final GlobalKey _heroKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  late final MiuixBgEffectController _bgController = MiuixBgEffectController(
    vsync: this,
  );

  static const double _heroExtent = 280.0;
  double _scrollOffset = 0.0;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final next = math.max(0.0, _scrollController.offset);
    setState(() => _scrollOffset = next);
  }

  double get _scrollProgress =>
      (_heroExtent <= 0 ? 0.0 : (_scrollOffset / _heroExtent)).clamp(0.0, 1.0);

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() => _checkingUpdate = false);
    showKonekoBanner(
      context,
      '当前已是最新版本 v$kAppVersion（UI-First 首发版）',
      level: BannerLevel.success,
    );
  }

  Widget _linkRow({
    required Glyph glyph,
    required Color color,
    required String title,
    required String subtitle,
    required String url,
  }) {
    return DecorationListItem(
      leading: Container(
        width: 36,
        height: 36,
        decoration: ShapeDecoration(
          color: color.withValues(alpha: 0.14),
          shape: AppShape.md,
        ),
        child: Center(child: GlyphIcon(glyph, size: 18, color: color)),
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
    final progress = _scrollProgress;

    _bgController.sync(
      playing:
          widget.dynamicBackground &&
          !context.disableAnimations &&
          progress < 1.0,
      colorInterpPeriod: preset.colorInterpPeriod,
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

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: MiuixAboutBackdrop(
            backdropKey: _backdropKey,
            controller: _bgController,
            preset: preset,
            alpha: (1.0 - progress).clamp(0.0, 1.0),
          ),
        ),
        SafeArea(
          bottom: false,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (widget.showBack)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: KonekoCircleButton(
                        glyph: Glyphs.chevronBack,
                        tooltip: '返回',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: KeyedSubtree(
                  key: _heroKey,
                  child: Transform.translate(
                    offset: Offset(0, _scrollOffset * 0.55),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                      child: Column(
                        children: [
                          fadeScale(
                            (progress - 0.35) / 0.15,
                            MiuixChromaticLogo(
                              assetPath: 'assets/images/logo.svg',
                              size: 98,
                              backdropKey: _backdropKey,
                              controller: _bgController,
                              preset: preset,
                            ),
                          ),
                          fadeScale(
                            (progress - 0.20) / 0.15,
                            MiuixChromaticTitle(
                              text: kAppName,
                              style: headlineStyle,
                              backdropKey: _backdropKey,
                              controller: _bgController,
                              preset: preset,
                            ),
                          ),
                          const SizedBox(height: 4),
                          fadeScale(
                            (progress - 0.05) / 0.15,
                            Column(
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
                                          ? colorScheme.surfaceContainer
                                              .withValues(alpha: 0.72)
                                          : const Color(0xB8FFFFFF),
                                      foregroundColor:
                                          colorScheme.onSurfaceVariant,
                                    ),
                                    KonekoChip(
                                      label: kPackageName,
                                      height: 26,
                                      fontSize: 11.5,
                                      backgroundColor: isDark
                                          ? colorScheme.surfaceContainer
                                              .withValues(alpha: 0.72)
                                          : const Color(0xB8FFFFFF),
                                      foregroundColor:
                                          colorScheme.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                KonekoChip(
                                  label: _checkingUpdate ? '正在检查更新...' : '检查更新',
                                  height: 40,
                                  fontSize: 13.5,
                                  leading: GlyphIcon(
                                    KonekoGlyphs.refresh,
                                    size: 16,
                                    color: colorScheme.primary,
                                  ),
                                  backgroundColor: isDark
                                      ? colorScheme.surfaceContainer
                                          .withValues(alpha: 0.75)
                                      : const Color(0xD8FFFFFF),
                                  foregroundColor: colorScheme.onSurface,
                                  onPressed: _checkUpdate,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    32 + MediaQuery.paddingOf(context).bottom + widget.bottomPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MiuixFrostedSection(
                        title: '项目与架构',
                        items: [
                          _linkRow(
                            glyph: KonekoGlyphs.code,
                            color: colorScheme.primary,
                            title: 'Koneko 测试仓库',
                            subtitle: 'github.com/AKLYILNEA/kk-test',
                            url: kRepoUrl,
                          ),
                          _linkRow(
                            glyph: KonekoGlyphs.palette,
                            color: colorScheme.primary,
                            title: 'UI 设计引擎 · prism_ui',
                            subtitle: 'github.com/chen08209/prism_ui',
                            url: kPrismUiUrl,
                          ),
                          _linkRow(
                            glyph: KonekoGlyphs.cpu,
                            color: colorScheme.primary,
                            title: '核心播放与规则兼容 · Kazumi',
                            subtitle: 'github.com/Predidit/Kazumi',
                            url: kKazumiUrl,
                          ),
                          _linkRow(
                            glyph: KonekoGlyphs.heart,
                            color: colorScheme.primary,
                            title: '多源合并体验参考 · Animeko',
                            subtitle: 'github.com/open-ani/animeko',
                            url: kAnimekoUrl,
                          ),
                        ],
                      ),
                      const MiuixFrostedSection(
                        title: '构建说明',
                        items: [
                          DecorationListItem(
                            title: Text('严格 UI / Core 剥离'),
                            subtitle: Text(
                              '当前 v0.0.1 为 UI-First 预览构建（koneko_contract + koneko_mock），下一阶段无缝接入 Kazumi 真核心。',
                            ),
                          ),
                          DecorationListItem(
                            title: Text('支持平台'),
                            subtitle: Text('Android arm64-v8a · Windows x64'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
