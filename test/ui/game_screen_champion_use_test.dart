import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/services/game_service.dart';
import 'package:simple_card_game/ui/screens/game_screen.dart';

/// Regression test for the Giga, Source Adept bug on the LOCAL board
/// (`game_screen.dart`): using a champion that has BOTH a play effect (draw)
/// and an Exhaust-gated activated ability (gain mastery) must fire BOTH halves
/// in one press — the champion is a SINGLE action (see `lib/ui/CLAUDE.md`).
///
/// Before the fix the modal exposed two separate buttons ("Activate" for the
/// draw, "Exhaust" for the ability); tapping only "Exhaust" granted the mastery
/// but silently skipped the draw. This test fails against that old behaviour
/// (hand unchanged) and passes once the single button fires both.
void main() {
  testWidgets(
      'local board: using a champion via its button both draws and grants '
      'the ability', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final game = GameService(playerCount: 2, random: Random(42));

    // A Giga-like champion: draw on activation + Exhaust gains 3 mastery.
    const champ = CardModel(
      id: 'giga_like',
      name: 'Giga-like',
      cost: 0,
      playEffects: [DrawCardsEffect(1)],
      cardType: CardType.champion,
      shield: 4,
      activatedAbility: ActivatedAbility(effects: [GainMasteryEffect(3)]),
    );
    // Place it in play as a persistent fixture (not activated/exhausted yet).
    game.currentPlayer.championsInPlay.add(champ);

    // The 'exhaust' debug hook auto-opens the champion detail modal.
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(gameService: game, debugOpenModal: 'exhaust'),
      ),
    );
    await tester.pumpAndSettle();

    final handBefore = game.currentPlayer.hand.length;
    final masteryBefore = game.currentPlayer.mastery;

    // The single champion action button is labelled "Exhaust" (it has an
    // activated ability). Tapping it must do everything the champion can do.
    expect(find.text('Exhaust'), findsOneWidget);
    await tester.tap(find.text('Exhaust'));
    await tester.pumpAndSettle();

    expect(game.currentPlayer.mastery, masteryBefore + 3,
        reason: 'Exhaust ability (gain 3 mastery) must resolve');
    expect(game.currentPlayer.hand.length, handBefore + 1,
        reason: 'the play-effect draw must ALSO fire (the Giga bug)');
  });
}
