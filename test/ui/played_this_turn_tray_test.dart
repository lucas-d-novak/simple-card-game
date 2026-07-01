import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/ui/widgets/card_detail_modal.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';
import 'package:simple_card_game/ui/widgets/played_this_turn_tray.dart';

void main() {
  const played = CardModel(
    id: 'played_1',
    name: 'Reactor Monk',
    cost: 2,
    playEffects: [GainGemsEffect(2)],
    faction: Faction.homodeus,
    cardType: CardType.regular,
  );

  const fastPlayed = CardModel(
    id: 'fast_1',
    name: 'Shadow Fiend',
    cost: 3,
    playEffects: [GainPowerEffect(3)],
    faction: Faction.wraethe,
    cardType: CardType.mercenary,
  );

  Future<void> pumpTray(
    WidgetTester tester, {
    List<CardModel> playedCards = const [],
    List<CardModel> fastPlayedCards = const [],
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayedThisTurnTray(
            playedCards: playedCards,
            fastPlayedCards: fastPlayedCards,
            screenWidth: 1400,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders a small card for a played card', (tester) async {
    await pumpTray(tester, playedCards: [played]);

    // The tray tile for the played card is present, and it renders a card face.
    expect(find.byKey(const ValueKey('playedTray_played_1')), findsOneWidget);
    expect(find.text('Reactor Monk'), findsOneWidget);

    // No red fast-play shading on a normally-played card.
    expect(find.byKey(const ValueKey('fastPlayShade_played_1')), findsNothing);
  });

  testWidgets('a fast-played card shows the red shading', (tester) async {
    await pumpTray(
      tester,
      playedCards: [played],
      fastPlayedCards: [fastPlayed],
    );

    // The fast-played card carries the distinct red-shade overlay + FAST tag;
    // the normally-played one does not.
    expect(find.byKey(const ValueKey('fastPlayShade_fast_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('fastPlayShade_played_1')), findsNothing);
    expect(find.text('FAST'), findsOneWidget);
  });

  testWidgets('tapping a card opens the zoom modal with no action buttons',
      (tester) async {
    await pumpTray(tester, playedCards: [played]);

    await tester.tap(find.byKey(const ValueKey('playedTray_played_1')));
    await tester.pumpAndSettle();

    // The zoom modal is open on the tapped card...
    final modalFinder = find.byType(CardDetailModal);
    expect(modalFinder, findsOneWidget);
    expect(find.byKey(const ValueKey('detail_played_1')), findsOneWidget);

    // ...and it has NO action buttons (the card is already played): both the
    // primary and secondary action builders are null.
    final modal = tester.widget<CardDetailModal>(modalFinder);
    expect(modal.actionFor, isNull);
    expect(modal.secondaryActionFor, isNull);
  });

  testWidgets('empty tray takes no space', (tester) async {
    await pumpTray(tester);
    // Nothing renders when there is nothing played this turn.
    expect(find.byKey(const ValueKey('playedThisTurnTray')), findsNothing);
    expect(find.byType(GameCardWidget), findsNothing);
  });
}
