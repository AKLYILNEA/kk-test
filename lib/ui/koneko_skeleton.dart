import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

/// Coordinates a single shimmer [AnimationController] across all descendant
/// [KonekoSkeletonBox] widgets.
///
/// The ticker runs ONLY when [animate] is true (e.g. after the route push
/// animation settles) AND at least one [KonekoSkeletonBox] is mounted. When
/// no skeletons are visible, zero tickers run and tests settle immediately.
class KonekoSkeletonScope extends StatefulWidget {
  const KonekoSkeletonScope({
    super.key,
    required this.animate,
    required this.child,
  });

  final bool animate;
  final Widget child;

  @override
  State<KonekoSkeletonScope> createState() => _KonekoSkeletonScopeState();
}

class _KonekoSkeletonScopeState extends State<KonekoSkeletonScope>
    with SingleTickerProviderStateMixin {
  static const _period = Duration(milliseconds: 1450);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _period,
  );
  int _consumers = 0;
  bool _disableAnimations = false;

  void _attach() {
    _consumers++;
    _syncTicker();
  }

  void _detach() {
    if (_consumers > 0) _consumers--;
    _syncTicker();
  }

  void _syncTicker() {
    if (!mounted) return;
    final shouldRun = widget.animate && _consumers > 0 && !_disableAnimations;
    if (shouldRun) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else if (_controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = context.disableAnimations;
    if (disabled != _disableAnimations) {
      _disableAnimations = disabled;
      _syncTicker();
    }
  }

  @override
  void didUpdateWidget(covariant KonekoSkeletonScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _KonekoSkeletonInherited(
      scope: this,
      animate: widget.animate && !_disableAnimations,
      child: widget.child,
    );
  }
}

class _KonekoSkeletonInherited extends InheritedWidget {
  const _KonekoSkeletonInherited({
    required this.scope,
    required this.animate,
    required super.child,
  });

  final _KonekoSkeletonScopeState scope;
  final bool animate;

  static _KonekoSkeletonInherited? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_KonekoSkeletonInherited>();

  @override
  bool updateShouldNotify(covariant _KonekoSkeletonInherited oldWidget) =>
      !identical(oldWidget.scope, scope) || oldWidget.animate != animate;
}

/// A superellipse (or circular) shimmering placeholder block matching
/// Koneko / prism_ui surface geometry.
class KonekoSkeletonBox extends StatefulWidget {
  const KonekoSkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.corner = 10,
    this.circle = false,
    this.baseColor,
    this.highlightColor,
  });

  final double? width;
  final double height;
  final double corner;
  final bool circle;
  final Color? baseColor;
  final Color? highlightColor;

  @override
  State<KonekoSkeletonBox> createState() => _KonekoSkeletonBoxState();
}

class _KonekoSkeletonBoxState extends State<KonekoSkeletonBox> {
  _KonekoSkeletonScopeState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextScope = _KonekoSkeletonInherited.maybeOf(context)?.scope;
    if (!identical(nextScope, _scope)) {
      _scope?._detach();
      _scope = nextScope;
      _scope?._attach();
    }
  }

  @override
  void dispose() {
    _scope?._detach();
    _scope = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inherited = _KonekoSkeletonInherited.maybeOf(context);
    final colors = context.colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final base =
        widget.baseColor ??
        colors.surfaceContainerHighest.withValues(alpha: isDark ? 0.56 : 0.72);
    final highlight =
        widget.highlightColor ??
        (isDark
            ? colors.onSurface.withValues(alpha: 0.14)
            : colors.surfaceContainerLowest.withValues(alpha: 0.88));
    final animate = inherited?.animate == true;
    final progress = animate ? inherited!.scope._controller : null;

    return ExcludeSemantics(
      child: SizedBox(
        width: widget.width ?? double.infinity,
        height: widget.height,
        child: CustomPaint(
          painter: _SkeletonShimmerPainter(
            progress: progress,
            baseColor: base,
            highlightColor: highlight,
            corner: widget.corner,
            circle: widget.circle,
          ),
        ),
      ),
    );
  }
}

class _SkeletonShimmerPainter extends CustomPainter {
  _SkeletonShimmerPainter({
    required this.progress,
    required this.baseColor,
    required this.highlightColor,
    required this.corner,
    required this.circle,
  }) : super(repaint: progress);

  final Animation<double>? progress;
  final Color baseColor;
  final Color highlightColor;
  final double corner;
  final bool circle;

  final Paint _paint = Paint()..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final anim = progress;
    if (anim == null) {
      _paint
        ..shader = null
        ..color = baseColor;
    } else {
      final t = anim.value;
      final bandWidth = (size.width * 0.68).clamp(64.0, 220.0);
      final startX = -bandWidth + (size.width + bandWidth * 2) * t;
      _paint
        ..color = const Color(0xFFFFFFFF)
        ..shader = ui.Gradient.linear(
          Offset(startX - bandWidth * 0.5, 0),
          Offset(startX + bandWidth * 0.5, size.height * 0.18),
          [baseColor, highlightColor, baseColor],
          const [0.0, 0.5, 1.0],
        );
    }

    if (circle) {
      canvas.drawOval(rect, _paint);
    } else {
      SuperellipseBorder(
        borderRadius: AppRadius.all(corner),
      ).paintInterior(canvas, rect, _paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SkeletonShimmerPainter oldDelegate) =>
      !identical(oldDelegate.progress, progress) ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.highlightColor != highlightColor ||
      oldDelegate.corner != corner ||
      oldDelegate.circle != circle;
}

/// Top-aligned fade transition used when replacing a skeleton placeholder
/// with live content without shifting layout geometry.
class KonekoSkeletonFade extends StatelessWidget {
  const KonekoSkeletonFade({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 220),
  });

  final Widget child;
  final Duration duration;

  static Widget _topLayoutBuilder(
    Widget? currentChild,
    List<Widget> previousChildren,
  ) {
    return Stack(
      alignment: AlignmentDirectional.topStart,
      fit: StackFit.passthrough,
      children: [
        ...previousChildren,
        ?currentChild,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final effective = context.motionDuration(duration);
    if (effective == Duration.zero) return child;
    return AnimatedSwitcher(
      duration: effective,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOut,
      layoutBuilder: _topLayoutBuilder,
      child: child,
    );
  }
}
