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
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = ViewScope.isMobileOf(context);
    final colorScheme = context.colorScheme;
    final settings = ref.watch(themeSettingsProvider);
    final rawIndex = ref.watch(navIndexProvider);
    final navNotifier = ref.read(navIndexProvider.notifier);

    if (isMobile) {
      final mobileIndex = rawIndex.clamp(0, _mobileDestinations.length - 1);
      final dockInset = settings.floatingNavigationBar
          ? NavigationDock.insetOf(context) + 8
          : 0.0;

      final page = _buildMobilePage(mobileIndex, dockInset);
      final animatedPage = _TabTransition(
        index: mobileIndex,
        mode: settings.tabAnimation,
        child: KeyedSubtree(key: ValueKey(mobileIndex), child: page),
      );

      return Surface(
        color: SurfaceLevel.page.colorOf(colorScheme),
        child: settings.floatingNavigationBar
            ? Stack(
                fit: StackFit.expand,
                children: [
                  animatedPage,
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: NavigationDock(
                      destinations: _mobileDestinations,
                      selectedIndex: mobileIndex,
                      onSelected: navNotifier.select,
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Expanded(child: animatedPage),
                  NavigationBar(
                    selectedIndex: mobileIndex,
                    onDestinationSelected: navNotifier.select,
                    destinations: [
                      for (final d in _mobileDestinations)
                        NavigationDestination(
                          icon: GlyphIcon(d.glyph),
                          label: d.label,
                        ),
                    ],
                  ),
                ],
              ),
      );
    }

    // Desktop / Wide layout with authentic prism_ui NavigationSidebar
    final desktopIndex = rawIndex.clamp(0, _desktopDestinations.length - 1);
    final page = _buildDesktopPage(desktopIndex);
    final canExpandInline = ViewScope.sizeOf(context).width >= 960;

    return Surface(
      color: SurfaceLevel.page.colorOf(colorScheme),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Surface(
            color: colorScheme.chromeSurface,
            shape: BorderDirectional(
              end: Divider.createBorderSide(context),
            ),
            child: NavigationSidebar(
              destinations: _desktopDestinations,
              selectedIndex: desktopIndex,
              expanded: canExpandInline && settings.sidebarExpanded,
              onSelected: navNotifier.select,
              onToggle: canExpandInline
                  ? () => ref
                        .read(themeSettingsProvider.notifier)
                        .update(
                          (s) => s.copyWith(sidebarExpanded: !s.sidebarExpanded),
                        )
                  : null,
            ),
          ),
          Expanded(
            child: _TabTransition(
              index: desktopIndex,
              mode: settings.tabAnimation,
              child: KeyedSubtree(key: ValueKey(desktopIndex), child: page),
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
    _ => const AboutPage(showBack: false),
  };
}

class _TabTransition extends StatelessWidget {
  const _TabTransition({
    required this.index,
    required this.mode,
    required this.child,
  });

  final int index;
  final TabAnimationMode mode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: context.motionDuration(
        mode == TabAnimationMode.fade
            ? const Duration(milliseconds: 200)
            : const Duration(milliseconds: 240),
      ),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        if (mode == TabAnimationMode.fade) {
          return FadeTransition(opacity: animation, child: child);
        }
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.03, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
