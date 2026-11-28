import 'dart:async';

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
      final pages = _ShellPages(
        count: _mobileDestinations.length,
        mode: mode,
        bottomPadding: dockInset,
      );

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
          Expanded(
            child: _ShellPages(
              count: _desktopDestinations.length,
              mode: mode,
              desktop: true,
            ),
          ),
        ],
      ),
    );
  }
}

const _mobileIndices = [0, 1, 2, 8];

int _mobileIndexOf(int index) => index.clamp(0, 3);

// The PageView preserves each destination. For distant switches it swaps the
// outgoing page into the adjacent slot so intermediate pages never flash by.
class _ShellPages extends ConsumerStatefulWidget {
  const _ShellPages({
    required this.count,
    required this.mode,
    this.desktop = false,
    this.bottomPadding = 0,
  });

  final int count;
  final TabAnimationMode mode;
  final double bottomPadding;
  final bool desktop;

  @override
  ConsumerState<_ShellPages> createState() => _ShellPagesState();
}

class _ShellPagesState extends ConsumerState<_ShellPages> {
  late final _controller = PageController(
    initialPage: _mapIndex(ref.read(navIndexProvider)),
  );
  final _pages = <int, Widget>{};
  List<int>? _order;
  int _switch = 0;

  int _mapIndex(int index) =>
      widget.desktop ? index.clamp(0, widget.count - 1) : _mobileIndexOf(index);

  @override
  void initState() {
    super.initState();
    // Read before a selection change can initialize the controller.
    final controller = _controller;
    ref.listenManual(navIndexProvider, (previous, next) {
      final index = _mapIndex(next);
      if (previous != null && index == _mapIndex(previous)) return;
      final request = ++_switch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.hasClients && request == _switch) {
          unawaited(_showPage(index, request));
        }
      });
    });
  }

  @override
  void didUpdateWidget(covariant _ShellPages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bottomPadding != oldWidget.bottomPadding ||
        widget.desktop != oldWidget.desktop) {
      _pages.clear();
    }
  }

  Widget _buildMobilePage(int index, double bottomPadding) => switch (index) {
    0 => HomePage(bottomPadding: bottomPadding),
    1 => SchedulePage(bottomPadding: bottomPadding),
    2 => LibraryPage(bottomPadding: bottomPadding),
    _ => MyPage(bottomPadding: bottomPadding),
  };

  Widget _buildDesktopPage(int index) => switch (index) {
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

  Future<void> _showPage(int index, int request) async {
    if (!_controller.hasClients) return;
    final position = _controller.page?.round() ?? index;
    final current = _order?[position] ?? position;
    if (_order != null) {
      setState(() => _order = null);
      _controller.jumpToPage(current);
    }
    if (widget.desktop || context.disableAnimations) {
      _controller.jumpToPage(index);
      return;
    }
    if ((index - current).abs() > 1) {
      final adjacent = index > current ? index - 1 : index + 1;
      setState(() {
        _order = List.generate(widget.count, (slot) => slot)
          ..[adjacent] = current
          ..[current] = adjacent;
      });
      _controller.jumpToPage(adjacent);
    }
    final fade = widget.mode == TabAnimationMode.fade;
    await _controller.animateToPage(
      index,
      duration: fade ? fadeTabDuration : kTabScrollDuration,
      curve: fade ? fadeTabCurve : Curves.easeOut,
    );
    if (mounted && request == _switch && _order != null) {
      setState(() => _order = null);
    }
  }

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
      findChildIndexCallback: (key) {
        final index = (key as ValueKey<int>).value;
        return _order?.indexOf(index) ?? index;
      },
      itemBuilder: (context, position) {
        final index = _order?[position] ?? position;
        final page = _pages.putIfAbsent(
          index,
          () => PageFocusScope(
            child: widget.desktop
                ? _buildDesktopPage(index)
                : _buildMobilePage(index, widget.bottomPadding),
          ),
        );
        return KeepScope(
          key: ValueKey(index),
          child: Consumer(
            child: page,
            builder: (context, ref, page) {
              final active = ref.watch(
                navIndexProvider.select((value) => _mapIndex(value) == index),
              );
              final body = PageActivityScope(
                isActive: active,
                child: TickerMode(
                  enabled: active,
                  child: ExcludeFocus(
                    excluding: !active,
                    child: KeyboardInsetHold(
                      child: widget.desktop
                          ? _DesktopStack(active: active, child: page!)
                          : page!,
                    ),
                  ),
                ),
              );
              return widget.desktop
                  ? body
                  : _TabPage(
                      controller: _controller,
                      position: position,
                      fade: widget.mode == TabAnimationMode.fade,
                      child: body,
                    );
            },
          ),
        );
      },
    );
  }
}

class _TabPage extends StatefulWidget {
  const _TabPage({
    required this.controller,
    required this.position,
    required this.fade,
    required this.child,
  });

  final PageController controller;
  final int position;
  final bool fade;
  final Widget child;

  @override
  State<_TabPage> createState() => _TabPageState();
}

class _TabPageState extends State<_TabPage> {
  final _fadeOffset = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    if (widget.fade) widget.controller.addListener(_updateFadeOffset);
    _updateFadeOffset();
  }

  @override
  void didUpdateWidget(covariant _TabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fade != widget.fade ||
        oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_updateFadeOffset);
      if (widget.fade) widget.controller.addListener(_updateFadeOffset);
    }
    _updateFadeOffset();
  }

  void _updateFadeOffset() => _fadeOffset.value = widget.fade ? _delta : 0;

  double get _delta {
    final controller = widget.controller;
    if (!controller.hasClients) return 0;
    final metrics = controller.position;
    if (!metrics.hasContentDimensions || metrics.viewportDimension == 0) {
      return 0;
    }
    return (widget.position - metrics.pixels / metrics.viewportDimension).clamp(
      -1.0,
      1.0,
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateFadeOffset);
    _fadeOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlassScope.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ValueListenableBuilder(
      valueListenable: _fadeOffset,
      builder: (_, delta, child) {
        return FractionalTranslation(
          translation: Offset(rtl ? delta : -delta, 0),
          child: Opacity(opacity: 1 - delta.abs(), child: child),
        );
      },
      child: RepaintBoundary(
        child: LiquidGlassHost(enabled: glass, child: widget.child),
      ),
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
