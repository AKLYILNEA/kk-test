import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The blur behind a modal barrier.
///
/// The sigma is constant: animating it rebuilt the filter on every frame, which
/// is what made sheets stutter on Windows. A desktop window is also many times
/// the pixels of a phone screen, so it takes a lighter blur.
class BarrierBlur extends StatelessWidget {
  const BarrierBlur({super.key});

  static bool get _isDesktop => switch (defaultTargetPlatform) {
    TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS =>
      true,
    _ => false,
  };

  static double get sigma => _isDesktop ? 2.0 : 5.0;

  @override
  Widget build(BuildContext context) {
    final sigma = BarrierBlur.sigma;
    return RepaintBoundary(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: ui.TileMode.clamp,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Paints a modal scrim directly in the render layer so barrier fades never
/// rebuild widgets during sheet or dialog transitions.
class AnimatedBarrierPaint extends SingleChildRenderObjectWidget {
  const AnimatedBarrierPaint({
    super.key,
    required this.progress,
    required this.color,
    super.child,
  });

  final Animation<double> progress;
  final Color color;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderAnimatedBarrierPaint(progress: progress, color: color);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAnimatedBarrierPaint renderObject,
  ) {
    renderObject
      ..progress = progress
      ..color = color;
  }
}

class _RenderAnimatedBarrierPaint extends RenderProxyBox {
  _RenderAnimatedBarrierPaint({
    required Animation<double> progress,
    required Color color,
  }) : _progress = progress,
       _color = color;

  final Paint _paint = Paint();

  Animation<double> _progress;
  set progress(Animation<double> value) {
    if (identical(value, _progress)) {
      return;
    }
    if (attached) {
      _progress.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _progress = value;
    markNeedsPaint();
  }

  Color _color;
  set color(Color value) {
    if (value == _color) {
      return;
    }
    _color = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final factor = _progress.value.clamp(0.0, 1.0);
    if (factor > 0 && _color.a > 0) {
      _paint.color = _color.withValues(alpha: _color.a * factor);
      context.canvas.drawRect(offset & size, _paint);
    }
    super.paint(context, offset);
  }
}
