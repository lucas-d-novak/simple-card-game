import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/game_state_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Coverage for the action-log enhancements:
///  - TASK 2: guard blocks + shield-absorbed notes in the log.
///  - TASK 3: structured resource-grant data on `played` entries (round-trips
///    through GameStateCodec, so it also ships to clients).

CardModel _card({
  required String id,
  Faction faction = Faction.none,
  CardType cardType = CardType.regular,
  int shield = 0,
  bool guard = false,
  List<CardEffect> playEffects = const [],
}) =>
    CardModel(
      id: id,
      name: id,
      cost: 0,
      faction: faction,
      cardType: cardType,
      shield: shield,
      hasGuard: guard,
      playEffects: playEffects,
    );

void main() {
  group('Action log — guard / shield notes (TASK 2)', () {
    test('guard blocking a direct attack is logged', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final defender = game.players.firstWhere((p) => p.id != attacker.id);

      defender.championsInPlay
          .add(_card(id: 'guardian', cardType: CardType.champion, guard: true));
      attacker.powerPool = 5;

      final ok = game.attackPlayer(defender.id, 3);
      expect(ok, isFalse, reason: 'guard blocks the direct attack');
      expect(
        game.actionLog.any((e) => e.message.contains('guard blocked')),
        isTrue,
        reason: 'a guard-blocked attack should be logged',
      );
    });

    test('destroying a shielded champion notes the absorbed shield', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final defender = game.players.firstWhere((p) => p.id != attacker.id);

      defender.championsInPlay
          .add(_card(id: 'wall', cardType: CardType.champion, shield: 4));
      attacker.powerPool = 4;

      final ok = game.attackChampion('wall', defender.id);
      expect(ok, isTrue);
      final destroyEntry =
          game.actionLog.lastWhere((e) => e.message.contains('destroyed'));
      expect(destroyEntry.message, contains('shield 4 absorbed'));
    });
  });

  group('Action log — resource grant icons data (TASK 3)', () {
    test('a played card records its flat resource grants', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.hand.add(_card(id: 'gemmy', playEffects: const [
        GainGemsEffect(3),
        GainPowerEffect(1),
      ]));

      game.playCard('gemmy');
      final entry = game.actionLog.lastWhere((e) => e.cardId == 'gemmy');
      expect(entry.grants.length, 2);
      final gem = entry.grants.firstWhere((g) => g.kind == 'gem');
      final power = entry.grants.firstWhere((g) => g.kind == 'power');
      expect(gem.amount, 3);
      expect(power.amount, 1);
    });

    test('conditional / scaling grants are NOT counted (never a wrong icon)',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.hand.add(_card(id: 'condy', playEffects: [
        const GainGemsEffect(1),
        ConditionalEffect(
          condition: const GameCondition(
              kind: GameConditionKind.highestMasteryAmongPlayers),
          then: const [GainGemsEffect(5)],
        ),
      ]));

      game.playCard('condy');
      final entry = game.actionLog.lastWhere((e) => e.cardId == 'condy');
      // Only the flat +1 gem is counted; the conditional +5 is skipped.
      expect(entry.grants.length, 1);
      expect(entry.grants.single.kind, 'gem');
      expect(entry.grants.single.amount, 1);
    });

    test('grants round-trip through GameStateCodec', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.hand.add(_card(id: 'shiny', playEffects: const [
        GainMasteryEffect(2),
        GainHealthEffect(1),
      ]));
      game.playCard('shiny');

      final json = GameStateCodec.encode(game);
      final restored = GameStateCodec.decode(json);

      final entry =
          restored.actionLog.lastWhere((e) => e.cardId == 'shiny');
      expect(entry.grants.map((g) => g.kind).toSet(),
          {'mastery', 'health'});
      expect(entry.grants.firstWhere((g) => g.kind == 'mastery').amount, 2);
      expect(entry.grants.firstWhere((g) => g.kind == 'health').amount, 1);
    });
  });
}
