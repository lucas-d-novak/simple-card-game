import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Engine Phase 2 wave 5a — copy-effect (Family 9), center-deck scry
/// (extends Family 8), opponent draw/discard (Family 13).
void main() {
  group('copyPlayedCard — Family 9', () {
    test('re-resolves a chosen non-champion card\'s play effects', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const ally = CardModel(
        id: 'gem_ally',
        name: 'Gem Ally',
        cost: 0,
        faction: Faction.undergrowth,
        playEffects: [GainGemsEffect(3)],
      );
      // The copy card; play it after the ally so the ally is in history.
      const copier = CardModel(
        id: 'ojas',
        name: 'Ojas Genesis Druid',
        cost: 0,
        faction: Faction.undergrowth,
        playEffects: [CopyPlayedCardEffect()],
      );
      player.hand.addAll([ally, copier]);

      game.playCard('gem_ally'); // +3 gems
      game.playCard('ojas'); // deferred no-op
      expect(player.gemPool, 3);

      // Copy the ally — re-resolves +3 gems.
      expect(game.copyPlayedCard('gem_ally'), true);
      expect(player.gemPool, 6);
    });

    test('nonChampion filter refuses to copy a champion', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const champ = CardModel(
        id: 'a_champ',
        name: 'A Champ',
        cost: 0,
        cardType: CardType.champion,
        shield: 1,
        playEffects: [GainPowerEffect(5)],
      );
      player.championsInPlay.add(champ);
      player.cardsPlayedThisTurn.add(champ);

      expect(
        game.copyPlayedCard('a_champ', filter: CopyFilter.nonChampion),
        false,
      );
    });

    test('re-entrancy guard: copying a copy card is a no-op', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const copier = CardModel(
        id: 'self_copy',
        name: 'Self Copy',
        cost: 0,
        playEffects: [GainGemsEffect(1), CopyPlayedCardEffect(filter: CopyFilter.any)],
      );
      player.cardsPlayedThisTurn.add(copier);
      player.gemPool = 0;

      // Even with CopyFilter.any, a card containing a CopyPlayedCardEffect is
      // not copyable (prevents infinite recursion).
      expect(game.copyPlayedCard('self_copy', filter: CopyFilter.any), false);
      expect(player.gemPool, 0);
    });

    test('infinityShard effect is not copied (no mastery / no spurious win)',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // A card that gains gems AND has an InfinityShardEffect; copying should
      // re-resolve the gems but SKIP the shard.
      const shardCard = CardModel(
        id: 'shardy',
        name: 'Shardy',
        cost: 0,
        playEffects: [GainGemsEffect(2), InfinityShardEffect()],
      );
      player.cardsPlayedThisTurn.add(shardCard);
      player.mastery = 29; // would win if the shard were copied
      player.gemPool = 0;

      expect(game.copyPlayedCard('shardy', filter: CopyFilter.any), true);
      expect(player.gemPool, 2); // gems copied
      expect(player.mastery, 29); // shard skipped → no mastery gain
      expect(game.isGameOver, false); // no spurious win
    });

    test('unknown card id is a no-op', () {
      final game = GameService(playerCount: 2, random: Random(7));
      expect(game.copyPlayedCard('does_not_exist'), false);
    });
  });

  group('centerDeckScry — extends Family 8', () {
    test('reveal returns the top of the infinity deck without removing it', () {
      final game = GameService(playerCount: 2, random: Random(7));
      const top = CardModel(id: 'top_card', name: 'Top', cost: 3, playEffects: []);
      game.infinityDeck.add(top);

      final revealed = game.centerDeckScryReveal();
      expect(revealed?.id, 'top_card');
      // Not removed by a peek.
      expect(game.infinityDeck.last.id, 'top_card');
    });

    test('acquire disposition moves revealed card to discard', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      const top =
          CardModel(id: 'defiant_top', name: 'Defiant Top', cost: 2, playEffects: []);
      game.infinityDeck.add(top);

      expect(
        game.centerDeckScryResolve('defiant_top',
            disposition: CenterScryDisposition.acquire),
        true,
      );
      expect(player.discardPile.map((c) => c.id), contains('defiant_top'));
      expect(game.infinityDeck.where((c) => c.id == 'defiant_top'), isEmpty);
    });

    test('oblivion: toHandLosePowerEqualToCost takes card to hand and loses power',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      const top = CardModel(
        id: 'oblivion_top',
        name: 'Oblivion Top',
        cost: 4,
        playEffects: [],
      );
      game.infinityDeck.add(top);
      player.powerPool = 10;

      expect(
        game.centerDeckScryResolve('oblivion_top',
            disposition: CenterScryDisposition.toHandLosePowerEqualToCost),
        true,
      );
      expect(player.hand.map((c) => c.id), contains('oblivion_top'));
      expect(player.powerPool, 6); // 10 - cost 4
    });

    test('lose-power is floored at 0', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      const top = CardModel(
        id: 'pricey_top',
        name: 'Pricey Top',
        cost: 7,
        playEffects: [],
      );
      game.infinityDeck.add(top);
      player.powerPool = 2;

      expect(
        game.centerDeckScryResolve('pricey_top',
            disposition: CenterScryDisposition.toHandLosePowerEqualToCost),
        true,
      );
      expect(player.powerPool, 0);
    });

    test('resolve fails when cardId is not the current top', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.infinityDeck.add(
          const CardModel(id: 'real_top', name: 'Real', cost: 1, playEffects: []));
      expect(game.centerDeckScryResolve('wrong_id'), false);
    });
  });

  group('OpponentDrawsEffect / OpponentDiscardsEffect — Family 13', () {
    test('each other player draws a card', () {
      final game = GameService(playerCount: 3, random: Random(7));
      final caster = game.currentPlayer;

      final handsBefore =
          game.players.map((p) => p.hand.length).toList(growable: false);

      const card = CardModel(
        id: 'blitz',
        name: 'Blitz Shard Runner',
        cost: 0,
        playEffects: [OpponentDrawsEffect(count: 1)],
      );
      caster.hand.add(card);
      final casterHandBefore = caster.hand.length;
      game.playCard('blitz');

      for (var i = 0; i < game.players.length; i++) {
        if (game.players[i].id == caster.id) continue;
        expect(game.players[i].hand.length, handsBefore[i] + 1);
      }
      // Caster only loses the played 'blitz' card, gains nothing.
      expect(caster.hand.length, casterHandBefore - 1);
    });

    test('each other player discards a card from hand', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final caster = game.currentPlayer;
      final opponent = game.players[1];

      final oppHandBefore = opponent.hand.length;
      final oppDiscardBefore = opponent.discardPile.length;

      const card = CardModel(
        id: 'blitz_m',
        name: 'Blitz Shard Runner (mastery)',
        cost: 0,
        playEffects: [OpponentDiscardsEffect(count: 1)],
      );
      caster.hand.add(card);
      game.playCard('blitz_m');

      expect(opponent.hand.length, oppHandBefore - 1);
      expect(opponent.discardPile.length, oppDiscardBefore + 1);
    });

    test('discard takes only what the opponent has when hand is short', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final caster = game.currentPlayer;
      final opponent = game.players[1];

      opponent.hand.clear();
      opponent.hand.add(const CardModel(
          id: 'lone', name: 'Lone', cost: 0, playEffects: []));

      const card = CardModel(
        id: 'big_discard',
        name: 'Big Discard',
        cost: 0,
        playEffects: [OpponentDiscardsEffect(count: 5)],
      );
      caster.hand.add(card);
      game.playCard('big_discard');

      expect(opponent.hand, isEmpty);
      expect(opponent.discardPile.map((c) => c.id), contains('lone'));
    });
  });

  // -------------------------------------------------------------------------
  // Engine Phase 3 wave 4 — faction-filtered copy (taur_archpriest) and
  // banish-a-card-played-this-turn (blood_for_blood).
  // -------------------------------------------------------------------------
  group('copyPlayedCard faction filter — taur_archpriest', () {
    test('copies a matching-faction ally', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      const ugAlly = CardModel(
        id: 'ug_ally',
        name: 'UG Ally',
        cost: 0,
        faction: Faction.undergrowth,
        playEffects: [GainGemsEffect(3)],
      );
      player.hand.add(ugAlly);
      game.playCard('ug_ally');
      expect(player.gemPool, 3);

      // Copy with an undergrowth filter -> re-resolves +3 gems.
      expect(
        game.copyPlayedCard('ug_ally',
            filter: CopyFilter.nonChampion, faction: Faction.undergrowth),
        true,
      );
      expect(player.gemPool, 6);
    });

    test('refuses to copy a non-matching-faction card', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      const wrAlly = CardModel(
        id: 'wr_ally',
        name: 'WR Ally',
        cost: 0,
        faction: Faction.wraethe,
        playEffects: [GainGemsEffect(3)],
      );
      player.hand.add(wrAlly);
      game.playCard('wr_ally');
      final gemsAfterPlay = player.gemPool;

      // Undergrowth filter rejects the Wraethe card — no copy, no extra gems.
      expect(
        game.copyPlayedCard('wr_ally',
            filter: CopyFilter.nonChampion, faction: Faction.undergrowth),
        false,
      );
      expect(player.gemPool, gemsAfterPlay);
    });
  });

  group('banishCard playedThisTurn — blood_for_blood', () {
    test('banishes a card played this turn (removed from game + history)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      const ally = CardModel(
        id: 'spent',
        name: 'Spent',
        cost: 0,
        faction: Faction.wraethe,
        playEffects: [GainPowerEffect(2)],
      );
      player.hand.add(ally);
      game.playCard('spent');
      expect(player.cardsPlayedThisTurn.any((c) => c.id == 'spent'), true);

      expect(game.banishCard('spent', BanishSource.playedThisTurn), true);
      expect(game.removedFromGame.any((c) => c.id == 'spent'), true);
      expect(player.playedThisTurn.any((c) => c.id == 'spent'), false);
      // Purged from history so scaling/conditional counts no longer see it.
      expect(player.cardsPlayedThisTurn.any((c) => c.id == 'spent'), false);
    });

    test('returns false when the named card was not played this turn', () {
      final game = GameService(playerCount: 2, random: Random(7));
      expect(game.banishCard('never', BanishSource.playedThisTurn), false);
    });
  });
}
