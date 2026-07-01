import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/services/game_client.dart';
import 'package:simple_card_game/ui/screens/network_game_screen.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';

/// Mobile-PORTRAIT layout of the networked board: the six-card market re-flows
/// into a 3x2 grid of larger cards, and the board lays out without overflow. In
/// LANDSCAPE the single-row market is unchanged. This is a responsive change,
/// so both orientations are asserted here.
void main() {
  late Map<String, dynamic> fixture;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final raw = await rootBundle.loadString('assets/fixtures/net_board.json');
    fixture = (jsonDecode(raw) as Map).cast<String, dynamic>();
  });

  GameClient clientFor(Map<String, dynamic> state) {
    final me = state['you'] as String? ?? 'p0';
    return GameClient(playerId: me)..gameState = state;
  }

  Future<void> pumpBoard(WidgetTester tester, Size physicalSize) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = clientFor(fixture);
    await tester
        .pumpWidget(MaterialApp(home: NetworkGameScreen(client: client)));
    await tester.pump();
  }

  /// Center-row card ids from the fixture — the 6 market slots.
  List<String> centerRowIds() =>
      (fixture['centerRow'] as List).cast<String>();

  /// The number of GameCardWidgets whose card id is one of the center-row ids.
  int marketCardCount(WidgetTester tester) {
    final ids = centerRowIds().toSet();
    return tester
        .widgetList<GameCardWidget>(find.byType(GameCardWidget))
        .where((w) => ids.contains(w.card.id))
        .length;
  }

  /// The distinct top-Y offsets of the market cards — one value = single row,
  /// two values = the 3x2 portrait grid.
  Set<double> marketRowTops(WidgetTester tester) {
    final ids = centerRowIds().toSet();
    final tops = <double>{};
    for (final el in find.byType(GameCardWidget).evaluate()) {
      final w = el.widget as GameCardWidget;
      if (!ids.contains(w.card.id)) continue;
      tops.add(tester.getTopLeft(find.byWidget(w)).dy.roundToDouble());
    }
    return tops;
  }

  testWidgets(
      'mobile PORTRAIT renders the 6-card market as a 3x2 grid without overflow',
      (tester) async {
    // A tall, narrow phone surface (portrait): width < mobileMaxWidth (600).
    await pumpBoard(tester, const Size(390, 844));

    // All six market cards render (re-flowed into two rows of three).
    expect(marketCardCount(tester), 6,
        reason: 'all six center-row cards render in portrait');

    // The 3x2 grid means the market cards sit on TWO distinct rows.
    expect(marketRowTops(tester).length, 2,
        reason: 'portrait market is two rows of three (3x2 grid)');

    // No layout overflow was thrown while building the portrait board.
    expect(tester.takeException(), isNull);
  });

  testWidgets('LANDSCAPE keeps the single-row market layout', (tester) async {
    // A comfortable landscape surface (width > mobileMaxWidth, ample height so
    // the board fits). All six cards render in ONE row — the portrait 3x2
    // re-flow must NOT apply.
    await pumpBoard(tester, const Size(1200, 900));

    expect(marketCardCount(tester), 6,
        reason: 'all six center-row cards render in landscape');
    expect(marketRowTops(tester).length, 1,
        reason: 'landscape market stays a single row of six');
    expect(tester.takeException(), isNull);
  });
}
