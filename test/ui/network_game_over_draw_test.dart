import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/services/game_client.dart';
import 'package:simple_card_game/ui/screens/network_game_screen.dart';

/// The networked game-over panel (`_NetworkGameOver`) must render a genuine
/// DRAW when the engine reports a mutual knockout — `winType == 'draw'` with no
/// `winnerId` (e.g. an AllPlayersLoseHealthEffect like bound_for_life drops the
/// last players at once). It must NOT invent a winner via
/// `players.where((p) => !p.eliminated).firstOrNull` (which would show a random
/// player or "Unknown Wins"). A real elimination win must still name the winner.
void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  /// A minimal game-over redacted state. `_PlayerView.parse` only requires each
  /// player's `id`; everything else defaults, so this stays small.
  Map<String, dynamic> gameOverState({
    required String? winType,
    required String? winnerId,
    required bool p0Eliminated,
    required bool p1Eliminated,
  }) {
    return {
      'you': 'p0',
      'currentPlayerIndex': 0,
      'turnNumber': 8,
      'isGameOver': true,
      if (winnerId != null) 'winnerId': winnerId,
      if (winType != null) 'winType': winType,
      'centerRow': <String>[],
      'destinyRow': <String>[],
      'actionLog': <Map<String, dynamic>>[],
      'players': [
        {
          'id': 'p0',
          'name': 'Alice',
          'health': p0Eliminated ? 0 : 12,
          'mastery': 4,
          'eliminated': p0Eliminated,
        },
        {
          'id': 'p1',
          'name': 'Bob',
          'health': p1Eliminated ? 0 : 9,
          'mastery': 3,
          'eliminated': p1Eliminated,
        },
      ],
    };
  }

  Future<void> pump(WidgetTester tester, Map<String, dynamic> state) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = GameClient(playerId: 'p0')..gameState = state;
    await tester.pumpWidget(
      MaterialApp(home: NetworkGameScreen(client: client)),
    );
    await tester.pump();
  }

  testWidgets('mutual knockout (winType draw, no winnerId) shows Draw, names no '
      'winner', (tester) async {
    await pump(
      tester,
      gameOverState(
        winType: 'draw',
        winnerId: null,
        p0Eliminated: true,
        p1Eliminated: true,
      ),
    );

    // The draw is rendered explicitly.
    expect(find.text('Draw'), findsOneWidget);
    expect(
      find.text('Mutual knockout — all players eliminated at once'),
      findsOneWidget,
    );

    // No player is fabricated as the winner, and it is not framed as a victory.
    expect(find.textContaining('Wins'), findsNothing);
    expect(find.text('Victory!'), findsNothing);
    expect(find.text('Alice Wins'), findsNothing);
    expect(find.text('Bob Wins'), findsNothing);
    expect(find.text('Unknown Wins'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('real elimination win still names the winner (control)',
      (tester) async {
    await pump(
      tester,
      gameOverState(
        winType: 'elimination',
        winnerId: 'p1',
        p0Eliminated: true,
        p1Eliminated: false,
      ),
    );

    // The surviving opponent is named as the winner — no draw branch.
    expect(find.text('Bob Wins'), findsOneWidget);
    expect(find.text('Draw'), findsNothing);
    expect(
      find.text('Mutual knockout — all players eliminated at once'),
      findsNothing,
    );

    expect(tester.takeException(), isNull);
  });
}
