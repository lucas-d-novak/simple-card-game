import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/services/game_client.dart';
import 'package:simple_card_game/ui/screens/network_game_screen.dart';

/// §C Ingeminex — networked board UI: a shared neutral boss shipped in the
/// redacted `ingeminex` array renders as a tappable tile with an HP bar; tapping
/// it (on your turn, with power) sends an `attackIngeminex` action.
class _RecordingClient extends GameClient {
  _RecordingClient({required super.playerId});

  final List<Map<String, dynamic>> sent = [];

  @override
  void sendAction(String type, [Map<String, dynamic> extra = const {}]) {
    sent.add({'type': type, ...extra});
  }
}

void main() {
  late Map<String, dynamic> baseFixture;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final raw = await rootBundle.loadString('assets/fixtures/net_board.json');
    baseFixture = (jsonDecode(raw) as Map).cast<String, dynamic>();
  });

  /// p0's turn with power, plus one shared Ingeminex boss (3 of 10 damage).
  Map<String, dynamic> stateWithBoss() {
    final state =
        (jsonDecode(jsonEncode(baseFixture)) as Map).cast<String, dynamic>();
    for (final p in (state['players'] as List).cast<Map>()) {
      if (p['id'] == 'p0') p['powerPool'] = 5;
    }
    state['ingeminex'] = [
      {
        'id': 'brutality',
        'name': 'Brutality',
        'maxHealth': 10,
        'damageTaken': 3,
        'remainingHealth': 7,
      },
    ];
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

  testWidgets('a shared Ingeminex boss renders with its name + HP', (tester) async {
    final client = _RecordingClient(playerId: 'p0')..gameState = stateWithBoss();
    await pumpBoard(tester, client);

    expect(find.byKey(const ValueKey('ingeminex_brutality')), findsOneWidget);
    expect(find.text('Brutality'), findsWidgets);
    expect(find.text('7/10 HP'), findsOneWidget);
  });

  testWidgets('tapping the boss sends an attackIngeminex action', (tester) async {
    final client = _RecordingClient(playerId: 'p0')..gameState = stateWithBoss();
    await pumpBoard(tester, client);

    await tester.tap(find.byKey(const ValueKey('ingeminex_brutality')));
    await tester.pump();

    final attack = client.sent.where((a) => a['type'] == 'attackIngeminex');
    expect(attack, hasLength(1));
    expect(attack.single['ingeminexId'], 'brutality');
    expect(attack.single['amount'], 5, reason: 'commits the whole power pool');
  });
}
