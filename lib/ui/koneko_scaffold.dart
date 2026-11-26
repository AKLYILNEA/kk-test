import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

/// The shared floating toolbar for Koneko's scrollable pages.
class KonekoScaffold extends StatelessWidget {
  const KonekoScaffold({
    super.key,
    required this.title,
    required this.body,
    this.showBack = false,
    this.actions = const [],
    this.barBackgroundColor,
    this.leadingShadows = const [],
  });

  final String title;
  final Widget body;
  final bool showBack;
  final List<IconButtonData> actions;
  final Color? barBackgroundColor;
  final List<BoxShadow> leadingShadows;

  Widget _button(IconButtonData data) => ElasticPress(
    enabled: !data.isLoading && data.onPressed != null,
    child: AppBarActionButton(data: data),
  );

  @override
  Widget build(BuildContext context) {
    final mobile = context.isMobileView;
    final compactTitle =
        mobile && ModalRoute.of(context)?.impliesAppBarDismissal == true;
    final grouped = actions.length >= 3;
    const idle = AlwaysStoppedAnimation(false);

    return PrismScaffold(
      bar: ScaffoldBar(
        isCompact: false,
        listenable: idle,
        loading: idle,
        backgroundColor: barBackgroundColor,
        builder: (context) {
          final back = AppBarActionButton(
            data: IconButtonData(
              glyph: Glyphs.backFor(Theme.of(context).platform),
              tooltip: UiLocalizations.of(context).back,
              onPressed: () => Navigator.maybePop(context),
            ),
          );
          return TonalButtonTheme(
            glass: LiquidGlassScope.of(context),
            child: AppBar(
              clipBehavior: Clip.none,
              titleSpacing: showBack ? 0 : null,
              titleTextStyle:
                  (compactTitle
                          ? AppTextStyle.headline
                          : AppTextStyle.pageTitle)
                      .of(context),
              leading: showBack
                  ? Center(
                      child: BarItemPresence(
                        child: ElasticPress(
                          child: leadingShadows.isEmpty
                              ? back
                              : DecoratedBox(
                                  decoration: ShapeDecoration(
                                    shape: AppShape.full,
                                    shadows: leadingShadows,
                                  ),
                                  child: back,
                                ),
                        ),
                      ),
                    )
                  : null,
              title: BarItemPresence.title(child: Text(title)),
              actions: actions.isEmpty
                  ? const []
                  : genActions([
                      if (grouped)
                        BarItemPresence(
                          child: TonalButtonGroup(
                            children: [
                              for (final data in actions.take(2))
                                AppBarActionButton(data: data),
                            ],
                          ),
                        ),
                      for (final data in actions.skip(grouped ? 2 : 0))
                        BarItemPresence(child: _button(data)),
                    ], edge: AppBarActionEdge.container),
            ),
          );
        },
      ),
      body: body,
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
