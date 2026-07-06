import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Wave-B Group 4 deferred-selection trio — ENGINE half (backlog §B5):
/// Swyft ("if you are Rez, you may recruit any card you fast-play") and
/// Carmine Eclipse (tuck fast-plays under; on-death PAY-to-recruit salvage).
void main() {
  // Fast-play target: a plain regular card with a gem cost (so salvage can
  // charge it) — used with the FREE warp path (fastPlayFromCenter).
  CardModel warpTarget() => const CardModel(
        id: 'warp_target',
        name: 'Warp Target',
        cost: 3,
        playEffects: [GainGemsEffect(1)],
      );

  // Fast-play target for the PAID mercenary path (payAndFastPlayFromCenter).
  CardModel mercTarget() => const CardModel(
        id: 'merc_target',
        name: 'Merc Target',
        cost: 2,
        cardType: CardType.mercenary,
        playEffects: [GainPowerEffect(1)],
      );

  CardModel swyft() => const CardModel(
        id: 'swyft',
        name: 'Swyft',
        cost: 5,
        cardType: CardType.champion,
        health: 3,
        playEffects: [
          AddStaticModifierEffect(
              StaticModifier(kind: StaticModifierKind.fastPlayRecruit)),
        ],
      );

  CardModel carmine({ActivatedAbility? activated}) => CardModel(
        id: 'carmine_eclipse',
        name: 'Carmine Eclipse',
        cost: 2,
        cardType: CardType.champion,
        health: 6,
        recruitUnderCardsOnDeath: true,
        activatedAbility: activated,
        playEffects: const [
          AddStaticModifierEffect(StaticModifier(
              kind: StaticModifierKind.shieldPerCardUnder, amount: 2)),
          AddStaticModifierEffect(
              StaticModifier(kind: StaticModifierKind.tuckFastPlaysUnder)),
        ],
      );

  // =========================================================================
  // Swyft — fast-play recruit
  // =========================================================================
  group('Swyft — recruitFastPlayedCard', () {
    test('with Swyft in play + Rez: warp fast-play recruits to discard', () {
      final game = GameService(
          playerCount: 2, random: Random(7), characters: [Character.rez, null]);
      final player = game.currentPlayer;
      player.hand.add(swyft());
      game.playCard('swyft');

      game.centerRow.insert(0, warpTarget());
      expect(game.fastPlayFromCenter('warp_target'), isTrue);
      // Warped (no Carmine) → sits in fastPlayedThisTurn awaiting the choice.
      expect(player.fastPlayedThisTurn.map((c) => c.id), contains('warp_target'));

      expect(game.recruitFastPlayedCard('warp_target'), isTrue);
      expect(player.fastPlayedThisTurn, isEmpty);
      expect(player.discardPile.map((c) => c.id), contains('warp_target'));
    });

    test('with Swyft in play + Rez: PAID mercenary fast-play recruits too', () {
      final game = GameService(
          playerCount: 2, random: Random(7), characters: [Character.rez, null]);
      final player = game.currentPlayer;
      player.hand.add(swyft());
      game.playCard('swyft');
      player.gemPool = 5;

      game.centerRow.insert(0, mercTarget());
      expect(game.payAndFastPlayFromCenter('merc_target'), isTrue);
      expect(
          player.fastPlayedThisTurn.map((c) => c.id), contains('merc_target'));

      expect(game.recruitFastPlayedCard('merc_target'), isTrue);
      expect(player.discardPile.map((c) => c.id), contains('merc_target'));
      expect(player.fastPlayedThisTurn, isEmpty);
    });

    test('no Swyft in play: recruit fails, card leaves at end of turn', () {
      final game = GameService(
          playerCount: 2, random: Random(7), characters: [Character.rez, null]);

      game.centerRow.insert(0, warpTarget());
      expect(game.fastPlayFromCenter('warp_target'), isTrue);
      expect(game.recruitFastPlayedCard('warp_target'), isFalse);

      game.endTurn();
      expect(game.removedFromGame.map((c) => c.id), contains('warp_target'));
    });

    test('Swyft in play but NOT Rez: recruit fails, card still leaves', () {
      final game = GameService(
          playerCount: 2,
          random: Random(7),
          characters: [Character.tetra, null]);
      final player = game.currentPlayer;
      player.hand.add(swyft());
      game.playCard('swyft');

      game.centerRow.insert(0, warpTarget());
      expect(game.fastPlayFromCenter('warp_target'), isTrue);
      expect(game.recruitFastPlayedCard('warp_target'), isFalse);
      expect(
          player.fastPlayedThisTurn.map((c) => c.id), contains('warp_target'));

      game.endTurn();
      expect(game.removedFromGame.map((c) => c.id), contains('warp_target'));
    });

    test('unknown card id: recruit fails', () {
      final game = GameService(
          playerCount: 2, random: Random(7), characters: [Character.rez, null]);
      game.currentPlayer.hand.add(swyft());
      game.playCard('swyft');
      expect(game.recruitFastPlayedCard('nope'), isFalse);
    });
  });

  // =========================================================================
  // Carmine — mandatory tuck of fast-plays
  // =========================================================================
  group('Carmine Eclipse — tuckFastPlaysUnder', () {
    test('warp fast-play is tucked under Carmine (not in fastPlayedThisTurn)',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.hand.add(carmine());
      game.playCard('carmine_eclipse');

      game.centerRow.insert(0, warpTarget());
      expect(game.fastPlayFromCenter('warp_target'), isTrue);

      expect(player.fastPlayedThisTurn, isEmpty);
      expect(player.cardsUnderCount('carmine_eclipse'), 1);
      expect(player.cardsUnderChampion['carmine_eclipse']!.map((c) => c.id),
          contains('warp_target'));
    });

    test('paid mercenary fast-play is also tucked under Carmine', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.hand.add(carmine());
      game.playCard('carmine_eclipse');
      player.gemPool = 5;

      game.centerRow.insert(0, mercTarget());
      expect(game.payAndFastPlayFromCenter('merc_target'), isTrue);
      expect(player.fastPlayedThisTurn, isEmpty);
      expect(player.cardsUnderCount('carmine_eclipse'), 1);
    });

    test('tuck raises Carmine health via shieldPerCardUnder', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final owner = game.players[0];
      owner.hand.add(carmine());
      game.playCard('carmine_eclipse');

      game.centerRow.insert(0, warpTarget());
      expect(game.fastPlayFromCenter('warp_target'), isTrue); // 1 card under

      game.endTurn(); // → player 1's turn
      final attacker = game.currentPlayer;
      expect(attacker.id, game.players[1].id);

      // Base health 6 + 2 per under-card = 8 needed to destroy.
      attacker.powerPool = 7;
      expect(game.attackChampion('carmine_eclipse', owner.id), isFalse,
          reason: '7 power < 8 health (6 base + 2 for the tucked card)');
      attacker.powerPool = 8;
      expect(game.attackChampion('carmine_eclipse', owner.id), isTrue);
    });
  });

  // =========================================================================
  // Carmine — on-death salvage (pendingUnderCardRecruit)
  // =========================================================================
  group('Carmine Eclipse — on-death under-card salvage', () {
    // Sets up player0 with Carmine + one tucked card, returns the game with
    // player1 as the current player ready to destroy it.
    GameService setup() {
      final game = GameService(playerCount: 2, random: Random(7));
      final owner = game.players[0];
      owner.hand.add(carmine());
      game.playCard('carmine_eclipse');
      game.centerRow.insert(0, warpTarget());
      game.fastPlayFromCenter('warp_target');
      game.endTurn();
      return game;
    }

    test('combat kill populates pendingUnderCardRecruit for the owner', () {
      final game = setup();
      final owner = game.players[0];
      game.currentPlayer.powerPool = 20;
      expect(game.attackChampion('carmine_eclipse', owner.id), isTrue);

      expect(game.pendingUnderCardRecruit[owner.id], isNotNull);
      expect(game.pendingUnderCardRecruit[owner.id]!.map((c) => c.id),
          contains('warp_target'));
      // The under-card did NOT go straight to the owner's discard.
      expect(owner.discardPile.map((c) => c.id), isNot(contains('warp_target')));
      // The champion itself still goes to the owner's discard as usual.
      expect(owner.discardPile.map((c) => c.id), contains('carmine_eclipse'));
      // The self-scoped modifiers were dropped with the champion.
      expect(owner.staticModifiers, isEmpty);
    });

    test('destroyChampion (no power cost) populates the salvage bucket', () {
      final game = setup();
      final owner = game.players[0];
      expect(game.destroyChampion('carmine_eclipse', owner.id), isTrue);
      expect(game.pendingUnderCardRecruit[owner.id]!.map((c) => c.id),
          contains('warp_target'));
    });

    test('self-banish populates the salvage bucket', () {
      // Carmine variant whose Exhaust ability self-banishes it.
      final game = GameService(playerCount: 2, random: Random(7));
      final owner = game.currentPlayer;
      owner.hand.add(carmine(
          activated: const ActivatedAbility(effects: [SelfBanishEffect()])));
      game.playCard('carmine_eclipse');
      game.centerRow.insert(0, warpTarget());
      game.fastPlayFromCenter('warp_target');

      expect(game.useActivatedAbility('carmine_eclipse'), isTrue);
      expect(game.removedFromGame.map((c) => c.id), contains('carmine_eclipse'));
      expect(game.pendingUnderCardRecruit[owner.id]!.map((c) => c.id),
          contains('warp_target'));
    });

    test('recruitUnderCard charges gems and moves the card to discard', () {
      final game = setup();
      final owner = game.players[0];
      game.currentPlayer.powerPool = 20;
      game.attackChampion('carmine_eclipse', owner.id);

      owner.gemPool = 5;
      // warp_target costs 3.
      expect(game.recruitUnderCard(owner.id, 'warp_target'), isTrue);
      expect(owner.gemPool, 2);
      expect(owner.discardPile.map((c) => c.id), contains('warp_target'));
      // Bucket emptied → key removed.
      expect(game.pendingUnderCardRecruit.containsKey(owner.id), isFalse);
    });

    test('recruitUnderCard fails with too few gems (no state change)', () {
      final game = setup();
      final owner = game.players[0];
      game.currentPlayer.powerPool = 20;
      game.attackChampion('carmine_eclipse', owner.id);

      owner.gemPool = 2; // < cost 3
      expect(game.recruitUnderCard(owner.id, 'warp_target'), isFalse);
      expect(owner.gemPool, 2);
      expect(game.pendingUnderCardRecruit[owner.id]!.map((c) => c.id),
          contains('warp_target'));
    });

    test('finishUnderCardSalvage banishes the remaining pending cards', () {
      final game = setup();
      final owner = game.players[0];
      game.currentPlayer.powerPool = 20;
      game.attackChampion('carmine_eclipse', owner.id);

      expect(game.finishUnderCardSalvage(owner.id), isTrue);
      expect(game.removedFromGame.map((c) => c.id), contains('warp_target'));
      expect(game.pendingUnderCardRecruit.containsKey(owner.id), isFalse);
      // Nothing left to finish.
      expect(game.finishUnderCardSalvage(owner.id), isFalse);
    });

    test('salvage is OWNER-authorized (works off the current player turn)', () {
      final game = setup();
      final owner = game.players[0];
      // Current player is player1 (Carmine's opponent).
      expect(game.currentPlayer.id, game.players[1].id);
      game.currentPlayer.powerPool = 20;
      game.attackChampion('carmine_eclipse', owner.id);

      owner.gemPool = 3;
      // owner (player0) salvages while it is player1's turn — not gated on
      // _currentPlayerCanAct.
      expect(game.recruitUnderCard(owner.id, 'warp_target'), isTrue);
    });
  });

  // =========================================================================
  // Regression — a champion WITHOUT the flag still discards under-cards
  // =========================================================================
  group('Paradigm regression — no recruitUnderCardsOnDeath', () {
    test('under-cards go to discard, no salvage bucket', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final owner = game.players[0];
      const paradigm = CardModel(
        id: 'paradigm',
        name: 'Paradigm',
        cost: 6,
        cardType: CardType.champion,
        health: 5,
        playEffects: [],
      );
      owner.championsInPlay.add(paradigm);
      final under = warpTarget();
      owner.cardsUnderChampion['paradigm'] = [under];

      game.endTurn(); // → player1's turn
      game.currentPlayer.powerPool = 20;
      expect(game.attackChampion('paradigm', owner.id), isTrue);

      expect(game.pendingUnderCardRecruit, isEmpty);
      expect(owner.discardPile.map((c) => c.id), contains('warp_target'));
    });
  });

  group('Carmine + Swyft precedence and destroy/elimination edge cases', () {
    test('Carmine tuck takes precedence over a live Swyft+Rez recruit', () {
      final game = GameService(
          playerCount: 2, random: Random(7), characters: [Character.rez, null]);
      final player = game.currentPlayer;
      player.hand.add(swyft());
      game.playCard('swyft');
      player.hand.add(carmine());
      game.playCard('carmine_eclipse');

      game.centerRow.insert(0, warpTarget());
      expect(game.fastPlayFromCenter('warp_target'), isTrue);
      // Tucked under Carmine (precedence) → never enters fastPlayedThisTurn,
      // so Swyft cannot recruit it.
      expect(player.fastPlayedThisTurn, isEmpty);
      expect(player.cardsUnderChampion['carmine_eclipse']!.map((c) => c.id),
          contains('warp_target'));
      expect(game.recruitFastPlayedCard('warp_target'), isFalse);
    });

    test('destroy-ALL champions still triggers Carmine salvage (not discard)',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final owner = game.players[1];
      owner.championsInPlay.add(carmine());
      owner.cardsUnderChampion['carmine_eclipse'] = [warpTarget()];

      final p0 = game.currentPlayer;
      p0.hand.add(const CardModel(
        id: 'wipe',
        name: 'Wipe',
        cost: 0,
        playEffects: [DestroyChampionEffect(all: true)],
      ));
      game.playCard('wipe');

      expect(owner.championsInPlay, isEmpty);
      // Under-card routed to the salvage bucket, NOT straight to discard.
      expect(game.pendingUnderCardRecruit['p1']?.map((c) => c.id),
          contains('warp_target'));
      expect(owner.discardPile.map((c) => c.id), isNot(contains('warp_target')));
    });

    test('eliminating a Carmine owner banishes their pending salvage bucket', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final owner = game.players[1];
      game.pendingUnderCardRecruit['p1'] = [warpTarget()];
      owner.health = 3;

      final p0 = game.currentPlayer;
      p0.powerPool = 5;
      game.attackPlayer('p1', 5);

      expect(owner.isEliminated, isTrue);
      expect(game.pendingUnderCardRecruit.containsKey('p1'), isFalse);
      expect(game.removedFromGame.map((c) => c.id), contains('warp_target'));
      // A zombie eliminated owner cannot still salvage.
      expect(game.recruitUnderCard('p1', 'warp_target'), isFalse);
    });
  });
}
