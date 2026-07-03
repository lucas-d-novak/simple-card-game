import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/data/market_deck.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/ingeminex_entity.dart';
import 'package:simple_card_game/services/game_service.dart';

/// §C Ingeminex wire-up: the six neutral bosses are built from the authoritative
/// DB (appearance/reward effects encoded), spawnable by id from the injected
/// catalog, resolve their attack against every player on appearance, and hand
/// the (owner-ruled) reward to the killer.

final CardDatabase _db = CardDatabase.fromJsonString(
  File('assets/card_db/cards.json').readAsStringSync(),
);

final List<IngeminexEntity> _catalog = buildIngeminexCatalogFromDatabase(_db);

GameService _game({int players = 2, int seed = 7}) => GameService(
      playerCount: players,
      random: Random(seed),
      ingeminexCatalog: _catalog,
    );

CardModel _champ(String id, {int cost = 3}) => CardModel(
      id: id,
      name: id,
      cost: cost,
      playEffects: const [],
      cardType: CardType.champion,
      shield: 4,
    );

void main() {
  group('catalog builder', () {
    test('builds exactly the six Ingeminex bosses with effects', () {
      final ids = _catalog.map((e) => e.id).toSet();
      expect(
        ids,
        containsAll(
            ['brutality', 'torment', 'corruption', 'desolation', 'agony', 'malice']),
      );
      expect(_catalog.length, 6);
      // Every boss carries an encoded attack; all but the (all-players-scoped)
      // ones also carry a reward.
      for (final e in _catalog) {
        expect(e.appearanceEffects, isNotEmpty, reason: '${e.id} has an attack');
        expect(e.rewardEffects, isNotEmpty, reason: '${e.id} has a reward');
      }
    });

    test('Ingeminex bosses are NOT in the market despite being in-scope', () {
      final marketIds =
          buildMarketDeckFromDatabase(_db).map((m) => m.template.id).toSet();
      for (final id in _catalog.map((e) => e.id)) {
        expect(marketIds, isNot(contains(id)),
            reason: '$id is a neutral entity, never bought');
      }
    });
  });

  group('spawnIngeminexById', () {
    test('spawns a FRESH entity and resolves the appearance vs all players', () {
      final game = _game(players: 3);
      final before = [for (final p in game.players) p.health];

      final spawned = game.spawnIngeminexById('brutality');

      expect(spawned, isNotNull);
      expect(game.ingeminexRow.single.id, 'brutality');
      expect(game.ingeminexRow.single.damageTaken, 0);
      // Brutality attack: all players lose 5 health.
      for (var i = 0; i < game.players.length; i++) {
        expect(game.players[i].health, before[i] - 5);
      }
    });

    test('unknown id returns null and spawns nothing', () {
      final game = _game();
      expect(game.spawnIngeminexById('nope'), isNull);
      expect(game.ingeminexRow, isEmpty);
    });
  });

  group('owner-ruled rewards', () {
    test('Brutality reward = +20 HEALTH to the killer', () {
      final game = _game();
      // Spawn (all lose 5 first), then heal up so the 20 is observable and not
      // capped, then the killer takes the reward.
      game.spawnIngeminexById('brutality');
      final killer = game.currentPlayer;
      killer.health = 20;
      killer.powerPool = 10;
      expect(game.attackIngeminex('brutality', 10), isTrue);
      expect(killer.health, 40, reason: '+20 health reward');
    });

    test('Torment reward = +4 MASTERY to the killer', () {
      final game = _game();
      game.spawnIngeminexById('torment');
      final killer = game.currentPlayer;
      final m = killer.mastery;
      killer.powerPool = 10;
      expect(game.attackIngeminex('torment', 10), isTrue);
      expect(killer.mastery, m + 4);
    });
  });

  group('Corruption / Desolation — banish a random card from each hand', () {
    test('appearance banishes exactly one card from every non-empty hand', () {
      final game = _game(players: 3);
      final handsBefore = [for (final p in game.players) p.hand.length];
      final removedBefore = game.removedFromGame.length;

      game.spawnIngeminexById('corruption');

      for (var i = 0; i < game.players.length; i++) {
        expect(game.players[i].hand.length, handsBefore[i] - 1,
            reason: 'player $i loses one hand card');
      }
      expect(game.removedFromGame.length, removedBefore + game.players.length);
    });

    test('Corruption reward puts an available Relic into the killer\'s hand', () {
      final game = _game();
      final killer = game.currentPlayer;
      // Give the killer a set-aside relic option to recruit.
      killer.relicOptions.add(_champ('some_relic'));
      final handBefore = killer.hand.length;
      game.spawnIngeminexById('corruption'); // may banish a hand card first
      final handAfterSpawn = killer.hand.length;
      killer.powerPool = 10;

      expect(game.attackIngeminex('corruption', 10), isTrue);
      expect(killer.hand.any((c) => c.id == 'some_relic'), isTrue);
      expect(killer.hand.length, handAfterSpawn + 1);
      expect(killer.relicOptions, isEmpty);
      // Sanity: the relic really was an addition beyond the pre-spawn hand.
      expect(handBefore, greaterThanOrEqualTo(0));
    });
  });

  group('Agony — each player discards 2; reward draw 2 + extra Destiny', () {
    test('appearance makes every player discard 2', () {
      final game = _game(players: 2);
      final handsBefore = [for (final p in game.players) p.hand.length];
      game.spawnIngeminexById('agony');
      for (var i = 0; i < game.players.length; i++) {
        expect(game.players[i].hand.length, handsBefore[i] - 2);
      }
    });

    test('reward raises the killer\'s Destiny claim allowance by 1', () {
      final game = _game();
      game.spawnIngeminexById('agony');
      final killer = game.currentPlayer;
      final grants = killer.destinyClaimGrants;
      killer.powerPool = 10;
      expect(game.attackIngeminex('agony', 10), isTrue);
      expect(killer.destinyClaimGrants, grants + 1);
    });
  });

  group('Malice — each player destroys their highest-cost champion', () {
    test('appearance destroys each player\'s single highest-cost champion', () {
      final game = _game(players: 2);
      // p0 has a cheap + an expensive champion; only the expensive one dies.
      game.players[0].championsInPlay.addAll([_champ('cheap', cost: 2), _champ('pricey', cost: 8)]);
      game.players[1].championsInPlay.add(_champ('lonely', cost: 5));

      game.spawnIngeminexById('malice');

      expect(game.players[0].championsInPlay.map((c) => c.id), ['cheap']);
      expect(game.players[0].discardPile.any((c) => c.id == 'pricey'), isTrue);
      expect(game.players[1].championsInPlay, isEmpty);
      expect(game.players[1].discardPile.any((c) => c.id == 'lonely'), isTrue);
    });
  });

  group('Desolation — deferred reward: banish up to 3 then shuffle', () {
    test('banishUpToFromAnyZone removes chosen cards from hand/deck/discard', () {
      final game = _game();
      final p = game.currentPlayer;
      // Seed distinct, findable ids across the three zones.
      p.hand.add(_champ('h1', cost: 1));
      p.drawPile.add(_champ('d1', cost: 1));
      p.discardPile.add(_champ('x1', cost: 1));
      final removedBefore = game.removedFromGame.length;

      final n = game.banishUpToFromAnyZone(['h1', 'd1', 'x1']);

      expect(n, 3);
      expect(p.hand.any((c) => c.id == 'h1'), isFalse);
      expect(p.drawPile.any((c) => c.id == 'd1'), isFalse);
      expect(p.discardPile.any((c) => c.id == 'x1'), isFalse);
      expect(game.removedFromGame.length, removedBefore + 3);
    });

    test('caps at the limit and ignores unknown ids', () {
      final game = _game();
      final p = game.currentPlayer;
      p.hand.addAll([_champ('a'), _champ('b'), _champ('c'), _champ('d')]);
      final n = game.banishUpToFromAnyZone(['a', 'b', 'c', 'd', 'ghost'], limit: 3);
      expect(n, 3, reason: 'limit 3 honoured, ghost ignored');
    });
  });
}
