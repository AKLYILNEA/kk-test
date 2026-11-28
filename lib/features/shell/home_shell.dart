import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/about/about_page.dart';
import 'package:koneko/features/discover/discover_page.dart';
import 'package:koneko/features/history/history_page.dart';
import 'package:koneko/features/home/home_page.dart';
import 'package:koneko/features/library/library_page.dart';
import 'package:koneko/features/my/my_page.dart';
import 'package:koneko/features/rules/rules_page.dart';
import 'package:koneko/features/schedule/schedule_page.dart';
import 'package:koneko/features/theme/theme_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

/// Responsive Koneko root shell:
/// - Mobile (`< 720dp`): authentic prism_ui [NavigationDock] (or [NavigationBar])
/// - Desktop / Tablet (`>= 720dp`): authentic prism_ui [NavigationSidebar]
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  static const _mobileDestinations = [
    NavigationDockDestination(glyph: KonekoGlyphs.home, label: '推荐'),
    NavigationDockDestination(glyph: KonekoGlyphs.calendar, label: '时间表'),
    NavigationDockDestination(glyph: KonekoGlyphs.heart, label: '追番'),
    NavigationDockDestination(glyph: KonekoGlyphs.user, label: '我的'),
  ];

  static const _desktopDestinations = [
    SidebarDestination(glyph: KonekoGlyphs.home, label: '推荐'),
    SidebarDestination(glyph: KonekoGlyphs.calendar, label: '时间表'),
    SidebarDestination(glyph: KonekoGlyphs.heart, label: '追番'),
    SidebarDestination(glyph: Glyphs.search, label: '发现搜索'),
    SidebarDestination(glyph: KonekoGlyphs.history, label: '观看历史'),
    SidebarDestination(glyph: KonekoGlyphs.puzzle, label: '规则管理'),
    SidebarDestination(glyph: KonekoGlyphs.palette, label: '外观主题'),
    SidebarDestination(glyph: KonekoGlyphs.info, label: '关于'),
    SidebarDestination(glyph: KonekoGlyphs.user, label: '我的'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = ViewScope.isMobileOf(context);
    final colorScheme = context.colorScheme;
    final mode = ref.watch(
      themeSettingsProvider.select((settings) => settings.tabAnimation),
    );

    if (isMobile) {
      final dockInset = NavigationDock.insetOf(context) + 8;
      final pages = _MobilePages(mode: mode, bottomPadding: dockInset);

      return Surface(
        color: SurfaceLevel.page.colorOf(colorScheme),
        child: Stack(
          fit: StackFit.expand,
          children: [
            pages,
            Align(
              alignment: Alignment.bottomCenter,
              child: Consumer(
                builder: (context, ref, _) => BarItemPresence.held(
                  child: NavigationDock(
                    destinations: _mobileDestinations,
                    selectedIndex: ref.watch(
                      navIndexProvider.select(_mobileIndexOf),
                    ),
                    onSelected: (index) => ref
                        .read(navIndexProvider.notifier)
                        .select(_mobileIndices[index]),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Desktop / Wide layout with authentic prism_ui NavigationSidebar
    final canExpandInline = ViewScope.sizeOf(context).width >= 960;

    return Surface(
      color: SurfaceLevel.page.colorOf(colorScheme),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Surface(
            color: colorScheme.chromeSurface,
            shape: BorderDirectional(end: Divider.createBorderSide(context)),
            child: Consumer(
              builder: (context, ref, _) => NavigationSidebar(
                destinations: _desktopDestinations,
                selectedIndex: ref
                    .watch(navIndexProvider)
                    .clamp(0, _desktopDestinations.length - 1),
                expanded:
                    canExpandInline &&
                    ref.watch(
                      themeSettingsProvider.select(
                        (settings) => settings.sidebarExpanded,
                      ),
                    ),
                onSelected: ref.read(navIndexProvider.notifier).select,
                onToggle: canExpandInline
                    ? () => ref
                          .read(themeSettingsProvider.notifier)
                          .update(
                            (settings) => settings.copyWith(
                              sidebarExpanded: !settings.sidebarExpanded,
                            ),
                          )
                    : null,
              ),
            ),
          ),
          Expanded(child: _DesktopPages(count: _desktopDestinations.length)),
        ],
      ),
    );
  }
}

const _mobileIndices = [0, 1, 2, 8];

int _mobileIndexOf(int index) => index.clamp(0, 3);

class _MobilePages extends ConsumerStatefulWidget {
  const _MobilePages({required this.mode, required this.bottomPadding});

  final TabAnimationMode mode;
  final double bottomPadding;

  @override
  ConsumerState<_MobilePages> createState() => _MobilePagesState();
}

class _MobilePagesState extends ConsumerState<_MobilePages>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  final _pages = <int, Widget>{};

  late int _shown;
  late int _requested;
  int? _preparing;
  _MobilePageMotion? _motion;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this)
      ..addStatusListener(_onMotionStatus);
    _shown = _requested = _mobileIndexOf(ref.read(navIndexProvider));
    _rememberPage(_shown);
    ref.listenManual(navIndexProvider.select(_mobileIndexOf), (_, index) {
      _select(index);
    });
  }

  void _rememberPage(int index) {
    _pages.putIfAbsent(index, () {
      final inset = widget.bottomPadding;
      return PageFocusScope(
        child: switch (index) {
          0 => HomePage(bottomPadding: inset),
          1 => SchedulePage(bottomPadding: inset),
          2 => LibraryPage(bottomPadding: inset),
          _ => MyPage(bottomPadding: inset),
        },
      );
    });
  }

  @override
  void didUpdateWidget(covariant _MobilePages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bottomPadding == oldWidget.bottomPadding) return;
    final visited = _pages.keys.toList();
    _pages.clear();
    for (final index in visited) {
      _rememberPage(index);
    }
  }

  void _select(int index) {
    _requested = index;
    if (context.disableAnimations) {
      _rememberPage(index);
      _showAtRest(index);
      return;
    }
    final motion = _motion;
    if (index == (motion?.destination ?? _shown)) {
      if (_preparing != null) setState(() => _preparing = null);
      return;
    }
    if (motion?.tracks.containsKey(index) ?? false) {
      _retarget(index);
      return;
    }

    // Prepare a new destination behind the current picture while the current
    // transition keeps running. Several taps in one frame need only one paint.
    setState(() => _preparing = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _preparing == index && _requested == index) {
        _retarget(index);
      }
    });
  }

  void _retarget(int destination) {
    final previous = _motion;
    final fade = previous?.fade ?? (widget.mode == TabAnimationMode.fade);
    final current = <int, double>{};
    if (previous == null) {
      current[_shown] = fade ? 1 : 0;
    } else {
      for (final entry in previous.tracks.entries) {
        final value = entry.value.evaluate(_progress);
        if ((fade ? value > 0 : value.abs() < 1) || entry.key == destination) {
          current[entry.key] = value;
        }
      }
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final direction = ((destination > (previous?.destination ?? _shown)) != rtl)
        ? 1.0
        : -1.0;
    final entering = current[destination] ?? (fade ? 0.0 : direction);
    final away = entering == 0 ? -direction : -entering.sign;
    final tracks = {
      if (!current.containsKey(destination))
        destination: Tween<double>(begin: entering, end: fade ? 1 : 0),
      for (final entry in current.entries)
        entry.key: Tween<double>(
          begin: entry.value,
          end: fade
              ? (entry.key == destination ? 1 : 0)
              : (entry.key == destination ? 0 : away),
        ),
    };

    _progress.value = 0;
    setState(() {
      _motion = _MobilePageMotion(destination, fade: fade, tracks: tracks);
      _preparing = null;
    });
    _progress.animateTo(
      1,
      duration: previous != null
          ? const Duration(milliseconds: 180)
          : fade
          ? fadeTabDuration
          : kTabScrollDuration,
      curve: previous != null
          ? Curves.easeOutCubic
          : fade
          ? fadeTabCurve
          : Curves.easeOut,
    );
  }

  void _onMotionStatus(AnimationStatus status) {
    final motion = _motion;
    if (status != AnimationStatus.completed || motion == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_motion, motion)) {
        // A target prepared during this frame still needs its own transition.
        _showAtRest(motion.destination, keepPreparing: true);
      }
    });
  }

  void _showAtRest(int index, {bool keepPreparing = false}) {
    _progress.stop();
    setState(() {
      _shown = index;
      _motion = null;
      if (!keepPreparing) _preparing = null;
    });
  }

  void _finishForTouch(int index) {
    if (_requested == index && _motion?.destination == index) {
      _showAtRest(index);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preparing = _preparing;
    if (preparing != null) _rememberPage(preparing);
    final motion = _motion;
    final visible = [
      ?preparing,
      if (motion == null) _shown else ...motion.tracks.keys,
    ];
    final active = motion == null && preparing == null;
    final order = [
      for (final index in _pages.keys)
        if (!visible.contains(index)) index,
      ...visible,
    ];

    final opacities = <int, Animation<double>>{};
    if (motion != null && motion.fade) {
      var start = 0.0;
      var end = 0.0;
      for (final entry in motion.tracks.entries) {
        start += entry.value.begin!;
        end += entry.value.end!;
        opacities[entry.key] = _TabLayerOpacity(
          weight: entry.value,
          totalThroughLayer: Tween<double>(begin: start, end: end),
        ).animate(_progress);
      }
    }

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final index in order)
            _MobileTabLayer(
              key: ValueKey(index),
              index: index,
              shown: visible.contains(index),
              active: active && index == _shown,
              snapshot: !active && visible.contains(index),
              onTouch: motion?.destination == index && preparing == null
                  ? () => _finishForTouch(index)
                  : null,
              opacity: opacities[index] ?? kAlwaysCompleteAnimation,
              offset: motion?.fade == false && motion!.tracks.containsKey(index)
                  ? Tween<Offset>(
                      begin: Offset(motion.tracks[index]!.begin!, 0),
                      end: Offset(motion.tracks[index]!.end!, 0),
                    ).animate(_progress)
                  : const AlwaysStoppedAnimation(Offset.zero),
              child: _pages[index]!,
            ),
        ],
      ),
    );
  }
}

class _MobilePageMotion {
  const _MobilePageMotion(
    this.destination, {
    required this.fade,
    required this.tracks,
  });

  final int destination;
  final bool fade;
  final Map<int, Tween<double>> tracks;
}

/// Converts a page's share of the final blend to its opacity in the stack.
/// This preserves the visible blend when a fade is retargeted.
class _TabLayerOpacity extends Animatable<double> {
  _TabLayerOpacity({required this.weight, required this.totalThroughLayer});

  final Tween<double> weight;
  final Tween<double> totalThroughLayer;

  @override
  double transform(double t) {
    final remaining = totalThroughLayer.transform(t);
    return remaining <= 0 ? 0 : (weight.transform(t) / remaining).clamp(0, 1);
  }
}

class _MobileTabLayer extends StatefulWidget {
  const _MobileTabLayer({
    super.key,
    required this.index,
    required this.shown,
    required this.active,
    required this.snapshot,
    required this.onTouch,
    required this.opacity,
    required this.offset,
    required this.child,
  });

  final int index;
  final bool shown;
  final bool active;
  final bool snapshot;
  final VoidCallback? onTouch;
  final Animation<double> opacity;
  final Animation<Offset> offset;
  final Widget child;

  @override
  State<_MobileTabLayer> createState() => _MobileTabLayerState();
}

class _MobileTabLayerState extends State<_MobileTabLayer> {
  late final _snapshot = SnapshotController(allowSnapshotting: widget.snapshot);

  @override
  void didUpdateWidget(covariant _MobileTabLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _snapshot.allowSnapshotting = widget.snapshot;
  }

  @override
  void dispose() {
    _snapshot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onTouch = widget.onTouch;
    return Offstage(
      offstage: !widget.shown,
      child: IgnorePointer(
        ignoring: !widget.active && onTouch == null,
        child: ExcludeSemantics(
          excluding: !widget.active,
          child: Listener(
            onPointerDown: onTouch == null ? null : (_) => onTouch(),
            child: SlideTransition(
              position: widget.offset,
              child: FadeTransition(
                opacity: widget.opacity,
                child: RepaintBoundary(
                  child: SnapshotWidget(
                    key: ValueKey('dock-page-snapshot-${widget.index}'),
                    controller: _snapshot,
                    mode: SnapshotMode.permissive,
                    autoresize: true,
                    child: LiquidGlassHost(
                      enabled: widget.shown && LiquidGlassScope.of(context),
                      child: _pageActivity(widget.active, widget.child),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _pageActivity(bool active, Widget child) => PageActivityScope(
  isActive: active,
  child: TickerMode(
    enabled: active,
    child: ExcludeFocus(
      excluding: !active,
      child: KeyboardInsetHold(child: child),
    ),
  ),
);

class _DesktopPages extends ConsumerStatefulWidget {
  const _DesktopPages({required this.count});

  final int count;

  @override
  ConsumerState<_DesktopPages> createState() => _DesktopPagesState();
}

class _DesktopPagesState extends ConsumerState<_DesktopPages> {
  late final _controller = PageController(initialPage: _selectedIndex);
  final _pages = <int, Widget>{};

  int get _selectedIndex =>
      ref.read(navIndexProvider).clamp(0, widget.count - 1);

  @override
  void initState() {
    super.initState();
    final controller = _controller;
    ref.listenManual(navIndexProvider, (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.hasClients) {
          controller.jumpToPage(_selectedIndex);
        }
      });
    });
  }

  Widget _buildPage(int index) => switch (index) {
    0 => const HomePage(),
    1 => const SchedulePage(),
    2 => const LibraryPage(),
    3 => const DiscoverPage(showBack: false),
    4 => const HistoryPage(showBack: false),
    5 => const RulesPage(showBack: false),
    6 => const ThemePage(showBack: false),
    7 => const AboutPage(showBack: false),
    _ => const MyPage(),
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _controller,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.count,
      itemBuilder: (context, index) {
        final page = _pages.putIfAbsent(
          index,
          () => PageFocusScope(child: _buildPage(index)),
        );
        return KeepScope(
          key: ValueKey(index),
          child: Consumer(
            child: page,
            builder: (context, ref, page) {
              final active = ref.watch(
                navIndexProvider.select(
                  (value) => value.clamp(0, widget.count - 1) == index,
                ),
              );
              return _pageActivity(
                active,
                _DesktopStack(active: active, child: page!),
              );
            },
          ),
        );
      },
    );
  }
}

class _DesktopStack extends StatefulWidget {
  const _DesktopStack({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_DesktopStack> createState() => _DesktopStackState();
}

class _DesktopStackState extends State<_DesktopStack> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler(
      enabled: widget.active,
      onPopWithResult: (result) => _navigator.currentState?.pop(result),
      child: Navigator(
        key: _navigator,
        pages: [RootPage(child: widget.child)],
        onDidRemovePage: (_) {},
      ),
    );
  }
}
