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
    SidebarDestination(glyph: KonekoGlyphs.history, label: '历史记录'),
    SidebarDestination(glyph: KonekoGlyphs.puzzle, label: '规则管理'),
    SidebarDestination(glyph: KonekoGlyphs.palette, label: '外观主题'),
    SidebarDestination(glyph: KonekoGlyphs.info, label: '关于'),
    SidebarDestination(glyph: KonekoGlyphs.user, label: '我的'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = ViewScope.isMobileOf(context);
    final colorScheme = context.colorScheme;
    final settings = ref.watch(themeSettingsProvider);
    final rawIndex = ref.watch(navIndexProvider);
    final navNotifier = ref.read(navIndexProvider.notifier);

    if (isMobile) {
      const mobileIndices = [0, 1, 2, 8];
      final mobileIndex = rawIndex < 3 ? rawIndex : 3;
      void select(int index) => navNotifier.select(mobileIndices[index]);
      final dockInset = settings.floatingNavigationBar
          ? NavigationDock.insetOf(context) + 8
          : 0.0;

      final pages = _ShellPages(
        index: mobileIndex,
        count: _mobileDestinations.length,
        mode: settings.tabAnimation,
        pageBuilder: (_, index) => _buildMobilePage(index, dockInset),
      );

      return Surface(
        color: SurfaceLevel.page.colorOf(colorScheme),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  pages,
                  if (settings.floatingNavigationBar)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: BarItemPresence.held(
                        child: NavigationDock(
                          destinations: _mobileDestinations,
                          selectedIndex: mobileIndex,
                          onSelected: select,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!settings.floatingNavigationBar)
              NavigationBar(
                selectedIndex: mobileIndex,
                onDestinationSelected: select,
                destinations: [
                  for (final (index, destination)
                      in _mobileDestinations.indexed)
                    NavigationDestination(
                      icon: AnimatedGlyph(
                        glyph: destination.glyph,
                        filled: index == mobileIndex,
                      ),
                      label: destination.label,
                    ),
                ],
              ),
          ],
        ),
      );
    }

    // Desktop / Wide layout with authentic prism_ui NavigationSidebar
    final desktopIndex = rawIndex.clamp(0, _desktopDestinations.length - 1);
    final canExpandInline = ViewScope.sizeOf(context).width >= 960;

    return Surface(
      color: SurfaceLevel.page.colorOf(colorScheme),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Surface(
            color: colorScheme.chromeSurface,
            shape: BorderDirectional(end: Divider.createBorderSide(context)),
            child: NavigationSidebar(
              destinations: _desktopDestinations,
              selectedIndex: desktopIndex,
              expanded: canExpandInline && settings.sidebarExpanded,
              onSelected: navNotifier.select,
              onToggle: canExpandInline
                  ? () => ref
                        .read(themeSettingsProvider.notifier)
                        .update(
                          (s) =>
                              s.copyWith(sidebarExpanded: !s.sidebarExpanded),
                        )
                  : null,
            ),
          ),
          Expanded(
            child: _ShellPages(
              index: desktopIndex,
              count: _desktopDestinations.length,
              mode: settings.tabAnimation,
              desktop: true,
              pageBuilder: (_, index) => _buildDesktopPage(index),
            ),
          ),
        ],
      ),
    );
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
}

// The PageView preserves each destination. For distant switches it swaps the
// outgoing page into the adjacent slot so intermediate pages never flash by.
class _ShellPages extends StatefulWidget {
  const _ShellPages({
    required this.index,
    required this.count,
    required this.mode,
    required this.pageBuilder,
    this.desktop = false,
  });

  final int index;
  final int count;
  final TabAnimationMode mode;
  final IndexedWidgetBuilder pageBuilder;
  final bool desktop;

  @override
  State<_ShellPages> createState() => _ShellPagesState();
}

class _ShellPagesState extends State<_ShellPages> {
  late final _controller = PageController(initialPage: widget.index);
  List<int>? _order;
  int _switch = 0;

  @override
  void didUpdateWidget(covariant _ShellPages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      final request = ++_switch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && request == _switch) {
          _showPage(widget.index, request);
        }
      });
    }
  }

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
        final active = index == widget.index;
        Widget page = PageFocusScope(child: widget.pageBuilder(context, index));
        if (widget.desktop) {
          page = _DesktopStack(active: active, child: page);
        }
        return KeepScope(
          key: ValueKey(index),
          child: _TabPage(
            controller: _controller,
            position: position,
            fade: !widget.desktop && widget.mode == TabAnimationMode.fade,
            active: active,
            child: PageActivityScope(
              isActive: active,
              child: TickerMode(
                enabled: active,
                child: ExcludeFocus(excluding: !active, child: page),
              ),
            ),
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
    required this.active,
    required this.child,
  });

  final PageController controller;
  final int position;
  final bool fade;
  final bool active;
  final Widget child;

  @override
  State<_TabPage> createState() => _TabPageState();
}

class _TabPageState extends State<_TabPage> {
  final _snapshot = SnapshotController();

  @override
  void dispose() {
    _snapshot.dispose();
    super.dispose();
  }

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
  Widget build(BuildContext context) {
    final glass = LiquidGlassScope.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final liveArrival = widget.fade && !glass && widget.active;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (_, child) {
        final offset = _delta;
        _snapshot.allowSnapshotting = !liveArrival && offset.abs() > 0.001;
        final delta = widget.fade ? offset : 0.0;
        return FractionalTranslation(
          translation: Offset(rtl ? delta : -delta, 0),
          child: Opacity(opacity: 1 - delta.abs(), child: child),
        );
      },
      child: SnapshotWidget(
        controller: _snapshot,
        mode: SnapshotMode.permissive,
        autoresize: true,
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
