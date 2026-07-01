import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/widgets/action_playback_overlay.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';

/// Test host that lets us mutate the [entries] passed to the overlay and rebuild,
/// simulating successive server states whose action-log tail grows.
class _Host extends StatefulWidget {
  const _Host({required this.controller, this.speed});

  final ValueNotifier<List<PlaybackEntry>> controller;
  final AnimationSpeed? speed;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) {
    Widget overlay = ValueListenableBuilder<List<PlaybackEntry>>(
      valueListenable: widget.controller,
      builder: (_, entries, __) =>
          ActionPlaybackOverlay(entries: entries),
    );
    if (widget.speed != null) {
      overlay = AnimationSettings(initialSpeed: widget.speed!, child: overlay);
    }
    return MaterialApp(home: Scaffold(body: overlay));
  }
}

const _card = CardModel(
  id: 'chaos_imp_1',
  name: 'Chaos Imp',
  cost: 2,
  faction: Faction.wraethe,
  cardType: CardType.regular,
  playEffects: [GainPowerEffect(2)],
);

void main() {
  group('ActionPlaybackOverlay', () {
    testWidgets(
        'does NOT replay the initial backlog on first mount', (tester) async {
      final ctl = ValueNotifier<List<PlaybackEntry>>(const [
        PlaybackEntry(message: 'Alice played Crystal'),
        PlaybackEntry(message: 'Alice recruited Chaos Imp', card: _card),
      ]);
      await tester.pumpWidget(_Host(controller: ctl));
      await tester.pump();

      // Nothing from the backlog should be shown.
      expect(find.text('Alice played Crystal'), findsNothing);
      expect(find.text('Alice recruited Chaos Imp'), findsNothing);
      expect(find.byType(GameCardWidget), findsNothing);
    });

    testWidgets(
        'a newly-appended card-carrying entry animates in with a mini card '
        '(instant mode does not hang)', (tester) async {
      // Instant mode: no AnimationSettings wrapper → falls back to instant.
      final ctl = ValueNotifier<List<PlaybackEntry>>(const [
        PlaybackEntry(message: 'Alice played Crystal'),
      ]);
      await tester.pumpWidget(_Host(controller: ctl));
      await tester.pump();

      // Grow the log by ONE card-carrying entry — a new server state arrives.
      ctl.value = const [
        PlaybackEntry(message: 'Alice played Crystal'),
        PlaybackEntry(message: 'Bob played Chaos Imp', card: _card),
      ];
      // No pumpAndSettle needed / possible to hang: instant mode uses no timers.
      await tester.pump();
      await tester.pump();

      expect(find.text('Bob played Chaos Imp'), findsOneWidget);
      // The shrunk-down mini card is shown.
      final mini = tester.widget<GameCardWidget>(find.byType(GameCardWidget));
      expect(mini.card.id, 'chaos_imp_1');
      expect(mini.compact, isTrue);
      expect(mini.width, 70);
    });

    testWidgets(
        'a card-less entry (focus) shows text only, no mini card',
        (tester) async {
      final ctl = ValueNotifier<List<PlaybackEntry>>(const []);
      await tester.pumpWidget(_Host(controller: ctl));
      await tester.pump();

      ctl.value = const [
        PlaybackEntry(message: 'Alice focused (1 gem → 1 mastery)'),
      ];
      await tester.pump();
      await tester.pump();

      expect(find.text('Alice focused (1 gem → 1 mastery)'), findsOneWidget);
      expect(find.byType(GameCardWidget), findsNothing);
    });

    testWidgets(
        'with animation ON, entries play back ONE AT A TIME (queue drains '
        'over time, not all at once)', (tester) async {
      final ctl = ValueNotifier<List<PlaybackEntry>>(const []);
      await tester.pumpWidget(
        _Host(controller: ctl, speed: AnimationSpeed.fast),
      );
      await tester.pump();

      // Two new entries arrive in the same state update.
      ctl.value = const [
        PlaybackEntry(message: 'Alice played Crystal', card: _card),
        PlaybackEntry(message: 'Alice played Blaster'),
      ];
      await tester.pump(); // ingest + show first
      await tester.pump(const Duration(milliseconds: 300)); // fade-in settles

      // Only the FIRST entry is on screen; the second is still queued.
      expect(find.text('Alice played Crystal'), findsOneWidget);
      expect(find.text('Alice played Blaster'), findsNothing);

      // Advance past the per-entry dwell (1.2s) + fade to reveal the second.
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Alice played Blaster'), findsOneWidget);

      // Let the last toast expire so there are no pending timers at teardown.
      await tester.pump(const Duration(milliseconds: 1600));
    });
  });
}
