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

  group('Action log — player references use SEAT IDS (name-resolvable)', () {
    // The UI's shared log renderer (and the server name rewrite) resolve engine
    // seat ids (`p0`) to real player names. So messages that reference a player
    // must embed the SEAT ID, never the raw PlayerState.name — otherwise the
    // networked board shows "Player 2" instead of the lobby username.
    test('direct-attack damage references the victim by seat id', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final victim = game.players.firstWhere((p) => p.id != attacker.id);
      attacker.powerPool = 5;

      game.attackPlayer(victim.id, 3);
      final entry =
          game.actionLog.lastWhere((e) => e.message.contains('damage to'));
      expect(entry.message, 'dealt 3 damage to ${victim.id}');
      expect(entry.message, isNot(contains(victim.name)));
    });

    test('turn header references the current player by seat id', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.endTurn(); // advances the turn → logs a header for the next player
      final header =
          game.actionLog.lastWhere((e) => e.message.contains('Turn'));
      expect(header.message, '— Turn 1: ${game.currentPlayer.id} —');
    });

    test('win message references the winner by seat id', () {
      final game = GameService(playerCount: 2, random: Random(7));
      // Eliminate p0; ending the (eliminated) player's turn advances to the sole
      // survivor and logs the win via _advanceTurn.
      game.players[0].health = 0;
      game.endTurn();
      expect(game.isGameOver, isTrue);
      final win = game.actionLog.lastWhere((e) => e.message.contains('wins!'));
      expect(win.message, '${game.winnerId} wins!');
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

    test('a conditional bonus that does NOT fire is not shown (delta = reality)',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      // Both players at mastery 0 → not the (strict) highest → +5 does NOT fire.
      me.hand.add(_card(id: 'condy', playEffects: [
        const GainGemsEffect(1),
        const ConditionalEffect(
          condition: GameCondition(
              kind: GameConditionKind.highestMasteryAmongPlayers),
          then: [GainGemsEffect(5)],
        ),
      ]));

      game.playCard('condy');
      final entry = game.actionLog.lastWhere((e) => e.cardId == 'condy');
      // Only the realized +1 gem is shown; the un-fired conditional is not.
      expect(entry.grants.length, 1);
      expect(entry.grants.single.kind, 'gem');
      expect(entry.grants.single.amount, 1);
    });

    test('a conditional bonus that DOES fire is shown at its realized total', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.mastery = 5; // strictly highest → the +5 conditional fires
      me.hand.add(_card(id: 'condy', playEffects: [
        const GainGemsEffect(1),
        const ConditionalEffect(
          condition: GameCondition(
              kind: GameConditionKind.highestMasteryAmongPlayers),
          then: [GainGemsEffect(5)],
        ),
      ]));

      game.playCard('condy');
      final entry = game.actionLog.lastWhere((e) => e.cardId == 'condy');
      // Delta captures the realized 1 + 5 = 6 gems (the old flat reader showed 1).
      final gem = entry.grants.firstWhere((g) => g.kind == 'gem');
      expect(gem.amount, 6);
    });

    test('a SCALING Infinity Shard logs its realized POWER (old reader skipped it)',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      // InfinityShardEffect is not a flat GainX, so the old static reader logged
      // NOTHING. It grants power scaled by mastery tier (0 below mastery 5, 6 at
      // mastery 10-14). At mastery 10 the delta reader captures the +6 power.
      me.mastery = 10;
      me.hand.add(_card(id: 'shard', playEffects: const [InfinityShardEffect()]));
      game.playCard('shard');
      final entry = game.actionLog.lastWhere((e) => e.cardId == 'shard');
      final power = entry.grants.firstWhere((g) => g.kind == 'power');
      expect(power.amount, 6);
    });

    test('grants round-trip through GameStateCodec', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      // Below the 50-HP cap so the +1 health actually registers (a player at the
      // cap would gain 0 and the health grant would correctly drop out).
      me.health = 40;
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
