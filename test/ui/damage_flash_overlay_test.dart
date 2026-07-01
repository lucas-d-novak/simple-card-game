import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/services/game_client.dart';
import 'package:simple_card_game/ui/screens/network_game_screen.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/widgets/damage_flash_overlay.dart';

/// Test host that lets us mutate the [seq] passed to the overlay and rebuild,
/// simulating successive server states carrying a growing damage sequence.
class _Host extends StatefulWidget {
  const _Host({
    required this.controller,
    required this.isVictim,
    this.speed,
  });

  final ValueNotifier<int> controller;
  final bool isVictim;
  final AnimationSpeed? speed;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) {
    Widget overlay = ValueListenableBuilder<int>(
      valueListenable: widget.controller,
      builder: (_, seq, __) => DamageFlashOverlay(
        seq: seq,
        amount: 4,
        attackerName: 'Alice',
        victimName: 'Bob',
        isVictim: widget.isVictim,
      ),
    );
    if (widget.speed != null) {
      overlay = AnimationSettings(initialSpeed: widget.speed!, child: overlay);
    }
    return MaterialApp(home: Scaffold(body: overlay));
  }
}

void main() {
  group('DamageFlashOverlay', () {
    testWidgets('does NOT replay the event present at first mount',
        (tester) async {
      // A damage event (seq 3) is already present when the widget mounts (e.g.
      // a player joins/resyncs mid-game). It must NOT flash on that first frame.
      final ctl = ValueNotifier<int>(3);
      await tester.pumpWidget(
        _Host(controller: ctl, isVictim: false, speed: AnimationSpeed.fast),
      );
      await tester.pump();

      expect(find.text('-4'), findsNothing);
      expect(find.textContaining('hit'), findsNothing);
    });

    testWidgets(
        'flashes ONCE when a new (higher) seq arrives, then fades out',
        (tester) async {
      final ctl = ValueNotifier<int>(0);
      await tester.pumpWidget(
        _Host(controller: ctl, isVictim: false, speed: AnimationSpeed.fast),
      );
      await tester.pump();

      // A new direct-damage event lands.
      ctl.value = 1;
      await tester.pump(); // ingest + show
      await tester.pump(const Duration(milliseconds: 400)); // fade/scale settles

      expect(find.text('-4'), findsOneWidget);
      // Attacker names both sides when the viewer is NOT the victim.
      expect(find.text('Alice hit Bob for 4'), findsOneWidget);

      // After the hold + fade the flash clears.
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('-4'), findsNothing);
    });

    testWidgets('victim screen reads "… hit YOU for N"', (tester) async {
      final ctl = ValueNotifier<int>(0);
      await tester.pumpWidget(
        _Host(controller: ctl, isVictim: true, speed: AnimationSpeed.fast),
      );
      await tester.pump();

      ctl.value = 1;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Alice hit YOU for 4'), findsOneWidget);

      // Drain the hold timer so nothing is pending at teardown.
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets(
        'instant mode renders nothing and schedules NO timers', (tester) async {
      // No AnimationSettings wrapper → instant mode.
      final ctl = ValueNotifier<int>(0);
      await tester.pumpWidget(_Host(controller: ctl, isVictim: false));
      await tester.pump();

      ctl.value = 1;
      await tester.pump();
      await tester.pump();

      // Nothing shown, and no pending timers (pump would throw otherwise).
      expect(find.text('-4'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('NetworkGameScreen with lastDamage', () {
    late Map<String, dynamic> fixture;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final raw = await rootBundle.loadString('assets/fixtures/net_board.json');
      fixture = (jsonDecode(raw) as Map).cast<String, dynamic>();
    });

    testWidgets(
        'board builds with a lastDamage present (no exceptions, no timers '
        'in instant mode)', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final state = Map<String, dynamic>.from(fixture);
      final me = state['you'] as String? ?? 'p0';
      final players = (state['players'] as List).cast<Map>();
      final otherId = players
          .map((p) => p['id'] as String)
          .firstWhere((id) => id != me, orElse: () => me);
      // Attach a fresh direct-damage event: someone hit the local player.
      state['lastDamage'] = {
        'seq': 1,
        'fromId': otherId,
        'toId': me,
        'fromName': 'Opponent',
        'toName': 'You',
        'amount': 5,
      };

      final client = GameClient(playerId: me)..gameState = state;
      await tester
          .pumpWidget(MaterialApp(home: NetworkGameScreen(client: client)));
      await tester.pump();
      await tester.pump();

      // The board built and the overlay is in the tree; instant mode means it
      // renders nothing and leaves no pending timers.
      expect(find.byType(DamageFlashOverlay), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
