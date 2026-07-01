import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/game_state_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/ingeminex_entity.dart';
import 'package:simple_card_game/services/game_service.dart';

/// GameStateCodec round-trips the neutral Ingeminex entity, its accumulated
/// damage, and its appearance/reward effects — so the authoritative server's
/// persistence / undo / reconnect keep the boss faithful.

void main() {
  test('Ingeminex entity + accumulated damage survive an encode/decode', () {
    final game = GameService(playerCount: 2, random: Random(7));
    game.spawnIngeminex(IngeminexEntity(
      id: 'brutality',
      name: 'Brutality',
      art: 'brutality.jpg',
      appearanceEffects: const [AllPlayersLoseHealthEffect(5)],
      rewardEffects: const [GainGemsEffect(20)],
    ));

    // Partially damage it (not lethal) so `damageTaken` is a non-trivial value.
    game.currentPlayer.powerPool = 7;
    expect(game.attackIngeminex('brutality', 7), isTrue);
    expect(game.ingeminexRow.single.damageTaken, 7);

    // Round-trip through JSON (proving the map is JSON-safe too).
    final json =
        jsonDecode(jsonEncode(GameStateCodec.encode(game))) as Map<String, dynamic>;
    final restored = GameStateCodec.decode(json);

    expect(restored.ingeminexRow, hasLength(1));
    final e = restored.ingeminexRow.single;
    expect(e.id, 'brutality');
    expect(e.name, 'Brutality');
    expect(e.art, 'brutality.jpg');
    expect(e.maxHealth, 10);
    expect(e.damageTaken, 7, reason: 'accumulated damage must be preserved');
    expect(e.remainingHealth, 3);

    // Effects round-tripped and remain functional: 3 more damage kills it and
    // the reward (gain 20) resolves for the killer.
    expect(e.appearanceEffects.single, isA<AllPlayersLoseHealthEffect>());
    expect(e.rewardEffects.single, isA<GainGemsEffect>());

    restored.currentPlayer.powerPool = 3;
    final gemsBefore = restored.currentPlayer.gemPool;
    expect(restored.attackIngeminex('brutality', 3), isTrue);
    expect(restored.ingeminexRow, isEmpty);
    expect(restored.currentPlayer.gemPool, gemsBefore + 20);
  });

  test('a game with no Ingeminex omits the key and round-trips clean', () {
    final game = GameService(playerCount: 2, random: Random(7));
    final encoded = GameStateCodec.encode(game);
    expect(encoded.containsKey('ingeminex'), isFalse);
    final restored = GameStateCodec.decode(
        jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>);
    expect(restored.ingeminexRow, isEmpty);
  });
}
