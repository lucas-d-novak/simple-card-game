import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_service.dart';

class ZeroRandom implements Random {
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
}

void main() {
  group('GameService initialization (Step 5a)', () {
    test('2-player game initializes with correct state', () {
      final game = GameService(playerCount: 2, random: Random(7));

      expect(game.players, hasLength(2));
      expect(game.currentPlayerIndex, 0);
      expect(game.turnNumber, 1);
      expect(game.removedFromGame, isEmpty);
      expect(game.isGameOver, false);

      for (final player in game.players) {
        expect(player.health, 50);
        expect(player.mastery, 0);
        expect(player.gemPool, 0);
        expect(player.powerPool, 0);
      }
    });

    test('3-player game initializes with 3 players', () {
      final game = GameService(playerCount: 3, random: Random(7));
      expect(game.players, hasLength(3));
    });

    test('each player starts with 10 total cards across hand and draw pile',
        () {
      final game = GameService(playerCount: 2, random: Random(7));

      // All players start with 5 cards in hand, 5 in draw pile
      expect(game.players[0].hand, hasLength(5));
      expect(game.players[0].drawPile, hasLength(5));

      expect(game.players[1].hand, hasLength(5));
      expect(game.players[1].drawPile, hasLength(5));
    });

    test('all players draw 5 cards at start', () {
      final game = GameService(playerCount: 2, random: Random(7));

      expect(game.players[0].hand, hasLength(5));
      expect(game.players[1].hand, hasLength(5));
    });
  });

  group('Center row / market (Step 6)', () {
    test('center row starts with 6 cards', () {
      final game = GameService(playerCount: 2, random: Random(7));
      expect(game.centerRow, hasLength(6));
    });

    test('infinity deck is populated', () {
      final game = GameService(playerCount: 2, random: Random(7));
      // Full catalog with variable copy counts (151 total), minus 6 dealt to center row
      expect(game.infinityDeck, hasLength(151 - 6));
    });

    test('buying a card refills center row to 6', () {
      final game = GameService(playerCount: 2, random: Random(7));

      // Give player enough gems to buy something
      game.currentPlayer.gemPool = 20;
      final cardToBuy = game.centerRow.first;
      final result = game.buyCard(cardToBuy.id);

      expect(result, true);
      expect(game.centerRow, hasLength(6));
    });

    test('buying when infinity deck is empty does not refill', () {
      final game = GameService(playerCount: 2, random: Random(7));

      // Empty the infinity deck
      game.infinityDeck.clear();
      game.currentPlayer.gemPool = 100;

      final cardToBuy = game.centerRow.first;
      game.buyCard(cardToBuy.id);

      expect(game.centerRow, hasLength(5)); // 6 - 1, no refill
    });

    test('no always-available basic card exists', () {
      final game = GameService(playerCount: 2, random: Random(7));

      // Buy everything
      game.currentPlayer.gemPool = 10000;
      game.infinityDeck.clear();

      while (game.centerRow.isNotEmpty) {
        game.buyCard(game.centerRow.first.id);
      }

      expect(game.centerRow, isEmpty);
      // No card magically appears
      expect(game.centerRow, isEmpty);
    });
  });

  group('Play card effects (Step 5b)', () {
    test('playing a Crystal adds 1 gem to pool', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final crystal =
          game.currentPlayer.hand.firstWhere((c) => c.name == 'Crystal',
              orElse: () => throw StateError(
                  'No Crystal in hand. Hand: ${game.currentPlayer.hand.map((c) => c.name)}'));

      game.playCard(crystal.id);

      expect(game.currentPlayer.gemPool, 1);
      expect(
        game.currentPlayer.playedThisTurn.map((c) => c.id),
        contains(crystal.id),
      );
    });

    test('playing a Blaster adds 1 power to pool', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // Add a Blaster to hand directly to avoid RNG dependency
      const blaster = CardModel(
        id: 'test_blaster',
        name: 'Blaster',
        cost: 0,
        playEffects: [GainPowerEffect(1)],
      );
      player.hand.add(blaster);

      game.playCard('test_blaster');

      expect(player.powerPool, 1);
    });

    test('playCard moves card from hand to playedThisTurn', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final card = game.currentPlayer.hand.first;
      final handSizeBefore = game.currentPlayer.hand.length;

      game.playCard(card.id);

      expect(game.currentPlayer.hand, hasLength(handSizeBefore - 1));
      expect(game.currentPlayer.playedThisTurn, hasLength(1));
    });

    test('playCard returns false for unknown card id', () {
      final game = GameService(playerCount: 2, random: Random(7));
      expect(game.playCard('nonexistent'), false);
    });

    test('playCard with DrawCardsEffect draws from draw pile', () {
      final game = GameService(playerCount: 2, random: ZeroRandom());
      final player = game.currentPlayer;

      // Manually add a card with draw effect to hand
      const drawCard = CardModel(
        id: 'test_draw',
        name: 'Test Draw',
        cost: 0,
        playEffects: [DrawCardsEffect(2)],
      );
      player.hand.add(drawCard);
      final handSizeBefore = player.hand.length;
      final drawPileSizeBefore = player.drawPile.length;

      game.playCard('test_draw');

      // Hand should grow by 2 (drew 2) minus 1 (played the draw card)
      expect(player.hand, hasLength(handSizeBefore + 1));
      expect(player.drawPile, hasLength(drawPileSizeBefore - 2));
    });

    test('draw pile auto-reshuffles from discard when empty', () {
      final game = GameService(playerCount: 2, random: ZeroRandom());
      final player = game.currentPlayer;

      // Move all draw pile to discard
      player.discardPile.addAll(player.drawPile);
      player.drawPile.clear();
      final discardCount = player.discardPile.length;

      // Add a draw card
      const drawCard = CardModel(
        id: 'test_draw2',
        name: 'Test Draw',
        cost: 0,
        playEffects: [DrawCardsEffect(1)],
      );
      player.hand.add(drawCard);

      game.playCard('test_draw2');

      expect(player.discardPile, isEmpty);
      expect(player.drawPile, hasLength(discardCount - 1));
    });

    test('ChooseOneEffect with choiceIndex 0 applies first option', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // Add Shard Reactor to hand (choose 2 gems OR 2 power)
      const reactor = CardModel(
        id: 'test_reactor',
        name: 'Shard Reactor',
        cost: 0,
        playEffects: [
          ChooseOneEffect([
            [GainGemsEffect(2)],
            [GainPowerEffect(2)],
          ]),
        ],
      );
      player.hand.add(reactor);

      game.playCard('test_reactor', choiceIndex: 0);

      expect(player.gemPool, 2);
      expect(player.powerPool, 0);
    });

    test('ChooseOneEffect with choiceIndex 1 applies second option', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const reactor = CardModel(
        id: 'test_reactor2',
        name: 'Shard Reactor',
        cost: 0,
        playEffects: [
          ChooseOneEffect([
            [GainGemsEffect(2)],
            [GainPowerEffect(2)],
          ]),
        ],
      );
      player.hand.add(reactor);

      game.playCard('test_reactor2', choiceIndex: 1);

      expect(player.gemPool, 0);
      expect(player.powerPool, 2);
    });

    // Engine Phase 3 wave 5 — choose-N-distinct (red_fortune Mastery-15).
    test('ChooseOneEffect pick:2 resolves two distinct choices', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      final gemsBefore = player.gemPool;
      final powerBefore = player.powerPool;

      const card = CardModel(
        id: 'choose_two',
        name: 'Choose Two',
        cost: 0,
        playEffects: [
          ChooseOneEffect([
            [GainGemsEffect(2)],
            [GainPowerEffect(2)],
            [GainMasteryEffect(1)],
          ], pick: 2),
        ],
      );
      player.hand.add(card);
      // Start at index 0 -> resolves choices 0 and 1 (distinct): +2 gems, +2 power.
      game.playCard('choose_two', choiceIndex: 0);
      expect(player.gemPool, gemsBefore + 2);
      expect(player.powerPool, powerBefore + 2);
    });

    test('ChooseOneEffect pick wraps and stays distinct at the end', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      final gemsBefore = player.gemPool;
      final powerBefore = player.powerPool;

      const card = CardModel(
        id: 'choose_two_wrap',
        name: 'Choose Two Wrap',
        cost: 0,
        playEffects: [
          ChooseOneEffect([
            [GainGemsEffect(2)],
            [GainPowerEffect(2)],
          ], pick: 2),
        ],
      );
      player.hand.add(card);
      // Start at last index -> resolves choice 1 then wraps to 0 (both distinct).
      game.playCard('choose_two_wrap', choiceIndex: 1);
      expect(player.gemPool, gemsBefore + 2);
      expect(player.powerPool, powerBefore + 2);
    });

    test('GainMasteryEffect increases player mastery', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const masteryCard = CardModel(
        id: 'test_mastery',
        name: 'Test Mastery',
        cost: 0,
        playEffects: [GainMasteryEffect(3)],
      );
      player.hand.add(masteryCard);

      game.playCard('test_mastery');
      expect(player.mastery, 3);
    });

    test('GainHealthEffect heals the player', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.takeDamage(10);

      const healCard = CardModel(
        id: 'test_heal',
        name: 'Test Heal',
        cost: 0,
        playEffects: [GainHealthEffect(5)],
      );
      player.hand.add(healCard);

      game.playCard('test_heal');
      expect(player.health, 45); // 50 - 10 + 5
    });

    test('OpponentLosesHealthEffect damages opponent in 2-player game', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const damageCard = CardModel(
        id: 'test_opp_damage',
        name: 'Test Damage',
        cost: 0,
        playEffects: [OpponentLosesHealthEffect(7)],
      );
      player.hand.add(damageCard);

      game.playCard('test_opp_damage');

      final opponent = game.players.firstWhere((p) => p.id != player.id);
      expect(opponent.health, 43); // 50 - 7
    });
  });

  group('Buy card (Step 5c)', () {
    test('buyCard subtracts gems and card goes to discard', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.gemPool = 20;

      final card = game.centerRow.first;
      final cardId = card.id;
      final cardCost = card.cost;

      expect(game.buyCard(cardId), true);
      expect(game.currentPlayer.gemPool, 20 - cardCost);
      expect(
        game.currentPlayer.discardPile.map((c) => c.id),
        contains(cardId),
      );
    });

    test('buyCard fails if insufficient gems', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.gemPool = 0;

      final expensiveCard =
          game.centerRow.firstWhere((c) => c.cost > 0);
      expect(game.buyCard(expensiveCard.id), false);
    });

    test('buyCard fails if card not in center row', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.gemPool = 100;
      expect(game.buyCard('nonexistent_card'), false);
    });
  });

  group('End turn & cycling (Step 5d)', () {
    test('endTurn moves played regular cards to discard', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // Play all hand cards
      while (player.hand.isNotEmpty) {
        game.playCard(player.hand.first.id);
      }
      final playedCount = player.playedThisTurn.length;

      game.endTurn();

      // Cards should be in discard now (the previous player)
      expect(game.players[0].playedThisTurn, isEmpty);
      expect(game.players[0].discardPile, hasLength(playedCount));
    });

    test('endTurn resets gem and power pools', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.gemPool = 5;
      game.currentPlayer.powerPool = 3;

      game.endTurn();

      expect(game.players[0].gemPool, 0);
      expect(game.players[0].powerPool, 0);
    });

    test('endTurn draws 5 cards for the player who just ended', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // Play all cards from hand
      while (player.hand.isNotEmpty) {
        game.playCard(player.hand.first.id);
      }
      expect(player.hand, isEmpty);

      game.endTurn();

      // Player 0 should now have 5 new cards
      expect(game.players[0].hand, hasLength(5));
    });

    test('turn cycling advances player index', () {
      final game = GameService(playerCount: 2, random: Random(7));
      expect(game.currentPlayerIndex, 0);

      game.endTurn();
      expect(game.currentPlayerIndex, 1);

      game.endTurn();
      expect(game.currentPlayerIndex, 0);
    });

    test('turnNumber increments when cycling back to player 0', () {
      final game = GameService(playerCount: 2, random: Random(7));
      expect(game.turnNumber, 1);

      game.endTurn(); // p0 -> p1
      expect(game.turnNumber, 1);

      game.endTurn(); // p1 -> p0, new round
      expect(game.turnNumber, 2);
    });

    test('3-player turn cycling works correctly', () {
      final game = GameService(playerCount: 3, random: Random(7));
      expect(game.currentPlayerIndex, 0);

      game.endTurn();
      expect(game.currentPlayerIndex, 1);

      game.endTurn();
      expect(game.currentPlayerIndex, 2);

      game.endTurn();
      expect(game.currentPlayerIndex, 0);
      expect(game.turnNumber, 2);
    });
  });

  group('Mercenary cleanup (Step 7)', () {
    test('mercenaries are removed from game during endTurn, not discarded', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // Add a mercenary to hand and play it
      const merc = CardModel(
        id: 'test_merc',
        name: 'Test Mercenary',
        cost: 0,
        playEffects: [GainPowerEffect(5)],
        cardType: CardType.mercenary,
      );
      player.hand.add(merc);
      game.playCard('test_merc');

      expect(player.playedThisTurn.map((c) => c.id), contains('test_merc'));

      game.endTurn();

      expect(
        game.removedFromGame.map((c) => c.id),
        contains('test_merc'),
      );
      // Mercenary should NOT be in discard
      expect(
        game.players[0].discardPile.map((c) => c.id),
        isNot(contains('test_merc')),
      );
    });
  });

  group('Elimination', () {
    test('eliminated player is skipped in turn cycling', () {
      final game = GameService(playerCount: 3, random: Random(7));

      // Eliminate player 1
      game.players[1].takeDamage(60);
      expect(game.players[1].isEliminated, true);

      game.endTurn(); // p0 -> should skip p1, go to p2
      expect(game.currentPlayerIndex, 2);

      game.endTurn(); // p2 -> p0
      expect(game.currentPlayerIndex, 0);
    });

    test('game is over when only one player remains', () {
      final game = GameService(playerCount: 2, random: Random(7));

      game.players[1].takeDamage(60);
      game.endTurn();

      expect(game.isGameOver, true);
    });

    test('eliminated player cards are moved to removedFromGame on attackPlayer', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final target = game.players[1];

      // Give the target cards in every zone to verify they're all cleared
      const extraCard = CardModel(
        id: 'target_hand_card',
        name: 'Target Hand Card',
        cost: 0,
        playEffects: [],
      );
      const champCard = CardModel(
        id: 'target_champ',
        name: 'Target Champion',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 2,
      );
      target.hand.add(extraCard);
      target.championsInPlay.add(champCard);

      // Verify non-empty zones before attack
      expect(target.hand.isNotEmpty, true);
      expect(target.drawPile.isNotEmpty, true);
      expect(target.championsInPlay.isNotEmpty, true);

      final removedBefore = game.removedFromGame.length;

      // Deal lethal damage
      game.currentPlayer.powerPool = 100;
      game.attackPlayer('p1', 50);

      expect(target.isEliminated, true);
      expect(target.hand, isEmpty);
      expect(target.drawPile, isEmpty);
      expect(target.discardPile, isEmpty);
      expect(target.playedThisTurn, isEmpty);
      expect(target.championsInPlay, isEmpty);
      // Cards were added to removedFromGame
      expect(game.removedFromGame.length, greaterThan(removedBefore));
    });

    test('OpponentLosesHealthEffect eliminated player cards cleared in 3-player', () {
      final game = GameService(playerCount: 3, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      // Ensure target has cards in zones
      expect(target.drawPile.isNotEmpty, true);

      // Play a card that deals enough direct damage to eliminate target
      const damageCard = CardModel(
        id: 'lethal_opp_damage',
        name: 'Lethal Opp Damage',
        cost: 0,
        playEffects: [OpponentLosesHealthEffect(50)],
      );
      attacker.hand.add(damageCard);

      game.playCard('lethal_opp_damage');

      expect(target.isEliminated, true);
      expect(target.hand, isEmpty);
      expect(target.drawPile, isEmpty);
      expect(target.discardPile, isEmpty);
      expect(target.championsInPlay, isEmpty);
    });
  });

  group('OpponentLosesHealthEffect multiplayer', () {
    test('OpponentLosesHealthEffect damages all opponents in 3-player game', () {
      final game = GameService(playerCount: 3, random: Random(7));
      final attacker = game.currentPlayer; // p0

      const damageCard = CardModel(
        id: 'test_opp_damage_3p',
        name: 'Multi Damage',
        cost: 0,
        playEffects: [OpponentLosesHealthEffect(5)],
      );
      attacker.hand.add(damageCard);

      game.playCard('test_opp_damage_3p');

      // Both opponents should take 5 damage
      expect(game.players[1].health, 45); // 50 - 5
      expect(game.players[2].health, 45); // 50 - 5
      // Attacker is unaffected
      expect(game.players[0].health, 50);
    });

    test('OpponentLosesHealthEffect skips already-eliminated opponents', () {
      final game = GameService(playerCount: 3, random: Random(7));
      final attacker = game.currentPlayer; // p0

      // Pre-eliminate p2
      game.players[2].takeDamage(60);
      expect(game.players[2].isEliminated, true);

      const damageCard = CardModel(
        id: 'test_opp_skip_elim',
        name: 'Skip Eliminated',
        cost: 0,
        playEffects: [OpponentLosesHealthEffect(5)],
      );
      attacker.hand.add(damageCard);

      game.playCard('test_opp_skip_elim');

      expect(game.players[1].health, 45); // took damage
      expect(game.players[2].health, lessThanOrEqualTo(0)); // still dead, no double-damage
    });
  });

  // =========================================================================
  // NEW MECHANICS TESTS
  // =========================================================================

  group('Champion deployment (Step 13a)', () {
    test('playing a champion card adds it to championsInPlay, not playedThisTurn', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const champion = CardModel(
        id: 'test_champion',
        name: 'Test Champion',
        cost: 0,
        playEffects: [GainPowerEffect(2)],
        cardType: CardType.champion,
        shield: 3,
      );
      player.hand.add(champion);

      game.playCard('test_champion');

      expect(player.championsInPlay.map((c) => c.id), contains('test_champion'));
      expect(player.playedThisTurn.map((c) => c.id), isNot(contains('test_champion')));
      expect(player.powerPool, 2); // effects still resolve
    });

    test('champion effects resolve when first played', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const champion = CardModel(
        id: 'test_champ_effect',
        name: 'Power Champion',
        cost: 0,
        playEffects: [GainPowerEffect(3), GainMasteryEffect(1)],
        cardType: CardType.champion,
        shield: 2,
      );
      player.hand.add(champion);

      game.playCard('test_champ_effect');

      expect(player.powerPool, 3);
      expect(player.mastery, 1);
    });

    test('champions persist across turns', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const champion = CardModel(
        id: 'test_persist_champ',
        name: 'Persistent Champion',
        cost: 0,
        playEffects: [GainPowerEffect(1)],
        cardType: CardType.champion,
        shield: 2,
      );
      player.hand.add(champion);
      game.playCard('test_persist_champ');

      expect(player.championsInPlay, hasLength(1));

      // End turn and come back (2 turns: p0 -> p1 -> p0)
      game.endTurn();
      game.endTurn();

      // Champion should still be in play
      expect(game.players[0].championsInPlay, hasLength(1));
      expect(game.players[0].championsInPlay.first.id, 'test_persist_champ');
    });

    test('champions are not moved to discard during cleanup', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const champion = CardModel(
        id: 'test_no_discard_champ',
        name: 'No Discard Champion',
        cost: 0,
        playEffects: [GainPowerEffect(1)],
        cardType: CardType.champion,
        shield: 2,
      );
      player.hand.add(champion);
      game.playCard('test_no_discard_champ');

      game.endTurn();

      expect(
        game.players[0].discardPile.map((c) => c.id),
        isNot(contains('test_no_discard_champ')),
      );
      expect(
        game.players[0].championsInPlay.map((c) => c.id),
        contains('test_no_discard_champ'),
      );
    });

    test('champion effects activate when player manually activates', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const champion = CardModel(
        id: 'test_retrigger_champ',
        name: 'Retrigger Champion',
        cost: 0,
        playEffects: [GainPowerEffect(2)],
        cardType: CardType.champion,
        shield: 2,
      );
      player.hand.add(champion);
      game.playCard('test_retrigger_champ');

      expect(player.powerPool, 2); // from initial play

      // End turn, cycle back to p0
      game.endTurn(); // p0 -> p1, resets p0 power to 0
      game.endTurn(); // p1 -> p0

      // Champions do NOT auto-trigger — power should be 0
      expect(game.players[0].powerPool, 0);

      // Manually activate the champion
      expect(game.activateChampion('test_retrigger_champ'), true);
      expect(game.players[0].powerPool, 2);
    });

    test('champion cannot be activated twice in same turn', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const champion = CardModel(
        id: 'test_double_activate',
        name: 'Double Activate Champion',
        cost: 0,
        playEffects: [GainPowerEffect(3)],
        cardType: CardType.champion,
        shield: 2,
      );
      player.hand.add(champion);
      game.playCard('test_double_activate');

      // Cycle back to p0
      game.endTurn();
      game.endTurn();

      // First activation works
      expect(game.activateChampion('test_double_activate'), true);
      expect(game.players[0].powerPool, 3);

      // Second activation is rejected
      expect(game.activateChampion('test_double_activate'), false);
      expect(game.players[0].powerPool, 3); // unchanged
    });

    test('multiple champions can each be activated manually', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const champ1 = CardModel(
        id: 'test_multi_champ_1',
        name: 'Champion A',
        cost: 0,
        playEffects: [GainPowerEffect(1)],
        cardType: CardType.champion,
        shield: 2,
      );
      const champ2 = CardModel(
        id: 'test_multi_champ_2',
        name: 'Champion B',
        cost: 0,
        playEffects: [GainGemsEffect(3)],
        cardType: CardType.champion,
        shield: 2,
      );
      player.hand.addAll([champ1, champ2]);
      game.playCard('test_multi_champ_1');
      game.playCard('test_multi_champ_2');

      // Cycle back to p0
      game.endTurn();
      game.endTurn();

      // Not yet activated — resources should be 0
      expect(game.players[0].powerPool, 0);
      expect(game.players[0].gemPool, 0);

      // Activate each champion
      game.activateChampion('test_multi_champ_1');
      game.activateChampion('test_multi_champ_2');

      expect(game.players[0].powerPool, 1);
      expect(game.players[0].gemPool, 3);
    });
  });

  group('Guard & champion targeting (Step 13b)', () {
    test('attackChampion destroys champion and deducts power', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      const champion = CardModel(
        id: 'target_champ',
        name: 'Target Champion',
        cost: 0,
        playEffects: [GainPowerEffect(1)],
        cardType: CardType.champion,
        shield: 3,
      );
      target.championsInPlay.add(champion);
      attacker.powerPool = 5;

      final result = game.attackChampion('target_champ', 'p1');

      expect(result, true);
      expect(attacker.powerPool, 2); // 5 - 3
      expect(target.championsInPlay, isEmpty);
      expect(target.discardPile.map((c) => c.id), contains('target_champ'));
    });

    test('attackChampion fails with insufficient power', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      const champion = CardModel(
        id: 'tough_champ',
        name: 'Tough Champion',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 5,
      );
      target.championsInPlay.add(champion);
      attacker.powerPool = 3;

      expect(game.attackChampion('tough_champ', 'p1'), false);
      expect(attacker.powerPool, 3); // unchanged
      expect(target.championsInPlay, hasLength(1)); // still there
    });

    test('attackChampion fails for nonexistent champion', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.powerPool = 10;

      expect(game.attackChampion('nonexistent', 'p1'), false);
    });

    test('attackChampion fails when targeting self', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const champion = CardModel(
        id: 'own_champ',
        name: 'Own Champion',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 2,
      );
      player.championsInPlay.add(champion);
      player.powerPool = 10;

      expect(game.attackChampion('own_champ', player.id), false);
    });

    test('attackPlayer deals damage and deducts power', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.powerPool = 10;

      final result = game.attackPlayer('p1', 5);

      expect(result, true);
      expect(game.currentPlayer.powerPool, 5);
      expect(game.players[1].health, 45);
    });

    test('attackPlayer fails if target has guard champion', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.powerPool = 10;

      const guard = CardModel(
        id: 'guard_champ',
        name: 'Guard Champion',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 3,
        hasGuard: true,
      );
      game.players[1].championsInPlay.add(guard);

      expect(game.attackPlayer('p1', 5), false);
      expect(game.players[1].health, 50); // unchanged
    });

    test('attackPlayer succeeds after guard champion is destroyed', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.powerPool = 10;

      const guard = CardModel(
        id: 'guard_to_destroy',
        name: 'Guard to Destroy',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 3,
        hasGuard: true,
      );
      game.players[1].championsInPlay.add(guard);

      // Destroy the guard first
      game.attackChampion('guard_to_destroy', 'p1');
      expect(game.currentPlayer.powerPool, 7); // 10 - 3

      // Now attack player
      final result = game.attackPlayer('p1', 5);
      expect(result, true);
      expect(game.players[1].health, 45);
      expect(game.currentPlayer.powerPool, 2); // 7 - 5
    });

    test('attackPlayer fails with insufficient power', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.powerPool = 3;

      expect(game.attackPlayer('p1', 5), false);
      expect(game.players[1].health, 50);
    });

    test('attackPlayer fails for zero or negative amount', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.powerPool = 10;

      expect(game.attackPlayer('p1', 0), false);
      expect(game.attackPlayer('p1', -1), false);
    });

    test('attackPlayer fails when targeting self', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.powerPool = 10;

      expect(game.attackPlayer('p0', 5), false);
    });

    test('attackPlayer can eliminate opponent', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.powerPool = 60;

      game.attackPlayer('p1', 50);

      expect(game.players[1].health, 0);
      expect(game.players[1].isEliminated, true);
      expect(game.isGameOver, true);
    });

    test('multiple attacks per turn are allowed', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.powerPool = 10;

      game.attackPlayer('p1', 3);
      expect(game.players[1].health, 47);
      expect(game.currentPlayer.powerPool, 7);

      game.attackPlayer('p1', 4);
      expect(game.players[1].health, 43);
      expect(game.currentPlayer.powerPool, 3);
    });

    test('non-guard champion does not block player attacks', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.powerPool = 10;

      const nonGuard = CardModel(
        id: 'non_guard_champ',
        name: 'Non-Guard Champion',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 3,
        hasGuard: false,
      );
      game.players[1].championsInPlay.add(nonGuard);

      // Can still attack player directly
      expect(game.attackPlayer('p1', 5), true);
      expect(game.players[1].health, 45);
    });

    test('attackPlayer fails if target is already eliminated', () {
      final game = GameService(playerCount: 3, random: Random(7));
      game.players[1].takeDamage(60);
      game.currentPlayer.powerPool = 10;

      expect(game.attackPlayer('p1', 5), false);
    });
  });

  group('Ally abilities (Step 9)', () {
    test('ally ability triggers when same-faction card is already in play', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // Clear hand and add two same-faction cards
      player.hand.clear();
      const card1 = CardModel(
        id: 'wraethe_1',
        name: 'Wraethe Card 1',
        cost: 0,
        playEffects: [GainPowerEffect(1)],
        faction: Faction.wraethe,
      );
      const card2 = CardModel(
        id: 'wraethe_2',
        name: 'Wraethe Card 2',
        cost: 0,
        playEffects: [GainPowerEffect(1)],
        faction: Faction.wraethe,
        allyAbility: [GainPowerEffect(3)],
      );
      player.hand.addAll([card1, card2]);

      // Play first card (no ally yet)
      game.playCard('wraethe_1');
      expect(player.powerPool, 1);

      // Play second card (ally triggers: +1 play + 3 ally = 4 more)
      game.playCard('wraethe_2');
      expect(player.powerPool, 5); // 1 + 1 + 3
    });

    test('ally ability does not trigger without matching faction in play', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      player.hand.clear();
      const card = CardModel(
        id: 'solo_wraethe',
        name: 'Solo Wraethe',
        cost: 0,
        playEffects: [GainPowerEffect(1)],
        faction: Faction.wraethe,
        allyAbility: [GainPowerEffect(5)],
      );
      player.hand.add(card);

      game.playCard('solo_wraethe');

      // Only play effect, no ally ability
      expect(player.powerPool, 1);
    });

    test('ally ability triggers with champion of same faction in play', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // Put a champion in play first
      const champion = CardModel(
        id: 'order_champ',
        name: 'Order Champion',
        cost: 0,
        playEffects: [GainPowerEffect(1)],
        faction: Faction.order,
        cardType: CardType.champion,
        shield: 2,
      );
      player.championsInPlay.add(champion);

      // Play a same-faction card
      player.hand.clear();
      const card = CardModel(
        id: 'order_card',
        name: 'Order Card',
        cost: 0,
        playEffects: [GainGemsEffect(1)],
        faction: Faction.order,
        allyAbility: [GainHealthEffect(3)],
      );
      player.hand.add(card);

      game.playCard('order_card');

      expect(player.gemPool, 1); // play effect
      expect(player.health, 53); // ally ability: +3 health
    });

    test('countsAsAllFactions triggers ally ability for any faction', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // Put a universal soldier in play (counts as all factions)
      const universal = CardModel(
        id: 'universal_test',
        name: 'Universal Test',
        cost: 0,
        playEffects: [GainPowerEffect(1)],
        cardType: CardType.champion,
        shield: 2,
        countsAsAllFactions: true,
      );
      player.championsInPlay.add(universal);

      // Play any faction card with ally ability
      player.hand.clear();
      const homoCard = CardModel(
        id: 'homo_card',
        name: 'Homodeus Card',
        cost: 0,
        playEffects: [GainGemsEffect(1)],
        faction: Faction.homodeus,
        allyAbility: [GainMasteryEffect(2)],
      );
      player.hand.add(homoCard);

      game.playCard('homo_card');

      expect(player.gemPool, 1);
      expect(player.mastery, 2); // ally triggered
    });

    test('factionless card without countsAsAllFactions does not trigger allies', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      player.hand.clear();
      // Play a factionless card first
      const card1 = CardModel(
        id: 'factionless_1',
        name: 'Factionless 1',
        cost: 0,
        playEffects: [GainGemsEffect(1)],
      );
      const card2 = CardModel(
        id: 'factionless_2',
        name: 'Factionless 2',
        cost: 0,
        playEffects: [GainGemsEffect(1)],
        allyAbility: [GainPowerEffect(5)],
      );
      player.hand.addAll([card1, card2]);

      game.playCard('factionless_1');
      game.playCard('factionless_2');

      expect(player.powerPool, 0); // ally should NOT trigger
      expect(player.gemPool, 2);
    });

    test('different factions do not trigger ally abilities', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      player.hand.clear();
      const card1 = CardModel(
        id: 'wraethe_solo',
        name: 'Wraethe Solo',
        cost: 0,
        playEffects: [GainPowerEffect(1)],
        faction: Faction.wraethe,
      );
      const card2 = CardModel(
        id: 'order_solo',
        name: 'Order Solo',
        cost: 0,
        playEffects: [GainGemsEffect(1)],
        faction: Faction.order,
        allyAbility: [GainHealthEffect(10)],
      );
      player.hand.addAll([card1, card2]);

      game.playCard('wraethe_solo');
      game.playCard('order_solo');

      expect(player.health, 50); // no ally trigger
    });
  });

  group('Mastery threshold effects (Step 11)', () {
    test('mastery bonus triggers when mastery meets threshold', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 5;

      player.hand.clear();
      const card = CardModel(
        id: 'test_mastery_card',
        name: 'Mastery Card',
        cost: 0,
        playEffects: [GainGemsEffect(1)],
        masteryThreshold: 5,
        masteryBonus: [DrawCardsEffect(2)],
      );
      player.hand.add(card);
      final drawPileBefore = player.drawPile.length;

      game.playCard('test_mastery_card');

      expect(player.gemPool, 1); // play effect
      // Drew 2 cards from mastery bonus
      expect(player.drawPile, hasLength(drawPileBefore - 2));
    });

    test('mastery bonus does not trigger below threshold', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 4; // below threshold of 5

      player.hand.clear();
      const card = CardModel(
        id: 'test_below_threshold',
        name: 'Below Threshold',
        cost: 0,
        playEffects: [GainGemsEffect(1)],
        masteryThreshold: 5,
        masteryBonus: [GainPowerEffect(10)],
      );
      player.hand.add(card);

      game.playCard('test_below_threshold');

      expect(player.gemPool, 1);
      expect(player.powerPool, 0); // mastery bonus NOT triggered
    });

    test('mastery bonus triggers when mastery exceeds threshold', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 15; // well above threshold of 5

      player.hand.clear();
      const card = CardModel(
        id: 'test_exceed_threshold',
        name: 'Exceed Threshold',
        cost: 0,
        playEffects: [GainPowerEffect(1)],
        masteryThreshold: 5,
        masteryBonus: [GainPowerEffect(5)],
      );
      player.hand.add(card);

      game.playCard('test_exceed_threshold');

      expect(player.powerPool, 6); // 1 from play + 5 from mastery bonus
    });

    test('card with no mastery threshold ignores mastery check', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 100;

      player.hand.clear();
      const card = CardModel(
        id: 'test_no_threshold',
        name: 'No Threshold',
        cost: 0,
        playEffects: [GainGemsEffect(2)],
        // no masteryThreshold, no masteryBonus
      );
      player.hand.add(card);

      game.playCard('test_no_threshold');
      expect(player.gemPool, 2);
    });

    test('mastery gained from play effects can trigger mastery bonus on same card', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 3;

      player.hand.clear();
      // Card gives 2 mastery, bringing total to 5, which meets threshold
      const card = CardModel(
        id: 'test_self_mastery',
        name: 'Self Mastery',
        cost: 0,
        playEffects: [GainMasteryEffect(2)],
        masteryThreshold: 5,
        masteryBonus: [GainPowerEffect(3)],
      );
      player.hand.add(card);

      game.playCard('test_self_mastery');

      expect(player.mastery, 5);
      expect(player.powerPool, 3); // mastery bonus triggered
    });
  });

  group('Banish & Scrap (Step 8)', () {
    test('banishCard from hand removes card permanently', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      final cardToBanish = player.hand.first;
      final handSizeBefore = player.hand.length;

      final result = game.banishCard(cardToBanish.id, BanishSource.hand);

      expect(result, true);
      expect(player.hand, hasLength(handSizeBefore - 1));
      expect(game.removedFromGame.map((c) => c.id), contains(cardToBanish.id));
    });

    test('banishCard from discard removes card permanently', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // Put a card in discard
      const discardCard = CardModel(
        id: 'banish_discard_test',
        name: 'Banish Me',
        cost: 0,
        playEffects: [],
      );
      player.discardPile.add(discardCard);

      final result = game.banishCard('banish_discard_test', BanishSource.discard);

      expect(result, true);
      expect(player.discardPile.map((c) => c.id), isNot(contains('banish_discard_test')));
      expect(game.removedFromGame.map((c) => c.id), contains('banish_discard_test'));
    });

    test('banishCard handOrDiscard checks hand first then discard', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      final handCard = player.hand.first;
      final result = game.banishCard(handCard.id, BanishSource.handOrDiscard);

      expect(result, true);
      expect(game.removedFromGame.map((c) => c.id), contains(handCard.id));
    });

    test('banishCard handOrDiscard falls back to discard', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const discardCard = CardModel(
        id: 'banish_fallback',
        name: 'Banish Fallback',
        cost: 0,
        playEffects: [],
      );
      player.discardPile.add(discardCard);

      final result = game.banishCard('banish_fallback', BanishSource.handOrDiscard);

      expect(result, true);
      expect(game.removedFromGame.map((c) => c.id), contains('banish_fallback'));
    });

    test('banishCard fails for nonexistent card', () {
      final game = GameService(playerCount: 2, random: Random(7));

      expect(game.banishCard('nonexistent', BanishSource.hand), false);
      expect(game.banishCard('nonexistent', BanishSource.discard), false);
      expect(game.banishCard('nonexistent', BanishSource.handOrDiscard), false);
    });

    test('scrapFromCenterRow removes card and refills', () {
      final game = GameService(playerCount: 2, random: Random(7));

      final cardToScrap = game.centerRow.first;
      final result = game.scrapFromCenterRow(cardToScrap.id);

      expect(result, true);
      expect(game.centerRow, hasLength(6)); // refilled
      expect(game.removedFromGame.map((c) => c.id), contains(cardToScrap.id));
      expect(game.centerRow.map((c) => c.id), isNot(contains(cardToScrap.id)));
    });

    test('scrapFromCenterRow fails for nonexistent card', () {
      final game = GameService(playerCount: 2, random: Random(7));

      expect(game.scrapFromCenterRow('nonexistent'), false);
    });

    test('scrapFromCenterRow does not refill when infinity deck is empty', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.infinityDeck.clear();

      final cardToScrap = game.centerRow.first;
      game.scrapFromCenterRow(cardToScrap.id);

      expect(game.centerRow, hasLength(5));
    });
  });

  group('Infinity Shard scaling (Step 12)', () {
    test('Infinity Shard gives 1 mastery and 0 power at mastery 0', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 0;

      player.hand.clear();
      const shard = CardModel(
        id: 'test_shard_0',
        name: 'Infinity Shard',
        cost: 0,
        playEffects: [InfinityShardEffect()],
      );
      player.hand.add(shard);

      game.playCard('test_shard_0');
      expect(player.mastery, 1);
      expect(player.powerPool, 0);
      expect(player.gemPool, 0);
    });

    test('Infinity Shard at mastery 4 bumps to 5 and gives 3 power (enters tier 5-9)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 4;

      player.hand.clear();
      const shard = CardModel(
        id: 'test_shard_4',
        name: 'Infinity Shard',
        cost: 0,
        playEffects: [InfinityShardEffect()],
      );
      player.hand.add(shard);

      game.playCard('test_shard_4');
      expect(player.mastery, 5);
      expect(player.powerPool, 3); // mastery evaluated after +1: 5 → tier 5-9
      expect(player.gemPool, 0);
    });

    test('Infinity Shard gives 1 mastery and 3 power at mastery 5', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 5;

      player.hand.clear();
      const shard = CardModel(
        id: 'test_shard_5',
        name: 'Infinity Shard',
        cost: 0,
        playEffects: [InfinityShardEffect()],
      );
      player.hand.add(shard);

      game.playCard('test_shard_5');
      expect(player.mastery, 6);
      expect(player.powerPool, 3);
      expect(player.gemPool, 0);
    });

    test('Infinity Shard gives 1 mastery and 6 power at mastery 10', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 10;

      player.hand.clear();
      const shard = CardModel(
        id: 'test_shard_10',
        name: 'Infinity Shard',
        cost: 0,
        playEffects: [InfinityShardEffect()],
      );
      player.hand.add(shard);

      game.playCard('test_shard_10');
      expect(player.mastery, 11);
      expect(player.powerPool, 6);
      expect(player.gemPool, 0);
    });

    test('Infinity Shard gives 1 mastery and 10 power at mastery 15', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 15;

      player.hand.clear();
      const shard = CardModel(
        id: 'test_shard_15',
        name: 'Infinity Shard',
        cost: 0,
        playEffects: [InfinityShardEffect()],
      );
      player.hand.add(shard);

      game.playCard('test_shard_15');
      expect(player.mastery, 16);
      expect(player.powerPool, 10);
      expect(player.gemPool, 0);
    });

    test('Infinity Shard gives 1 mastery and 15 power at mastery 20', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 20;

      player.hand.clear();
      const shard = CardModel(
        id: 'test_shard_20',
        name: 'Infinity Shard',
        cost: 0,
        playEffects: [InfinityShardEffect()],
      );
      player.hand.add(shard);

      game.playCard('test_shard_20');
      expect(player.mastery, 21);
      expect(player.powerPool, 15);
      expect(player.gemPool, 0);
    });

    test('Infinity Shard gives 1 mastery and 20 power at mastery 25', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 25;

      player.hand.clear();
      const shard = CardModel(
        id: 'test_shard_25',
        name: 'Infinity Shard',
        cost: 0,
        playEffects: [InfinityShardEffect()],
      );
      player.hand.add(shard);

      game.playCard('test_shard_25');
      expect(player.mastery, 26);
      expect(player.powerPool, 20);
      expect(player.gemPool, 0);
    });

    test('Infinity Shard at mastery 29 bumps to 30 and triggers instant win', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 29;

      player.hand.clear();
      const shard = CardModel(
        id: 'test_shard_29',
        name: 'Infinity Shard',
        cost: 0,
        playEffects: [InfinityShardEffect()],
      );
      player.hand.add(shard);

      game.playCard('test_shard_29');
      expect(player.mastery, 30);
      expect(game.isGameOver, true); // mastery 29 +1 = 30 → instant win
      expect(game.winnerId, player.id);
    });

    test('Infinity Shard at mastery 30 causes instant win', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 30;

      player.hand.clear();
      const shard = CardModel(
        id: 'test_shard_30',
        name: 'Infinity Shard',
        cost: 0,
        playEffects: [InfinityShardEffect()],
      );
      player.hand.add(shard);

      game.playCard('test_shard_30');

      expect(game.isGameOver, true);
      expect(game.winnerId, player.id);
    });

    test('Infinity Shard at mastery 50 causes instant win', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 50;

      player.hand.clear();
      const shard = CardModel(
        id: 'test_shard_50',
        name: 'Infinity Shard',
        cost: 0,
        playEffects: [InfinityShardEffect()],
      );
      player.hand.add(shard);

      game.playCard('test_shard_50');

      expect(game.isGameOver, true);
      expect(game.winnerId, player.id);
    });

    test('Infinity Shard at mastery 9 bumps to 10 and gives 6 power (enters tier 10-14)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 9;

      player.hand.clear();
      const shard = CardModel(
        id: 'test_shard_9',
        name: 'Infinity Shard',
        cost: 0,
        playEffects: [InfinityShardEffect()],
      );
      player.hand.add(shard);

      game.playCard('test_shard_9');
      expect(player.mastery, 10);
      expect(player.powerPool, 6); // mastery evaluated after +1: 10 → tier 10-14
      expect(player.gemPool, 0);
    });
  });

  group('Win conditions (Step 15)', () {
    test('elimination win sets winnerId', () {
      final game = GameService(playerCount: 2, random: Random(7));

      game.players[1].takeDamage(60);
      game.endTurn();

      expect(game.isGameOver, true);
      expect(game.winnerId, 'p0');
    });

    test('Infinity Shard instant win sets winnerId', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 30;

      player.hand.clear();
      const shard = CardModel(
        id: 'win_shard',
        name: 'Infinity Shard',
        cost: 0,
        playEffects: [InfinityShardEffect()],
      );
      player.hand.add(shard);

      game.playCard('win_shard');

      expect(game.isGameOver, true);
      expect(game.winnerId, 'p0');
    });

    test('3-player game: elimination of 2 players ends game', () {
      final game = GameService(playerCount: 3, random: Random(7));

      game.players[1].takeDamage(60);
      game.players[2].takeDamage(60);

      game.endTurn();

      expect(game.isGameOver, true);
      expect(game.winnerId, 'p0');
    });

    test('winnerId is null while game is in progress', () {
      final game = GameService(playerCount: 2, random: Random(7));
      expect(game.winnerId, isNull);
    });
  });

  group('ConditionalPowerEffect (Step 10)', () {
    test('perChampionControlled grants power per champion', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // Add 3 champions in play
      for (int i = 0; i < 3; i++) {
        player.championsInPlay.add(CardModel(
          id: 'cond_champ_$i',
          name: 'Conditional Champion $i',
          cost: 0,
          playEffects: [],
          cardType: CardType.champion,
          shield: 1,
        ));
      }

      player.hand.clear();
      const condCard = CardModel(
        id: 'test_conditional',
        name: 'Conditional Power',
        cost: 0,
        playEffects: [ConditionalPowerEffect(PowerCondition.perChampionControlled)],
      );
      player.hand.add(condCard);

      game.playCard('test_conditional');

      expect(player.powerPool, 3); // 1 per champion
    });

    test('perChampionControlled grants 0 power with no champions', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      player.hand.clear();
      const condCard = CardModel(
        id: 'test_cond_zero',
        name: 'Conditional Zero',
        cost: 0,
        playEffects: [ConditionalPowerEffect(PowerCondition.perChampionControlled)],
      );
      player.hand.add(condCard);

      game.playCard('test_cond_zero');

      expect(player.powerPool, 0);
    });
  });

  group('Combined mechanics integration tests', () {
    test('champion with mastery bonus re-triggers bonus when manually activated', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 5;

      // Play a champion with mastery bonus
      player.hand.clear();
      const champion = CardModel(
        id: 'mastery_champ',
        name: 'Mastery Champion',
        cost: 0,
        playEffects: [GainPowerEffect(2)],
        cardType: CardType.champion,
        shield: 3,
        masteryThreshold: 5,
        masteryBonus: [GainPowerEffect(3)],
      );
      player.hand.add(champion);
      game.playCard('mastery_champ');

      // First play: 2 power + 3 mastery bonus = 5
      expect(player.powerPool, 5);

      // Cycle back to p0
      game.endTurn(); // p0 -> p1, resets power
      game.endTurn(); // p1 -> p0

      // Champions don't auto-trigger — power should be 0
      expect(game.players[0].powerPool, 0);

      // Manually activate champion
      game.activateChampion('mastery_champ');

      // Champion re-triggers: 2 power + 3 mastery bonus = 5
      expect(game.players[0].powerPool, 5);
    });

    test('champion with ally ability and another same-faction card in play', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // Place two same-faction champions
      player.hand.clear();
      const champ1 = CardModel(
        id: 'ally_champ_1',
        name: 'Homodeus Champion 1',
        cost: 0,
        playEffects: [GainGemsEffect(1)],
        faction: Faction.homodeus,
        cardType: CardType.champion,
        shield: 2,
        allyAbility: [GainMasteryEffect(1)],
      );
      const champ2 = CardModel(
        id: 'ally_champ_2',
        name: 'Homodeus Champion 2',
        cost: 0,
        playEffects: [GainPowerEffect(1)],
        faction: Faction.homodeus,
        cardType: CardType.champion,
        shield: 2,
        allyAbility: [GainMasteryEffect(1)],
      );
      player.hand.addAll([champ1, champ2]);

      // Play first champion - no ally yet
      game.playCard('ally_champ_1');
      expect(player.mastery, 0); // no ally

      // Play second champion - ally triggers
      game.playCard('ally_champ_2');
      expect(player.mastery, 1); // ally ability of champ2 triggered
    });

    test('full turn flow: play cards, attack champion, attack player', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      // Set up: give attacker power cards, give target a guard champion
      attacker.hand.clear();
      const powerCard = CardModel(
        id: 'power_for_combat',
        name: 'Power Card',
        cost: 0,
        playEffects: [GainPowerEffect(10)],
      );
      attacker.hand.add(powerCard);

      const guard = CardModel(
        id: 'combat_guard',
        name: 'Combat Guard',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 3,
        hasGuard: true,
      );
      target.championsInPlay.add(guard);

      // Play the power card
      game.playCard('power_for_combat');
      expect(attacker.powerPool, 10);

      // Can't attack player directly due to guard
      expect(game.attackPlayer('p1', 5), false);

      // Destroy the guard
      expect(game.attackChampion('combat_guard', 'p1'), true);
      expect(attacker.powerPool, 7); // 10 - 3

      // Now attack the player
      expect(game.attackPlayer('p1', 5), true);
      expect(target.health, 45);
      expect(attacker.powerPool, 2);
    });

    test('champion ally ability re-triggers when manually activated', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // Play two same-faction champions
      player.hand.clear();
      const champ1 = CardModel(
        id: 'retrigger_ally_1',
        name: 'Wraethe Champion 1',
        cost: 0,
        playEffects: [GainPowerEffect(1)],
        faction: Faction.wraethe,
        cardType: CardType.champion,
        shield: 2,
        allyAbility: [GainPowerEffect(2)],
      );
      const champ2 = CardModel(
        id: 'retrigger_ally_2',
        name: 'Wraethe Champion 2',
        cost: 0,
        playEffects: [GainPowerEffect(1)],
        faction: Faction.wraethe,
        cardType: CardType.champion,
        shield: 2,
        allyAbility: [GainPowerEffect(2)],
      );
      player.hand.addAll([champ1, champ2]);

      game.playCard('retrigger_ally_1');
      game.playCard('retrigger_ally_2');

      // Cycle back
      game.endTurn();
      game.endTurn();

      // No auto-trigger — power is 0
      expect(game.players[0].powerPool, 0);

      // Manually activate both champions
      game.activateChampion('retrigger_ally_1');
      game.activateChampion('retrigger_ally_2');

      // champ1: play effects (1 power) + ally ability (2 power, because champ2 is in play)
      // champ2: play effects (1 power) + ally ability (2 power, because champ1 is in play)
      // Total: 1 + 2 + 1 + 2 = 6
      expect(game.players[0].powerPool, 6);
    });
  });

  group('DestroyChampionEffect (Phase 1)', () {
    CardModel champ(String id, {int shield = 3, bool guard = false}) =>
        CardModel(
          id: id,
          name: id,
          cost: 0,
          playEffects: const [],
          cardType: CardType.champion,
          shield: shield,
          hasGuard: guard,
        );

    test('destroyChampion sends target to owner discard, costs no power', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      final opp = game.players.firstWhere((p) => p.id != me.id);
      me.powerPool = 0;
      opp.championsInPlay.add(champ('enemy_champ', shield: 5));

      final result = game.destroyChampion('enemy_champ', opp.id);

      expect(result, true);
      expect(opp.championsInPlay, isEmpty);
      expect(opp.discardPile.map((c) => c.id), contains('enemy_champ'));
      expect(me.powerPool, 0); // no power spent
    });

    test('destroyChampion returns false for missing champion (no target)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final opp = game.players.firstWhere((p) => p.id != game.currentPlayer.id);
      expect(game.destroyChampion('nope', opp.id), false);
    });

    test('destroyChampion cannot target your own champion', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.championsInPlay.add(champ('my_champ'));
      expect(game.destroyChampion('my_champ', me.id), false);
      expect(me.championsInPlay, hasLength(1));
    });

    test('all variant destroys every enemy champion across opponents', () {
      final game = GameService(playerCount: 3, random: Random(7));
      final me = game.currentPlayer;
      final opps = game.players.where((p) => p.id != me.id).toList();
      opps[0].championsInPlay.addAll([champ('a'), champ('b')]);
      opps[1].championsInPlay.add(champ('c'));

      me.hand.clear();
      me.hand.add(const CardModel(
        id: 'wipe',
        name: 'Wipe',
        cost: 0,
        playEffects: [DestroyChampionEffect(all: true)],
      ));

      game.playCard('wipe');

      expect(opps[0].championsInPlay, isEmpty);
      expect(opps[1].championsInPlay, isEmpty);
      expect(opps[0].discardPile.map((c) => c.id), containsAll(['a', 'b']));
      expect(opps[1].discardPile.map((c) => c.id), contains('c'));
    });

    test('all variant is a no-op when no enemy champions exist', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.hand.clear();
      me.hand.add(const CardModel(
        id: 'wipe2',
        name: 'Wipe2',
        cost: 0,
        playEffects: [DestroyChampionEffect(all: true)],
      ));
      // Should not throw.
      expect(game.playCard('wipe2'), true);
    });

    test('single-target effect defers (does not auto-destroy on play)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      final opp = game.players.firstWhere((p) => p.id != me.id);
      opp.championsInPlay.add(champ('survivor'));

      me.hand.clear();
      me.hand.add(const CardModel(
        id: 'single_destroy',
        name: 'Single Destroy',
        cost: 0,
        playEffects: [DestroyChampionEffect()],
      ));
      game.playCard('single_destroy');

      // No target chosen yet — champion still in play.
      expect(opp.championsInPlay, hasLength(1));
    });
  });

  group('ReturnFromDiscardEffect (Phase 1)', () {
    CardModel disc(String id,
            {CardType type = CardType.regular,
            Faction faction = Faction.none}) =>
        CardModel(
          id: id,
          name: id,
          cost: 0,
          playEffects: const [],
          cardType: type,
          faction: faction,
        );

    test('returns any card from discard to hand', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.discardPile.add(disc('reclaim'));

      final result = game.returnFromDiscard('reclaim');

      expect(result, true);
      expect(me.discardPile.where((c) => c.id == 'reclaim'), isEmpty);
      expect(me.hand.map((c) => c.id), contains('reclaim'));
    });

    test('returns false on empty / missing discard card', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.discardPile.clear();
      expect(game.returnFromDiscard('ghost'), false);
    });

    test('champion filter rejects a non-champion card', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.discardPile.add(disc('reg', type: CardType.regular));

      final result =
          game.returnFromDiscard('reg', filter: ReturnFilter.champion);

      expect(result, false);
      expect(me.discardPile.map((c) => c.id), contains('reg'));
      expect(me.hand.map((c) => c.id), isNot(contains('reg')));
    });

    test('champion filter accepts a champion card', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.discardPile.add(disc('hero', type: CardType.champion));

      expect(
        game.returnFromDiscard('hero', filter: ReturnFilter.champion),
        true,
      );
      expect(me.hand.map((c) => c.id), contains('hero'));
    });

    test('faction filter matches only the named faction', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.discardPile.add(disc('green', faction: Faction.undergrowth));
      me.discardPile.add(disc('gold', faction: Faction.homodeus));

      expect(
        game.returnFromDiscard('gold',
            filter: ReturnFilter.faction, faction: Faction.undergrowth),
        false,
      );
      expect(
        game.returnFromDiscard('green',
            filter: ReturnFilter.faction, faction: Faction.undergrowth),
        true,
      );
      expect(me.hand.map((c) => c.id), contains('green'));
    });

    test('faction filter with null faction never matches', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.discardPile.add(disc('x', faction: Faction.order));
      expect(
        game.returnFromDiscard('x', filter: ReturnFilter.faction),
        false,
      );
    });
  });

  group('ConditionalPowerEffect expansion (Phase 1)', () {
    CardModel factionCard(String id, Faction faction,
            {List<CardEffect> effects = const []}) =>
        CardModel(
          id: id,
          name: id,
          cost: 0,
          playEffects: effects,
          faction: faction,
        );

    test('perCardInDiscard grants power per discard card', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.discardPile
          .addAll([factionCard('d1', Faction.none), factionCard('d2', Faction.none)]);
      me.hand.clear();
      me.hand.add(factionCard('scaler', Faction.none,
          effects: const [
            ConditionalPowerEffect(PowerCondition.perCardInDiscard)
          ]));

      game.playCard('scaler');

      expect(me.powerPool, 2);
    });

    test('perCardInDiscard grants 0 with empty discard', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.discardPile.clear();
      me.hand.clear();
      me.hand.add(factionCard('scaler0', Faction.none,
          effects: const [
            ConditionalPowerEffect(PowerCondition.perCardInDiscard)
          ]));

      game.playCard('scaler0');

      expect(me.powerPool, 0);
    });

    test('perAllyPlayedThisTurn counts same-faction cards played, excluding self',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.hand.clear();
      // Two Wraethe cards played first, then the scaler (also Wraethe).
      me.hand.add(factionCard('w1', Faction.wraethe));
      me.hand.add(factionCard('w2', Faction.wraethe));
      me.hand.add(factionCard('o1', Faction.order)); // different faction
      me.hand.add(factionCard('scaler_ally', Faction.wraethe,
          effects: const [
            ConditionalPowerEffect(PowerCondition.perAllyPlayedThisTurn)
          ]));

      game.playCard('w1');
      game.playCard('w2');
      game.playCard('o1');
      game.playCard('scaler_ally');

      // 2 prior Wraethe allies; the Order card and the scaler itself excluded.
      expect(me.powerPool, 2);
    });

    test('perAllyPlayedThisTurn is 0 when no allies played', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.hand.clear();
      me.hand.add(factionCard('lone', Faction.homodeus,
          effects: const [
            ConditionalPowerEffect(PowerCondition.perAllyPlayedThisTurn)
          ]));

      game.playCard('lone');

      expect(me.powerPool, 0);
    });

    test('perFactionPlayedThisTurn counts distinct factions, ignoring none', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.hand.clear();
      me.hand.add(factionCard('a', Faction.wraethe));
      me.hand.add(factionCard('b', Faction.wraethe)); // duplicate faction
      me.hand.add(factionCard('c', Faction.order));
      me.hand.add(factionCard('n', Faction.none)); // ignored
      me.hand.add(factionCard('scaler_fac', Faction.homodeus,
          effects: const [
            ConditionalPowerEffect(PowerCondition.perFactionPlayedThisTurn)
          ]));

      game.playCard('a');
      game.playCard('b');
      game.playCard('c');
      game.playCard('n');
      game.playCard('scaler_fac');

      // Distinct factions played: wraethe, order, homodeus = 3 (none ignored).
      expect(me.powerPool, 3);
    });

    test('cardsPlayedThisTurn resets after endTurn', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.hand.clear();
      me.hand.add(factionCard('p1', Faction.order));
      game.playCard('p1');
      expect(me.cardsPlayedThisTurn, isNotEmpty);

      game.endTurn();
      expect(me.cardsPlayedThisTurn, isEmpty);
    });
  });

  group('Exhaust / activated abilities', () {
    // Deploys [champion] for player 0 and cycles the turn back to player 0 so
    // the champion is a persistent fixture (not freshly played this turn).
    GameService deployForP0(CardModel champion) {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.hand.add(champion);
      game.playCard(champion.id);
      game.endTurn(); // p0 -> p1
      game.endTurn(); // p1 -> p0 (resets p0 resources, clears exhaust)
      return game;
    }

    CardModel abilityChampion({
      required String id,
      required ActivatedAbility ability,
      List<CardEffect> playEffects = const [],
    }) {
      return CardModel(
        id: id,
        name: id,
        cost: 0,
        playEffects: playEffects,
        cardType: CardType.champion,
        shield: 3,
        activatedAbility: ability,
      );
    }

    test('useActivatedAbility resolves the ability effects', () {
      final game = deployForP0(abilityChampion(
        id: 'exh_power',
        ability: const ActivatedAbility(effects: [GainPowerEffect(4)]),
      ));

      expect(game.players[0].powerPool, 0);
      expect(game.useActivatedAbility('exh_power'), true);
      expect(game.players[0].powerPool, 4);
    });

    test('using the ability exhausts the champion (blocks re-use same turn)',
        () {
      final game = deployForP0(abilityChampion(
        id: 'exh_block',
        ability: const ActivatedAbility(effects: [GainGemsEffect(2)]),
      ));

      expect(game.useActivatedAbility('exh_block'), true);
      expect(game.players[0].gemPool, 2);
      expect(game.players[0].exhaustedChampions, contains('exh_block'));

      // Second use the same turn is rejected and changes nothing.
      expect(game.useActivatedAbility('exh_block'), false);
      expect(game.players[0].gemPool, 2);
    });

    test('exhaust clears at the start of the owner\'s next turn', () {
      final game = deployForP0(abilityChampion(
        id: 'exh_next',
        ability: const ActivatedAbility(effects: [GainPowerEffect(1)]),
      ));

      expect(game.useActivatedAbility('exh_next'), true);
      expect(game.players[0].powerPool, 1);

      // Cycle a full round back to p0.
      game.endTurn(); // p0 -> p1 (clears p0 exhaust on cleanup)
      game.endTurn(); // p1 -> p0
      expect(game.players[0].exhaustedChampions, isEmpty);

      // Usable again next turn.
      expect(game.useActivatedAbility('exh_next'), true);
      expect(game.players[0].powerPool, 1);
    });

    test('champion with no activated ability returns false', () {
      final game = deployForP0(const CardModel(
        id: 'plain_champ',
        name: 'plain',
        cost: 0,
        playEffects: [GainPowerEffect(2)],
        cardType: CardType.champion,
        shield: 3,
      ));

      expect(game.useActivatedAbility('plain_champ'), false);
      expect(game.players[0].exhaustedChampions, isEmpty);
    });

    test('unknown champion id returns false', () {
      final game = deployForP0(abilityChampion(
        id: 'exh_known',
        ability: const ActivatedAbility(effects: [GainPowerEffect(1)]),
      ));
      expect(game.useActivatedAbility('does_not_exist'), false);
    });

    test('gem cost is paid on success', () {
      final game = deployForP0(abilityChampion(
        id: 'exh_gemcost',
        ability: const ActivatedAbility(
          effects: [GainPowerEffect(5)],
          cost: ActivationCost(gems: 2),
        ),
      ));
      game.players[0].gemPool = 3;

      expect(game.useActivatedAbility('exh_gemcost'), true);
      expect(game.players[0].gemPool, 1); // 3 - 2
      expect(game.players[0].powerPool, 5);
    });

    test('insufficient gems rejects the ability (no state change)', () {
      final game = deployForP0(abilityChampion(
        id: 'exh_poorgems',
        ability: const ActivatedAbility(
          effects: [GainPowerEffect(5)],
          cost: ActivationCost(gems: 2),
        ),
      ));
      game.players[0].gemPool = 1;

      expect(game.useActivatedAbility('exh_poorgems'), false);
      expect(game.players[0].gemPool, 1); // untouched
      expect(game.players[0].powerPool, 0); // effect not applied
      expect(game.players[0].exhaustedChampions, isEmpty); // not exhausted
    });

    test('mastery cost is paid and insufficient mastery is rejected', () {
      final game = deployForP0(abilityChampion(
        id: 'exh_mastery',
        ability: const ActivatedAbility(
          effects: [GainPowerEffect(3)],
          cost: ActivationCost(mastery: 5),
        ),
      ));

      // Mastery starts at 0 — too low.
      expect(game.players[0].mastery, 0);
      expect(game.useActivatedAbility('exh_mastery'), false);
      expect(game.players[0].exhaustedChampions, isEmpty);

      // Give enough mastery, now it works and the cost is deducted.
      game.players[0].mastery = 7;
      expect(game.useActivatedAbility('exh_mastery'), true);
      expect(game.players[0].mastery, 2); // 7 - 5
      expect(game.players[0].powerPool, 3);
    });

    test('health cost cannot be lethal to oneself', () {
      final game = deployForP0(abilityChampion(
        id: 'exh_health',
        ability: const ActivatedAbility(
          effects: [GainPowerEffect(10)],
          cost: ActivationCost(health: 5),
        ),
      ));

      // Reduce health to exactly the cost — paying would be lethal.
      game.players[0].health = 5;
      expect(game.useActivatedAbility('exh_health'), false);
      expect(game.players[0].health, 5);

      // One more health makes it payable.
      game.players[0].health = 6;
      expect(game.useActivatedAbility('exh_health'), true);
      expect(game.players[0].health, 1);
      expect(game.players[0].powerPool, 10);
    });

    test('activated ability is independent from the free activateChampion', () {
      // The champion has BOTH a normal play effect (re-resolvable via
      // activateChampion) AND an Exhaust ability. Using one must not consume the
      // other.
      final game = deployForP0(abilityChampion(
        id: 'exh_both',
        playEffects: const [GainGemsEffect(1)],
        ability: const ActivatedAbility(effects: [GainPowerEffect(2)]),
      ));

      // Free activation (play effects) — gems.
      expect(game.activateChampion('exh_both'), true);
      expect(game.players[0].gemPool, 1);
      // Exhaust ability still available — power.
      expect(game.useActivatedAbility('exh_both'), true);
      expect(game.players[0].powerPool, 2);

      // Both are now spent for the turn; both are independently blocked.
      expect(game.activateChampion('exh_both'), false);
      expect(game.useActivatedAbility('exh_both'), false);
      expect(game.players[0].gemPool, 1);
      expect(game.players[0].powerPool, 2);
    });

    test('exhausting does not block the free activation and vice versa', () {
      final game = deployForP0(abilityChampion(
        id: 'exh_order',
        playEffects: const [GainGemsEffect(3)],
        ability: const ActivatedAbility(effects: [GainPowerEffect(1)]),
      ));

      // Use the Exhaust ability first.
      expect(game.useActivatedAbility('exh_order'), true);
      expect(game.players[0].exhaustedChampions, contains('exh_order'));
      // The free activation is still available afterwards.
      expect(game.activateChampion('exh_order'), true);
      expect(game.players[0].gemPool, 3);
    });

    test('multiple champions exhaust independently', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final p0 = game.currentPlayer;
      p0.hand.addAll([
        abilityChampion(
          id: 'exh_a',
          ability: const ActivatedAbility(effects: [GainPowerEffect(1)]),
        ),
        abilityChampion(
          id: 'exh_b',
          ability: const ActivatedAbility(effects: [GainGemsEffect(2)]),
        ),
      ]);
      game.playCard('exh_a');
      game.playCard('exh_b');
      game.endTurn();
      game.endTurn();

      // Exhaust only champion A.
      expect(game.useActivatedAbility('exh_a'), true);
      expect(game.players[0].exhaustedChampions, contains('exh_a'));
      expect(game.players[0].exhaustedChampions, isNot(contains('exh_b')));

      // Champion B is still usable.
      expect(game.useActivatedAbility('exh_b'), true);
      expect(game.players[0].gemPool, 2);
      expect(game.players[0].powerPool, 1);
    });

    test('a freshly played champion can use its activated ability the same turn',
        () {
      // Exhaust gating is about the ABILITY, not summoning sickness — playing a
      // champion this turn does not stop its activated ability being used.
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.hand.add(abilityChampion(
        id: 'exh_fresh',
        ability: const ActivatedAbility(effects: [GainPowerEffect(2)]),
      ));
      game.playCard('exh_fresh');

      expect(game.useActivatedAbility('exh_fresh'), true);
      expect(game.currentPlayer.powerPool, 2);
    });
  });

  // -------------------------------------------------------------------------
  // Wave 1 — mastery REPLACE (vs additive) behavior
  // -------------------------------------------------------------------------
  group('mastery replace vs additive', () {
    // A card that normally gives 2 gems but, at mastery 15, gives 5 power.
    CardModel replaceCard() => const CardModel(
          id: 'test_replace',
          name: 'Replace Card',
          cost: 0,
          playEffects: [GainGemsEffect(2)],
          masteryThreshold: 15,
          masteryBonus: [GainPowerEffect(5)],
          masteryReplaces: true,
        );

    // Same effects, but additive (the legacy default).
    CardModel additiveCard() => const CardModel(
          id: 'test_additive',
          name: 'Additive Card',
          cost: 0,
          playEffects: [GainGemsEffect(2)],
          masteryThreshold: 15,
          masteryBonus: [GainPowerEffect(5)],
          // masteryReplaces defaults to false
        );

    test('REPLACE below threshold: playEffects resolve, bonus does NOT', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 10; // below 15
      player.hand.add(replaceCard());

      game.playCard('test_replace');

      expect(player.gemPool, 2, reason: 'playEffects resolved');
      expect(player.powerPool, 0, reason: 'mastery bonus did NOT resolve');
    });

    test('REPLACE at/above threshold: bonus resolves INSTEAD of playEffects',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 15; // at threshold
      player.hand.add(replaceCard());

      game.playCard('test_replace');

      // The distinguishing assertion: playEffects were SKIPPED.
      expect(player.gemPool, 0, reason: 'playEffects did NOT resolve');
      expect(player.powerPool, 5, reason: 'mastery bonus resolved instead');
    });

    test('ADDITIVE default below threshold is unchanged (playEffects only)',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 10;
      player.hand.add(additiveCard());

      game.playCard('test_additive');

      expect(player.gemPool, 2);
      expect(player.powerPool, 0);
    });

    test('ADDITIVE default at threshold is unchanged (BOTH resolve)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 15;
      player.hand.add(additiveCard());

      game.playCard('test_additive');

      // Proves the default behavior is untouched: playEffects AND bonus.
      expect(player.gemPool, 2, reason: 'playEffects still resolve');
      expect(player.powerPool, 5, reason: 'mastery bonus added on top');
    });

    // Wave 1 review follow-up: masteryReplaces=true is meaningless without a
    // bonus to replace WITH; it must degrade safely to playEffects rather than
    // resolving nothing.
    test('REPLACE with empty masteryBonus degrades to playEffects at threshold',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 30; // well above any threshold
      player.hand.add(const CardModel(
        id: 'test_replace_empty',
        name: 'Replace Empty',
        cost: 0,
        playEffects: [GainGemsEffect(2)],
        masteryThreshold: 15,
        masteryBonus: [], // nothing to replace with
        masteryReplaces: true,
      ));

      game.playCard('test_replace_empty');

      // Did NOT silently resolve nothing — playEffects still ran.
      expect(player.gemPool, 2, reason: 'falls back to playEffects');
      expect(player.powerPool, 0);
    });

    test('REPLACE applies to champion free activation too', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 15;
      const champ = CardModel(
        id: 'test_replace_champ',
        name: 'Replace Champ',
        cost: 0,
        cardType: CardType.champion,
        shield: 3,
        playEffects: [GainGemsEffect(2)],
        masteryThreshold: 15,
        masteryBonus: [GainPowerEffect(5)],
        masteryReplaces: true,
      );
      player.hand.add(champ);
      game.playCard('test_replace_champ'); // deploy resolves replace once

      expect(player.gemPool, 0);
      expect(player.powerPool, 5);

      // Free activation a fresh turn would also replace; simulate by reusing.
      player.activatedChampions.clear();
      player.gemPool = 0;
      player.powerPool = 0;
      expect(game.activateChampion('test_replace_champ'), true);
      expect(player.gemPool, 0);
      expect(player.powerPool, 5);
    });
  });

  // -------------------------------------------------------------------------
  // Wave 1 — ActivatedAbility mastery replace / additive
  // -------------------------------------------------------------------------
  group('activated ability mastery tier', () {
    CardModel wyrm({required bool replaces}) => CardModel(
          id: 'test_wyrm',
          name: 'Shard Wyrm',
          cost: 0,
          cardType: CardType.champion,
          shield: 4,
          playEffects: const [GainGemsEffect(1)],
          activatedAbility: ActivatedAbility(
            effects: const [GainPowerEffect(2), GainMasteryEffect(2)],
            masteryThreshold: 15,
            masteryBonusEffects: const [
              GainPowerEffect(5),
              GainMasteryEffect(5),
            ],
            replaces: replaces,
          ),
        );

    test('below threshold: base effects resolve, bonus does NOT', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.hand.add(wyrm(replaces: true));
      game.playCard('test_wyrm');
      player.mastery = 10; // below 15 (play gave none; set after deploy)

      expect(game.useActivatedAbility('test_wyrm'), true);
      expect(player.powerPool, 2, reason: 'base 2 power');
      expect(player.mastery, 12, reason: '10 + base 2 mastery');
    });

    test('REPLACE at threshold: bonus resolves INSTEAD of base', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.hand.add(wyrm(replaces: true));
      game.playCard('test_wyrm');
      player.mastery = 15;

      expect(game.useActivatedAbility('test_wyrm'), true);
      // Distinguishing: base (2/2) skipped, bonus (5/5) instead.
      expect(player.powerPool, 5);
      expect(player.mastery, 20, reason: '15 + bonus 5 (NOT base 2)');
    });

    test('ADDITIVE at threshold: base AND bonus both resolve', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.hand.add(wyrm(replaces: false));
      game.playCard('test_wyrm');
      player.mastery = 15;

      expect(game.useActivatedAbility('test_wyrm'), true);
      expect(player.powerPool, 7, reason: 'base 2 + bonus 5');
      expect(player.mastery, 22, reason: '15 + base 2 + bonus 5');
    });

    test('plain ability with no mastery fields is unaffected', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 30;
      const plain = CardModel(
        id: 'test_plain_exh',
        name: 'Plain Exhaust',
        cost: 0,
        cardType: CardType.champion,
        shield: 2,
        playEffects: [GainGemsEffect(1)],
        activatedAbility: ActivatedAbility(effects: [GainPowerEffect(3)]),
      );
      player.hand.add(plain);
      game.playCard('test_plain_exh');

      expect(game.useActivatedAbility('test_plain_exh'), true);
      expect(player.powerPool, 3);
    });
  });

  // -------------------------------------------------------------------------
  // Engine Phase 2 — Wave 2 (self-contained leaf effects)
  // -------------------------------------------------------------------------

  group('Wave 2: SelfBanishEffect', () {
    test('regular card banishes itself after resolving its other effects', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      const card = CardModel(
        id: 'aion_guide',
        name: 'Aion Guide',
        cost: 0,
        playEffects: [GainGemsEffect(3), SelfBanishEffect()],
      );
      player.hand.add(card);

      expect(game.playCard('aion_guide'), true);
      // Other effect still resolved.
      expect(player.gemPool, 3);
      // Source moved to removedFromGame, not lingering in any zone.
      expect(game.removedFromGame.map((c) => c.id), contains('aion_guide'));
      expect(player.playedThisTurn.any((c) => c.id == 'aion_guide'), false);
      expect(player.cardsPlayedThisTurn.any((c) => c.id == 'aion_guide'),
          false);
    });

    test('self-banished card is NOT discarded after endTurn', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      const card = CardModel(
        id: 'wandering_ghost',
        name: 'Wandering Ghost',
        cost: 0,
        playEffects: [GainPowerEffect(2), SelfBanishEffect()],
      );
      player.hand.add(card);
      game.playCard('wandering_ghost');

      game.endTurn();

      expect(game.removedFromGame.map((c) => c.id), contains('wandering_ghost'));
      expect(player.discardPile.any((c) => c.id == 'wandering_ghost'), false);
    });

    test('champion source self-banishes out of championsInPlay', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      const champ = CardModel(
        id: 'ghost_champ',
        name: 'Ghost Champion',
        cost: 0,
        cardType: CardType.champion,
        shield: 2,
        playEffects: [GainGemsEffect(1), SelfBanishEffect()],
      );
      player.hand.add(champ);
      game.playCard('ghost_champ');

      expect(player.gemPool, 1);
      expect(player.championsInPlay.any((c) => c.id == 'ghost_champ'), false);
      expect(game.removedFromGame.map((c) => c.id), contains('ghost_champ'));
    });
  });

  group('Wave 2: ResetChampionEffect / resetChampion()', () {
    CardModel exhaustChampion(String id) => CardModel(
          id: id,
          name: id,
          cost: 0,
          playEffects: const [],
          cardType: CardType.champion,
          shield: 3,
          activatedAbility:
              const ActivatedAbility(effects: [GainPowerEffect(1)]),
        );

    test('reset un-exhausts a champion so it is usable again same turn', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.hand.add(exhaustChampion('reset_me'));
      game.playCard('reset_me');

      // Exhaust it.
      expect(game.useActivatedAbility('reset_me'), true);
      expect(player.powerPool, 1);
      expect(player.exhaustedChampions, contains('reset_me'));
      // Cannot reuse while exhausted.
      expect(game.useActivatedAbility('reset_me'), false);

      // Reset it.
      expect(game.resetChampion('reset_me'), true);
      expect(player.exhaustedChampions, isEmpty);

      // Usable again this same turn.
      expect(game.useActivatedAbility('reset_me'), true);
      expect(player.powerPool, 2);
    });

    test('resetChampion rejects a champion that is not exhausted', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.hand.add(exhaustChampion('not_exhausted'));
      game.playCard('not_exhausted');

      expect(game.resetChampion('not_exhausted'), false);
    });

    test('resetChampion rejects a champion the player does not control', () {
      final game = GameService(playerCount: 2, random: Random(7));
      // p1 owns and exhausts a champion; p0 (current) cannot reset it.
      final p1 = game.players[1];
      p1.championsInPlay.add(exhaustChampion('enemy_champ'));
      p1.exhaustedChampions.add('enemy_champ');

      expect(game.resetChampion('enemy_champ'), false);
      expect(p1.exhaustedChampions, contains('enemy_champ'));
    });

    test('ResetChampionEffect is a no-op during resolution (deferred)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.championsInPlay.add(exhaustChampion('deferred_champ'));
      player.exhaustedChampions.add('deferred_champ');
      const card = CardModel(
        id: 'g_48',
        name: 'g_48',
        cost: 0,
        playEffects: [ResetChampionEffect()],
      );
      player.hand.add(card);

      game.playCard('g_48');
      // Effect alone does not reset — selection is deferred to resetChampion().
      expect(player.exhaustedChampions, contains('deferred_champ'));
    });
  });

  group('Wave 2: AllPlayersLoseHealthEffect', () {
    test('every player including the current one loses N health', () {
      final game = GameService(playerCount: 3, random: Random(7));
      final player = game.currentPlayer;
      const card = CardModel(
        id: 'bound_for_life',
        name: 'Bound For Life',
        cost: 0,
        playEffects: [AllPlayersLoseHealthEffect(4)],
      );
      player.hand.add(card);

      game.playCard('bound_for_life');

      for (final p in game.players) {
        expect(p.health, 46);
      }
    });

    test('triggers game over when an opponent hits 0', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      game.players[1].health = 5;
      player.health = 40;
      const card = CardModel(
        id: 'bound_for_life_lethal',
        name: 'Bound For Life',
        cost: 0,
        playEffects: [AllPlayersLoseHealthEffect(5)],
      );
      player.hand.add(card);

      game.playCard('bound_for_life_lethal');

      expect(game.players[1].isEliminated, true);
      expect(game.isGameOver, true);
      expect(game.winnerId, 'p0');
      expect(player.health, 35);
    });

    // Wave 2 combat-reviewer fix: a player who self-eliminates via
    // AllPlayersLoseHealth (the only effect that can kill the acting player)
    // must not keep acting. The game continues (>=2 others alive); the dead
    // player can no longer play/buy/attack, and endTurn hands off to a live one.
    test('current player self-eliminating cannot keep acting (3-player)', () {
      final game = GameService(playerCount: 3, random: Random(7));
      final p0 = game.currentPlayer;
      p0.health = 4; // lethal to self
      p0.hand.add(const CardModel(
        id: 'self_kill',
        name: 'Bound For Life',
        cost: 0,
        playEffects: [AllPlayersLoseHealthEffect(5)],
      ));
      // Give p0 something else to attempt afterwards.
      p0.powerPool = 10;

      game.playCard('self_kill');

      expect(p0.isEliminated, true, reason: 'self-eliminated');
      expect(game.isGameOver, false, reason: 'two others still alive');
      // The dead current player must not be able to act.
      expect(game.attackPlayer('p1', 5), false, reason: 'dead cannot attack');
      p0.hand.add(const CardModel(
          id: 'x', name: 'x', cost: 0, playEffects: [GainGemsEffect(1)]));
      expect(game.playCard('x'), false, reason: 'dead cannot play');
      // endTurn is the recovery path: hands control to a live player.
      game.endTurn();
      expect(game.currentPlayer.isEliminated, false,
          reason: 'control passed to a live player');
    });

    test('multiple players eliminated in one resolution -> game over', () {
      final game = GameService(playerCount: 3, random: Random(7));
      final p0 = game.currentPlayer;
      game.players[1].health = 3;
      game.players[2].health = 3;
      p0.health = 40;
      p0.hand.add(const CardModel(
        id: 'wipe',
        name: 'Bound For Life',
        cost: 0,
        playEffects: [AllPlayersLoseHealthEffect(5)],
      ));

      game.playCard('wipe');

      expect(game.players[1].isEliminated, true);
      expect(game.players[2].isEliminated, true);
      expect(game.isGameOver, true, reason: 'only p0 remains');
      expect(game.winnerId, 'p0');
    });
  });

  group('Wave 2: unblockedDamageThisTurn counter + condition', () {
    test('attackPlayer increments unblockedDamageThisTurn by damage dealt', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final p0 = game.currentPlayer;
      p0.powerPool = 10;

      expect(p0.unblockedDamageThisTurn, 0);
      expect(game.attackPlayer('p1', 3), true);
      expect(p0.unblockedDamageThisTurn, 3);
      expect(game.attackPlayer('p1', 4), true);
      expect(p0.unblockedDamageThisTurn, 7);
    });

    test('counter resets on the next turn', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final p0 = game.currentPlayer;
      p0.powerPool = 10;
      game.attackPlayer('p1', 5);
      expect(p0.unblockedDamageThisTurn, 5);

      game.endTurn(); // p0 -> p1 (resets p0)
      expect(p0.unblockedDamageThisTurn, 0);
    });

    // Wave 2 combat-reviewer #3: each player's counter is independent and
    // resets on THEIR own turn boundary, not anyone else's.
    test('each player counter resets on their own turn (multiplayer)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final p0 = game.currentPlayer;
      p0.powerPool = 10;
      game.attackPlayer('p1', 4);
      expect(p0.unblockedDamageThisTurn, 4);

      game.endTurn(); // now p1's turn; p0 was reset
      final p1 = game.currentPlayer;
      expect(p1.id, 'p1');
      expect(p0.unblockedDamageThisTurn, 0, reason: 'p0 reset on its endTurn');
      p1.powerPool = 10;
      game.attackPlayer('p0', 6);
      expect(p1.unblockedDamageThisTurn, 6, reason: 'p1 counts independently');

      game.endTurn(); // back to p0; p1 reset
      expect(p1.unblockedDamageThisTurn, 0, reason: 'p1 reset on its endTurn');
    });

    test('unblockedDamageAtLeast condition met after enough damage', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final p0 = game.currentPlayer;
      p0.powerPool = 10;
      game.attackPlayer('p1', 5);

      const card = CardModel(
        id: 'blood_for_blood',
        name: 'Blood For Blood',
        cost: 0,
        playEffects: [
          ConditionalEffect(
            condition: GameCondition(
              kind: GameConditionKind.unblockedDamageAtLeast,
              threshold: 5,
            ),
            then: [GainPowerEffect(3)],
          ),
        ],
      );
      p0.hand.add(card);
      game.playCard('blood_for_blood');

      // 10 power - 5 spent attacking + 3 from the met condition.
      expect(p0.powerPool, 8);
    });

    test('unblockedDamageAtLeast condition NOT met below threshold', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final p0 = game.currentPlayer;
      p0.powerPool = 10;
      game.attackPlayer('p1', 2); // only 2 unblocked

      const card = CardModel(
        id: 'blood_for_blood_2',
        name: 'Blood For Blood',
        cost: 0,
        playEffects: [
          ConditionalEffect(
            condition: GameCondition(
              kind: GameConditionKind.unblockedDamageAtLeast,
              threshold: 5,
            ),
            then: [GainPowerEffect(3)],
          ),
        ],
      );
      p0.hand.add(card);
      game.playCard('blood_for_blood_2');

      // 10 - 2 spent, condition not met so no bonus.
      expect(p0.powerPool, 8);
    });
  });

  // -------------------------------------------------------------------------
  // Engine Phase 2 — Wave 3 (deferred-selection action effects)
  // -------------------------------------------------------------------------

  group('Wave 3: RecruitFromCenterEffect / recruitFromCenter()', () {
    // Replace the center row with a known card so cost/destination is testable.
    CardModel seedCenter(GameService game, {required int cost, String id = 'recruit_target'}) {
      final card = CardModel(id: id, name: id, cost: cost, playEffects: const []);
      game.centerRow.clear();
      game.centerRow.add(card);
      return card;
    }

    test('effect alone changes nothing (deferred selection)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      seedCenter(game, cost: 2);
      final centerBefore = game.centerRow.length;
      const card = CardModel(
        id: 'portal_monk',
        name: 'Portal Monk',
        cost: 0,
        playEffects: [RecruitFromCenterEffect(maxCost: 4, free: true)],
      );
      player.hand.add(card);

      game.playCard('portal_monk');

      // No recruit happened: center row unchanged, no card in discard/hand.
      expect(game.centerRow.length, centerBefore);
      expect(player.discardPile.any((c) => c.id == 'recruit_target'), false);
    });

    test('free recruit to discard (default destination), no gems charged', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      seedCenter(game, cost: 3);
      player.gemPool = 5;

      expect(
        game.recruitFromCenter('recruit_target', free: true, maxCost: 4),
        true,
      );
      expect(player.gemPool, 5); // free → no charge
      expect(game.centerRow.any((c) => c.id == 'recruit_target'), false);
      expect(player.discardPile.last.id, 'recruit_target');
      expect(game.centerRow.length, 6); // refilled
    });

    test('paid recruit charges the card cost', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      seedCenter(game, cost: 3);
      player.gemPool = 5;

      expect(game.recruitFromCenter('recruit_target', free: false), true);
      expect(player.gemPool, 2); // 5 - 3
    });

    test('paid recruit rejected when unaffordable (no state change)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      seedCenter(game, cost: 3);
      player.gemPool = 2;

      expect(game.recruitFromCenter('recruit_target', free: false), false);
      expect(player.gemPool, 2);
      expect(game.centerRow.any((c) => c.id == 'recruit_target'), true);
    });

    test('rejected when over maxCost (no state change)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      seedCenter(game, cost: 5);
      player.gemPool = 9;

      expect(
        game.recruitFromCenter('recruit_target', free: true, maxCost: 4),
        false,
      );
      expect(game.centerRow.any((c) => c.id == 'recruit_target'), true);
      expect(player.gemPool, 9);
    });

    test('rejected when card not in center row', () {
      final game = GameService(playerCount: 2, random: Random(7));
      expect(game.recruitFromCenter('not_present', free: true), false);
    });

    test('recruit to hand', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      seedCenter(game, cost: 2);

      expect(
        game.recruitFromCenter('recruit_target', free: true, toHand: true),
        true,
      );
      expect(player.hand.any((c) => c.id == 'recruit_target'), true);
      expect(player.discardPile.any((c) => c.id == 'recruit_target'), false);
    });

    test('recruit to top of deck is the next card drawn', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      // Ensure a known draw pile.
      player.drawPile
        ..clear()
        ..addAll([
          const CardModel(id: 'bottom', name: 'bottom', cost: 0, playEffects: []),
        ]);
      player.hand.clear();
      seedCenter(game, cost: 2);

      expect(
        game.recruitFromCenter('recruit_target',
            free: true, toTopOfDeck: true),
        true,
      );
      // Not in discard/hand yet.
      expect(player.discardPile.any((c) => c.id == 'recruit_target'), false);
      expect(player.hand.any((c) => c.id == 'recruit_target'), false);

      // The card is now on TOP of the draw pile — it is what scryReveal (which
      // peeks the next-to-draw card) returns, i.e. the very next draw.
      expect(game.scryReveal().single.id, 'recruit_target');
      // And it is the last element of drawPile (the removeLast() draw target).
      expect(player.drawPile.last.id, 'recruit_target');
    });
  });

  group('Wave 3: FastPlayFromCenterEffect / fastPlayFromCenter()', () {
    CardModel seedCenter(
      GameService game, {
      required int cost,
      List<CardEffect> playEffects = const [],
      CardType cardType = CardType.regular,
      Faction faction = Faction.none,
      String id = 'warp_target',
    }) {
      final card = CardModel(
        id: id,
        name: id,
        cost: cost,
        playEffects: playEffects,
        cardType: cardType,
        faction: faction,
      );
      game.centerRow.clear();
      game.centerRow.add(card);
      return card;
    }

    test('effect alone changes nothing (deferred selection)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      seedCenter(game, cost: 2, playEffects: [const GainPowerEffect(3)]);
      const card = CardModel(
        id: 'aion_egressor',
        name: 'Aion Egressor',
        cost: 0,
        playEffects: [FastPlayFromCenterEffect(maxCost: 4)],
      );
      player.hand.add(card);

      game.playCard('aion_egressor');
      expect(player.powerPool, 0); // warp target not played
      expect(game.centerRow.any((c) => c.id == 'warp_target'), true);
    });

    test('card is played (effects resolve) then banished, center refilled', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      seedCenter(game, cost: 2, playEffects: [const GainPowerEffect(3)]);

      expect(game.fastPlayFromCenter('warp_target', maxCost: 4), true);
      expect(player.powerPool, 3); // play effects resolved
      // The physical card is banished and out of the discard/play-area zones.
      expect(player.playedThisTurn.any((c) => c.id == 'warp_target'), false);
      expect(player.discardPile.any((c) => c.id == 'warp_target'), false);
      expect(game.removedFromGame.any((c) => c.id == 'warp_target'), true);
      // But it STAYS recorded in cardsPlayedThisTurn — it was genuinely played,
      // so later cards' play-history scaling should still count it.
      expect(player.cardsPlayedThisTurn.any((c) => c.id == 'warp_target'), true,
          reason: 'warped ally still counts as played this turn');
      expect(game.centerRow.length, 6); // refilled
    });

    test('warped ally counts toward a later card\'s play-history scaling', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      // Seed an Order ally in the center to warp.
      seedCenter(game,
          cost: 2, faction: Faction.order, playEffects: const []);
      expect(game.fastPlayFromCenter('warp_target', maxCost: 4), true);

      // Now play an Order card whose effect scales per Order ally played.
      player.hand.add(const CardModel(
        id: 'scaler',
        name: 'Scaler',
        cost: 0,
        faction: Faction.order,
        playEffects: [
          ScalingResourceEffect(
            resource: ScalingResource.power,
            condition: ScalingCondition.perAllyPlayedThisTurn,
          ),
        ],
      ));
      game.playCard('scaler');
      // The banished-but-played warp target counts -> 1 power.
      expect(player.powerPool, 1,
          reason: 'warped ally counted toward later scaling');
    });

    test('warped card is NOT pulled into discard after endTurn', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      seedCenter(game, cost: 2, playEffects: [const GainPowerEffect(3)]);
      game.fastPlayFromCenter('warp_target', maxCost: 4);

      game.endTurn();

      expect(player.discardPile.any((c) => c.id == 'warp_target'), false,
          reason: 'cleanup must not discard a banished warp card');
      expect(game.removedFromGame.any((c) => c.id == 'warp_target'), true);
    });

    test('alliesOnly:false allows a champion to be warped (banished, not kept)',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      seedCenter(game,
          cost: 2,
          cardType: CardType.champion,
          playEffects: [const GainPowerEffect(3)]);

      expect(game.fastPlayFromCenter('warp_target'), true); // alliesOnly false
      expect(player.powerPool, 3);
      // Banished, did NOT persist as a champion.
      expect(player.championsInPlay.any((c) => c.id == 'warp_target'), false);
      expect(game.removedFromGame.any((c) => c.id == 'warp_target'), true);
    });

    test('rejected over maxCost (no state change)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      seedCenter(game, cost: 5, playEffects: [const GainPowerEffect(3)]);

      expect(game.fastPlayFromCenter('warp_target', maxCost: 4), false);
      expect(player.powerPool, 0);
      expect(game.centerRow.any((c) => c.id == 'warp_target'), true);
    });

    test('alliesOnly rejects a champion', () {
      final game = GameService(playerCount: 2, random: Random(7));
      seedCenter(game,
          cost: 2,
          cardType: CardType.champion,
          playEffects: [const GainPowerEffect(3)]);

      expect(game.fastPlayFromCenter('warp_target', alliesOnly: true), false);
      expect(game.centerRow.any((c) => c.id == 'warp_target'), true);
    });

    test('rejected when card not in center row', () {
      final game = GameService(playerCount: 2, random: Random(7));
      expect(game.fastPlayFromCenter('not_present'), false);
    });
  });

  group('Wave 3: ScryEffect / scryReveal() + scryResolve()', () {
    test('scryReveal does not remove the card', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.drawPile
        ..clear()
        ..addAll([
          const CardModel(id: 'under', name: 'under', cost: 0, playEffects: []),
          const CardModel(id: 'top', name: 'top', cost: 0, playEffects: []),
        ]);
      final sizeBefore = player.drawPile.length;

      final revealed = game.scryReveal();
      expect(revealed.single.id, 'top'); // top = end of drawPile
      expect(player.drawPile.length, sizeBefore); // not removed
    });

    test('effect alone changes nothing (deferred selection)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.drawPile
        ..clear()
        ..addAll([const CardModel(id: 'top', name: 'top', cost: 0, playEffects: [])]);
      player.hand.clear();
      const card = CardModel(
        id: 'keeper',
        name: 'Keeper',
        cost: 0,
        playEffects: [ScryEffect()],
      );
      player.hand.add(card);

      game.playCard('keeper');
      // 'top' still on the deck; nothing drawn/discarded by the effect alone.
      expect(player.drawPile.any((c) => c.id == 'top'), true);
    });

    test('scryResolve keep=true draws to hand (drawOrDiscard)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.drawPile
        ..clear()
        ..addAll([const CardModel(id: 'top', name: 'top', cost: 0, playEffects: [])]);
      player.hand.clear();

      expect(game.scryResolve('top', keep: true), true);
      expect(player.hand.single.id, 'top');
      expect(player.drawPile.any((c) => c.id == 'top'), false);
      expect(player.discardPile.any((c) => c.id == 'top'), false);
    });

    test('scryResolve keep=false discards (drawOrDiscard)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.drawPile
        ..clear()
        ..addAll([const CardModel(id: 'top', name: 'top', cost: 0, playEffects: [])]);
      player.discardPile.clear();

      expect(game.scryResolve('top', keep: false), true);
      expect(player.discardPile.single.id, 'top');
      expect(player.drawPile.any((c) => c.id == 'top'), false);
    });

    test('scryResolve keep=false banishes (drawOrBanish)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.drawPile
        ..clear()
        ..addAll([const CardModel(id: 'top', name: 'top', cost: 0, playEffects: [])]);

      expect(
        game.scryResolve('top',
            keep: false, disposition: ScryDisposition.drawOrBanish),
        true,
      );
      expect(game.removedFromGame.any((c) => c.id == 'top'), true);
      expect(player.drawPile.any((c) => c.id == 'top'), false);
    });

    test('scryResolve rejects a card not in the draw pile', () {
      final game = GameService(playerCount: 2, random: Random(7));
      expect(game.scryResolve('absent', keep: true), false);
    });

    // Wave 3 recruit/scry-reviewer follow-ups.
    test('toHand disposition: keep=true draws to hand', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.drawPile
        ..clear()
        ..addAll(
            [const CardModel(id: 'top', name: 'top', cost: 0, playEffects: [])]);
      player.hand.clear();

      expect(
        game.scryResolve('top',
            keep: true, disposition: ScryDisposition.toHand),
        true,
      );
      expect(player.hand.single.id, 'top');
      expect(player.drawPile.any((c) => c.id == 'top'), false);
    });

    test('toHand disposition: keep=false leaves the card on top (no-op)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.drawPile
        ..clear()
        ..addAll(
            [const CardModel(id: 'top', name: 'top', cost: 0, playEffects: [])]);
      player.hand.clear();

      expect(
        game.scryResolve('top',
            keep: false, disposition: ScryDisposition.toHand),
        true,
      );
      // Left on top, not drawn or discarded.
      expect(player.drawPile.last.id, 'top');
      expect(player.hand.isEmpty, true);
      expect(player.discardPile.any((c) => c.id == 'top'), false);
    });

    // Engine Phase 3 — oblivion_gatekeeper: own-deck reveal-to-hand, lose power
    // equal to the revealed card's cost (mandatory; ignores Guard).
    test('toHandLosePowerEqualToCost: takes card to hand and deducts its cost',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.drawPile
        ..clear()
        ..addAll([
          const CardModel(id: 'top', name: 'top', cost: 3, playEffects: [])
        ]);
      player.hand.clear();
      player.powerPool = 5;

      expect(
        game.scryResolve('top',
            keep: true,
            disposition: ScryDisposition.toHandLosePowerEqualToCost),
        true,
      );
      expect(player.hand.single.id, 'top');
      expect(player.drawPile.any((c) => c.id == 'top'), false);
      expect(player.powerPool, 2); // 5 - cost 3
    });

    test('toHandLosePowerEqualToCost: power floored at 0 (cost exceeds pool)',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.drawPile
        ..clear()
        ..addAll([
          const CardModel(id: 'pricey', name: 'pricey', cost: 8, playEffects: [])
        ]);
      player.hand.clear();
      player.powerPool = 2;

      // keep is ignored — the disposition is mandatory.
      expect(
        game.scryResolve('pricey',
            keep: false,
            disposition: ScryDisposition.toHandLosePowerEqualToCost),
        true,
      );
      expect(player.hand.single.id, 'pricey');
      expect(player.powerPool, 0); // floored, not negative
    });

    test('scryReveal(count: 2) returns the top two cards, top first', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.drawPile
        ..clear()
        ..addAll([
          const CardModel(id: 'bottom', name: 'bottom', cost: 0, playEffects: []),
          const CardModel(id: 'under', name: 'under', cost: 0, playEffects: []),
          const CardModel(id: 'top', name: 'top', cost: 0, playEffects: []),
        ]);

      final revealed = game.scryReveal(count: 2);
      expect(revealed.map((c) => c.id).toList(), ['top', 'under'],
          reason: 'top of deck (end of list) first');
      expect(player.drawPile.length, 3, reason: 'reveal does not remove');
    });
  });
}
