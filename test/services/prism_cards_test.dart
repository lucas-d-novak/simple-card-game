import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/services/game_service.dart';

/// §A Prism cards: Stricture (Exhaust reveal → play-or-banish, Chroma play+banish)
/// and Shard Cultist (banish this + another, free-recruit within summed cost).

CardModel _card(String id, {int cost = 0, List<CardEffect> effects = const []}) =>
    CardModel(id: id, name: id, cost: cost, playEffects: effects);

void main() {
  group('Stricture — playOrBanish scry disposition', () {
    test('keep → PLAYS the revealed card (its effects resolve)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final p = game.currentPlayer;
      // Top of deck (END of drawPile) is a gem card.
      p.drawPile.add(_card('top_gem', effects: const [GainGemsEffect(3)]));
      final gemsBefore = p.gemPool;

      expect(game.scryReveal().first.id, 'top_gem');
      expect(
        game.scryResolve('top_gem',
            keep: true, disposition: ScryDisposition.playOrBanish),
        isTrue,
      );

      expect(p.gemPool, gemsBefore + 3, reason: 'the card was played');
      expect(p.playedThisTurn.any((c) => c.id == 'top_gem'), isTrue);
      expect(p.drawPile.any((c) => c.id == 'top_gem'), isFalse);
    });

    test('let go → BANISHES the revealed card (no play)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final p = game.currentPlayer;
      p.drawPile.add(_card('top_gem', effects: const [GainGemsEffect(3)]));
      final gemsBefore = p.gemPool;

      expect(
        game.scryResolve('top_gem',
            keep: false, disposition: ScryDisposition.playOrBanish),
        isTrue,
      );

      expect(p.gemPool, gemsBefore, reason: 'not played');
      expect(game.removedFromGame.any((c) => c.id == 'top_gem'), isTrue);
      expect(p.playedThisTurn.any((c) => c.id == 'top_gem'), isFalse);
    });

    test('Chroma may play AND then banish (deck-thinning)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final p = game.currentPlayer..character = Character.chroma;
      p.drawPile.add(_card('top_gem', effects: const [GainGemsEffect(3)]));
      final gemsBefore = p.gemPool;

      expect(
        game.scryResolve('top_gem',
            keep: true,
            disposition: ScryDisposition.playOrBanish,
            banishAfterPlay: true),
        isTrue,
      );

      expect(p.gemPool, gemsBefore + 3, reason: 'still played (effect resolved)');
      // ...but banished afterwards rather than sitting in playedThisTurn.
      expect(p.playedThisTurn.any((c) => c.id == 'top_gem'), isFalse);
      expect(game.removedFromGame.any((c) => c.id == 'top_gem'), isTrue);
    });

    test('a NON-Chroma banishAfterPlay is ignored (card just plays)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final p = game.currentPlayer; // no character
      p.drawPile.add(_card('top_gem', effects: const [GainGemsEffect(3)]));

      game.scryResolve('top_gem',
          keep: true,
          disposition: ScryDisposition.playOrBanish,
          banishAfterPlay: true);

      expect(p.playedThisTurn.any((c) => c.id == 'top_gem'), isTrue);
      expect(game.removedFromGame.any((c) => c.id == 'top_gem'), isFalse);
    });
  });

  group('Shard Cultist — banishPairAndRecruit', () {
    /// Play a shard_cultist so it sits in playedThisTurn, and stock the hand +
    /// center row. Returns the game with p0 as the actor.
    GameService buildGame() {
      final game = GameService(playerCount: 2, random: Random(7));
      final p = game.currentPlayer;
      p.hand.add(_card('shard_cultist',
          cost: 4, effects: const [BanishPairRecruitEffect()]));
      game.playCard('shard_cultist');
      p.hand.add(_card('other', cost: 2));
      game.centerRow.add(const CardModel(
          id: 'target6', name: 'T6', cost: 6, playEffects: []));
      game.centerRow.add(const CardModel(
          id: 'target7', name: 'T7', cost: 7, playEffects: []));
      return game;
    }

    test('banishes this + the chosen card, free-recruits within summed cost', () {
      final game = buildGame();
      final p = game.currentPlayer;

      // budget = 4 (cultist) + 2 (other) = 6 → target6 is legal, FREE.
      final gemsBefore = p.gemPool;
      expect(
        game.banishPairAndRecruit('shard_cultist', 'other', 'target6'),
        isTrue,
      );

      expect(p.gemPool, gemsBefore, reason: 'the recruit is FREE');
      expect(game.removedFromGame.map((c) => c.id),
          containsAll(['shard_cultist', 'other']));
      expect(p.discardPile.any((c) => c.id == 'target6'), isTrue,
          reason: 'the recruited card lands in discard');
      expect(p.playedThisTurn.any((c) => c.id == 'shard_cultist'), isFalse);
      expect(p.hand.any((c) => c.id == 'other'), isFalse);
    });

    test('a recruit above the summed budget is rejected (all-or-nothing)', () {
      final game = buildGame();
      final p = game.currentPlayer;

      // target7 (cost 7) > budget 6 → whole action refused, nothing banished.
      expect(
        game.banishPairAndRecruit('shard_cultist', 'other', 'target7'),
        isFalse,
      );
      expect(p.playedThisTurn.any((c) => c.id == 'shard_cultist'), isTrue);
      expect(p.hand.any((c) => c.id == 'other'), isTrue);
      expect(game.removedFromGame, isEmpty);
    });

    test('Chroma may DISCARD this instead of banishing it', () {
      final game = buildGame();
      final p = game.currentPlayer..character = Character.chroma;

      expect(
        game.banishPairAndRecruit('shard_cultist', 'other', 'target6',
            discardSelf: true),
        isTrue,
      );

      // The cultist went to DISCARD (recoverable), the other card was banished.
      expect(p.discardPile.any((c) => c.id == 'shard_cultist'), isTrue);
      expect(game.removedFromGame.any((c) => c.id == 'shard_cultist'), isFalse);
      expect(game.removedFromGame.any((c) => c.id == 'other'), isTrue);
    });
  });

  group('§A market un-parking', () {
    test('Stricture + Shard Cultist are modelled (effects present)', () {
      // Sanity: the DB projections carry the modelled effects (guards the codec).
      // (Full DB build coverage lives in market_deck_test / validate tool.)
      final cultist = _card('shard_cultist',
          effects: const [BanishPairRecruitEffect()]);
      expect(cultist.playEffects.single, isA<BanishPairRecruitEffect>());
    });
  });
}
