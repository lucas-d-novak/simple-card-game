import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Engine coverage for the 2026-07-01 card-mechanics wave (opponent-loses-mastery,
/// character-identity conditionals, same-name-played condition, mill, self /
/// return-all / return-to-deck-top from discard, on-recruit-to-hand).

final CardDatabase _db = CardDatabase.fromJsonString(
  File('assets/card_db/cards.json').readAsStringSync(),
);

CardModel _model(String id) => _db.byId(id)!.model;

CardModel _card({
  required String id,
  String? name,
  Faction faction = Faction.none,
  CardType cardType = CardType.regular,
  int cost = 0,
  List<CardEffect> playEffects = const [],
}) =>
    CardModel(
      id: id,
      name: name ?? id,
      cost: cost,
      faction: faction,
      cardType: cardType,
      playEffects: playEffects,
    );

void main() {
  group('OpponentLosesMasteryEffect (new effect)', () {
    test('reduces every living opponent\'s mastery, floored at 0', () {
      final game = GameService(playerCount: 3, random: Random(7));
      game.players[1].mastery = 5;
      game.players[2].mastery = 1; // seat 2 already low
      final me = game.currentPlayer;
      me.hand.add(_card(
        id: 'zap',
        playEffects: const [OpponentLosesMasteryEffect(2)],
      ));

      game.playCard('zap');

      expect(game.players[1].mastery, 3);
      expect(game.players[2].mastery, 0, reason: 'floored at 0, not negative');
    });

    test('Venator of the Wastes: champion in play -> opponent loses 2 mastery',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.players[1].mastery = 6;
      final me = game.currentPlayer;
      // No champion in play yet -> conditional does not fire.
      me.hand.add(_model('venator_of_the_wastes'));
      game.playCard('venator_of_the_wastes');
      expect(game.players[1].mastery, 6, reason: 'no champion => no loss');
      expect(me.powerPool, 4, reason: 'still gains 4 power');

      // Now with a champion in play.
      me.championsInPlay.add(_card(
        id: 'champ',
        cardType: CardType.champion,
        faction: Faction.homodeus,
      ));
      me.hand.add(_model('venator_of_the_wastes'));
      game.playCard('venator_of_the_wastes');
      expect(game.players[1].mastery, 4, reason: 'champion in play => -2 mastery');
    });

    test('Skry-77 Mastery-20: you gain 2 mastery AND opponent loses 2 mastery',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.mastery = 20;
      game.players[1].mastery = 10;
      me.hand.add(_model('skry_77'));

      game.playCard('skry_77');

      // Base (opponentLosesHealth 3 / gainHealth 3) + Mastery-20 bonus
      // (gainMastery 2 + opponentLosesMastery 2). Net mastery: 20 + 2 = 22.
      expect(me.mastery, 22);
      expect(game.players[1].mastery, 8, reason: 'opponent loses 2 mastery');
    });

    test('Skry-77 below mastery 20 does NOT touch mastery', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.mastery = 5;
      game.players[1].mastery = 10;
      me.hand.add(_model('skry_77'));

      game.playCard('skry_77');

      expect(me.mastery, 5);
      expect(game.players[1].mastery, 10);
    });
  });

  group('character-identity conditionals (isCharacter)', () {
    test('Hounds of Volos: if you are Volos, gain 5 POWER (not gems)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.character = Character.volos;
      me.hand.add(_model('hounds_of_volos'));

      game.playCard('hounds_of_volos');

      expect(me.gemPool, 5, reason: 'base gem gain stays 5');
      expect(me.powerPool, 5, reason: 'Volos branch grants POWER');
    });

    test('Hounds of Volos: non-Volos player gets no bonus power', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.character = Character.tetra;
      me.hand.add(_model('hounds_of_volos'));

      game.playCard('hounds_of_volos');

      expect(me.gemPool, 5);
      expect(me.powerPool, 0);
    });
  });

  group('sameNamePlayedThisTurn condition (Cinder Scars)', () {
    CardModel cinder(String id) {
      final m = _model('cinder_scars');
      return CardModel(
        id: id,
        name: m.name,
        cost: m.cost,
        faction: m.faction,
        cardType: m.cardType,
        playEffects: m.playEffects,
      );
    }

    test('second copy of a same-named card grants the +3 power', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.hand.add(cinder('cs_a'));
      me.hand.add(cinder('cs_b'));

      game.playCard('cs_a');
      expect(me.powerPool, 0, reason: 'first copy: no other copy played yet');

      game.playCard('cs_b');
      expect(me.powerPool, 3, reason: 'second copy sees the first => +3 power');
    });
  });

  group('MillEffect (Legion Carrier)', () {
    test('moves the top N of the draw pile to discard', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      final drawBefore = me.drawPile.length;
      final discardBefore = me.discardPile.length;
      me.hand.add(_model('legion_carrier'));

      game.playCard('legion_carrier');

      expect(me.gemPool, 2);
      expect(me.drawPile.length, drawBefore - 3);
      expect(me.discardPile.length, discardBefore + 3);
    });
  });

  group('ReturnFromDiscard self / all', () {
    test('The Dispossessed returns a discarded copy after a Wraethe card', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      // A previously-discarded copy of The Dispossessed (same name, diff id).
      final discardedCopy = _card(
        id: 'the_dispossessed_99',
        name: 'The Dispossessed',
        faction: Faction.wraethe,
      );
      me.discardPile.add(discardedCopy);
      // Play a Wraethe card first so the condition holds.
      me.hand.add(_card(id: 'wr', faction: Faction.wraethe));
      game.playCard('wr');

      me.hand.add(_model('the_dispossessed'));
      game.playCard('the_dispossessed');

      expect(me.powerPool, 3);
      expect(me.hand.any((c) => c.id == 'the_dispossessed_99'), isTrue,
          reason: 'the discarded copy returned to hand');
      expect(me.discardPile.any((c) => c.id == 'the_dispossessed_99'), isFalse);
    });

    test('The Dispossessed does nothing without a Wraethe card played', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.discardPile.add(_card(
        id: 'the_dispossessed_99',
        name: 'The Dispossessed',
        faction: Faction.wraethe,
      ));
      me.hand.add(_model('the_dispossessed'));
      game.playCard('the_dispossessed');

      expect(me.discardPile.any((c) => c.id == 'the_dispossessed_99'), isTrue,
          reason: 'condition not met => copy stays in discard');
    });

    test('The World Piercer Mastery-20 returns ALL mercenaries from discard',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.mastery = 20;
      me.discardPile.add(_card(id: 'm1', cardType: CardType.mercenary));
      me.discardPile.add(_card(id: 'm2', cardType: CardType.mercenary));
      me.discardPile.add(_card(id: 'reg', cardType: CardType.regular));
      me.hand.add(_model('the_world_piercer'));

      game.playCard('the_world_piercer');

      expect(me.hand.any((c) => c.id == 'm1'), isTrue);
      expect(me.hand.any((c) => c.id == 'm2'), isTrue);
      expect(me.discardPile.any((c) => c.id == 'reg'), isTrue,
          reason: 'non-mercenary stays');
      expect(me.powerPool, 2, reason: 'Mastery-20 bonus still grants 2 power');
    });
  });

  group('ReturnFromDiscardToDeckTop (Dash)', () {
    test('deferred method puts a discard card on top of the deck', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      final fetched = _card(id: 'aion_thing');
      me.discardPile.add(fetched);
      me.hand.add(_model('dash'));

      final handBefore = me.hand.length;
      game.playCard('dash'); // draws 1 (the return step is deferred)
      // Dash drew a card.
      expect(me.hand.length, handBefore - 1 + 1);

      final ok = game.returnFromDiscardToDeckTop('aion_thing');
      expect(ok, isTrue);
      expect(me.discardPile.any((c) => c.id == 'aion_thing'), isFalse);
      expect(me.drawPile.last.id, 'aion_thing',
          reason: 'returned to the TOP (end) of the draw pile');
    });
  });

  group('RecruitToHand on-recruit trigger', () {
    test('Breaker goes to hand when recruited (buyCard), not discard', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      final breaker = _model('breaker');
      game.centerRow.add(breaker);
      me.gemPool = breaker.cost + 5;

      final ok = game.buyCard(breaker.id);
      expect(ok, isTrue);
      expect(me.hand.any((c) => c.id == breaker.id), isTrue);
      expect(me.discardPile.any((c) => c.id == breaker.id), isFalse);
    });

    test('Nexus goes to hand only when you are Tetra', () {
      // Non-Tetra: to discard.
      final g1 = GameService(playerCount: 2, random: Random(7));
      g1.currentPlayer.character = Character.decima;
      final nexus1 = _model('nexus_datic_hunter');
      g1.centerRow.add(nexus1);
      g1.currentPlayer.gemPool = nexus1.cost + 5;
      g1.buyCard(nexus1.id);
      expect(g1.currentPlayer.discardPile.any((c) => c.id == nexus1.id), isTrue);
      expect(g1.currentPlayer.hand.any((c) => c.id == nexus1.id), isFalse);

      // Tetra: to hand.
      final g2 = GameService(playerCount: 2, random: Random(7));
      g2.currentPlayer.character = Character.tetra;
      final nexus2 = _model('nexus_datic_hunter');
      g2.centerRow.add(nexus2);
      g2.currentPlayer.gemPool = nexus2.cost + 5;
      g2.buyCard(nexus2.id);
      expect(g2.currentPlayer.hand.any((c) => c.id == nexus2.id), isTrue);
      expect(g2.currentPlayer.discardPile.any((c) => c.id == nexus2.id), isFalse);
    });
  });
}
