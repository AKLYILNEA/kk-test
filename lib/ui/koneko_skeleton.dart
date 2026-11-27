import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

/// Coordinates a single shared breathing [AnimationController] across all
/// descendant [KonekoSkeletonPulse] and [KonekoSkeletonBox] widgets.
///
/// Zero shaders and zero `CustomPaint` calls per frame: Impeller composites
/// a single hardware opacity uniform over each static [RepaintBoundary] group.
/// The ticker runs ONLY while [animate] is true AND at least one skeleton is
/// mounted, so idle pages and settled tests run zero tickers.
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
  late final Animation<double> _opacity = _controller.drive(
    const _BreathPulse(),
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
      inPulseGroup: false,
      child: widget.child,
    );
  }
}

class _BreathPulse extends Animatable<double> {
  const _BreathPulse();

  @override
  double transform(double t) => 0.68 + 0.32 * math.cos(2 * math.pi * t);
}

class _KonekoSkeletonInherited extends InheritedWidget {
  const _KonekoSkeletonInherited({
    required this.scope,
    required this.animate,
    required this.inPulseGroup,
    required super.child,
  });

  final _KonekoSkeletonScopeState scope;
  final bool animate;
  final bool inPulseGroup;

  static _KonekoSkeletonInherited? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_KonekoSkeletonInherited>();

  @override
  bool updateShouldNotify(covariant _KonekoSkeletonInherited oldWidget) =>
      !identical(oldWidget.scope, scope) ||
      oldWidget.animate != animate ||
      oldWidget.inPulseGroup != inPulseGroup;
}

/// Groups multiple [KonekoSkeletonBox] descendants under a single cached
/// [RepaintBoundary] + hardware-composited [FadeTransition], eliminating per-box
/// animation layers and shader allocations.
class KonekoSkeletonPulse extends StatefulWidget {
  const KonekoSkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<KonekoSkeletonPulse> createState() => _KonekoSkeletonPulseState();
}

class _KonekoSkeletonPulseState extends State<KonekoSkeletonPulse> {
  _KonekoSkeletonScopeState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inherited = _KonekoSkeletonInherited.maybeOf(context);
    final nextScope = inherited != null && !inherited.inPulseGroup
        ? inherited.scope
        : null;
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
    if (inherited != null && inherited.inPulseGroup) {
      return widget.child;
    }
    final staticChild = inherited == null
        ? widget.child
        : _KonekoSkeletonInherited(
            scope: inherited.scope,
            animate: inherited.animate,
            inPulseGroup: true,
            child: widget.child,
          );
    if (inherited == null || !inherited.animate) {
      return RepaintBoundary(child: staticChild);
    }
    return FadeTransition(
      opacity: inherited.scope._opacity,
      child: RepaintBoundary(child: staticChild),
    );
  }
}

/// A lightweight superellipse (or circular) placeholder block matching
/// Koneko / prism_ui surface geometry with zero shader allocations.
class KonekoSkeletonBox extends StatefulWidget {
  const KonekoSkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.corner = 10,
    this.circle = false,
    this.baseColor,
  });

  final double? width;
  final double height;
  final double corner;
  final bool circle;
  final Color? baseColor;

  @override
  State<KonekoSkeletonBox> createState() => _KonekoSkeletonBoxState();
}

class _KonekoSkeletonBoxState extends State<KonekoSkeletonBox> {
  _KonekoSkeletonScopeState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inherited = _KonekoSkeletonInherited.maybeOf(context);
    final nextScope = inherited != null && !inherited.inPulseGroup
        ? inherited.scope
        : null;
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
    final box = DecoratedBox(
      decoration: ShapeDecoration(
        color: base,
        shape: widget.circle
            ? const CircleBorder()
            : SuperellipseBorder(borderRadius: AppRadius.all(widget.corner)),
      ),
    );
    final sized = SizedBox(
      width: widget.width ?? double.infinity,
      height: widget.height,
      child: box,
    );
    final animateSelf =
        inherited != null && inherited.animate && !inherited.inPulseGroup;
    return ExcludeSemantics(
      child: animateSelf
          ? FadeTransition(opacity: inherited.scope._opacity, child: sized)
          : sized,
    );
  }
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
      children: [...previousChildren, ?currentChild],
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

/// Kazumi-style first-entrance gate for bottom-dock / sidebar tab pages.
///
/// On the very first switch into a tab, keeps the initial transition frames
/// ultra-light by showing static placeholders while the tab animation runs,
/// then flips [tabEntered] once so subsequent visits stay live with zero flash.
/// Driven by a [Ticker] (not a raw Timer) so Flutter's frame scheduler and
/// `pumpAndSettle` settle deterministically with zero dangling timers.
mixin TabEntranceMixin<T extends StatefulWidget>
    on State<T>, TickerProvider {
  static const _entranceDuration = Duration(milliseconds: 160);

  bool _tabEntered = false;
  Ticker? _entranceTicker;

  bool get tabEntered => _tabEntered;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tabEntered) return;
    if (!PageActivityScope.isActiveOf(context)) {
      _entranceTicker?.stop();
      return;
    }
    if (context.disableAnimations) {
      _tabEntered = true;
      return;
    }
    _entranceTicker ??= createTicker((elapsed) {
      if (elapsed >= _entranceDuration) {
        _entranceTicker?.stop();
        if (mounted && !_tabEntered) {
          setState(() => _tabEntered = true);
        }
      }
    });
    if (!_entranceTicker!.isActive) {
      _entranceTicker!.start();
    }
  }

  @override
  void dispose() {
    _entranceTicker?.dispose();
    super.dispose();
  }
}
