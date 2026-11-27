import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/l10n.dart';
import 'package:prism_ui/color.dart';
import 'package:prism_ui/deferred_push.dart';
import 'package:prism_ui/drag_back.dart';
import 'package:prism_ui/liquid_glass.dart';
import 'package:prism_ui/shape.dart';
import 'package:prism_ui/sheet_navigator.dart';
import 'package:prism_ui/surface.dart';
import 'package:prism_ui/theme_data.dart';

const Duration _sideSheetEnterDuration = Duration(milliseconds: 300);
const Duration _sideSheetExitDuration = Duration(milliseconds: 200);
const Curve _sideSheetCurve = Easing.standardDecelerate;

const double _minWidth = 360;
const double _maxWidth = 560;
const double _widthFactor = 0.4;

double _widthFor(double viewWidth) {
  return (viewWidth * _widthFactor).clamp(_minWidth, _maxWidth);
}

class SideSheet extends StatefulWidget {
  const SideSheet({super.key, this.backgroundColor, required this.builder});

  final WidgetBuilder builder;

  final Color? backgroundColor;

  @override
  State<SideSheet> createState() => _SideSheetState();

  static AnimationController createAnimationController(TickerProvider vsync) {
    return AnimationController(
      duration: _sideSheetEnterDuration,
      reverseDuration: _sideSheetExitDuration,
      debugLabel: 'SideSheet',
      vsync: vsync,
    );
  }
}

class _SideSheetState extends State<SideSheet> {
  final GlobalKey _childKey = GlobalKey(debugLabel: 'SideSheet child');

  @override
  Widget build(BuildContext context) {
    return Surface(
      key: _childKey,
      color:
          widget.backgroundColor ??
          SurfaceLevel.page.colorOf(Theme.of(context).colorScheme),
      shape: AppShape.none,
      child: widget.builder(context),
    );
  }
}

typedef _SizeChangeCallback<Size> = void Function(Size);

class _SideSheetLayoutWithSizeListener extends SingleChildRenderObjectWidget {
  const _SideSheetLayoutWithSizeListener({
    required this.onChildSizeChanged,
    required this.width,
    super.child,
  });

  final _SizeChangeCallback<Size> onChildSizeChanged;
  final double width;

  @override
  _RenderSideSheetLayoutWithSizeListener createRenderObject(
    BuildContext context,
  ) {
    return _RenderSideSheetLayoutWithSizeListener(
      onChildSizeChanged: onChildSizeChanged,
      width: width,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSideSheetLayoutWithSizeListener renderObject,
  ) {
    renderObject.onChildSizeChanged = onChildSizeChanged;
    renderObject.width = width;
  }
}

class _RenderSideSheetLayoutWithSizeListener extends RenderShiftedBox {
  _RenderSideSheetLayoutWithSizeListener({
    RenderBox? child,
    required _SizeChangeCallback<Size> onChildSizeChanged,
    required double width,
  }) : _onChildSizeChanged = onChildSizeChanged,
       _width = width,
       super(child);

  Size _lastSize = Size.zero;

  _SizeChangeCallback<Size> get onChildSizeChanged => _onChildSizeChanged;
  _SizeChangeCallback<Size> _onChildSizeChanged;

  set onChildSizeChanged(_SizeChangeCallback<Size> newCallback) {
    if (_onChildSizeChanged == newCallback) {
      return;
    }

    _onChildSizeChanged = newCallback;
    markNeedsLayout();
  }

  double get width => _width;
  double _width;

  set width(double newValue) {
    if (_width == newValue) {
      return;
    }

    _width = newValue;
    markNeedsLayout();
  }

  Size _getSize(BoxConstraints constraints) {
    return constraints.constrain(constraints.biggest);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final double width = _getSize(
      BoxConstraints.tightForFinite(height: height),
    ).width;
    if (width.isFinite) {
      return width;
    }
    return 0.0;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final double width = _getSize(
      BoxConstraints.tightForFinite(height: height),
    ).width;
    if (width.isFinite) {
      return width;
    }
    return 0.0;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final double height = _getSize(
      BoxConstraints.tightForFinite(width: width),
    ).height;
    if (height.isFinite) {
      return height;
    }
    return 0.0;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final double height = _getSize(
      BoxConstraints.tightForFinite(width: width),
    ).height;
    if (height.isFinite) {
      return height;
    }
    return 0.0;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return _getSize(constraints);
  }

  BoxConstraints _getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.tightFor(
      width: math.min(width, constraints.maxWidth),
      height: constraints.maxHeight,
    );
  }

  Offset _getPositionForChild(Size size, Size childSize) {
    return Offset(size.width - childSize.width, 0.0);
  }

  @override
  void performLayout() {
    size = _getSize(constraints);
    if (child != null) {
      final BoxConstraints childConstraints = _getConstraintsForChild(
        constraints,
      );
      assert(childConstraints.debugAssertIsValid(isAppliedConstraint: true));
      child!.layout(
        childConstraints,
        parentUsesSize: !childConstraints.isTight,
      );
      final BoxParentData childParentData = child!.parentData! as BoxParentData;
      childParentData.offset = _getPositionForChild(
        size,
        childConstraints.isTight ? childConstraints.smallest : child!.size,
      );
      final Size childSize = childConstraints.isTight
          ? childConstraints.smallest
          : child!.size;

      if (_lastSize != childSize) {
        _lastSize = childSize;
        _onChildSizeChanged.call(_lastSize);
      }
    }
  }
}

class _ModalSideSheet<T> extends StatefulWidget {
  const _ModalSideSheet({super.key, required this.route, this.backgroundColor});

  final ModalSideSheetRoute<T> route;
  final Color? backgroundColor;

  @override
  _ModalSideSheetState<T> createState() => _ModalSideSheetState<T>();
}

class _ModalSideSheetState<T> extends State<_ModalSideSheet<T>> {
  final _motionSnapshot = SnapshotController();
  bool _glass = false;
  bool _pointerDown = false;
  bool _hadProgress = false;

  @override
  void initState() {
    super.initState();
    widget.route.animation!
      ..addListener(_handleTick)
      ..addStatusListener(_handleStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _glass = LiquidGlassScope.of(context);
    _updateSnapshot();
  }

  @override
  void didUpdateWidget(_ModalSideSheet<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.route != oldWidget.route) {
      oldWidget.route.animation!
        ..removeListener(_handleTick)
        ..removeStatusListener(_handleStatus);
      widget.route.animation!
        ..addListener(_handleTick)
        ..addStatusListener(_handleStatus);
      _hadProgress = widget.route.animation!.value > 0;
      _updateSnapshot();
    }
  }

  @override
  void dispose() {
    widget.route.animation!
      ..removeListener(_handleTick)
      ..removeStatusListener(_handleStatus);
    _motionSnapshot.dispose();
    super.dispose();
  }

  void _handleTick() {
    final hasProgress = widget.route.animation!.value > 0;
    if (hasProgress != _hadProgress) {
      _hadProgress = hasProgress;
      _updateSnapshot();
    }
  }

  void _handleStatus(AnimationStatus _) => _updateSnapshot();

  void _updateSnapshot() {
    final animation = widget.route.animation!;
    _motionSnapshot.allowSnapshotting =
        !_glass &&
        !_pointerDown &&
        (widget.route.isDragBackActive ||
            (animation.isAnimating && animation.value > 0));
  }

  String _getRouteLabel(UiLocalizations localizations) {
    switch (Theme.of(context).platform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return '';
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return localizations.dialog;
    }
  }

  EdgeInsets _getNewClipDetails(Size topLayerSize) {
    return EdgeInsets.fromLTRB(0, 0, topLayerSize.width, 0);
  }

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasMediaQuery(context));
    final localizations = UiLocalizations.of(context);
    final String routeLabel = _getRouteLabel(localizations);
    final width = _widthFor(MediaQuery.sizeOf(context).width);

    final route = widget.route;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: routeLabel,
      explicitChildNodes: true,
      child: ClipRect(
        child: _SideSheetLayoutWithSizeListener(
          onChildSizeChanged: (Size size) {
            widget.route._didChangeBarrierSemanticsClip(
              _getNewClipDetails(size),
            );
          },
          width: width,
          child: _SideSheetSlide(
            animation: route.animation!,
            isDragBackActive: () => route.isDragBackActive,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                if (!_pointerDown) {
                  _pointerDown = true;
                  _updateSnapshot();
                }
              },
              child: RepaintBoundary(
                child: SnapshotWidget(
                  controller: _motionSnapshot,
                  mode: SnapshotMode.permissive,
                  autoresize: true,
                  child: route.dragBackDetector(
                    SideSheet(
                      builder: route.builder,
                      backgroundColor: widget.backgroundColor,
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

class _SideSheetSlide extends SingleChildRenderObjectWidget {
  const _SideSheetSlide({
    required this.animation,
    required this.isDragBackActive,
    super.child,
  });

  final Animation<double> animation;
  final bool Function() isDragBackActive;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSideSheetSlide(
      animation: animation,
      isDragBackActive: isDragBackActive,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSideSheetSlide renderObject,
  ) {
    renderObject
      ..animation = animation
      ..isDragBackActive = isDragBackActive;
  }
}

class _RenderSideSheetSlide extends RenderProxyBox {
  _RenderSideSheetSlide({
    required Animation<double> animation,
    required bool Function() isDragBackActive,
  }) : _animation = animation,
       _isDragBackActive = isDragBackActive;

  final _transformLayer = LayerHandle<TransformLayer>();

  Animation<double> _animation;
  set animation(Animation<double> value) {
    if (identical(value, _animation)) return;
    if (attached) {
      _animation.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _animation = value;
    markNeedsPaint();
  }

  bool Function() _isDragBackActive;
  set isDragBackActive(bool Function() value) {
    if (identical(value, _isDragBackActive)) return;
    _isDragBackActive = value;
    markNeedsPaint();
  }

  double get _dx {
    final curve = _isDragBackActive() ? Curves.linear : _sideSheetCurve;
    final t = curve.transform(_animation.value);
    return (1.0 - t) * size.width;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _animation.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _transformLayer.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final dx = _dx;
    if (dx.abs() < 0.01) {
      _transformLayer.layer = null;
      context.paintChild(child, offset);
      return;
    }
    _transformLayer.layer = context.pushTransform(
      needsCompositing,
      offset,
      Matrix4.translationValues(dx, 0, 0),
      (context, offset) => context.paintChild(child, offset),
      oldLayer: _transformLayer.layer,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final dx = _dx;
    if (dx.abs() >= 0.01) {
      transform.translateByDouble(dx, 0, 0, 1);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    final dx = _dx;
    return result.addWithPaintTransform(
      transform: dx.abs() < 0.01 ? null : Matrix4.translationValues(dx, 0, 0),
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }
}

class ModalSideSheetRoute<T> extends PopupRoute<T>
    with
        DragBackRouteMixin<T>,
        SheetCoverRouteMixin<T>,
        DeferredPushRouteMixin<T> {
  ModalSideSheetRoute({
    required this.builder,
    this.barrierLabel,
    this.barrierOnTapHint,
    this.backgroundColor,
    this.modalBarrierColor,
  });

  final WidgetBuilder builder;

  final Color? backgroundColor;

  final Color? modalBarrierColor;

  final String? barrierOnTapHint;

  final ValueNotifier<EdgeInsets> _clipDetailsNotifier =
      ValueNotifier<EdgeInsets>(EdgeInsets.zero);

  @override
  void dispose() {
    _clipDetailsNotifier.dispose();
    super.dispose();
  }

  bool _didChangeBarrierSemanticsClip(EdgeInsets newClipDetails) {
    if (_clipDetailsNotifier.value == newClipDetails) {
      return false;
    }
    _clipDetailsNotifier.value = newClipDetails;
    return true;
  }

  @override
  Duration get transitionDuration => _sideSheetEnterDuration;

  @override
  Duration get reverseTransitionDuration => _sideSheetExitDuration;

  @override
  bool get barrierDismissible => true;

  @override
  final String? barrierLabel;

  @override
  Color get barrierColor => modalBarrierColor ?? Colors.black54;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final Widget content = DisplayFeatureSubScreen(
      child: Builder(
        builder: (BuildContext context) {
          final colorScheme = Theme.of(context).colorScheme;
          return _ModalSideSheet<T>(
            route: this,
            backgroundColor:
                backgroundColor ?? SurfaceLevel.page.colorOf(colorScheme),
          );
        },
      ),
    );

    return ElevatedSurfaceTheme(child: content);
  }

  @override
  Widget buildModalBarrier() {
    if (barrierColor.a != 0 && !offstage) {
      assert(barrierColor != barrierColor.opacity0);
      final Animation<Color?> color = animation!.drive(
        ColorTween(
          begin: barrierColor.opacity0,
          end: barrierColor,
        ).chain(CurveTween(curve: barrierCurve)),
      );
      return AnimatedModalBarrier(
        color: color,
        dismissible: barrierDismissible,
        semanticsLabel: barrierLabel,
        barrierSemanticsDismissible: semanticsDismissible,
        clipDetailsNotifier: _clipDetailsNotifier,
        semanticsOnTapHint: barrierOnTapHint,
      );
    } else {
      return ModalBarrier(
        dismissible: barrierDismissible,
        semanticsLabel: barrierLabel,
        barrierSemanticsDismissible: semanticsDismissible,
        clipDetailsNotifier: _clipDetailsNotifier,
        semanticsOnTapHint: barrierOnTapHint,
      );
    }
  }
}

Future<T?> showModalSideSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  Color? barrierColor,
}) {
  assert(debugCheckHasMediaQuery(context));

  final navigator = sheetNavigatorOf(context);
  final localizations = UiLocalizations.of(context);
  return navigator.push(
    ModalSideSheetRoute<T>(
      builder: builder,
      barrierLabel: localizations.close,
      barrierOnTapHint: localizations.close,
      backgroundColor: backgroundColor,
      modalBarrierColor: barrierColor,
    ),
  );
}
