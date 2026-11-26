import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

/// Configures FlClash-style inline expanding AppBar search inside [KonekoScaffold].
class KonekoSearchConfig {
  const KonekoSearchConfig({
    required this.onChanged,
    this.hintText = '搜索...',
    this.tooltip = '搜索',
  });

  final ValueChanged<String> onChanged;
  final String hintText;
  final String tooltip;
}

/// The shared floating toolbar for Koneko's scrollable pages, supporting
/// FlClash's smooth inline expanding AppBar search animation.
class KonekoScaffold extends StatefulWidget {
  const KonekoScaffold({
    super.key,
    required this.title,
    required this.body,
    this.showBack = false,
    this.actions = const [],
    this.searchConfig,
    this.barBackgroundColor,
    this.leadingShadows = const [],
  });

  final String title;
  final Widget body;
  final bool showBack;
  final List<IconButtonData> actions;
  final KonekoSearchConfig? searchConfig;
  final Color? barBackgroundColor;
  final List<BoxShadow> leadingShadows;

  @override
  State<KonekoScaffold> createState() => _KonekoScaffoldState();
}

class _KonekoScaffoldState extends State<KonekoScaffold> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _searchFocusNode.unfocus();
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
      widget.searchConfig?.onChanged('');
    }
    setState(() => _searching = false);
  }

  Widget _button(IconButtonData data) => ElasticPress(
    enabled: !data.isLoading && data.onPressed != null,
    child: AppBarActionButton(data: data),
  );

  @override
  Widget build(BuildContext context) {
    final mobile = context.isMobileView;
    final compactTitle =
        mobile && ModalRoute.of(context)?.impliesAppBarDismissal == true;
    final search = widget.searchConfig;
    final effectiveActions = <IconButtonData>[
      if (search != null)
        IconButtonData(
          glyph: Glyphs.search,
          tooltip: search.tooltip,
          onPressed: _openSearch,
        ),
      ...widget.actions,
    ];
    final grouped = effectiveActions.length >= 3;
    const idle = AlwaysStoppedAnimation(false);

    return PrismScaffold(
      bar: ScaffoldBar(
        isCompact: false,
        listenable: idle,
        loading: idle,
        backgroundColor: widget.barBackgroundColor,
        builder: (context) {
          final colorScheme = context.colorScheme;
          final back = AppBarActionButton(
            data: IconButtonData(
              glyph: Glyphs.backFor(Theme.of(context).platform),
              tooltip: UiLocalizations.of(context).back,
              onPressed: () => Navigator.maybePop(context),
            ),
          );

          if (search != null && _searching) {
            return TonalButtonTheme(
              glass: LiquidGlassScope.of(context),
              child: AppBar(
                clipBehavior: Clip.none,
                titleSpacing: 14,
                title: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.92, end: 1.0),
                  duration: context.motionDuration(
                    const Duration(milliseconds: 240),
                  ),
                  curve: Curves.easeOutCubic,
                  builder: (context, scale, child) => Opacity(
                    opacity: ((scale - 0.92) / 0.08).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: scale,
                      alignment: AlignmentDirectional.centerEnd,
                      child: child,
                    ),
                  ),
                  child: SearchField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    fill: SurfaceLevel.card.colorOf(colorScheme),
                    hintText: search.hintText,
                    onChanged: search.onChanged,
                  ),
                ),
                actions: genActions([
                  BarItemPresence(
                    child: _button(
                      IconButtonData(
                        glyph: Glyphs.close,
                        tooltip: '关闭搜索',
                        onPressed: _closeSearch,
                      ),
                    ),
                  ),
                ], edge: AppBarActionEdge.container),
              ),
            );
          }

          return TonalButtonTheme(
            glass: LiquidGlassScope.of(context),
            child: AppBar(
              clipBehavior: Clip.none,
              titleSpacing: widget.showBack ? 0 : null,
              titleTextStyle:
                  (compactTitle
                          ? AppTextStyle.headline
                          : AppTextStyle.pageTitle)
                      .of(context),
              leading: widget.showBack
                  ? Center(
                      child: BarItemPresence(
                        child: ElasticPress(
                          child: widget.leadingShadows.isEmpty
                              ? back
                              : DecoratedBox(
                                  decoration: ShapeDecoration(
                                    shape: AppShape.full,
                                    shadows: widget.leadingShadows,
                                  ),
                                  child: back,
                                ),
                        ),
                      ),
                    )
                  : null,
              title: BarItemPresence.title(child: Text(widget.title)),
              actions: effectiveActions.isEmpty
                  ? const []
                  : genActions([
                      if (grouped)
                        BarItemPresence(
                          child: TonalButtonGroup(
                            children: [
                              for (final data in effectiveActions.take(2))
                                AppBarActionButton(data: data),
                            ],
                          ),
                        ),
                      for (final data in effectiveActions.skip(grouped ? 2 : 0))
                        BarItemPresence(child: _button(data)),
                    ], edge: AppBarActionEdge.container),
            ),
          );
        },
      ),
      body: widget.body,
    );
  }
}

/// Lets the first item start below the toolbar and scroll under its gradient.
class KonekoScrollStart extends StatelessWidget {
  const KonekoScrollStart({super.key});

  @override
  Widget build(BuildContext context) =>
      SliverToBoxAdapter(child: SizedBox(height: context.contentTopPadding));
}
