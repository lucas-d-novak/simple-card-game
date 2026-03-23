import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/services/deck_service.dart';

void main() {
  group('DeckService', () {
    test(
        'initializes with the starting deck, market row, and empty discard pile',
        () {
      final DeckService service = DeckService(random: Random(7));

      expect(service.deckCount, 6);
      expect(service.discardCount, 0);
      expect(service.marketCount, 4);
      expect(service.lastDrawn, isNull);
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
      final drawnCard = service.drawCard();

      expect(drawnCard, isNotNull);
      expect(service.deckCount, initialDeckCount - 1);
      expect(service.lastDrawn, same(drawnCard));
    });

    test('resetGame restores a fresh deck, market row, and empty discard pile',
        () {
      final DeckService service = DeckService(random: Random(7));

      service.drawCard();
      service.buyCardFromMarket('m1');

      service.resetGame();

      expect(service.deckCount, 6);
      expect(service.discardCount, 0);
      expect(service.marketCount, 4);
      expect(service.lastDrawn, isNull);
      expect(
        service.marketRow.map((card) => card.id).toList(),
        equals(<String>['m1', 'm2', 'm3', 'm4']),
      );
    });

    test('drawCard reshuffles the discard pile into the deck when needed', () {
      final DeckService service = DeckService(random: Random(7));

      expect(service.buyCardFromMarket('m1'), isTrue);

      for (int i = 0; i < 6; i++) {
        service.drawCard();
      }

      expect(service.deckCount, 0);
      expect(service.discardCount, 1);

      final drawnCard = service.drawCard();

      expect(drawnCard?.id, 'm1');
      expect(service.lastDrawn?.id, 'm1');
      expect(service.deckCount, 0);
      expect(service.discardCount, 0);
    });

    test('drawCard returns null when both deck and discard pile are empty', () {
      final DeckService service = DeckService(random: Random(7));

      for (int i = 0; i < 6; i++) {
        service.drawCard();
      }

      expect(service.drawCard(), isNull);
      expect(service.deckCount, 0);
      expect(service.discardCount, 0);
    });

    test('buyCardFromMarket moves cards to discard and rejects unknown ids',
        () {
      final DeckService service = DeckService(random: Random(7));

      expect(service.buyCardFromMarket('missing-card'), isFalse);
      expect(service.buyCardFromMarket('m2'), isTrue);

      expect(service.marketCount, 3);
      expect(service.discardCount, 1);
      expect(service.discardPile.single.id, 'm2');
      expect(service.buyCardFromMarket('m2'), isFalse);
      expect(service.marketCount, 3);
      expect(service.discardCount, 1);
    });
  });
}
