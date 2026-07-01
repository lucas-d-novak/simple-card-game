import 'dart:async';

import 'package:flutter/material.dart';

import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';

/// A prominent, one-shot attack-damage animation for the networked board.
///
/// When one player deals direct damage to another, the server ships a single
/// structured `lastDamage` event (see `LastDamageEvent` / `views.dart`). Both
/// the attacker's and the victim's clients render THIS overlay from that same
/// event, so both screens show WHO hit WHOM for HOW MUCH:
///
///  * a large red **-N** damage number, and
///  * a caption reading **"<Attacker> hit <Victim> for N"**.
///
/// The [isVictim] flag lets the copy read naturally on the victim's own screen
/// ("<Attacker> hit YOU for N") — the number and motion are identical on both
/// sides so the event is unmistakably the same one.
///
/// ## Fire-once semantics
///
/// The widget tracks the incoming [seq] (the engine's monotonic damage counter)
/// as a high-water mark: on first mount it establishes a baseline and does NOT
/// replay whatever the last event was (so joining / resyncing doesn't flash a
/// stale hit); thereafter each rebuild whose [seq] exceeds the mark plays the
/// animation exactly ONCE.
///
/// ## Instant mode (tests / reduced motion)
///
/// Timing comes from [AnimationTiming.of]. In instant mode the widget shows
/// NOTHING and schedules NO timers (mirrors the other board overlays), so widget
/// tests never hang or leak pending timers.
class DamageFlashOverlay extends StatefulWidget {
  const DamageFlashOverlay({
    super.key,
    required this.seq,
    required this.amount,
    required this.attackerName,
    required this.victimName,
    required this.isVictim,
    this.hold = const Duration(milliseconds: 1400),
  });

  /// Monotonic sequence of the current damage event (0 = none yet). A strictly
  /// larger value than last seen triggers the flash.
  final int seq;

  /// Damage dealt (the -N number).
  final int amount;

  /// Display name of the attacker.
  final String attackerName;

  /// Display name of the victim.
  final String victimName;

  /// True when the local viewer is the one who took the damage (changes the
  /// caption to read "… hit YOU for N" and tints the flash toward the viewer's
  /// own health).
  final bool isVictim;

  /// How long the flash stays before fading out (ignored in instant mode).
  final Duration hold;

  @override
  State<DamageFlashOverlay> createState() => _DamageFlashOverlayState();
}

class _DamageFlashOverlayState extends State<DamageFlashOverlay> {
  /// Highest seq we've already handled. Initialised from the incoming seq so the
  /// event present at mount is treated as already seen (no replay on join).
  int _seen = 0;

  /// The event currently being shown, or null when idle.
  ({int amount, String attacker, String victim, bool isVictim})? _current;
  Timer? _timer;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _seen = widget.seq;
    _initialised = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pick up an event that landed between construction and first layout.
    if (_initialised) _maybeFlash();
  }

  @override
  void didUpdateWidget(covariant DamageFlashOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeFlash();
  }

  void _maybeFlash() {
    final seq = widget.seq;
    // Defensive: a lower seq means a new game / resync — rebaseline silently.
    if (seq < _seen) {
      _seen = seq;
      return;
    }
    if (seq <= _seen) return;
    _seen = seq;

    final event = (
      amount: widget.amount,
      attacker: widget.attackerName,
      victim: widget.victimName,
      isVictim: widget.isVictim,
    );

    final instant = AnimationTiming.of(context).isInstant;
    if (instant) {
      // No timers in instant mode: render nothing so tests neither hang nor
      // leak a pending timer. (The state change still already happened; the
      // board reflects the new health.)
      return;
    }

    setState(() => _current = event);
    _timer?.cancel();
    _timer = Timer(widget.hold, () {
      if (!mounted) return;
      setState(() => _current = null);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final instant = AnimationTiming.of(context).isInstant;
    final fade = instant
        ? Duration.zero
        : AnimationTiming.of(context).duration(AnimationRole.cardMove);

    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: fade,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.elasticOut),
            ),
            child: child,
          ),
        ),
        child: current == null
            ? const SizedBox.shrink(key: ValueKey('damage-flash-empty'))
            : _DamageFlash(
                key: ValueKey('damage-flash-$_seen'),
                amount: current.amount,
                attacker: current.attacker,
                victim: current.victim,
                isVictim: current.isVictim,
              ),
      ),
    );
  }
}

/// The visual: a big red "-N" with a caption naming attacker and victim.
class _DamageFlash extends StatelessWidget {
  const _DamageFlash({
    super.key,
    required this.amount,
    required this.attacker,
    required this.victim,
    required this.isVictim,
  });

  final int amount;
  final String attacker;
  final String victim;
  final bool isVictim;

  @override
  Widget build(BuildContext context) {
    // "<Attacker> hit YOU for N" on the victim's own screen; otherwise name both.
    final caption =
        isVictim ? '$attacker hit YOU for $amount' : '$attacker hit $victim for $amount';
    const red = BoardChrome.powerRed;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '-$amount',
            key: const ValueKey('damage-flash-number'),
            style: const TextStyle(
              color: red,
              fontSize: 96,
              fontWeight: FontWeight.w900,
              height: 1.0,
              shadows: [
                Shadow(color: Colors.black, blurRadius: 12, offset: Offset(0, 3)),
                Shadow(color: red, blurRadius: 24),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0E2236).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: red.withValues(alpha: 0.7)),
            ),
            child: Text(
              caption,
              key: const ValueKey('damage-flash-caption'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
