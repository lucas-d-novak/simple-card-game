import 'dart:async';

import 'package:flutter/material.dart';

import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';

/// One playable action-log entry: the display line plus an optional card to show
/// as a shrunk-down mini card.
@immutable
class PlaybackEntry {
  const PlaybackEntry({required this.message, this.card});

  /// e.g. "Alice played Chaos Imp". Rendered as the toast text.
  final String message;

  /// The public card involved (played / recruited / activated / destroyed), or
  /// null for card-less events (focus, turn change, direct attack, end turn).
  final CardModel? card;
}

/// A dynamic playback overlay for the networked board: as new public action-log
/// entries arrive, they animate in ONE AT A TIME as a ticker/toast near the top
/// of the board, each showing the message and — when the action involves a card
/// — a small [GameCardWidget]. This lets a player WATCH the opponent's turn
/// unfold instead of only seeing the final state.
///
/// Feed it the CURRENT action-log tail via [entries] (oldest→newest). The widget
/// tracks a high-water mark internally: on first mount it establishes a baseline
/// and does NOT replay the backlog (so joining a game doesn't dump 80 toasts);
/// thereafter each rebuild that grows [entries] enqueues only the newly appended
/// entries and reveals them at a readable pace (~1.2s each), fading in/out.
///
/// Respects [AnimationTiming]: in instant mode (tests / reduced motion) it skips
/// the fade and shows only the newest entry with no pending timers, so widget
/// tests never hang.
class ActionPlaybackOverlay extends StatefulWidget {
  const ActionPlaybackOverlay({
    super.key,
    required this.entries,
    this.perEntry = const Duration(milliseconds: 1200),
  });

  /// The current action-log tail, oldest first. Each element is the raw redacted
  /// map ({turn, playerId?, message, cardId?}) already resolved to a
  /// [PlaybackEntry] by the caller is NOT required — pass [PlaybackEntry]s.
  final List<PlaybackEntry> entries;

  /// How long each toast stays before auto-advancing to the next queued entry.
  final Duration perEntry;

  @override
  State<ActionPlaybackOverlay> createState() => _ActionPlaybackOverlayState();
}

class _ActionPlaybackOverlayState extends State<ActionPlaybackOverlay> {
  /// How many entries we have already accounted for (shown or enqueued). Anything
  /// beyond this index in [widget.entries] is "new" and gets queued. Initialised
  /// to the incoming length so the initial backlog is NOT replayed on join.
  int _consumed = 0;

  final List<PlaybackEntry> _queue = [];
  PlaybackEntry? _current;
  Timer? _timer;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    // Baseline: treat everything present at first mount as already seen.
    _consumed = widget.entries.length;
    _initialised = true;
  }

  @override
  void didUpdateWidget(covariant ActionPlaybackOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ingestNew();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pick up entries that arrived between construction and first layout (and
    // whenever inherited animation settings change).
    if (_initialised) _ingestNew();
  }

  /// Enqueue any entries appended since we last consumed, then start pumping.
  void _ingestNew() {
    final all = widget.entries;
    // Defensive: if the log SHRANK (new game / resync), rebaseline without a
    // burst of stale toasts.
    if (all.length < _consumed) {
      _consumed = all.length;
      return;
    }
    if (all.length == _consumed) return;
    final fresh = all.sublist(_consumed);
    _consumed = all.length;
    _queue.addAll(fresh);
    _pump();
  }

  /// Show the next queued entry if idle.
  void _pump() {
    if (_current != null) return; // a toast is already on screen
    if (_queue.isEmpty) return;

    final next = _queue.removeAt(0);
    setState(() => _current = next);

    final instant = AnimationTiming.of(context).isInstant;
    if (instant) {
      // No timers in instant/reduced-motion mode: collapse the queue to the
      // latest entry so tests don't hang and the board still reflects "an action
      // happened". We keep the most recent one visible statically.
      if (_queue.isNotEmpty) {
        final latest = _queue.removeLast();
        _queue.clear();
        setState(() => _current = latest);
      }
      return;
    }

    _timer?.cancel();
    _timer = Timer(widget.perEntry, () {
      if (!mounted) return;
      setState(() => _current = null);
      _pump();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final instant = AnimationTiming.of(context).isInstant;
    final current = _current;
    final fade = instant
        ? Duration.zero
        : AnimationTiming.of(context).duration(AnimationRole.cardMove);

    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: fade,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1,
            child: child,
          ),
        ),
        child: current == null
            ? const SizedBox.shrink(key: ValueKey('playback-empty'))
            : _PlaybackToast(
                key: ValueKey('playback-$_consumed-${current.message}'),
                entry: current,
              ),
      ),
    );
  }
}

/// The visual toast: a rounded chrome pill with the message and, when present, a
/// shrunk-down mini card.
class _PlaybackToast extends StatelessWidget {
  const _PlaybackToast({super.key, required this.entry});

  final PlaybackEntry entry;

  @override
  Widget build(BuildContext context) {
    final card = entry.card;
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0E2236).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BoardChrome.goldText.withValues(alpha: 0.5)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (card != null && card.name.isNotEmpty) ...[
              // Shrunk-down mini version of the involved card.
              GameCardWidget(
                key: const ValueKey('playback-mini-card'),
                card: card,
                width: 70,
                compact: true,
                showCost: false,
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                entry.message,
                key: const ValueKey('playback-message'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
