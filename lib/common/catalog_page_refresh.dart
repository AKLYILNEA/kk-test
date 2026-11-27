import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/core_providers.dart';
import 'package:prism_ui/prism_ui.dart';

/// Keeps catalog changes off hidden pages and holds feed refreshes during routes.
mixin CatalogPageRefreshMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T>, RouteMotionHoldMixin<T> {
  bool _catalogVisible = false;
  bool _catalogDirty = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(catalogUpdatesProvider, (_, _) {
      _catalogDirty = true;
      _flushCatalogChanges();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _catalogVisible =
        PageActivityScope.isActiveOf(context) &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _flushCatalogChanges();
  }

  void _flushCatalogChanges() {
    if (!_catalogVisible || !_catalogDirty) return;
    updateWhenRouteSettled(() {
      if (mounted && _catalogVisible && _catalogDirty) {
        setState(() => _catalogDirty = false);
      }
    });
  }
}
