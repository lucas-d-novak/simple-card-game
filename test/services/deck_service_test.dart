import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/services/deck_service.dart';

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

void drawAndPlayUntilAffordable(DeckService service, String cardId) {
  final CardModel marketCard =
      service.marketRow.firstWhere((card) => card.id == cardId);

  while (service.deckCount > 0) {
    if (service.canAffordCard(marketCard)) {
      return;
    }

    final CardModel? drawnCard = service.drawCard();
    if (drawnCard == null) {
      return;
    }

    service.playCardFromHand(drawnCard.id);
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
      expect(service.playedCards, isEmpty);
      expect(service.discardCount, 0);
      expect(service.marketCount, 5);
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
        equals(<String>['m1', 'm2', 'm3', 'm4', 'm5']),
      );
    });

    test('market row includes Scout as a cost 3 draw card', () {
      final DeckService service = DeckService(random: Random(7));

      final CardModel scout =
          service.marketRow.firstWhere((card) => card.id == 'm5');
      final DrawCardsEffect scoutEffect =
          scout.playEffects.single as DrawCardsEffect;

      expect(scout.name, 'Scout');
      expect(scout.cost, 3);
      expect(scout.playEffects, hasLength(1));
      expect(scoutEffect.count, 2);
      expect(gainMoneyAmount(scout), 0);
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

    test('drawCards draws up to the requested number and tracks the last draw',
        () {
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

      expect(
          service.hand.map((card) => card.id), isNot(contains(cardToPlay.id)));
      expect(service.playedCards, contains(same(cardToPlay)));
      expect(service.playedCards, hasLength(1));
      expect(service.lastDrawn, same(lastDrawnCard));
      expect(service.availableMoney, gainMoneyAmount(cardToPlay));
    });

    test('playCardFromHand rejects unknown and already played cards', () {
      final DeckService service = DeckService(random: Random(7));

      final CardModel drawnCard = service.drawCard()!;

      expect(service.playCardFromHand('missing-card'), isFalse);
      expect(service.playCardFromHand(drawnCard.id), isTrue);
      expect(service.playCardFromHand(drawnCard.id), isFalse);
      expect(
          service.playedCards.map((card) => card.id).toList(), [drawnCard.id]);
    });

    test(
        'lastDrawn remains the most recently drawn card after that card is played',
        () {
      final DeckService service = DeckService(random: Random(7));

      final List<CardModel> drawnCards = service.drawCards(2);
      final CardModel lastDrawnCard = drawnCards.last;

      expect(service.playCardFromHand(lastDrawnCard.id), isTrue);

      expect(service.lastDrawn, same(lastDrawnCard));
      expect(service.playedCards.last, same(lastDrawnCard));
    });

    test('playCardFromHand applies Scout draw effects without adding money', () {
      final DeckService service = DeckService(random: ZeroRandom());

      drawAndPlayUntilAffordable(service, 'm5');
      expect(service.buyCardFromMarket('m5'), isTrue);
      expect(service.shuffleDiscardIntoDeck(), isTrue);
      expect(service.drawCard()?.id, 'c2');
      expect(service.drawCard()?.id, 'm5');

      final int handCountBeforePlay = service.hand.length;
      final int deckCountBeforePlay = service.deckCount;
      final int availableMoneyBeforePlay = service.availableMoney;

      expect(service.playCardFromHand('m5'), isTrue);

      expect(service.playedCards.last.id, 'm5');
      expect(service.hand.map((card) => card.id).toList(), ['c2', 'c5', 'c4']);
      expect(service.hand, hasLength(handCountBeforePlay + 1));
      expect(service.deckCount, deckCountBeforePlay - 2);
      expect(service.lastDrawn?.id, 'c4');
      expect(service.availableMoney, availableMoneyBeforePlay);
    });

    test('Scout draw effects reuse discard reshuffle behavior when needed', () {
      final DeckService service = DeckService(random: ZeroRandom());

      drawAndPlayUntilAffordable(service, 'm5');
      expect(service.buyCardFromMarket('m5'), isTrue);
      expect(service.shuffleDiscardIntoDeck(), isTrue);
      expect(service.drawCard()?.id, 'c2');
      expect(service.drawCard()?.id, 'm5');
      expect(service.buyCardFromMarket('m4'), isTrue);

      while (service.deckCount > 0) {
        service.drawCard();
      }

      expect(service.discardPile.map((card) => card.id).toList(), ['m4']);
      expect(service.availableMoney, 0);
      expect(service.playCardFromHand('m5'), isTrue);
      expect(service.hand.map((card) => card.id), contains('m4'));
      expect(service.lastDrawn?.id, 'm4');
      expect(service.deckCount, 0);
      expect(service.discardCount, 0);
      expect(service.availableMoney, 0);
    });

    test(
        'resetGame restores a fresh deck, market row, and clears hand, played, and discard',
        () {
      final DeckService service = DeckService(random: Random(7));

      drawAndPlayUntilAffordable(service, 'm4');
      service.buyCardFromMarket('m4');

      service.resetGame();

      expect(service.deckCount, 6);
      expect(service.hand, isEmpty);
      expect(service.playedCards, isEmpty);
      expect(service.discardCount, 0);
      expect(service.marketCount, 5);
      expect(service.lastDrawn, isNull);
      expect(service.availableMoney, 0);
      expect(
        service.marketRow.map((card) => card.id).toList(),
        equals(<String>['m1', 'm2', 'm3', 'm4', 'm5']),
      );
    });

    test('drawCard reshuffles the discard pile into the deck when needed', () {
      final DeckService service = DeckService(random: Random(7));

      drawAndPlayUntilAffordable(service, 'm4');
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

    test(
        'shuffleDiscardIntoDeck mixes newly bought cards into the current deck',
        () {
      final DeckService service = DeckService(random: Random(7));

      drawAndPlayUntilAffordable(service, 'm4');
      final int deckCountBeforeShuffle = service.deckCount;
      final int handCountBeforeShuffle = service.hand.length;
      final int playedCountBeforeShuffle = service.playedCards.length;
      final CardModel? lastDrawnBeforeShuffle = service.lastDrawn;

      expect(service.buyCardFromMarket('m4'), isTrue);

      expect(service.shuffleDiscardIntoDeck(), isTrue);

      expect(service.deckCount, deckCountBeforeShuffle + 1);
      expect(service.discardCount, 0);
      expect(service.deck.map((card) => card.id), contains('m4'));
      expect(service.hand, hasLength(handCountBeforeShuffle));
      expect(service.playedCards, hasLength(playedCountBeforeShuffle));
      expect(service.lastDrawn, same(lastDrawnBeforeShuffle));
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

      service.drawCards(2);

      expect(service.buyCardFromMarket('missing-card'), isFalse);
      expect(service.buyCardFromMarket('m2'), isFalse);

      expect(service.marketCount, 5);
      expect(service.discardCount, 0);
      expect(service.availableMoney, 0);
    });

    test(
        'buyCardFromMarket moves affordable cards to discard and subtracts money',
        () {
      final DeckService service = DeckService(random: Random(7));

      drawAndPlayUntilAffordable(service, 'm4');
      final int moneyInHandBeforePurchase = service.availableMoney;
      final int cardsInHandBeforePurchase = service.hand.length;
      final int playedCardsBeforePurchase = service.playedCards.length;
      final CardModel? lastDrawnBeforePurchase = service.lastDrawn;

      expect(moneyInHandBeforePurchase, greaterThanOrEqualTo(2));
      expect(service.canAffordCard(service.marketRow[3]), isTrue);
      expect(service.canAffordCard(service.marketRow[0]), isFalse);

      expect(service.buyCardFromMarket('m4'), isTrue);

      expect(service.marketCount, 4);
      expect(service.discardCount, 1);
      expect(service.discardPile.first.id, 'm4');
      expect(service.hand, hasLength(cardsInHandBeforePurchase));
      expect(service.playedCards, hasLength(playedCardsBeforePurchase));
      expect(service.lastDrawn, same(lastDrawnBeforePurchase));
      expect(service.availableMoney, moneyInHandBeforePurchase - 2);
      expect(service.buyCardFromMarket('m4'), isFalse);
      expect(service.marketCount, 4);
      expect(service.discardCount, 1);
    });

    test('buyCardFromMarket supports multiple purchases until money runs out',
        () {
      final DeckService service = DeckService(random: Random(7));

      drawAndPlayUntilAffordable(service, 'm1');
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
