import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/about/about_page.dart';
import 'package:koneko/features/history/history_page.dart';
import 'package:koneko/features/my/offline_page.dart';
import 'package:koneko/features/my/service_settings_page.dart';
import 'package:koneko/features/rules/rules_page.dart';
import 'package:koneko/features/theme/theme_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_image.dart';
import 'package:koneko/ui/koneko_polygon.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:prism_ui/shapes/shapes.dart' as shapes;

const _kBangumiRose = Color(0xFFF09199);
const _kBangumiRoseDeep = Color(0xFFD95B6A);

/// My / Space Hub Page:
/// - Handsome Bangumi hero card on top with expressive `cookie9Sided` polygon
///   avatar, `cookie12Sided` ambient watermark, and integrated watch stats.
/// - Kazumi's expressive polygon bento grid (sculpted Rules hero with
///   `clover4Leaf` badge + 2-column tool tiles + expressive polygon grouped
///   sections) rendered 100% with pure FlClash (`prism_ui`) surfaces.
class MyPage extends ConsumerWidget {
  const MyPage({super.key, this.bottomPadding = 0});

  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final rules = ref.watch(rulesProvider);
    final history = ref.watch(historyProvider);
    final library = ref.watch(libraryProvider);
    final profile = ref.watch(bangumiProfileProvider).value;
    final offlineEntries =
        ref.watch(offlineUpdatesProvider).value ??
        ref.watch(offlineLibraryProvider)?.entries ??
        const <OfflineEpisode>[];

    final enabledRules = rules.where((r) => r.enabled).length;
    final watchingCount = library
        .where((e) => e.status == CollectionStatus.watching)
        .length;
    final watchedSubjects = <int>{
      for (final h in history) h.subjectId,
      for (final c in library)
        if (c.watchedEpisodes > 0 || c.status == CollectionStatus.watched)
          c.subjectId,
    }.length;
    final watchedEpisodes = library.fold<int>(
      0,
      (sum, entry) => sum + entry.watchedEpisodes,
    );

    void openHistory() =>
        BaseNavigator.push<void>(context, const HistoryPage(showBack: true));
    void openRules() =>
        BaseNavigator.push<void>(context, const RulesPage(showBack: true));
    void openSync() =>
        BaseNavigator.push<void>(context, const ServiceSettingsPage());
    void openOffline() =>
        BaseNavigator.push<void>(context, const OfflinePage());
    void openTheme() => BaseNavigator.push<void>(context, const ThemePage());
    void openAbout() =>
        BaseNavigator.push<void>(context, const AboutPage(showBack: true));

    return KonekoScaffold(
      title: '我的',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;
          final horizontalPad = isWide ? 24.0 : 16.0;

          final bangumiHero = _BangumiHeroCard(
            profile: profile,
            watchingCount: watchingCount,
            watchedSubjects: watchedSubjects,
            watchedEpisodes: watchedEpisodes,
            showInlineStats: !isWide,
            onPressed: openSync,
          );

          final statsPanel = _WatchFootprintCard(
            watchingCount: watchingCount,
            watchedSubjects: watchedSubjects,
            watchedEpisodes: watchedEpisodes,
          );

          final rulesHeroTile = _ExpressiveRulesTile(
            enabledRules: enabledRules,
            totalRules: rules.length,
            onPressed: openRules,
          );

          final historyTile = _ExpressiveToolTile(
            glyph: KonekoGlyphs.history,
            shape: KonekoPolygons.cookie6Sided,
            title: '观看历史',
            caption: history.isEmpty
                ? '暂无观看记录'
                : '共 ${history.length} 部番剧足迹',
            accent: colorScheme.primary,
            onPressed: openHistory,
          );

          final offlineTile = _ExpressiveToolTile(
            glyph: KonekoGlyphs.download,
            shape: KonekoPolygons.cookie4Sided,
            title: '离线缓存',
            caption: offlineEntries.isEmpty
                ? '管理本地下载剧集'
                : '已缓存 ${offlineEntries.length} 话',
            accent: const Color(0xFF2B8A6E),
            onPressed: openOffline,
          );

          final toolsPair = _AdaptivePair(
            first: historyTile,
            second: offlineTile,
          );

          return CustomScrollView(
            slivers: [
              const KonekoScrollStart(),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPad,
                  4,
                  horizontalPad,
                  28 + bottomPadding,
                ),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (isWide) ...[
                            _AdaptivePair(
                              gap: 14,
                              first: bangumiHero,
                              second: statsPanel,
                            ),
                            const SizedBox(height: 14),
                            _AdaptivePair(
                              gap: 14,
                              first: rulesHeroTile,
                              second: toolsPair,
                            ),
                            const SizedBox(height: 14),
                            _AdaptivePair(
                              gap: 14,
                              first: _ExpressivePrefsPanel(
                                onTheme: openTheme,
                                onSync: openSync,
                                onAbout: openAbout,
                              ),
                              second: KonekoCard(
                                corner: 28,
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  spacing: 12,
                                  children: [
                                    Row(
                                      spacing: 10,
                                      children: [
                                        KonekoPolygonBadge(
                                          glyph: KonekoGlyphs.info,
                                          shape: KonekoPolygons.softBurst,
                                          size: 40,
                                          iconSize: 19,
                                          backgroundColor: colorScheme.primary
                                              .withValues(alpha: 0.13),
                                          foregroundColor: colorScheme.primary,
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            spacing: 2,
                                            children: [
                                              Text(
                                                '关于 Koneko',
                                                style: AppTextStyle.headline
                                                    .of(
                                                      context,
                                                      emphasized: true,
                                                    )
                                                    .copyWith(
                                                      color:
                                                          colorScheme.onSurface,
                                                    ),
                                              ),
                                              Text(
                                                'v$kAppVersion · 纯净追番体验',
                                                style: AppTextStyle.caption1
                                                    .of(context)
                                                    .copyWith(
                                                      color: colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        KonekoChip(
                                          label: '查看详情',
                                          height: 30,
                                          fontSize: 12,
                                          onPressed: openAbout,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ] else ...[
                            bangumiHero,
                            const SizedBox(height: 12),
                            rulesHeroTile,
                            const SizedBox(height: 12),
                            toolsPair,
                            KonekoSection(
                              title: '偏好与服务',
                              items: [
                                DecorationListItem(
                                  leading: KonekoPolygonBadge(
                                    glyph: KonekoGlyphs.palette,
                                    shape: KonekoPolygons.flower,
                                    size: 36,
                                    iconSize: 18,
                                    backgroundColor: colorScheme.primary
                                        .withValues(alpha: 0.13),
                                    foregroundColor: colorScheme.primary,
                                  ),
                                  title: const Text('外观主题'),
                                  subtitle: const Text('主题色、字体与弹幕'),
                                  trailing: const GlyphIcon(
                                    Glyphs.chevronForward,
                                  ),
                                  onPressed: openTheme,
                                ),
                                DecorationListItem(
                                  leading: KonekoPolygonBadge(
                                    glyph: KonekoGlyphs.cloud,
                                    shape: KonekoPolygons.cookie9Sided,
                                    size: 36,
                                    iconSize: 18,
                                    backgroundColor: _kBangumiRose.withValues(
                                      alpha: 0.18,
                                    ),
                                    foregroundColor: _kBangumiRoseDeep,
                                  ),
                                  title: const Text('同步设置'),
                                  subtitle: const Text('Bangumi / WebDAV'),
                                  trailing: const GlyphIcon(
                                    Glyphs.chevronForward,
                                  ),
                                  onPressed: openSync,
                                ),
                              ],
                            ),
                            KonekoSection(
                              title: '关于',
                              items: [
                                DecorationListItem(
                                  leading: KonekoPolygonBadge(
                                    glyph: KonekoGlyphs.info,
                                    shape: KonekoPolygons.softBurst,
                                    size: 36,
                                    iconSize: 18,
                                    backgroundColor: colorScheme.primary
                                        .withValues(alpha: 0.13),
                                    foregroundColor: colorScheme.primary,
                                  ),
                                  title: const Text('关于 Koneko'),
                                  subtitle: const Text('v$kAppVersion'),
                                  trailing: const GlyphIcon(
                                    Glyphs.chevronForward,
                                  ),
                                  onPressed: openAbout,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Handsome Bangumi profile hero card modeled 1:1 after FlClash's
/// `CurrentOutboundCard` startup widget: crisp [SurfaceLevel.card] fill with
/// one giant clipped `cookie12Sided` flower sweeping out of the top-right edge,
/// paired with a `cookie9Sided` polygon avatar and integrated watch stats.
class _BangumiHeroCard extends StatelessWidget {
  const _BangumiHeroCard({
    required this.profile,
    required this.watchingCount,
    required this.watchedSubjects,
    required this.watchedEpisodes,
    required this.showInlineStats,
    required this.onPressed,
  });

  static const _decorationGrowth = 0.06;
  static const _decorationTurn = 2 * math.pi / 12;
  static const _decorationBottomGap = 10.0;

  final BangumiProfile? profile;
  final int watchingCount;
  final int watchedSubjects;
  final int watchedEpisodes;
  final bool showInlineStats;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final cardColor = SurfaceLevel.card.colorOf(colorScheme);
    final toneColor = SurfaceLevel.block.colorOf(colorScheme);
    final isBound = profile != null;
    final displayName = (profile?.nickname.trim().isNotEmpty ?? false)
        ? profile!.nickname
        : 'Bangumi 番组计划';
    final handleText = profile != null
        ? (profile!.username.isNotEmpty
              ? '@${profile!.username}${profile!.id > 0 ? ' · ID ${profile!.id}' : ''}'
              : 'ID ${profile!.id}')
        : '点击绑定账号，云端同步追番与进度';
    final signText = profile?.sign.trim() ?? '';

    final shape = SuperellipseBorder(borderRadius: AppRadius.all(30));
    final decorationSize = showInlineStats ? 216.0 : 256.0;
    final decorationEnd = showInlineStats ? -48.0 : -52.0;
    final decorationBottom =
        _decorationBottomGap + decorationSize * _decorationGrowth / 2;

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: konekoCardShadows(colorScheme),
      ),
      child: PressSurface(
        fill: cardColor,
        shape: shape,
        clipsChild: true,
        onPressed: onPressed,
        child: Stack(
          children: [
            // 1:1 FlClash CurrentOutboundCard sweeping top-right cookie-12 motif
            Positioned.fill(
              child: IgnorePointer(
                child: ClipPath(
                  clipper: ShapeBorderClipper(
                    shape: shape,
                    textDirection: Directionality.of(context),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      PositionedDirectional(
                        end: decorationEnd,
                        bottom: decorationBottom,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: isBound ? 1 : 0),
                          duration: context.motionDuration(
                            const Duration(milliseconds: 450),
                          ),
                          curve: Curves.easeOutBack,
                          builder: (_, progress, _) => Transform.rotate(
                            angle: _decorationTurn * progress,
                            child: Transform.scale(
                              scale: 1 + _decorationGrowth * progress,
                              child: SizedBox.square(
                                dimension: decorationSize,
                                child: DecoratedBox(
                                  decoration: ShapeDecoration(
                                    color: Color.lerp(
                                      Color.alphaBlend(
                                        _kBangumiRose.withValues(
                                          alpha: isDark ? 0.11 : 0.08,
                                        ),
                                        toneColor,
                                      ),
                                      Color.alphaBlend(
                                        _kBangumiRose.withValues(
                                          alpha: isDark ? 0.18 : 0.13,
                                        ),
                                        cardColor,
                                      ),
                                      progress.clamp(0, 1),
                                    ),
                                    shape: KonekoPolygonBorder(
                                      KonekoPolygons.cookie12Sided,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SurfaceScope(
              level: SurfaceLevel.card,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (isBound && profile!.avatarUrl.isNotEmpty)
                          KonekoAvatar(
                            name: displayName,
                            avatarUrl: profile!.avatarUrl,
                            size: 62,
                            polygon: KonekoPolygons.cookie9Sided,
                            backgroundColor: _kBangumiRose.withValues(
                              alpha: 0.22,
                            ),
                            foregroundColor: _kBangumiRoseDeep,
                            borderSide: BorderSide(
                              color: _kBangumiRose.withValues(alpha: 0.55),
                              width: 1.5,
                            ),
                          )
                        else
                          KonekoPolygonBadge(
                            shape: KonekoPolygons.sunny,
                            size: 62,
                            backgroundColor: _kBangumiRose.withValues(
                              alpha: isDark ? 0.24 : 0.22,
                            ),
                            foregroundColor: _kBangumiRoseDeep,
                            borderSide: BorderSide(
                              color: _kBangumiRose.withValues(alpha: 0.42),
                              width: 1.2,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const GlyphIcon(
                                  KonekoGlyphs.star,
                                  size: 20,
                                  color: _kBangumiRoseDeep,
                                  fill: 1,
                                ),
                                Text(
                                  'bgm',
                                  style: AppTextStyle.caption2
                                      .of(context, emphasized: true)
                                      .copyWith(
                                        fontSize: 10,
                                        height: 1.05,
                                        color: _kBangumiRoseDeep,
                                        letterSpacing: 0.4,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 4,
                            children: [
                              Row(
                                spacing: 6,
                                children: [
                                  Flexible(
                                    child: Text(
                                      displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyle.title3
                                          .of(context, emphasized: true)
                                          .copyWith(
                                            color: colorScheme.onSurface,
                                          ),
                                    ),
                                  ),
                                  KonekoChip(
                                    label: 'bgm.tv',
                                    height: 20,
                                    fontSize: 10,
                                    backgroundColor: _kBangumiRose.withValues(
                                      alpha: isDark ? 0.24 : 0.18,
                                    ),
                                    foregroundColor: isDark
                                        ? _kBangumiRose
                                        : _kBangumiRoseDeep,
                                  ),
                                ],
                              ),
                              Text(
                                handleText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyle.footnote
                                    .of(context)
                                    .copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              if (signText.isNotEmpty)
                                Text(
                                  signText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyle.caption1
                                      .of(context)
                                      .copyWith(
                                        color: colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.8),
                                      ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        KonekoChip(
                          label: isBound ? '已绑定' : '去绑定',
                          height: 28,
                          fontSize: 11.5,
                          backgroundColor: isBound
                              ? colorScheme.successContainer
                              : _kBangumiRose.withValues(
                                  alpha: isDark ? 0.24 : 0.18,
                                ),
                          foregroundColor: isBound
                              ? colorScheme.onSuccessContainer
                              : (isDark ? _kBangumiRose : _kBangumiRoseDeep),
                          trailing: GlyphIcon(
                            Glyphs.chevronForward,
                            size: 12,
                            color: isBound
                                ? colorScheme.onSuccessContainer
                                : (isDark ? _kBangumiRose : _kBangumiRoseDeep),
                          ),
                        ),
                      ],
                    ),
                    if (showInlineStats) ...[
                      const SizedBox(height: 14),
                      _InlineStatsStrip(
                        watchingCount: watchingCount,
                        watchedSubjects: watchedSubjects,
                        watchedEpisodes: watchedEpisodes,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineStatsStrip extends StatelessWidget {
  const _InlineStatsStrip({
    required this.watchingCount,
    required this.watchedSubjects,
    required this.watchedEpisodes,
  });

  final int watchingCount;
  final int watchedSubjects;
  final int watchedEpisodes;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return KonekoBlock(
      corner: 20,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      color: SurfaceLevel.block.colorOf(colorScheme).withValues(alpha: 0.82),
      child: Row(
        children: [
          KonekoPolygonBadge(
            glyph: KonekoGlyphs.star,
            shape: KonekoPolygons.sunny,
            size: 32,
            iconSize: 15,
            fill: 1,
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatMetric(value: watchingCount, label: '在看番剧'),
          ),
          Container(
            width: 1,
            height: 24,
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
          Expanded(
            child: _StatMetric(value: watchedSubjects, label: '看过番剧'),
          ),
          Container(
            width: 1,
            height: 24,
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
          Expanded(
            child: _StatMetric(value: watchedEpisodes, label: '观看集数'),
          ),
        ],
      ),
    );
  }
}

class _WatchFootprintCard extends StatelessWidget {
  const _WatchFootprintCard({
    required this.watchingCount,
    required this.watchedSubjects,
    required this.watchedEpisodes,
  });

  final int watchingCount;
  final int watchedSubjects;
  final int watchedEpisodes;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return KonekoCard(
      corner: 30,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            spacing: 10,
            children: [
              KonekoPolygonBadge(
                glyph: KonekoGlyphs.star,
                shape: KonekoPolygons.sunny,
                size: 36,
                iconSize: 16,
                fill: 1,
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              Text(
                '观看足迹',
                style: AppTextStyle.headline
                    .of(context, emphasized: true)
                    .copyWith(color: colorScheme.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatMetric(
                  value: watchingCount,
                  label: '在看番剧',
                  large: true,
                ),
              ),
              Expanded(
                child: _StatMetric(
                  value: watchedSubjects,
                  label: '看过番剧',
                  large: true,
                ),
              ),
              Expanded(
                child: _StatMetric(
                  value: watchedEpisodes,
                  label: '观看集数',
                  large: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatMetric extends StatelessWidget {
  const _StatMetric({
    required this.value,
    required this.label,
    this.large = false,
  });

  final int value;
  final String label;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$value',
            style: (large ? AppTextStyle.title1 : AppTextStyle.headline)
                .of(context, emphasized: true)
                .copyWith(
                  color: colorScheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.caption2
              .of(context)
              .copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Kazumi-inspired expressive primary hero tile for Rules Management,
/// with asymmetric sculpted corner (`topRight: 52`) and large `clover4Leaf`
/// polygon badge, built on FlClash [PressSurface].
class _ExpressiveRulesTile extends StatelessWidget {
  const _ExpressiveRulesTile({
    required this.enabledRules,
    required this.totalRules,
    required this.onPressed,
  });

  final int enabledRules;
  final int totalRules;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    const shape = SuperellipseBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(28),
        topRight: Radius.circular(56),
        bottomLeft: Radius.circular(28),
        bottomRight: Radius.circular(28),
      ),
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: konekoCardShadows(colorScheme),
      ),
      child: PressSurface(
        fill: colorScheme.primary,
        shape: shape,
        clipsChild: true,
        onPressed: onPressed,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '规则管理',
                      style: AppTextStyle.title3
                          .of(context, emphasized: true)
                          .copyWith(color: colorScheme.onPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '已启用 $enabledRules / $totalRules · 管理番剧播放源',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(
                            color: colorScheme.onPrimary.withValues(
                              alpha: 0.86,
                            ),
                          ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: 46,
                      height: 28,
                      decoration: ShapeDecoration(
                        color: colorScheme.onPrimary,
                        shape: AppShape.full,
                      ),
                      child: Center(
                        child: GlyphIcon(
                          Glyphs.chevronForward,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              KonekoPolygonBadge(
                glyph: KonekoGlyphs.puzzle,
                shape: KonekoPolygons.clover4Leaf,
                size: 72,
                iconSize: 32,
                backgroundColor: colorScheme.onPrimary.withValues(alpha: 0.18),
                foregroundColor: colorScheme.onPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kazumi-style expressive tool bento card (History / Offline) in FlClash style
/// with a distinct polygon icon badge and crisp arrow cue.
class _ExpressiveToolTile extends StatelessWidget {
  const _ExpressiveToolTile({
    required this.glyph,
    required this.shape,
    required this.title,
    required this.caption,
    required this.accent,
    required this.onPressed,
  });

  final Glyph glyph;
  final shapes.RoundedPolygon shape;
  final String title;
  final String caption;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return KonekoCard(
      corner: 26,
      padding: const EdgeInsets.all(16),
      onPressed: onPressed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              KonekoPolygonBadge(
                glyph: glyph,
                shape: shape,
                size: 42,
                iconSize: 20,
                backgroundColor: accent.withValues(alpha: 0.14),
                foregroundColor: accent,
              ),
              const Spacer(),
              GlyphIcon(
                Glyphs.chevronForward,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.headline
                .of(context, emphasized: true)
                .copyWith(color: colorScheme.onSurface),
          ),
          const SizedBox(height: 3),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Wide-screen preferences bento panel mirroring Kazumi's 3-way connected
/// expressive action strip in pure FlClash style.
class _ExpressivePrefsPanel extends StatelessWidget {
  const _ExpressivePrefsPanel({
    required this.onTheme,
    required this.onSync,
    required this.onAbout,
  });

  final VoidCallback onTheme;
  final VoidCallback onSync;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final items = [
      (
        '外观主题',
        KonekoGlyphs.palette,
        KonekoPolygons.flower,
        colorScheme.primary,
        onTheme,
      ),
      (
        '同步设置',
        KonekoGlyphs.cloud,
        KonekoPolygons.cookie9Sided,
        _kBangumiRoseDeep,
        onSync,
      ),
      (
        '关于',
        KonekoGlyphs.info,
        KonekoPolygons.softBurst,
        colorScheme.primary,
        onAbout,
      ),
    ];

    return KonekoCard(
      corner: 28,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '偏好与服务',
            style: AppTextStyle.headline
                .of(context, emphasized: true)
                .copyWith(color: colorScheme.onSurface),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: PressSurface(
                      fill: SurfaceLevel.block.colorOf(colorScheme),
                      shape: SuperellipseBorder(
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(i == 0 ? 20 : 10),
                          right: Radius.circular(
                            i == items.length - 1 ? 20 : 10,
                          ),
                        ),
                      ),
                      clipsChild: true,
                      onPressed: items[i].$5,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 14,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 8,
                          children: [
                            KonekoPolygonBadge(
                              glyph: items[i].$2,
                              shape: items[i].$3,
                              size: 40,
                              iconSize: 19,
                              backgroundColor: items[i].$4.withValues(
                                alpha: 0.14,
                              ),
                              foregroundColor: items[i].$4,
                            ),
                            Text(
                              items[i].$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.footnote
                                  .of(context, emphasized: true)
                                  .copyWith(color: colorScheme.onSurface),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdaptivePair extends StatelessWidget {
  const _AdaptivePair({
    required this.first,
    required this.second,
    this.gap = 12,
  });

  final Widget first;
  final Widget second;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: first),
          SizedBox(width: gap),
          Expanded(child: second),
        ],
      ),
    );
  }
}
