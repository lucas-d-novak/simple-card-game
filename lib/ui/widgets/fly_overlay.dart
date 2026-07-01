import 'package:flutter/material.dart';

/// A single transient "fly" animation: a widget that tweens from a source
/// global rect to a destination global rect (with scale + fade), then removes
/// itself from the [Overlay].
///
/// This is the low-level primitive behind [BoardAnimator]. Callers normally use
/// the [BoardAnimator] façade (`flyCard` / `flyResource`) rather than spawning
/// [FlyingWidget]s directly.
///
/// The widget positions itself in the ambient [Overlay]'s coordinate space, so
/// [from] / [to] must be GLOBAL rects (resolved from `GlobalKey` render boxes).
class FlyingWidget extends StatefulWidget {
  const FlyingWidget({
    super.key,
    required this.from,
    required this.to,
    required this.child,
    required this.duration,
    required this.onDone,
    this.curve = Curves.easeInOutCubic,
    this.startScale = 1.0,
    this.endScale = 1.0,
    this.fadeOut = true,
    this.arc = 0.0,
  });

  /// Global source rect (where the flight starts).
  final Rect from;

  /// Global destination rect (where the flight ends).
  final Rect to;

  /// The transient visual that flies (a mini card face, a resource pip, …).
  final Widget child;

  /// How long the flight lasts. Callers pass a role-resolved duration from
  /// `AnimationTiming`; it should be non-zero (instant mode is handled upstream
  /// by [BoardAnimator], which spawns nothing).
  final Duration duration;

  /// Called exactly once when the flight completes (or is force-removed).
  final VoidCallback onDone;

  final Curve curve;

  /// Scale applied to [child] at the start / end of the flight. A pip that
  /// grows into a counter uses startScale < 1; a card shrinking into a pile uses
  /// endScale < 1.
  final double startScale;
  final double endScale;

  /// Whether the child fades out over the last portion of the flight.
  final bool fadeOut;

  /// Vertical arc height in logical pixels: the flight bows upward by this much
  /// at its midpoint, giving pips a little "toss" feel. 0 = straight line.
  final double arc;

  @override
  State<FlyingWidget> createState() => _FlyingWidgetState();
}

class _FlyingWidgetState extends State<FlyingWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
    _controller.forward();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = widget.curve.transform(_controller.value);

        // Interpolate the centre of the flying widget from source → dest.
        final fromCenter = widget.from.center;
        final toCenter = widget.to.center;
        final x = fromCenter.dx + (toCenter.dx - fromCenter.dx) * t;
        var y = fromCenter.dy + (toCenter.dy - fromCenter.dy) * t;
        // Parabolic arc: peaks at the midpoint.
        if (widget.arc != 0) {
          y -= widget.arc * (4 * t * (1 - t));
        }

        final scale =
            widget.startScale + (widget.endScale - widget.startScale) * t;

        // Size interpolates from the source rect toward the dest rect so a card
        // shrinking into a pile visibly reduces.
        final w = widget.from.width + (widget.to.width - widget.from.width) * t;
        final h =
            widget.from.height + (widget.to.height - widget.from.height) * t;

        // Fade out only over the final third so the flight stays visible.
        final opacity = widget.fadeOut
            ? (1.0 - ((t - 0.66) / 0.34).clamp(0.0, 1.0))
            : 1.0;

        return Positioned(
          left: x - w / 2,
          top: y - h / 2,
          width: w,
          height: h,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: child,
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
