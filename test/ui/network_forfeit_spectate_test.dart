import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/services/game_client.dart';
import 'package:simple_card_game/ui/screens/network_game_screen.dart';

/// Widget coverage for the three network-layer features on the in-game board:
///  - the top-right FORFEIT button + its "Are you sure?" confirm dialog,
///  - the read-only SPECTATING chrome (no Forfeit button, SPECTATING badge),
///  - the server-restart heads-up banner on an unexpected disconnect.
void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  /// A minimal in-progress 2-player redacted state. `_PlayerView.parse` only
  /// needs each player's `id`; the rest default.
  Map<String, dynamic> liveState({required String you}) => {
        'you': you,
        'currentPlayerIndex': 0,
        'turnNumber': 3,
        'isGameOver': false,
        'centerRow': <String>[],
        'destinyRow': <String>[],
        'actionLog': <Map<String, dynamic>>[],
        'players': [
          {'id': 'p0', 'name': 'Alice', 'health': 20, 'mastery': 2},
          {'id': 'p1', 'name': 'Bob', 'health': 20, 'mastery': 1},
        ],
      };

  Future<GameClient> pump(
    WidgetTester tester, {
    required String you,
    bool spectating = false,
    bool serverRestarting = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = GameClient(playerId: 'alice')
      ..gameState = liveState(you: you)
      ..spectating = spectating
      ..serverRestarting = serverRestarting;
    await tester.pumpWidget(
      MaterialApp(home: NetworkGameScreen(client: client)),
    );
    await tester.pump();
    return client;
  }

  testWidgets('a seated player sees a Forfeit button that confirms before '
      'ending the game', (tester) async {
    await pump(tester, you: 'p0');

    final forfeitBtn = find.byKey(const ValueKey('forfeitGameButton'));
    expect(forfeitBtn, findsOneWidget);

    await tester.tap(forfeitBtn);
    await tester.pumpAndSettle();

    // The confirm dialog appears with both actions.
    expect(find.text('Forfeit game?'), findsOneWidget);
    expect(find.byKey(const ValueKey('forfeitCancelButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('forfeitConfirmButton')), findsOneWidget);

    // Cancel dismisses without ending the game.
    await tester.tap(find.byKey(const ValueKey('forfeitCancelButton')));
    await tester.pumpAndSettle();
    expect(find.text('Forfeit game?'), findsNothing);

    // Confirm path closes the dialog (sends forfeit — a no-op without a socket).
    await tester.tap(forfeitBtn);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('forfeitConfirmButton')));
    await tester.pumpAndSettle();
    expect(find.text('Forfeit game?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a spectator board is read-only: SPECTATING badge, no Forfeit',
      (tester) async {
    // A spectator's `you` matches no seat (server sends '').
    await pump(tester, you: '', spectating: true);

    expect(find.text('SPECTATING'), findsOneWidget);
    expect(find.byKey(const ValueKey('forfeitGameButton')), findsNothing);
    // Not the spectator's turn → the End Turn control is absent/disabled.
    expect(find.text('YOUR TURN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unexpected disconnect shows the server-restart heads-up',
      (tester) async {
    await pump(tester, you: 'p0', serverRestarting: true);

    expect(find.byKey(const ValueKey('serverRestartBanner')), findsOneWidget);
    expect(
      find.text('Heads up! Server is restarting… try refreshing shortly.'),
      findsOneWidget,
    );

    // Dismissible.
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('serverRestartBanner')), findsNothing);
  });
}
