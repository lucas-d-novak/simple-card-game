import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/services/game_client.dart';
import 'package:simple_card_game/ui/screens/network_game_screen.dart';

/// The networked market gesture model: TAP a card → SELECT it (open the detail
/// popup). The popup offers Recruit, plus Fast Play for MERCENARIES only.
void main() {
  late Map<String, dynamic> fixture;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final raw =
        await rootBundle.loadString('assets/fixtures/net_board.json');
    fixture = (jsonDecode(raw) as Map).cast<String, dynamic>();
  });

  GameClient clientFor(Map<String, dynamic> state) {
    final me = state['you'] as String? ?? 'p0';
    return GameClient(playerId: me)..gameState = state;
  }

  Future<void> pumpBoard(WidgetTester tester, GameClient client) async {
    // A wide landscape surface so the full board lays out without overflow.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: NetworkGameScreen(client: client)));
    await tester.pump();
  }

  /// Find a center-row card id of the given cardType from the fixture.
  String centerCardOfType(String cardType) {
    final cards = (fixture['cards'] as Map).cast<String, dynamic>();
    for (final id in (fixture['centerRow'] as List).cast<String>()) {
      final c = cards[id] as Map?;
      if (c != null && c['cardType'] == cardType) return id;
    }
    throw StateError('no center-row card of type $cardType in fixture');
  }

  testWidgets('tapping a market MERCENARY shows Recruit AND Fast Play', (
    tester,
  ) async {
    final client = clientFor(fixture);
    await pumpBoard(tester, client);

    // Long-press opens the same popup as tap (both call _openMarketDetail); use
    // it here since the market card is a tap target within a scrollable row.
    final mercName = ((fixture['cards']
            as Map)[centerCardOfType('mercenary')] as Map)['name'] as String;

    // The card face shows the card name; tap it to open the detail popup.
    final cardFinder = find.text(mercName).first;
    expect(cardFinder, findsWidgets);
    await tester.tap(cardFinder);
    await tester.pumpAndSettle();

    expect(find.text('Recruit'), findsOneWidget,
        reason: 'mercenary popup offers Recruit');
    expect(find.text('Fast Play'), findsOneWidget,
        reason: 'mercenary popup offers Fast Play');
  });

  testWidgets('tapping a market CHAMPION shows Recruit but NOT Fast Play', (
    tester,
  ) async {
    final client = clientFor(fixture);
    await pumpBoard(tester, client);

    final champName = ((fixture['cards']
            as Map)[centerCardOfType('champion')] as Map)['name'] as String;

    await tester.tap(find.text(champName).first);
    await tester.pumpAndSettle();

    expect(find.text('Recruit'), findsOneWidget,
        reason: 'champion popup offers Recruit');
    expect(find.text('Fast Play'), findsNothing,
        reason: 'champions cannot be fast-played');
  });
}
