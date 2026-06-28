import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/player_state.dart';

void main() {
  group('PlayerState', () {
    late PlayerState player;

    setUp(() {
      player = PlayerState(id: 'p1', name: 'Alice');
    });

    test('initializes with 50 HP, 0 mastery, and empty zones', () {
      expect(player.health, 50);
      expect(player.mastery, 0);
      expect(player.gemPool, 0);
      expect(player.powerPool, 0);
      expect(player.hand, isEmpty);
      expect(player.drawPile, isEmpty);
      expect(player.discardPile, isEmpty);
      expect(player.playedThisTurn, isEmpty);
      expect(player.championsInPlay, isEmpty);
      expect(player.isEliminated, false);
    });

    test('addMastery increases mastery', () {
      player.addMastery(5);
      expect(player.mastery, 5);
      player.addMastery(3);
      expect(player.mastery, 8);
    });

    test('addMastery ignores zero and negative amounts', () {
      player.addMastery(5);
      player.addMastery(0);
      expect(player.mastery, 5);
      player.addMastery(-3);
      expect(player.mastery, 5);
    });

    test('health can go above 50 via heal', () {
      player.heal(10);
      expect(player.health, 60);
    });

    test('takeDamage reduces health', () {
      player.takeDamage(20);
      expect(player.health, 30);
    });

    test('isEliminated is true at 0 and below', () {
      player.takeDamage(50);
      expect(player.isEliminated, true);
      expect(player.health, 0);

      final player2 = PlayerState(id: 'p2', name: 'Bob');
      player2.takeDamage(60);
      expect(player2.isEliminated, true);
      expect(player2.health, -10);
    });

    test('resetTurnResources zeros gems and power but not mastery', () {
      player.gemPool = 5;
      player.powerPool = 3;
      player.addMastery(7);

      player.resetTurnResources();

      expect(player.gemPool, 0);
      expect(player.powerPool, 0);
      expect(player.mastery, 7);
    });

    test('cleanupTurn moves regular cards to discard', () {
      const regularCard = CardModel(
        id: 'r1',
        name: 'Crystal',
        cost: 0,
        playEffects: [GainGemsEffect(1)],
      );

      player.playedThisTurn.add(regularCard);
      final mercenaries = player.cleanupTurn();

      expect(mercenaries, isEmpty);
      expect(player.playedThisTurn, isEmpty);
      expect(player.discardPile, hasLength(1));
      expect(player.discardPile.first.id, 'r1');
    });

    test('cleanupTurn returns mercenaries separately', () {
      const regularCard = CardModel(
        id: 'r1',
        name: 'Crystal',
        cost: 0,
        playEffects: [GainGemsEffect(1)],
      );
      const mercCard = CardModel(
        id: 'm1',
        name: 'Chaos Imp',
        cost: 2,
        playEffects: [GainPowerEffect(3)],
        cardType: CardType.mercenary,
      );

      player.playedThisTurn.addAll([regularCard, mercCard]);
      final mercenaries = player.cleanupTurn();

      expect(mercenaries, hasLength(1));
      expect(mercenaries.first.id, 'm1');
      expect(player.discardPile, hasLength(1));
      expect(player.discardPile.first.id, 'r1');
      expect(player.playedThisTurn, isEmpty);
    });

    test('cleanupTurn does not affect championsInPlay', () {
      const champion = CardModel(
        id: 'ch1',
        name: 'Shield Bearer',
        cost: 4,
        playEffects: [GainPowerEffect(2)],
        cardType: CardType.champion,
      );

      player.championsInPlay.add(champion);
      player.cleanupTurn();

      expect(player.championsInPlay, hasLength(1));
      expect(player.championsInPlay.first.id, 'ch1');
    });
  });
}
