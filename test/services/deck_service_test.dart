import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/services/deck_service.dart';

void drawUntilAffordable(DeckService service, String cardId) {
  while (service.deckCount > 0) {
    final marketCard = service.marketRow.firstWhere((card) => card.id == cardId);
    if (service.canAffordCard(marketCard)) {
      return;
    }

    service.drawCard();
  }
}

void main() {
  group('DeckService', () {
    test(
        'initializes with the starting deck, market row, and empty discard pile',
        () {
      final DeckService service = DeckService(random: Random(7));

      expect(service.deckCount, 6);
      expect(service.hand, isEmpty);
      expect(service.discardCount, 0);
      expect(service.marketCount, 4);
      expect(service.lastDrawn, isNull);
      expect(service.availableMoney, 0);
      expect(
        service.deck.map((card) => card.id).toSet(),
        equals(<String>{'c1', 'c2', 'c3', 'c4', 'c5', 'c6'}),
      );
      expect(
        service.deck.map((card) => card.id).toList(),
        isNot(equals(<String>['c1', 'c2', 'c3', 'c4', 'c5', 'c6'])),
      );
      expect(
        service.marketRow.map((card) => card.id).toList(),
        equals(<String>['m1', 'm2', 'm3', 'm4']),
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
      expect(service.lastDrawn, same(drawnCard));
      expect(service.availableMoney, drawnCard?.moneyValue);
    });

    test('drawCards draws up to the requested number and tracks the last draw',
        () {
      final DeckService service = DeckService(random: Random(7));

      final List<CardModel> drawnCards = service.drawCards(2);

      expect(drawnCards, hasLength(2));
      expect(service.deckCount, 4);
      expect(service.hand, equals(drawnCards));
      expect(service.lastDrawn, same(drawnCards.last));
      expect(
        service.availableMoney,
        drawnCards.fold(0, (total, card) => total + card.moneyValue),
      );
    });

    test('resetGame restores a fresh deck, market row, and empty discard pile',
        () {
      final DeckService service = DeckService(random: Random(7));

      drawUntilAffordable(service, 'm4');
      service.buyCardFromMarket('m4');

      service.resetGame();

      expect(service.deckCount, 6);
      expect(service.hand, isEmpty);
      expect(service.discardCount, 0);
      expect(service.marketCount, 4);
      expect(service.lastDrawn, isNull);
      expect(service.availableMoney, 0);
      expect(
        service.marketRow.map((card) => card.id).toList(),
        equals(<String>['m1', 'm2', 'm3', 'm4']),
      );
    });

    test('drawCard reshuffles the discard pile into the deck when needed', () {
      final DeckService service = DeckService(random: Random(7));

      drawUntilAffordable(service, 'm4');
      expect(service.buyCardFromMarket('m4'), isTrue);

      while (service.deckCount > 0) {
        service.drawCard();
      }

      expect(service.deckCount, 0);
      expect(service.discardCount, 1);

      final drawnCard = service.drawCard();

      expect(drawnCard?.id, 'm4');
      expect(service.hand.last.id, drawnCard?.id);
      expect(service.lastDrawn?.id, drawnCard?.id);
      expect(service.deckCount, 0);
      expect(service.discardCount, 0);
    });

    test('drawCard returns null when both deck and discard pile are empty', () {
      final DeckService service = DeckService(random: Random(7));

      for (int i = 0; i < 6; i++) {
        service.drawCard();
      }

      final int availableMoneyBeforeEmptyDraw = service.availableMoney;

      expect(service.drawCard(), isNull);
      expect(service.deckCount, 0);
      expect(service.discardCount, 0);
      expect(service.availableMoney, availableMoneyBeforeEmptyDraw);
    });

    test('buyCardFromMarket rejects unknown ids and unaffordable cards', () {
      final DeckService service = DeckService(random: Random(7));

      expect(service.buyCardFromMarket('missing-card'), isFalse);
      expect(service.buyCardFromMarket('m2'), isFalse);

      expect(service.marketCount, 4);
      expect(service.discardCount, 0);
      expect(service.availableMoney, 0);
    });

    test('buyCardFromMarket moves affordable cards to discard and subtracts money',
        () {
      final DeckService service = DeckService(random: Random(7));

      drawUntilAffordable(service, 'm4');
      final int moneyInHandBeforePurchase = service.availableMoney;
      final int cardsInHandBeforePurchase = service.hand.length;

      expect(moneyInHandBeforePurchase, greaterThanOrEqualTo(2));
      expect(service.canAffordCard(service.marketRow[3]), isTrue);
      expect(service.canAffordCard(service.marketRow[0]), isFalse);

      expect(service.buyCardFromMarket('m4'), isTrue);

      expect(service.marketCount, 3);
      expect(service.discardCount, 1);
      expect(service.discardPile.first.id, 'm4');
      expect(service.hand, hasLength(cardsInHandBeforePurchase));
      expect(service.lastDrawn, same(service.hand.last));
      expect(service.availableMoney, moneyInHandBeforePurchase - 2);
      expect(service.buyCardFromMarket('m4'), isFalse);
      expect(service.marketCount, 3);
      expect(service.discardCount, 1);
    });

    test('buyCardFromMarket supports multiple purchases until money runs out', () {
      final DeckService service = DeckService(random: Random(7));

      drawUntilAffordable(service, 'm1');
      final int startingMoney = service.availableMoney;

      expect(service.buyCardFromMarket('m4'), isTrue);
      expect(service.availableMoney, startingMoney - 2);
      expect(service.buyCardFromMarket('m3'), isTrue);
      expect(service.availableMoney, startingMoney - 5);
      expect(service.buyCardFromMarket('m2'), isFalse);
      expect(service.discardPile.map((card) => card.id).toList(), ['m4', 'm3']);
    });
  });
}
