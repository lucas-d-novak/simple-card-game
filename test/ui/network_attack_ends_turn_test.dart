import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/services/game_client.dart';
import 'package:simple_card_game/ui/screens/network_game_screen.dart';

/// The networked "Attack + End Turn" button: one press delivers the face attack
/// AND advances the turn — the attack action is sent, THEN endTurn.
class _RecordingClient extends GameClient {
  _RecordingClient({required super.playerId});

  final List<String> actions = [];

  @override
  void attackPlayer(String targetId, int amount) => actions.add('attack');

  @override
  void endTurn() => actions.add('endTurn');
}

void main() {
  late Map<String, dynamic> baseFixture;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final raw = await rootBundle.loadString('assets/fixtures/net_board.json');
    baseFixture = (jsonDecode(raw) as Map).cast<String, dynamic>();
  });

  /// A state where it's p0's turn, they have power and an EMPTY hand, and no
  /// champions are in play on either side — so the morphing primary button
  /// surfaces the Attack (+ End Turn) phase and a direct attack takes the
  /// non-killable path (no confirm dialog).
  Map<String, dynamic> attackReadyState() {
    final state =
        (jsonDecode(jsonEncode(baseFixture)) as Map).cast<String, dynamic>();
    for (final p in (state['players'] as List).cast<Map>()) {
      p['championsInPlay'] = <dynamic>[];
      if (p['id'] == 'p0') {
        p['hand'] = <String>[];
        p['handCount'] = 0;
        p['powerPool'] = 5;
      }
    }
    return state;
  }

  Future<void> pumpBoard(WidgetTester tester, GameClient client) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(MaterialApp(home: NetworkGameScreen(client: client)));
    await tester.pump();
  }

  testWidgets('pressing Attack + End Turn sends the attack THEN ends the turn',
      (tester) async {
    final client = _RecordingClient(playerId: 'p0')
      ..gameState = attackReadyState();
    await pumpBoard(tester, client);

    final button = find.textContaining('Attack + End Turn');
    expect(button, findsOneWidget, reason: 'the morphing button is in the '
        'Attack phase and advertises it also ends the turn');

    await tester.tap(button);
    await tester.pump();

    // Both actions fired, attack BEFORE endTurn — the turn is committed only
    // after the attack.
    expect(client.actions, ['attack', 'endTurn']);
  });
}
