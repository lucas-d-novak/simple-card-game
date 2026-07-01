import 'package:flutter/material.dart';

import '../theme/animation_timing.dart';

/// A small, self-animating numeric counter: it watches its own [value] and, when
/// that value changes, TWEENS the displayed integer from the old number to the
/// new one AND briefly FLASHES/pulses in place (green tint counting up, red tint
/// counting down). Purely LOCAL — it animates where it sits and does not fly
/// anything across the board (that's `BoardAnimator`, which is complementary).
///
/// ## Usage
///
/// ```dart
/// AnimatedCounter(
///   value: gems,
///   style: const TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold),
/// )
/// ```
///
/// Or provide a [builder] to render the tweened value however you like (icon +
/// number, custom layout, etc.):
///
/// ```dart
/// AnimatedCounter(
///   value: health,
///   builder: (context, shown) => Text('$shown HP'),
/// )
/// ```
///
/// ## Instant mode (tests / reduced motion)
///
/// Timing comes from [AnimationTiming.of]. When it resolves to `instant`
/// (widget tests with no [AnimationSettings], reduced-motion, or the `instant`
/// speed setting) the widget SNAPS to the final value with NO tween and NO
/// pending flash controller — so `pumpAndSettle` never hangs and no timer
/// leaks. This mirrors the instant-skip pattern in `shard_win_overlay.dart` and
/// `board_animator.dart`.
class AnimatedCounter extends StatefulWidget {
  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.builder,
    this.flashUpColor = const Color(0xFF57E389),
    this.flashDownColor = const Color(0xFFE05252),
    this.enableFlash = true,
  }) : assert(style != null || builder != null,
            'Provide either a style (default Text) or a builder.');

  /// The current target value. When it changes the widget tweens toward it.
  final int value;

  /// Text style for the default `Text('$shown')` rendering. Ignored when
  /// [builder] is supplied.
  final TextStyle? style;

  /// Optional custom renderer for the currently-tweened integer. When null a
  /// plain [Text] with [style] is used.
  final Widget Function(BuildContext context, int shown)? builder;

  /// Tint flashed over the widget when the value increases.
  final Color flashUpColor;

  /// Tint flashed over the widget when the value decreases.
  final Color flashDownColor;

  /// Whether to overlay the brief colour flash / scale pulse on change. The
  /// count-up tween still runs when false.
  final bool enableFlash;

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash;

  /// The value we tween FROM. Updated to the new value at the end of each change
  /// so the next change tweens from the right place.
  late int _from;
  bool _increased = true;

  @override
  void initState() {
    super.initState();
    _from = widget.value;
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1),
    );
  }

  @override
  void didUpdateWidget(AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _increased = widget.value > oldWidget.value;
      _from = oldWidget.value;

      // Resolve timing here (context is available). In instant mode we skip the
      // flash entirely so no controller is left running (clean for tests).
      final timing = AnimationTiming.of(context);
      if (widget.enableFlash && !timing.isInstant) {
        _flash
          ..duration = timing.counterTick
          ..forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  Widget _content(int shown) {
    if (widget.builder != null) return widget.builder!(context, shown);
    return Text('$shown', style: widget.style);
  }

  @override
  Widget build(BuildContext context) {
    final timing = AnimationTiming.of(context);
    final duration = timing.counterTick;

    // TweenAnimationBuilder animates from the current tween's `begin` to `end`
    // whenever `end` changes. By keying `begin` off the PREVIOUS value we get a
    // real count-up; in instant mode `duration` is zero so it snaps.
    final tween = TweenAnimationBuilder<double>(
      tween:
          Tween<double>(begin: _from.toDouble(), end: widget.value.toDouble()),
      duration: duration,
      curve: Curves.easeOut,
      builder: (context, v, _) => _content(v.round()),
    );

    if (timing.isInstant || !widget.enableFlash) {
      // No flash overlay, no controller in play — snap-clean for tests.
      return tween;
    }

    // IMPORTANT: keep the `child` (the counting TweenAnimationBuilder) at a
    // STABLE position in the element tree across flash frames. Re-parenting it
    // (bare on some frames, wrapped in Transform/ShaderMask on others) would
    // rebuild its State and restart the count-up tween. So the tween lives in a
    // Stack base on EVERY frame; the flash tint is a separate overlay layer.
    return AnimatedBuilder(
      animation: _flash,
      builder: (context, child) {
        final t = _flash.value; // 0..1
        // A quick pulse: tint fades in then out (peaks at the midpoint), and a
        // subtle scale bump reads as "this just changed".
        final pulse =
            (t <= 0 || t >= 1) ? 0.0 : (t < 0.5 ? t / 0.5 : (1 - t) / 0.5);
        final tint = (_increased ? widget.flashUpColor : widget.flashDownColor)
            .withValues(alpha: 0.9 * pulse);
        final scale = 1.0 + 0.28 * pulse;
        return Transform.scale(
          scale: scale,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              child!,
              if (pulse > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(color: tint),
                  ),
                ),
            ],
          ),
        );
      },
      child: tween,
    );
  }
}
