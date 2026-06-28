import 'package:flutter/widgets.dart';

/// Global animation speed setting.
///
/// Speed scales *durations and delays only*, never game logic. [instant] makes
/// every role resolve to [Duration.zero] so state snaps immediately — this is
/// also the default used by widget/golden tests for determinism.
enum AnimationSpeed {
  /// Deliberate, readable motion. Good for learning / accessibility.
  slow,

  /// Snappy default for experienced players.
  fast,

  /// No animation — everything snaps. Forced in tests and under reduced motion.
  instant,
}

/// A logical animation "role" used across the UI. Widgets look up a [Duration]
/// by role rather than hardcoding millisecond values, so all timing lives in
/// one place ([AnimationTiming]).
enum AnimationRole {
  /// A card moving between zones (hand → play, center → discard), and the
  /// generic card container morph (border / shadow on highlight).
  cardMove,

  /// A resource counter ticking up/down (health, mastery, gems, power).
  counterTick,

  /// Hover / tap-down scale affordance on a card.
  hoverScale,

  /// Pacing delay between phases (AI turn steps, clearing the just-played
  /// highlight). This is a *delay*, not a transition duration, but it scales
  /// with speed the same way.
  phaseDelay,
}

/// Resolves an [AnimationRole] to a concrete [Duration] for a given
/// [AnimationSpeed].
///
/// This is the single source of truth for animation timing. Obtain one from the
/// widget tree via [AnimationTiming.of] (which also honours reduced-motion), or
/// construct directly from a speed via [AnimationTiming.forSpeed].
@immutable
class AnimationTiming {
  const AnimationTiming(this.speed);

  /// Convenience alias matching the conceptual "resolve a timing for a speed".
  const AnimationTiming.forSpeed(this.speed);

  final AnimationSpeed speed;

  static const Map<AnimationRole, int> _slowMs = {
    AnimationRole.cardMove: 600,
    AnimationRole.counterTick: 500,
    AnimationRole.hoverScale: 250,
    AnimationRole.phaseDelay: 600,
  };

  static const Map<AnimationRole, int> _fastMs = {
    AnimationRole.cardMove: 250,
    AnimationRole.counterTick: 200,
    AnimationRole.hoverScale: 120,
    AnimationRole.phaseDelay: 250,
  };

  /// Duration for [role] under the current [speed].
  Duration duration(AnimationRole role) {
    switch (speed) {
      case AnimationSpeed.slow:
        return Duration(milliseconds: _slowMs[role]!);
      case AnimationSpeed.fast:
        return Duration(milliseconds: _fastMs[role]!);
      case AnimationSpeed.instant:
        return Duration.zero;
    }
  }

  // Role-specific shortcuts for readability at call sites.
  Duration get cardMove => duration(AnimationRole.cardMove);
  Duration get counterTick => duration(AnimationRole.counterTick);
  Duration get hoverScale => duration(AnimationRole.hoverScale);
  Duration get phaseDelay => duration(AnimationRole.phaseDelay);

  /// Whether motion is effectively disabled (instant mode).
  bool get isInstant => speed == AnimationSpeed.instant;

  /// Resolve the active timing from the widget tree.
  ///
  /// If the OS/browser requests reduced motion
  /// ([MediaQueryData.disableAnimations]) the result is forced to [instant]
  /// regardless of the configured speed.
  ///
  /// If no [AnimationSettings] is present above [context] (e.g. in a plain
  /// widget test that doesn't wrap the tree), the timing defaults to
  /// [AnimationSettings.fallbackSpeed] — which is [AnimationSpeed.instant] — so
  /// tests stay deterministic without any setup.
  static AnimationTiming of(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) return const AnimationTiming(AnimationSpeed.instant);
    final speed = AnimationSettings.maybeSpeedOf(context) ??
        AnimationSettings.fallbackSpeed;
    return AnimationTiming(speed);
  }
}

/// Inherited holder for the global [AnimationSpeed].
///
/// Wrap the app (above [MaterialApp.home]) in an [AnimationSettings] to make the
/// speed selectable and overridable at runtime. When absent, [AnimationTiming.of]
/// falls back to [fallbackSpeed] ([AnimationSpeed.instant]).
class AnimationSettings extends StatefulWidget {
  const AnimationSettings({
    super.key,
    this.initialSpeed = AnimationSpeed.fast,
    required this.child,
  });

  final AnimationSpeed initialSpeed;
  final Widget child;

  /// Speed used when no [AnimationSettings] is found in the tree. Instant keeps
  /// tests and goldens deterministic (no pending timers, no settle flakiness).
  static const AnimationSpeed fallbackSpeed = AnimationSpeed.instant;

  /// The nearest [AnimationSettingsController], or null if none.
  static AnimationSettingsController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_AnimationSettingsScope>()
        ?.controller;
  }

  /// The nearest controller. Throws if none is present.
  static AnimationSettingsController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No AnimationSettings found in context');
    return controller!;
  }

  /// The configured speed above [context], or null if no settings present.
  static AnimationSpeed? maybeSpeedOf(BuildContext context) =>
      maybeOf(context)?.speed;

  @override
  State<AnimationSettings> createState() => _AnimationSettingsState();
}

class _AnimationSettingsState extends State<AnimationSettings> {
  late AnimationSpeed _speed = widget.initialSpeed;

  void _setSpeed(AnimationSpeed speed) {
    if (speed == _speed) return;
    setState(() => _speed = speed);
  }

  @override
  Widget build(BuildContext context) {
    return _AnimationSettingsScope(
      controller: AnimationSettingsController(_speed, _setSpeed),
      child: widget.child,
    );
  }
}

/// Read/write handle for the global animation speed, exposed via
/// [AnimationSettings.of].
@immutable
class AnimationSettingsController {
  const AnimationSettingsController(this.speed, this._setSpeed);

  final AnimationSpeed speed;
  final ValueChanged<AnimationSpeed> _setSpeed;

  /// Change the global animation speed.
  void setSpeed(AnimationSpeed speed) => _setSpeed(speed);
}

class _AnimationSettingsScope extends InheritedWidget {
  const _AnimationSettingsScope({
    required this.controller,
    required super.child,
  });

  final AnimationSettingsController controller;

  @override
  bool updateShouldNotify(_AnimationSettingsScope oldWidget) =>
      controller.speed != oldWidget.controller.speed;
}
