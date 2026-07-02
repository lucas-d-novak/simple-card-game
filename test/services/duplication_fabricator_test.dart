import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Wave-B Group 4b — Duplication Fabricator (Order).
/// Owner ruling (§B5): play effect = +1 mastery, THEN (base, every play) reveal
/// the top card of EVERY player's deck and copy one revealed ALLY's effect.
/// Cannot copy another Duplication Fabricator; "this effect can't be copied".
/// After copying, LEAVE the revealed cards ON TOP (peek-only).

const _gemAlly = CardModel(
  id: 'gem_ally',
  name: 'Gem Ally',
  cost: 0,
  faction: Faction.undergrowth,
  playEffects: [GainGemsEffect(3)],
);

const _powerAlly = CardModel(
  id: 'power_ally',
  name: 'Power Ally',
  cost: 0,
  faction: Faction.wraethe,
  playEffects: [GainPowerEffect(2)],
);

const _dupFab = CardModel(
  id: 'duplication_fabricator',
  name: 'Duplication Fabricator',
  cost: 1,
  faction: Faction.order,
  cardType: CardType.regular,
  playEffects: [GainMasteryEffect(1), RevealAndCopyTopOfDecksEffect()],
);

void main() {
  group('revealTopOfAllDecks', () {
    test('populates pendingDeckReveal with each non-empty deck top', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final p0 = game.players[0];
      final p1 = game.players[1];
      p0.drawPile
        ..clear()
        ..addAll([_powerAlly, _gemAlly]); // top = _gemAlly (last)
      p1.drawPile
        ..clear()
        ..addAll([_gemAlly, _powerAlly]); // top = _powerAlly (last)

      game.revealTopOfAllDecks();

      expect(game.pendingDeckReveal.length, 2);
      final byOwner = {
        for (final e in game.pendingDeckReveal) e.ownerId: e.card.id,
      };
      expect(byOwner[p0.id], 'gem_ally');
      expect(byOwner[p1.id], 'power_ally');
    });

    test('leaves the revealed cards ON TOP (peek only)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final p0 = game.players[0];
      p0.drawPile
        ..clear()
        ..addAll([_powerAlly, _gemAlly]);
      final before = p0.drawPile.length;

      game.revealTopOfAllDecks();

      expect(p0.drawPile.length, before);
      expect(p0.drawPile.last.id, 'gem_ally');
    });

    test('skips a player with an empty deck (no draw and no discard)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final p0 = game.players[0];
      final p1 = game.players[1];
      p0.drawPile
        ..clear()
        ..add(_gemAlly);
      p1.drawPile.clear();
      p1.discardPile.clear();

      game.revealTopOfAllDecks();

      expect(game.pendingDeckReveal.length, 1);
      expect(game.pendingDeckReveal.single.ownerId, p0.id);
    });

    test('reshuffles discard into an empty draw pile before revealing', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final p0 = game.players[0];
      final p1 = game.players[1];
      p0.drawPile.clear();
      p0.discardPile
        ..clear()
        ..add(_gemAlly);
      p1.drawPile
        ..clear()
        ..add(_powerAlly);

      game.revealTopOfAllDecks();

      // p0 reshuffled: discard emptied, single card now on draw pile + revealed.
      expect(p0.discardPile, isEmpty);
      expect(p0.drawPile.length, 1);
      final p0Reveal =
          game.pendingDeckReveal.firstWhere((e) => e.ownerId == p0.id);
      expect(p0Reveal.card.id, 'gem_ally');
    });

    test('a fresh play supersedes any prior pending reveal', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.players[0].drawPile
        ..clear()
        ..add(_gemAlly);
      game.players[1].drawPile
        ..clear()
        ..add(_powerAlly);
      game.revealTopOfAllDecks();
      final first = game.pendingDeckReveal.length;
      game.revealTopOfAllDecks();
      expect(game.pendingDeckReveal.length, first); // not doubled
    });
  });

  group('copyRevealedCard', () {
    test('re-applies a chosen opponent-top ALLY effect to the caster', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final caster = game.currentPlayer; // players[0]
      final opponent = game.players[1];
      caster.drawPile
        ..clear()
        ..add(_powerAlly);
      opponent.drawPile
        ..clear()
        ..add(_gemAlly);
      caster.gemPool = 0;

      game.revealTopOfAllDecks();
      expect(game.copyRevealedCard('gem_ally'), true);

      expect(caster.gemPool, 3); // opponent's revealed ally copied to caster
      expect(game.pendingDeckReveal, isEmpty); // cleared on success
      // Peek-only: the opponent's card stays on top of THEIR deck.
      expect(opponent.drawPile.single.id, 'gem_ally');
    });

    test('refuses a champion (not an ally)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final caster = game.currentPlayer;
      const champ = CardModel(
        id: 'a_champ',
        name: 'A Champ',
        cost: 0,
        cardType: CardType.champion,
        shield: 3,
        playEffects: [GainPowerEffect(9)],
      );
      caster.drawPile
        ..clear()
        ..add(_gemAlly);
      game.players[1].drawPile
        ..clear()
        ..add(champ);
      caster.powerPool = 0;

      game.revealTopOfAllDecks();
      expect(game.copyRevealedCard('a_champ'), false);
      expect(caster.powerPool, 0); // nothing copied
      expect(game.pendingDeckReveal, isNotEmpty); // still pending
    });

    test('refuses to copy another Duplication Fabricator', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final caster = game.currentPlayer;
      caster.drawPile
        ..clear()
        ..add(_gemAlly);
      game.players[1].drawPile
        ..clear()
        ..add(_dupFab); // opponent's top is a Duplication Fabricator
      caster.mastery = 0;

      game.revealTopOfAllDecks();
      expect(game.copyRevealedCard('duplication_fabricator'), false);
      expect(caster.mastery, 0); // its +1 mastery not granted via copy
    });

    test('a revealed card that itself copies is not copyable (skip-list)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final caster = game.currentPlayer;
      const reflector = CardModel(
        id: 'reflector',
        name: 'Reflector',
        cost: 0,
        cardType: CardType.regular,
        playEffects: [
          GainGemsEffect(1),
          RevealAndCopyTopOfDecksEffect(),
        ],
      );
      caster.drawPile
        ..clear()
        ..add(_gemAlly);
      game.players[1].drawPile
        ..clear()
        ..add(reflector);
      caster.gemPool = 0;

      game.revealTopOfAllDecks();
      expect(game.copyRevealedCard('reflector'), false);
      expect(caster.gemPool, 0);
    });

    test('does not copy an InfinityShardEffect (no spurious win)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final caster = game.currentPlayer;
      const shardAlly = CardModel(
        id: 'shard_ally',
        name: 'Shard Ally',
        cost: 0,
        cardType: CardType.regular,
        playEffects: [GainGemsEffect(2), InfinityShardEffect()],
      );
      caster.drawPile
        ..clear()
        ..add(_gemAlly);
      game.players[1].drawPile
        ..clear()
        ..add(shardAlly);
      caster.mastery = 29; // would win if the shard were copied
      caster.gemPool = 0;

      game.revealTopOfAllDecks();
      expect(game.copyRevealedCard('shard_ally'), true);
      expect(caster.gemPool, 2); // gems copied
      expect(game.isGameOver, false); // shard skipped → no win
    });

    test('unknown / not-revealed card id is a no-op', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.drawPile
        ..clear()
        ..add(_gemAlly);
      game.players[1].drawPile.clear();
      game.revealTopOfAllDecks();
      expect(game.copyRevealedCard('not_revealed'), false);
    });
  });

  group('play effect ordering (mastery THEN reveal)', () {
    test('playing Duplication Fabricator grants +1 mastery then reveals', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final caster = game.currentPlayer;
      caster.hand
        ..clear()
        ..add(_dupFab);
      caster.drawPile
        ..clear()
        ..add(_powerAlly);
      game.players[1].drawPile
        ..clear()
        ..add(_gemAlly);
      final mastery0 = caster.mastery;

      expect(game.playCard('duplication_fabricator'), true);

      expect(caster.mastery, mastery0 + 1); // +1 mastery from the base effect
      expect(game.pendingDeckReveal.length, 2); // reveal ran after mastery
    });
  });

  group('self-exclusion name branch + end-of-turn cleanup', () {
    test('refuses a MARKET-suffixed Duplication Fabricator (name branch)', () {
      // Real recruited copies have suffixed ids (duplication_fabricator_0), so
      // the id check misses and only the NAME check blocks it — lock that path.
      final game = GameService(playerCount: 2, random: Random(7));
      final caster = game.currentPlayer;
      caster.drawPile
        ..clear()
        ..add(_gemAlly);
      const dupFabCopy = CardModel(
        id: 'duplication_fabricator_0',
        name: 'Duplication Fabricator',
        cost: 1,
        faction: Faction.order,
        playEffects: [GainMasteryEffect(1), RevealAndCopyTopOfDecksEffect()],
      );
      game.players[1].drawPile
        ..clear()
        ..add(dupFabCopy);

      game.revealTopOfAllDecks();
      expect(game.copyRevealedCard('duplication_fabricator_0'), false);
      expect(game.pendingDeckReveal, isNotEmpty); // still pending, nothing copied
    });

    test('endTurn drops a pending reveal — next player cannot consume it', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final caster = game.currentPlayer; // p0
      caster.drawPile
        ..clear()
        ..add(_gemAlly);
      game.players[1].drawPile
        ..clear()
        ..add(_powerAlly);

      game.revealTopOfAllDecks();
      expect(game.pendingDeckReveal, isNotEmpty);

      game.endTurn(); // caster ended without choosing → reveal is dropped
      expect(game.pendingDeckReveal, isEmpty);
      // The next player (p1, now current) cannot pick up p0's copy choice.
      expect(game.copyRevealedCard('power_ally'), false);
    });
  });
}
