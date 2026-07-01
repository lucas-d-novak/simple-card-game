import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/services/game_client.dart';
import 'package:simple_card_game/services/game_service.dart';
import 'package:simple_card_game/ui/screens/game_screen.dart';
import 'package:simple_card_game/ui/screens/network_game_screen.dart';
import 'package:simple_card_game/ui/widgets/board_animator.dart';

/// Smoke tests for the board fly-animation wiring. Boards are pumped WITHOUT an
/// AnimationSettings ancestor, so [AnimationTiming.of] falls back to instant and
/// [BoardAnimator] must spawn nothing and complete synchronously. If it leaked a
/// timer or spawned an overlay entry, `pumpAndSettle` would hang / fail — so the
/// suite passing IS the signal that instant-mode is honoured.
void main() {
  group('local board (GameScreen) with BoardAnimatorScope', () {
    testWidgets('pumps and settles cleanly (instant mode, no timer leak)',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final game = GameService(playerCount: 2, random: Random(42));
      await tester.pumpWidget(MaterialApp(home: GameScreen(gameService: game)));
      await tester.pumpAndSettle();

      // The animator scope is present but inert (no AnimationSettings → instant).
      expect(find.byType(BoardAnimatorScope), findsOneWidget);
    });

    testWidgets('playing a hand card via the zoom modal leaves no pending timers',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final game = GameService(playerCount: 2, random: Random(42));
      final firstCard = game.currentPlayer.hand.first;

      await tester.pumpWidget(MaterialApp(home: GameScreen(gameService: game)));
      await tester.pumpAndSettle();

      // Tap the first hand card → opens the zoom modal, which carries a Play
      // action that routes through _playCard (and its fly-resource trigger).
      await tester.tap(find.text(firstCard.name).first, warnIfMissed: false);
      await tester.pumpAndSettle();

      final playBtn = find.text('Play');
      if (playBtn.evaluate().isNotEmpty) {
        await tester.tap(playBtn.first);
        await tester.pumpAndSettle();
      }
      // Settling must complete without a pending-timer failure — the fly
      // triggers are no-ops in instant mode.
      expect(tester.takeException(), isNull);
    });
  });

  group('networked board (NetworkGameScreen) with BoardAnimatorScope', () {
    late Map<String, dynamic> fixture;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final raw = await rootBundle.loadString('assets/fixtures/net_board.json');
      fixture = (jsonDecode(raw) as Map).cast<String, dynamic>();
    });

    testWidgets('pumps and settles cleanly (instant mode, no timer leak)',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final me = fixture['you'] as String? ?? 'p0';
      final client = GameClient(playerId: me)..gameState = fixture;

      await tester.pumpWidget(
        MaterialApp(home: NetworkGameScreen(client: client)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BoardAnimatorScope), findsOneWidget);
    });
  });
}
