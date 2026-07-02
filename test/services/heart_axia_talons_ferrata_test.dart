import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/data/database/game_state_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Engine coverage for the 2026-07-01 card-mechanics wave (batch 2):
/// Axia self acquire-cost reduction, Ferrata Guard's Decima power branch,
/// The Heart of Nothing's next-turn draw bonus, and Entropic Talons' scaling
/// power from health gained this turn — plus codec round-trips of the new
/// PlayerState fields.

final CardDatabase _db = CardDatabase.fromJsonString(
  File('assets/card_db/cards.json').readAsStringSync(),
);

CardModel _model(String id) => _db.byId(id)!.model;

CardModel _champ(String id, {Faction faction = Faction.homodeus}) => CardModel(
      id: id,
      name: id,
      cost: 0,
      faction: faction,
      cardType: CardType.champion,
      playEffects: const [],
    );

void main() {
  group('Axia — self acquire-cost reduction (per Homodeus champion)', () {
    test('costs 1 less per Homodeus champion controlled', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      final axia = _model('axia'); // printed cost 7
      expect(axia.cost, 7);
      game.centerRow.insert(0, axia);
      me.gemPool = 10;

      // Two Homodeus champions in play -> pay 7 - 2 = 5.
      me.championsInPlay.add(_champ('h1'));
      me.championsInPlay.add(_champ('h2'));

      expect(game.buyCard(axia.id), isTrue);
      expect(me.gemPool, 5, reason: '7 - 2 Homodeus champions = 5');
    });

    test('no Homodeus champions -> full printed price', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      final axia = _model('axia');
      game.centerRow.insert(0, axia);
      me.gemPool = 7;
      expect(game.buyCard(axia.id), isTrue);
      expect(me.gemPool, 0, reason: 'no discount => cost 7');
    });

    test('only Homodeus champions count (a Wraethe champion does not discount)',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      final axia = _model('axia');
      game.centerRow.insert(0, axia);
      me.gemPool = 10;
      me.championsInPlay.add(_champ('h1'));
      me.championsInPlay.add(_champ('w1', faction: Faction.wraethe));
      expect(game.buyCard(axia.id), isTrue);
      expect(me.gemPool, 4, reason: '7 - 1 Homodeus (Wraethe ignored) = 6; 10 - 6 = 4');
    });

    test('floored at 0 — enough champions make it free', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      final axia = _model('axia');
      game.centerRow.insert(0, axia);
      me.gemPool = 0; // no gems at all
      for (var i = 0; i < 8; i++) {
        me.championsInPlay.add(_champ('h$i'));
      }
      // 7 - 8 = -1 -> floored to 0; buyable with 0 gems.
      expect(game.buyCard(axia.id), isTrue);
      expect(me.gemPool, 0);
      expect(me.discardPile.any((c) => c.name == 'Axia'), isTrue);
    });
  });

  group('Ferrata Guard — Decima "+2 power to your champions" branch', () {
    test('as Decima: +2 power per champion controlled (includes Ferrata)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.character = Character.decima;
      me.championsInPlay.add(_champ('c1'));
      me.hand.add(_model('ferrata_guard'));
      final power0 = me.powerPool;

      game.playCard('ferrata_guard');

      // c1 + Ferrata (now in play) = 2 champions, +2 each = +4 power.
      expect(me.powerPool, power0 + 4);
    });

    test('not Decima: no power granted by the branch', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.character = Character.tetra;
      me.championsInPlay.add(_champ('c1'));
      me.hand.add(_model('ferrata_guard'));
      final power0 = me.powerPool;

      game.playCard('ferrata_guard');

      expect(me.powerPool, power0, reason: 'Decima gate closed => no bonus');
    });
  });

  group('The Heart of Nothing — next-turn draw bonus on unblocked damage', () {
    test('10+ unblocked damage this turn => next hand is 5 + 3 = 8', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.powerPool = 20;
      me.hand.add(_model('the_heart_of_nothing'));
      game.playCard('the_heart_of_nothing'); // gain 5 power + arm marker

      game.attackPlayer(game.players[1].id, 10); // 10 unblocked damage
      expect(me.unblockedDamageThisTurn, greaterThanOrEqualTo(10));

      game.endTurn();
      expect(me.hand.length, 8, reason: '5 base + 3 next-turn bonus');
      expect(me.nextTurnDrawBonus, 0, reason: 'consumed by the draw');
    });

    test('below threshold => normal 5-card hand', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.powerPool = 20;
      me.hand.add(_model('the_heart_of_nothing'));
      game.playCard('the_heart_of_nothing');

      game.attackPlayer(game.players[1].id, 9); // 9 < 10
      game.endTurn();
      expect(me.hand.length, 5);
    });
  });

  group('Entropic Talons — power per health gained this turn', () {
    test('grants power equal to health gained this turn', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.takeDamage(20); // 30/50 so healing is not wasted at the cap
      me.heal(6); // healthGainedThisTurn = 6
      expect(me.healthGainedThisTurn, 6);

      me.hand.add(_model('entropic_talons'));
      final power0 = me.powerPool;
      game.playCard('entropic_talons'); // draw 2 + gain 6 power

      expect(me.powerPool, power0 + 6);
    });

    test('healthGainedThisTurn resets at end of turn', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.takeDamage(10);
      me.heal(5);
      expect(me.healthGainedThisTurn, 5);
      game.endTurn();
      expect(me.healthGainedThisTurn, 0);
    });

    test('health gain is counted post-cap (over-heal does not count)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.takeDamage(2); // 48/50
      me.heal(6); // only +2 to reach the 50 cap
      expect(me.health, 50);
      expect(me.healthGainedThisTurn, 2);
    });
  });

  group('New PlayerState fields — codec round-trip', () {
    test('nextTurnDrawBonus and healthGainedThisTurn survive a snapshot', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.players[0].nextTurnDrawBonus = 3;
      game.players[0].healthGainedThisTurn = 7;

      final restored = GameStateCodec.decode(GameStateCodec.encode(game));

      expect(restored.players[0].nextTurnDrawBonus, 3);
      expect(restored.players[0].healthGainedThisTurn, 7);
    });
  });
}
