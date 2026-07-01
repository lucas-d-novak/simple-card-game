import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/services/game_client.dart';
import 'package:simple_card_game/ui/screens/network_game_screen.dart';

/// Networked board: a PASSIVE-only aura champion (its only playEffect is an
/// `addStaticModifier`, no Exhaust ability) must show NO Activate/Exhaust button
/// in its zoom — its aura already applied on enter-play. A normal active
/// play-effect champion still shows an "Activate" button.
void main() {
  late Map<String, dynamic> fixture;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final raw = await rootBundle.loadString('assets/fixtures/net_board.json');
    fixture = (jsonDecode(raw) as Map).cast<String, dynamic>();
  });

  /// Deep-copy the fixture (so mutations don't leak between tests) and inject a
  /// champion into MY (p0) champions plus its card definition.
  Map<String, dynamic> fixtureWithMyChampion(
    Map<String, dynamic> cardJson,
  ) {
    final copy =
        (jsonDecode(jsonEncode(fixture)) as Map).cast<String, dynamic>();
    final id = cardJson['id'] as String;
    (copy['cards'] as Map)[id] = cardJson;
    final p0 = (copy['players'] as List)[0] as Map;
    (p0['championsInPlay'] as List).add(
      {'id': id, 'exhausted': false, 'activated': false, 'underCount': 0},
    );
    return copy;
  }

  Future<void> pumpBoard(WidgetTester tester, Map<String, dynamic> state) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = GameClient(playerId: 'p0')..gameState = state;
    await tester.pumpWidget(MaterialApp(home: NetworkGameScreen(client: client)));
    await tester.pump();
  }

  testWidgets('passive-only champion zoom shows NO Activate/Exhaust button',
      (tester) async {
    final state = fixtureWithMyChampion({
      'id': 'zetta_passive',
      'name': 'Zetta Passive',
      'cost': 5,
      'playEffects': [
        {'type': 'addStaticModifier', 'kind': 'cannotBeAttacked'},
      ],
      'faction': 'homodeus',
      'cardType': 'champion',
      'shield': 2,
    });
    await pumpBoard(tester, state);

    // Tap my passive champion (by its name on the board) to open the zoom.
    await tester.tap(find.text('Zetta Passive').first);
    await tester.pumpAndSettle();

    // The zoom is open (its scaled card is present) but carries no action.
    expect(find.byKey(const ValueKey('detail_zetta_passive')), findsOneWidget);
    expect(find.text('Activate'), findsNothing);
    expect(find.text('Exhaust'), findsNothing);
  });

  testWidgets('active play-effect champion zoom shows an "Activate" button',
      (tester) async {
    final state = fixtureWithMyChampion({
      'id': 'gem_champ',
      'name': 'Gem Champ',
      'cost': 3,
      'playEffects': [
        {'type': 'gainGems', 'amount': 2},
      ],
      'faction': 'undergrowth',
      'cardType': 'champion',
      'shield': 3,
    });
    await pumpBoard(tester, state);

    await tester.tap(find.text('Gem Champ').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('detail_gem_champ')), findsOneWidget);
    expect(find.text('Activate'), findsOneWidget);
    expect(find.text('Exhaust'), findsNothing);
  });
}
