import 'dart:math';

import 'package:shards_server/protocol.dart';
import 'package:shards_server/views.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/ingeminex_entity.dart';
import 'package:simple_card_game/services/game_service.dart';
import 'package:test/test.dart';

/// §C Ingeminex — server layer: the neutral entity is PUBLIC in every redacted
/// view (no hidden info), players spawn/attack it via the protocol, and the
/// killing blow awards the reward.

IngeminexEntity _torment() => IngeminexEntity(
      id: 'torment',
      name: 'Torment',
      appearanceEffects: const [AllPlayersLoseHealthEffect(2)],
      rewardEffects: const [GainMasteryEffect(4)],
    );

GameService _game() => GameService(
      playerCount: 2,
      random: Random(7),
      ingeminexCatalog: [_torment()],
    );

void main() {
  group('Ingeminex redaction (PUBLIC — no hidden info)', () {
    test('an absent Ingeminex row is omitted from the view', () {
      final view = redactFor(_game(), 'p0', stateVersion: 1);
      expect(view.containsKey('ingeminex'), isFalse);
    });

    test('a spawned Ingeminex is visible to BOTH players with its HP', () {
      final game = _game();
      game.spawnIngeminexById('torment');
      game.currentPlayer.powerPool = 3;
      game.attackIngeminex('torment', 3); // 3 of 10 damage

      for (final seat in ['p0', 'p1']) {
        final view = redactFor(game, seat, stateVersion: 1);
        final row = view['ingeminex'] as List;
        expect(row, hasLength(1), reason: '$seat sees the neutral boss');
        final e = row.single as Map;
        expect(e['id'], 'torment');
        expect(e['maxHealth'], 10);
        expect(e['damageTaken'], 3);
        expect(e['remainingHealth'], 7);
      }
    });
  });

  group('Ingeminex protocol actions', () {
    test('spawnIngeminex brings a catalog boss in; unknown id is rejected', () {
      final game = _game();
      expect(applyAction(game, 'p0', {
        'type': 'spawnIngeminex',
        'ingeminexId': 'torment',
      }).accepted, isTrue);
      expect(game.ingeminexRow.single.id, 'torment');

      expect(applyAction(game, 'p0', {
        'type': 'spawnIngeminex',
        'ingeminexId': 'nope',
      }).accepted, isFalse);
    });

    test('attackIngeminex spends power and the kill awards the reward', () {
      final game = _game();
      game.spawnIngeminexById('torment');
      game.currentPlayer.powerPool = 10;
      final masteryBefore = game.currentPlayer.mastery;

      final r = applyAction(game, 'p0', {
        'type': 'attackIngeminex',
        'ingeminexId': 'torment',
        'amount': 10,
      });

      expect(r.accepted, isTrue);
      expect(game.ingeminexRow, isEmpty, reason: '10 damage kills it');
      expect(game.currentPlayer.mastery, masteryBefore + 4,
          reason: 'Torment reward = +4 mastery to the killer');
    });

    test('an off-turn player cannot attack the Ingeminex', () {
      final game = _game();
      game.spawnIngeminexById('torment');
      // p1 is not the current player.
      final r = applyAction(game, 'p1', {
        'type': 'attackIngeminex',
        'ingeminexId': 'torment',
        'amount': 5,
      });
      expect(r.accepted, isFalse, reason: 'turn gate: not your turn');
    });
  });
}
