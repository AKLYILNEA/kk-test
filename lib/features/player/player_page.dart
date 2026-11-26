import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/ui/koneko_icon.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

enum _DrawerTab { episodes, sources, danmaku }

/// 05 · Immersive Liquid Glass Player HUD (UI-First mock playback stage).
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({
    super.key,
    required this.subjectId,
    required this.initialEpisode,
    required this.initialRuleId,
    required this.initialRuleName,
  });

  final int subjectId;
  final int initialEpisode;
  final String initialRuleId;
  final String initialRuleName;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  static const int _durationSeconds = 1425;

  late int _episode = widget.initialEpisode;
  late String _ruleId = widget.initialRuleId;
  late String _ruleName = widget.initialRuleName;
  int _positionSeconds = 360;
  bool _playing = true;
  bool _showHud = true;
  bool _showDanmaku = true;
  bool _drawerOpen = false;
  double _speed = 1.0;
  double _brightness = 0.78;
  bool _showGesturePill = false;
  _DrawerTab _drawerTab = _DrawerTab.episodes;
  Timer? _ticker;
  Timer? _gestureTimer;

  @override
  void initState() {
    super.initState();
    final hist = ref.read(historyProvider.notifier).entryFor(widget.subjectId);
    if (hist != null && hist.lastEpisode == _episode) {
      _positionSeconds = hist.lastPositionSeconds;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_playing || !mounted) return;
      setState(() {
        _positionSeconds = (_positionSeconds + 1).clamp(0, _durationSeconds);
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _gestureTimer?.cancel();
    _persistProgress();
    super.dispose();
  }

  void _persistProgress() {
    final catalog = ref.read(catalogRepositoryProvider);
    final subject = catalog.getSubjectById(widget.subjectId);
    ref.read(historyProvider.notifier).recordProgress(
      subjectId: widget.subjectId,
      episodeNumber: _episode,
      positionSeconds: _positionSeconds,
      durationSeconds: _durationSeconds,
      ruleId: _ruleId,
      ruleName: _ruleName,
    );
    if (subject != null) {
      ref
          .read(libraryProvider.notifier)
          .markEpisodeWatched(subject.subjectId, _episode, subject.totalEpisodes);
    }
  }

  void _adjustBrightness(double delta) {
    setState(() {
      _brightness = (_brightness + delta).clamp(0.15, 1.0);
      _showGesturePill = true;
    });
    _gestureTimer?.cancel();
    _gestureTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _showGesturePill = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogRepositoryProvider);
    final subject =
        catalog.getSubjectById(widget.subjectId) ?? catalog.getAllSubjects().first;
    final episodes = catalog.getEpisodes(
      subject.subjectId,
      watchedCount: _episode - 1,
      currentEp: _episode,
    );
    final probes = catalog.probeSources(subject.subjectId);
    final danmaku = catalog.getDanmaku(subject.subjectId, _episode);

    return ColoredBox(
      color: const Color(0xFF0A0D16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Simulated video canvas with poster palette atmosphere
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              if (_drawerOpen) {
                _drawerOpen = false;
              } else {
                _showHud = !_showHud;
              }
            }),
            onVerticalDragUpdate: (d) => _adjustBrightness(-d.delta.dy * 0.004),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: (0.42 + _brightness * 0.45).clamp(0.0, 1.0),
                  child: KonekoPosterArt(subject: subject),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x88000000),
                        Color(0x22000000),
                        Color(0xAA000000),
                      ],
                    ),
                  ),
                ),
                // Live scrolling mock danmaku overlay
                if (_showDanmaku)
                  IgnorePointer(
                    child: _DanmakuOverlay(
                      items: danmaku,
                      positionSeconds: _positionSeconds,
                    ),
                  ),
                // Center stage status watermark for UI-First MVP
                Center(
                  child: AnimatedOpacity(
                    opacity: _playing ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: _GlassPill(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 10,
                        children: [
                          const KonekoIcon(
                            KonekoIcons.pause,
                            size: 18,
                            color: Colors.white,
                          ),
                          Text(
                            '已暂停 · UI 演示播放器（media_kit 阶段接入真流）',
                            style: AppTextStyle.footnote
                                .of(context, emphasized: true)
                                .copyWith(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Gesture brightness pill
          if (_showGesturePill)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 74,
              left: 0,
              right: 0,
              child: Center(
                child: _GlassPill(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      const KonekoIcon(
                        KonekoIcons.sun,
                        size: 16,
                        color: Colors.white,
                      ),
                      Text(
                        '亮度 ${(_brightness * 100).round()}%',
                        style: AppTextStyle.footnote
                            .of(context, emphasized: true)
                            .copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Top Liquid Glass Pill HUD
          if (_showHud)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Expanded(
                    child: _GlassPill(
                      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
                      child: Row(
                        children: [
                          PressSurface(
                            fill: Colors.white.withValues(alpha: 0.14),
                            shape: AppShape.circle,
                            onPressed: () {
                              _persistProgress();
                              Navigator.of(context).maybePop();
                            },
                            child: const SizedBox.square(
                              dimension: 34,
                              child: Center(
                                child: GlyphIcon(
                                  Glyphs.chevronBack,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${subject.title} · 第 $_episode 话',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyle.subheadline
                                      .of(context, emphasized: true)
                                      .copyWith(color: Colors.white),
                                ),
                                Text(
                                  '$_ruleName · ${_speed.toStringAsFixed(2)}x',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyle.caption2
                                      .of(context)
                                      .copyWith(
                                        color: Colors.white.withValues(alpha: 0.78),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _GlassPill(
                    padding: const EdgeInsets.all(5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 4,
                      children: [
                        _HudSmallBtn(
                          label: _showDanmaku ? '弹幕开' : '弹幕关',
                          active: _showDanmaku,
                          onTap: () =>
                              setState(() => _showDanmaku = !_showDanmaku),
                        ),
                        _HudSmallBtn(
                          label: '选集/源',
                          active: _drawerOpen,
                          onTap: () =>
                              setState(() => _drawerOpen = !_drawerOpen),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Bottom Liquid Glass Pill Controls
          if (_showHud)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 14,
              child: _GlassPill(
                corner: 28,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          formatDurationShort(_positionSeconds),
                          style: AppTextStyle.caption1
                              .of(context, emphasized: true)
                              .copyWith(
                                color: Colors.white,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Slider(
                              min: 0,
                              max: _durationSeconds.toDouble(),
                              value: _positionSeconds.toDouble(),
                              onChanged: (v) => setState(
                                () => _positionSeconds = v.round(),
                              ),
                            ),
                          ),
                        ),
                        Text(
                          formatDurationShort(_durationSeconds),
                          style: AppTextStyle.caption1
                              .of(context, emphasized: true)
                              .copyWith(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        PressSurface(
                          fill: Colors.white.withValues(alpha: 0.16),
                          shape: AppShape.circle,
                          onPressed: () =>
                              setState(() => _playing = !_playing),
                          child: SizedBox.square(
                            dimension: 38,
                            child: Center(
                              child: KonekoIcon(
                                _playing ? KonekoIcons.pause : KonekoIcons.play,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PressSurface(
                          fill: Colors.white.withValues(alpha: 0.12),
                          shape: AppShape.circle,
                          onPressed: () {
                            if (_episode < subject.airedEpisodes) {
                              setState(() {
                                _episode += 1;
                                _positionSeconds = 0;
                              });
                              _persistProgress();
                            }
                          },
                          child: const SizedBox.square(
                            dimension: 38,
                            child: Center(
                              child: KonekoIcon(
                                KonekoIcons.skipNext,
                                size: 17,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        _HudSmallBtn(
                          label: '${_speed.toStringAsFixed(2)}x',
                          active: _speed != 1.0,
                          onTap: () {
                            const speeds = [1.0, 1.25, 1.5, 2.0, 0.75];
                            final next =
                                speeds[(speeds.indexOf(_speed) + 1) % speeds.length];
                            setState(() => _speed = next);
                          },
                        ),
                        const SizedBox(width: 6),
                        _HudSmallBtn(
                          label: '切源',
                          active: _drawerOpen && _drawerTab == _DrawerTab.sources,
                          onTap: () => setState(() {
                            _drawerTab = _DrawerTab.sources;
                            _drawerOpen = true;
                          }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Right-side Snapping Liquid Glass Drawer
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            top: MediaQuery.paddingOf(context).top + 12,
            bottom: MediaQuery.paddingOf(context).bottom + 12,
            right: _drawerOpen ? 12 : -360,
            width: 316,
            child: _GlassPill(
              corner: 28,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedControl<_DrawerTab>(
                    segments: const [
                      (_DrawerTab.episodes, '选集'),
                      (_DrawerTab.sources, '切源'),
                      (_DrawerTab.danmaku, '弹幕'),
                    ],
                    value: _drawerTab,
                    onChanged: (tab) => setState(() => _drawerTab = tab),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: switch (_drawerTab) {
                      _DrawerTab.episodes => GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 1.35,
                        ),
                        itemCount: episodes.length,
                        itemBuilder: (_, index) {
                          final ep = episodes[index];
                          final active = ep.episodeNumber == _episode;
                          return PressSurface(
                            fill: active
                                ? context.colorScheme.primary
                                : Colors.white.withValues(alpha: 0.12),
                            shape: AppShape.md,
                            onPressed: ep.state == EpisodeWatchState.unaired
                                ? null
                                : () {
                                    setState(() {
                                      _episode = ep.episodeNumber;
                                      _positionSeconds = 0;
                                    });
                                    _persistProgress();
                                  },
                            child: Center(
                              child: Text(
                                '${ep.episodeNumber}',
                                style: AppTextStyle.footnote
                                    .of(context, emphasized: true)
                                    .copyWith(color: Colors.white),
                              ),
                            ),
                          );
                        },
                      ),
                      _DrawerTab.sources => ListView.separated(
                        itemCount: probes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final p = probes[index];
                          final active = p.ruleId == _ruleId;
                          return PressSurface(
                            fill: active
                                ? context.colorScheme.primary.withValues(alpha: 0.35)
                                : Colors.white.withValues(alpha: 0.1),
                            shape: AppShape.md,
                            padding: const EdgeInsets.all(12),
                            onPressed: () {
                              setState(() {
                                _ruleId = p.ruleId;
                                _ruleName = p.ruleName;
                              });
                              _persistProgress();
                              showKonekoBanner(
                                context,
                                '已无缝切源至 ${p.ruleName}，保留 ${formatDurationShort(_positionSeconds)} 进度',
                                level: BannerLevel.success,
                              );
                            },
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.ruleName,
                                        style: AppTextStyle.subheadline
                                            .of(context, emphasized: true)
                                            .copyWith(color: Colors.white),
                                      ),
                                      Text(
                                        p.lineLabel,
                                        style: AppTextStyle.caption1
                                            .of(context)
                                            .copyWith(
                                              color: Colors.white
                                                  .withValues(alpha: 0.72),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${p.latencyMs}ms',
                                  style: AppTextStyle.caption1
                                      .of(context, emphasized: true)
                                      .copyWith(color: const Color(0xFF9CF6C8)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      _DrawerTab.danmaku => ListView.separated(
                        itemCount: danmaku.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final d = danmaku[index];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: ShapeDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              shape: AppShape.md,
                            ),
                            child: Text(
                              d.text,
                              style: AppTextStyle.footnote.of(context).copyWith(
                                color: Color(d.colorHex),
                              ),
                            ),
                          );
                        },
                      ),
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DanmakuOverlay extends StatelessWidget {
  const _DanmakuOverlay({
    required this.items,
    required this.positionSeconds,
  });

  final List<DanmakuItem> items;
  final int positionSeconds;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return Stack(
          children: [
            for (var i = 0; i < items.length; i++)
              Positioned(
                top: 90.0 + (items[i].lane % 4) * 34.0,
                left: w - (((positionSeconds * 38 + i * 160) % (w + 320)) - 60),
                child: Text(
                  items[i].text,
                  maxLines: 1,
                  style: AppTextStyle.callout
                      .of(context, emphasized: true)
                      .copyWith(
                        color: Color(items[i].colorHex).withValues(alpha: 0.92),
                        shadows: const [
                          Shadow(
                            color: Color(0xCC000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.corner = 1000,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double corner;

  @override
  Widget build(BuildContext context) {
    final shape = SuperellipseBorder(
      borderRadius: AppRadius.all(corner),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.18), width: 0.8),
    );
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: const Color(0x9E141824),
            shape: shape,
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _HudSmallBtn extends StatelessWidget {
  const _HudSmallBtn({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressSurface(
      fill: active
          ? context.colorScheme.primary
          : Colors.white.withValues(alpha: 0.14),
      shape: AppShape.full,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      onPressed: onTap,
      child: Text(
        label,
        style: AppTextStyle.caption1
            .of(context, emphasized: true)
            .copyWith(color: Colors.white),
      ),
    );
  }
}
