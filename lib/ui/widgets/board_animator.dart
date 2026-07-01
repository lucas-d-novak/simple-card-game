import 'package:flutter/material.dart';

import '../theme/animation_timing.dart';
import '../theme/board_chrome.dart';
import '../theme/game_theme.dart';
import 'fly_overlay.dart';
import 'resource_icons.dart';

/// A reusable, overlay-based "fly" animation system that telegraphs board
/// actions with motion: a card flying from the deck into the market, resource
/// pips flying from a played card to their counters, a recruited card flying to
/// the discard pile, and so on.
///
/// ## Usage
///
/// Wrap the board subtree in a [BoardAnimatorScope] (it inserts its own
/// [Overlay] so flights render above the board). Anchor the source/destination
/// widgets with `GlobalKey`s and call the façade at action time:
///
/// ```dart
/// BoardAnimator.of(context).flyCard(fromKey: deckKey, toKey: slotKey, card: c);
/// BoardAnimator.of(context)
///     .flyResource(fromKey: cardKey, toKey: gemCounterKey, icon: ResourceIcon.gem, count: 3);
/// ```
///
/// ## Instant mode (tests / reduced motion)
///
/// Every façade method resolves timing from [AnimationTiming.of]. When timing is
/// `instant` (widget tests with no `AnimationSettings`, reduced-motion, or the
/// `instant` speed setting) the methods spawn NOTHING and invoke their
/// `onComplete` synchronously. This mirrors [ShardWinOverlay]'s instant-skip so
/// tests never leak timers and motion-averse users opt out cleanly.
class BoardAnimator {
  BoardAnimator._(this._overlayState, this._timing);

  final OverlayState? _overlayState;
  final AnimationTiming _timing;

  /// Resolve the nearest [BoardAnimator] from the tree. Returns a no-op animator
  /// if no [BoardAnimatorScope] is present (so callers never need null checks
  /// and un-wrapped tests stay silent).
  static BoardAnimator of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_BoardAnimatorScope>();
    final timing = AnimationTiming.of(context);
    // Resolve the OverlayState lazily via the scope's key so we always get the
    // live state (the key's currentState may have been null when the scope was
    // first built).
    final overlay = scope?.overlayKey.currentState;
    if (overlay == null || timing.isInstant) {
      return BoardAnimator._noop(timing);
    }
    return BoardAnimator._(overlay, timing);
  }

  BoardAnimator._noop(this._timing) : _overlayState = null;

  /// True when this animator will not spawn anything (instant mode or no
  /// overlay). Exposed for tests.
  bool get isNoop => _overlayState == null || _timing.isInstant;

  // --------------------------------------------------------------------------
  // Rect resolution
  // --------------------------------------------------------------------------

  /// Resolve the current GLOBAL rect of a `GlobalKey`'d widget, or null if it is
  /// not laid out.
  static Rect? rectOf(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  }

  // --------------------------------------------------------------------------
  // Card flights
  // --------------------------------------------------------------------------

  /// Fly a small card face from [fromKey]'s rect to [toKey]'s rect. Used for
  /// market refill (deck → new slot), playing a hand card (hand → play area),
  /// and recruiting (market card → discard pile).
  ///
  /// No-op (calls [onComplete] immediately) in instant mode or if either anchor
  /// can't be resolved.
  void flyCard({
    required GlobalKey fromKey,
    required GlobalKey toKey,
    Color? factionColor,
    String? label,
    double endScale = 0.6,
    VoidCallback? onComplete,
  }) {
    final from = rectOf(fromKey);
    final to = rectOf(toKey);
    _flyCardRects(
      from: from,
      to: to,
      factionColor: factionColor,
      label: label,
      endScale: endScale,
      onComplete: onComplete,
    );
  }

  /// Rect-based variant of [flyCard] for callers that already resolved rects
  /// (e.g. a source captured before a widget was removed from the tree).
  void flyCardRects({
    required Rect? from,
    required Rect? to,
    Color? factionColor,
    String? label,
    double endScale = 0.6,
    VoidCallback? onComplete,
  }) =>
      _flyCardRects(
        from: from,
        to: to,
        factionColor: factionColor,
        label: label,
        endScale: endScale,
        onComplete: onComplete,
      );

  void _flyCardRects({
    required Rect? from,
    required Rect? to,
    Color? factionColor,
    String? label,
    double endScale = 0.6,
    VoidCallback? onComplete,
  }) {
    final overlay = _overlayState;
    if (overlay == null || from == null || to == null) {
      onComplete?.call();
      return;
    }
    _spawn(
      overlay: overlay,
      from: from,
      to: to,
      duration: _timing.cardMove,
      startScale: 1.0,
      endScale: endScale,
      arc: 18,
      child: _MiniCard(color: factionColor ?? GameTheme.gold, label: label),
      onComplete: onComplete,
    );
  }

  // --------------------------------------------------------------------------
  // Resource pips
  // --------------------------------------------------------------------------

  /// Fly [count] resource pips of [icon] from [fromKey] to [toKey], staggered so
  /// gaining N of a resource shows N quick pips arriving one after another.
  ///
  /// No-op in instant mode or if either anchor is unresolved.
  void flyResource({
    required GlobalKey fromKey,
    required GlobalKey toKey,
    required ResourceIcon icon,
    int count = 1,
    VoidCallback? onComplete,
  }) {
    final from = rectOf(fromKey);
    final to = rectOf(toKey);
    flyResourceRects(
      from: from,
      to: to,
      icon: icon,
      count: count,
      onComplete: onComplete,
    );
  }

  /// Rect-based variant of [flyResource].
  void flyResourceRects({
    required Rect? from,
    required Rect? to,
    required ResourceIcon icon,
    int count = 1,
    VoidCallback? onComplete,
  }) {
    final overlay = _overlayState;
    if (overlay == null || from == null || to == null || count <= 0) {
      onComplete?.call();
      return;
    }

    // Cap the visible pips so a big gem gain doesn't flood the overlay; the last
    // pip carries onComplete.
    final pips = count.clamp(1, 6);
    final base = _timing.counterTick;
    // A pip's own flight is a touch longer than a raw counter tick so it reads.
    final flightMs = (base.inMilliseconds * 1.4).round().clamp(120, 900);
    const staggerMs = 70;

    for (var i = 0; i < pips; i++) {
      final isLast = i == pips - 1;
      // Slightly jitter the source so overlapping pips fan out.
      final jitterX = (i - pips / 2) * 6.0;
      final jittered = from.shift(Offset(jitterX, 0));
      Future.delayed(Duration(milliseconds: staggerMs * i), () {
        if (!overlay.mounted) {
          if (isLast) onComplete?.call();
          return;
        }
        _spawn(
          overlay: overlay,
          from: jittered,
          to: to,
          duration: Duration(milliseconds: flightMs),
          startScale: 0.7,
          endScale: 1.15,
          arc: 26,
          child: _Pip(icon: icon),
          onComplete: isLast ? onComplete : null,
        );
      });
    }
  }

  // --------------------------------------------------------------------------
  // Spawning
  // --------------------------------------------------------------------------

  void _spawn({
    required OverlayState overlay,
    required Rect from,
    required Rect to,
    required Duration duration,
    required Widget child,
    double startScale = 1.0,
    double endScale = 1.0,
    double arc = 0.0,
    VoidCallback? onComplete,
  }) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => FlyingWidget(
        from: from,
        to: to,
        duration: duration,
        startScale: startScale,
        endScale: endScale,
        arc: arc,
        onDone: () {
          entry.remove();
          onComplete?.call();
        },
        child: child,
      ),
    );
    overlay.insert(entry);
  }
}

// ---------------------------------------------------------------------------
// Transient visuals
// ---------------------------------------------------------------------------

/// A faction-tinted mini card face that flies between zones.
class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.color, this.label});

  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(color, Colors.white, 0.25)!,
            Color.lerp(color, Colors.black, 0.35)!,
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.55),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: label == null
          ? null
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: FittedBox(
                  child: Text(
                    label!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// A single resource pip (gem / power / mastery / health) that flies to a
/// counter. Wrapped in a soft glow matching the resource colour.
class _Pip extends StatelessWidget {
  const _Pip({required this.icon});

  final ResourceIcon icon;

  Color get _glow {
    switch (icon) {
      case ResourceIcon.gem:
        return BoardChrome.gemBlue;
      case ResourceIcon.power:
        return BoardChrome.powerRed;
      case ResourceIcon.mastery:
        return BoardChrome.masteryGold;
      case ResourceIcon.health:
        return BoardChrome.healthGreen;
      case ResourceIcon.shield:
        return BoardChrome.shieldBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _glow.withValues(alpha: 0.7),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ResourceIconWidget(icon, size: 20),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scope
// ---------------------------------------------------------------------------

/// Wraps a board subtree so [BoardAnimator.of] can resolve an [Overlay] to
/// spawn flights into. Insert this ABOVE the board content (but inside the
/// route) so flights render over the board and its resource bars.
///
/// It supplies its OWN [Overlay] whose first entry is [child]; transient flights
/// are inserted as additional entries above it. This keeps flights on top of the
/// board without depending on the app's root overlay geometry.
class BoardAnimatorScope extends StatefulWidget {
  const BoardAnimatorScope({super.key, required this.child});

  final Widget child;

  @override
  State<BoardAnimatorScope> createState() => _BoardAnimatorScopeState();
}

class _BoardAnimatorScopeState extends State<BoardAnimatorScope> {
  final GlobalKey<OverlayState> _overlayKey = GlobalKey<OverlayState>();

  @override
  Widget build(BuildContext context) {
    return Overlay(
      key: _overlayKey,
      initialEntries: [
        OverlayEntry(
          builder: (context) => _BoardAnimatorScope(
            overlayKey: _overlayKey,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

class _BoardAnimatorScope extends InheritedWidget {
  const _BoardAnimatorScope({
    required this.overlayKey,
    required super.child,
  });

  final GlobalKey<OverlayState> overlayKey;

  @override
  bool updateShouldNotify(_BoardAnimatorScope oldWidget) =>
      overlayKey != oldWidget.overlayKey;
}
