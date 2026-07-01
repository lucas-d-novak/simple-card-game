import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/ingeminex_entity.dart';
import 'package:simple_card_game/services/game_service.dart';

/// The Ingeminex mechanic (neutral shared champion-row entity):
///   1. APPEARANCE deals its effect to ALL players (including the causer).
///   2. It is a NEUTRAL attackable — ANY player may hit it, not just opponents.
///   3. It dies at 10 accumulated damage; the KILLER (only) gets the reward.

/// Brutality: Attack = all players lose 5; Reward = gain 20 (gems).
IngeminexEntity _brutality() => IngeminexEntity(
      id: 'brutality',
      name: 'Brutality',
      appearanceEffects: const [AllPlayersLoseHealthEffect(5)],
      rewardEffects: const [GainGemsEffect(20)],
    );

/// Torment: Attack = all players lose 2; Reward = gain 4 (gems).
IngeminexEntity _torment() => IngeminexEntity(
      id: 'torment',
      name: 'Torment',
      appearanceEffects: const [AllPlayersLoseHealthEffect(2)],
      rewardEffects: const [GainGemsEffect(4)],
    );

void main() {
  group('Ingeminex appearance → hits ALL players', () {
    test('appearance damage hits every player INCLUDING the causer', () {
      final game = GameService(playerCount: 3, random: Random(7));
      final before = [for (final p in game.players) p.health];

      game.spawnIngeminex(_brutality());

      // Every seat — p0 (the current/causing player) included — lost 5.
      for (var i = 0; i < game.players.length; i++) {
        expect(game.players[i].health, before[i] - 5,
            reason: 'player $i should take the appearance damage');
      }
      // The entity is now in the neutral champion row, undamaged.
      expect(game.ingeminexRow, hasLength(1));
      expect(game.ingeminexRow.single.damageTaken, 0);
      expect(game.ingeminexRow.single.remainingHealth, 10);
    });

    test('appearance broadcasts exactly once (not once per player)', () {
      final game = GameService(playerCount: 4, random: Random(1));
      final p0 = game.players[0].health;
      game.spawnIngeminex(_torment());
      // Torment is "all players lose 2" resolved ONCE — p0 loses 2, not 2*N.
      expect(game.players[0].health, p0 - 2);
    });
  });

  group('Ingeminex is a NEUTRAL attackable (any player)', () {
    test('the current player may attack it even though it is "theirs"', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.spawnIngeminex(_brutality());
      game.currentPlayer.powerPool = 4;

      // Unlike attackChampion (which rejects your own board), the current player
      // CAN attack the neutral Ingeminex.
      expect(game.attackIngeminex('brutality', 4), isTrue);
      expect(game.ingeminexRow.single.damageTaken, 4);
      expect(game.currentPlayer.powerPool, 0);
    });

    test('a DIFFERENT player attacks it on their turn — damage accumulates',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.spawnIngeminex(_brutality());

      // p0 chips 4.
      game.players[0].powerPool = 4;
      expect(game.attackIngeminex('brutality', 4), isTrue);
      expect(game.ingeminexRow.single.damageTaken, 4);

      // Advance to p1 (skip through end-of-turn) and let them chip 3 more.
      game.endTurn();
      expect(game.currentPlayer.id, 'p1');
      game.players[1].powerPool = 3;
      expect(game.attackIngeminex('brutality', 3), isTrue);
      // Damage accumulated ACROSS players and turns.
      expect(game.ingeminexRow.single.damageTaken, 7);
      expect(game.ingeminexRow.single.remainingHealth, 3);
    });

    test('attacking an absent Ingeminex id fails', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.powerPool = 10;
      expect(game.attackIngeminex('nope', 5), isFalse);
    });
  });

  group('Ingeminex dies at 10 damage → KILLER gets the reward', () {
    test('exactly 10 accumulated damage kills it', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.spawnIngeminex(_brutality());
      game.currentPlayer.powerPool = 10;

      expect(game.attackIngeminex('brutality', 10), isTrue);
      expect(game.ingeminexRow, isEmpty, reason: '10 damage kills it');
    });

    test('only the KILLER receives the reward', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.spawnIngeminex(_brutality());

      // p0 chips it to 6 (not lethal) — no reward yet.
      game.players[0].powerPool = 6;
      expect(game.attackIngeminex('brutality', 6), isTrue);
      final p0GemsBefore = game.players[0].gemPool;
      expect(game.ingeminexRow, hasLength(1));

      // p1 lands the killing blow (needs 4 more of the 10).
      game.endTurn();
      final p1GemsBefore = game.players[1].gemPool;
      game.players[1].powerPool = 4;
      expect(game.attackIngeminex('brutality', 4), isTrue);

      // Reward (gain 20 gems) went to the KILLER (p1) ONLY.
      expect(game.players[1].gemPool, p1GemsBefore + 20);
      expect(game.players[0].gemPool, p0GemsBefore,
          reason: 'the non-killer gets nothing');
      expect(game.ingeminexRow, isEmpty);
    });

    test('overkill spends only what is needed to kill (no wasted power)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.spawnIngeminex(_torment());
      game.currentPlayer.powerPool = 25; // way more than the 10 HP

      expect(game.attackIngeminex('torment', 25), isTrue);
      // Only 10 power was spent (10 HP), 15 left over.
      expect(game.currentPlayer.powerPool, 15);
      expect(game.ingeminexRow, isEmpty);
      // Reward (gain 4) applied to the killer.
    });

    test('a player with too little power to cover the spend cannot attack', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.spawnIngeminex(_brutality());
      game.currentPlayer.powerPool = 2;
      // Asking to sink 5 when the entity needs 10 and you only have 2 → fail.
      expect(game.attackIngeminex('brutality', 5), isFalse);
      expect(game.ingeminexRow.single.damageTaken, 0);
    });
  });
}
