import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/services/deck_service.dart';
import 'package:simple_card_game/services/game_service.dart';

int gainMoneyAmount(CardModel card) {
  return card.playEffects
      .whereType<GainMoneyEffect>()
      .fold(0, (total, effect) => total + effect.amount);
}

class ZeroRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 0;
}

void drawAndPlayUntilAffordable(GameService service, String cardId) {
  final CardModel marketCard =
      service.marketRow.firstWhere((card) => card.id == cardId);

  while (service.currentPlayer.deckService.deckCount > 0) {
    if (service.canAffordCard(marketCard)) {
      return;
    }

    final CardModel? drawnCard = service.currentPlayer.deckService.drawCard();
    if (drawnCard == null) {
      return;
    }

    service.currentPlayer.deckService.playCardFromHand(drawnCard.id);
  }
}

void main() {
  group('DeckService', () {
    test('initializes with the starting deck and empty discard pile', () {
      final DeckService service = DeckService(random: Random(7));

      expect(service.deckCount, 6);
      expect(service.hand, isEmpty);
      expect(service.playedCards, isEmpty);
      expect(service.discardCount, 0);
      expect(service.lastDrawn, isNull);
      expect(service.availableMoney, 0);
      expect(
        service.deck.map((card) => card.id).toSet(),
        equals(<String>{'c1', 'c2', 'c3', 'c4', 'c5', 'c6'}),
      );
    });

    test('drawCard reduces deck size and updates the last drawn card', () {
      final DeckService service = DeckService(random: Random(7));

      final int initialDeckCount = service.deckCount;
      final CardModel? drawnCard = service.drawCard();

      expect(drawnCard, isNotNull);
      expect(service.deckCount, initialDeckCount - 1);
      expect(service.hand, hasLength(1));
      expect(service.hand.single, same(drawnCard));
      expect(service.playedCards, isEmpty);
      expect(service.lastDrawn, same(drawnCard));
      expect(service.availableMoney, 0);
    });

    test('drawCards draws up to the requested number and tracks the last draw', () {
      final DeckService service = DeckService(random: Random(7));

      final List<CardModel> drawnCards = service.drawCards(2);

      expect(drawnCards, hasLength(2));
      expect(service.deckCount, 4);
      expect(service.hand, equals(drawnCards));
      expect(service.playedCards, isEmpty);
      expect(service.lastDrawn, same(drawnCards.last));
      expect(service.availableMoney, 0);
    });

    test('playCardFromHand moves a hand card to played and adds its money', () {
      final DeckService service = DeckService(random: Random(7));

      final List<CardModel> drawnCards = service.drawCards(2);
      final CardModel cardToPlay = drawnCards.first;
      final CardModel lastDrawnCard = drawnCards.last;

      expect(service.playCardFromHand(cardToPlay.id), isTrue);

      expect(service.hand.map((card) => card.id), isNot(contains(cardToPlay.id)));
      expect(service.playedCards, contains(same(cardToPlay)));
      expect(service.playedCards, hasLength(1));
      expect(service.lastDrawn, same(lastDrawnCard));
      expect(service.availableMoney, gainMoneyAmount(cardToPlay));
    });

    test('lastDrawn remains the most recently drawn card after that card is played', () {
      final DeckService service = DeckService(random: Random(7));

      final List<CardModel> drawnCards = service.drawCards(2);
      final CardModel lastDrawnCard = drawnCards.last;

      expect(service.playCardFromHand(lastDrawnCard.id), isTrue);

      expect(service.lastDrawn, same(lastDrawnCard));
      expect(service.playedCards.last, same(lastDrawnCard));
    });
    
    test('deck service handles receivePurchasedCard and discardPlayedCards precisely', () {
      final DeckService service = DeckService(random: Random(7));
      service.drawCards(2);
      service.playCardFromHand(service.hand.first.id);
      
      final int initialMoney = service.availableMoney;
      
      // Mock purchasing
      service.receivePurchasedCard(const CardModel(id: 'mock', name: 'mock', cost: 1, playEffects: []));
      expect(service.discardCount, 1);
      expect(service.availableMoney, initialMoney - 1);
      
      // Mock discard
      service.discardPlayedCards();
      expect(service.playedCards.length, 0);
      expect(service.discardCount, 2); // The played card and the purchased card
      expect(service.availableMoney, 0);
    });
  });

  group('GameService', () {
    test('initializes with multiple players and the market row', () {
      final GameService game = GameService(numPlayers: 2, random: Random(7));
      expect(game.players, hasLength(2));
      expect(game.currentPlayerIndex, 0);
      expect(game.currentPlayer.name, 'Player 1');
      expect(game.marketRow, hasLength(5));
      expect(game.marketRow.map((c) => c.id).toList(), equals(<String>['m4_2', 'm3_2', 'm1_2', 'm5_2', 'm5_0']));
    });

    test('resetGame restores everything to initial state', () {
      final GameService game = GameService(numPlayers: 2, random: Random(7));
      game.currentPlayer.deckService.drawCards(2);
      game.endTurn();
      
      expect(game.currentPlayerIndex, 1);
      
      game.resetGame();
      expect(game.currentPlayerIndex, 0);
      expect(game.currentPlayer.deckService.hand, isEmpty);
      expect(game.marketRow, hasLength(5));
    });

    test('market row includes Scout as a cost 3 draw card', () {
      final GameService game = GameService(numPlayers: 2, random: Random(7));

      final CardModel scout =
          game.marketRow.firstWhere((card) => card.name == 'Scout');
      final DrawCardsEffect scoutEffect =
          scout.playEffects.single as DrawCardsEffect;

      expect(scout.name, 'Scout');
      expect(scout.cost, 3);
      expect(scout.playEffects, hasLength(1));
      expect(scoutEffect.count, 2);
      expect(gainMoneyAmount(scout), 0);
    });

    test('buyCardFromMarket removes market card, moves it to discard directly, and subtracts money', () {
      final GameService game = GameService(numPlayers: 2, random: Random(7));
      final activeDeck = game.currentPlayer.deckService;
      
      // Override random to be predictable or draw enough manually
      while(activeDeck.deckCount > 0 && activeDeck.availableMoney < 4) {
        final card = activeDeck.drawCard()!;
        activeDeck.playCardFromHand(card.id);
      }
      
      // Assume enough money is now drawn (4+)
      expect(activeDeck.availableMoney, greaterThanOrEqualTo(4));
      
      final int startDiscard = activeDeck.discardCount;
      final int startMoney = activeDeck.availableMoney;
      
      final CardModel cardToBuy = game.marketRow.firstWhere((c) => activeDeck.availableMoney >= c.cost);
      final int cost = cardToBuy.cost;
      expect(game.buyCardFromMarket(cardToBuy.id), isTrue); 
      expect(activeDeck.discardCount, startDiscard + 1);
      expect(activeDeck.availableMoney, startMoney - cost);
      expect(game.marketRow.map((c) => c.id).contains(cardToBuy.id), isFalse);
      expect(game.marketRow, hasLength(5)); // Refill test
    });

    test('endTurn discards ONLY played cards, advances turn, and automatically draws N cards for next player', () {
      final GameService game = GameService(numPlayers: 2, random: Random(7));
      final p1Deck = game.players[0].deckService;
      final p2Deck = game.players[1].deckService;

      // Current player draws 2 cards and plays 1
      p1Deck.drawCards(2);
      final cardIdToPlay = p1Deck.hand.first.id;
      final cardIdToKeep = p1Deck.hand.last.id;
      p1Deck.playCardFromHand(cardIdToPlay);

      expect(p1Deck.hand.length, 1);
      expect(p1Deck.playedCards.length, 1);

      // Trigger endTurn with 3 auto-draw
      game.endTurn();

      // Assert turn advanced
      expect(game.currentPlayerIndex, 1);
      expect(game.currentPlayer.name, 'Player 2');

      // Assert player 1 state: hand is left as is, played cards moved to discard.
      expect(p1Deck.hand.length, 1, reason: 'Hand should not be discarded at end of turn');
      expect(p1Deck.hand.first.id, cardIdToKeep);
      expect(p1Deck.playedCards.length, 0, reason: 'Played cards should be cleared');
      expect(p1Deck.discardCount, 1, reason: 'Played card moved to discard');
      expect(p1Deck.discardPile.first.id, cardIdToPlay);

      // Assert player 2 state: automatically drew 3 cards
      expect(p2Deck.hand.length, 5, reason: "Next player automatically draws up to initialStartingHandSize (5)");
    });
  });
}
