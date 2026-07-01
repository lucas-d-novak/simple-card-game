import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Regression coverage for the "Cloud Oracles may not have given me my draw"
/// bug report. cloud_oracles playEffects = [drawCards 1, conditional(
/// highestMasteryAmongPlayers -> gainGems 2)]. This asserts the FIRST effect
/// (drawCards) resolves when the card is played — i.e. a top-level DrawCardsEffect
/// sitting BEFORE a ConditionalEffect is not skipped.

/// A faithful stand-in for the DB's cloud_oracles printed effects.
CardModel _cloudOracles() => const CardModel(
      id: 'cloud_oracles',
      name: 'Cloud Oracles',
      cost: 2,
      faction: Faction.order,
      cardType: CardType.regular,
      playEffects: [
        DrawCardsEffect(1),
        ConditionalEffect(
          condition:
              GameCondition(kind: GameConditionKind.highestMasteryAmongPlayers),
          then: [GainGemsEffect(2)],
        ),
      ],
    );

CardModel _filler() => const CardModel(
      id: 'filler',
      name: 'Filler',
      cost: 0,
      faction: Faction.none,
      cardType: CardType.regular,
      playEffects: [],
    );

void main() {
  group('Cloud Oracles', () {
    test('drawing a card resolves when Cloud Oracles is played', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;

      // Ensure there IS a card to draw so a grown hand is unambiguous.
      me.drawPile.add(_filler());

      me.hand.add(_cloudOracles());
      final handBefore = me.hand.length; // includes the Cloud Oracles itself

      final ok = game.playCard('cloud_oracles');
      expect(ok, isTrue);

      // Net hand change: -1 (Cloud Oracles left hand into play) +1 (draw) = 0.
      // The proof the draw happened is that the drawn `filler` is now in hand.
      expect(me.hand.length, handBefore,
          reason: 'played 1 card, drew 1 → hand size unchanged');
      expect(me.hand.any((c) => c.id == 'filler'), isTrue,
          reason: 'the drawn card should now be in hand');
    });

    test('gains 2 gems when the player has the mastery lead', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      final opponent = game.players.firstWhere((p) => p.id != me.id);

      // Give the active player a strict mastery lead so the conditional fires.
      me.addMastery(5);
      // opponent stays at 0.
      expect(opponent.mastery, lessThan(me.mastery));

      me.drawPile.add(_filler());
      me.hand.add(_cloudOracles());

      final gemsBefore = me.gemPool;
      game.playCard('cloud_oracles');

      expect(me.gemPool, gemsBefore + 2,
          reason: 'mastery lead → conditional gainGems 2 resolves');
      // The draw also still happened.
      expect(me.hand.any((c) => c.id == 'filler'), isTrue);
    });

    test('no bonus gems when the player is NOT the sole mastery leader', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      final opponent = game.players.firstWhere((p) => p.id != me.id);

      // Tie → not a strict lead → no bonus gems (but the draw still happens).
      me.addMastery(3);
      opponent.addMastery(3);

      me.drawPile.add(_filler());
      me.hand.add(_cloudOracles());

      final gemsBefore = me.gemPool;
      game.playCard('cloud_oracles');

      expect(me.gemPool, gemsBefore,
          reason: 'not the sole leader → no bonus gems');
      expect(me.hand.any((c) => c.id == 'filler'), isTrue,
          reason: 'the draw still resolves regardless of the conditional');
    });
  });
}
