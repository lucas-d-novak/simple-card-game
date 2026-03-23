import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/main.dart';
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

class MaxRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.999999;

  @override
  int nextInt(int max) => max - 1;
}

Future<void> pumpDeckDrawApp(
  WidgetTester tester, {
  DeckService? deckService,
}) async {
  await tester.pumpWidget(DeckDrawApp(deckService: deckService));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final Finder finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _deckCount(int count) => find.text('Cards left in deck: $count');

Finder _discardCount(int count) => find.text('Discard pile: $count');

Finder _availableMoney(int amount) => find.text('Money remaining: $amount');

Finder _playedCard(String cardId) =>
    find.byKey(ValueKey('played-card-$cardId'));

Finder _marketCard(String cardId) =>
    find.byKey(ValueKey('market-card-$cardId'));

OutlinedButton _buyButton(WidgetTester tester, String cardId) {
  return tester
      .widget<OutlinedButton>(find.byKey(ValueKey('buy-card-$cardId')));
}

OutlinedButton _shuffleDiscardButton(WidgetTester tester) {
  return tester.widget<OutlinedButton>(
    find.byKey(const ValueKey('shuffle-discard-button')),
  );
}

Future<void> playUntilAffordable(
  WidgetTester tester,
  DeckService service,
  String cardId,
) async {
  final CardModel marketCard =
      service.marketRow.firstWhere((card) => card.id == cardId);

  while (service.deckCount > 0 || service.hand.isNotEmpty) {
    if (service.canAffordCard(marketCard)) {
      return;
    }

    if (service.hand.isEmpty) {
      await tapKey(tester, 'draw-card-button');
      continue;
    }

    await tapKey(tester, 'play-card-${service.hand.first.id}');
  }
}

void main() {
  testWidgets('DeckDrawApp renders the initial demo state', (
    WidgetTester tester,
  ) async {
    await pumpDeckDrawApp(tester);

    expect(find.text('Deck Draw Demo'), findsOneWidget);
    expect(find.text('Your hand'), findsOneWidget);
    expect(find.text('Played cards'), findsOneWidget);
    expect(find.text('No cards in hand.'), findsOneWidget);
    expect(find.text('No cards played.'), findsOneWidget);
    expect(_deckCount(6), findsOneWidget);
    expect(_discardCount(0), findsOneWidget);
    expect(_availableMoney(0), findsOneWidget);
    expect(find.text('Draw 2 cards'), findsOneWidget);
    expect(find.text('Reset & Shuffle Deck'), findsOneWidget);
    expect(find.text('Market row'), findsOneWidget);
    expect(_marketCard('m1'), findsOneWidget);
    expect(_marketCard('m5'), findsOneWidget);
    expect(
      find.descendant(
        of: _marketCard('m1'),
        matching: find.text('When played: Gain 5 money'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _marketCard('m5'), matching: find.text('Cost: 3')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _marketCard('m5'),
        matching: find.text('When played: Draw 2 cards'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('drawing 2 cards keeps them in hand until they are played', (
    WidgetTester tester,
  ) async {
    final DeckService service = DeckService(random: Random(7));
    await pumpDeckDrawApp(tester, deckService: service);

    await tapKey(tester, 'draw-card-button');

    expect(find.text('No cards in hand.'), findsNothing);
    expect(find.text('No cards played.'), findsOneWidget);
    expect(_deckCount(4), findsOneWidget);
    expect(_availableMoney(0), findsOneWidget);
    expect(service.hand, hasLength(2));
    expect(service.playedCards, isEmpty);
    for (final card in service.hand) {
      expect(find.byKey(ValueKey('hand-card-${card.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('play-card-${card.id}')), findsOneWidget);
    }
  });

  testWidgets('playing a hand card moves it to played and updates money', (
    WidgetTester tester,
  ) async {
    final DeckService service = DeckService(random: Random(7));
    await pumpDeckDrawApp(tester, deckService: service);

    await tapKey(tester, 'draw-card-button');
    final CardModel cardToPlay = service.hand.first;

    await tapKey(tester, 'play-card-${cardToPlay.id}');

    expect(find.byKey(ValueKey('hand-card-${cardToPlay.id}')), findsNothing);
    expect(_playedCard(cardToPlay.id), findsOneWidget);
    expect(find.text('No cards played.'), findsNothing);
    expect(_availableMoney(gainMoneyAmount(cardToPlay)), findsOneWidget);
    expect(service.playedCards.map((card) => card.id), contains(cardToPlay.id));
    expect(service.hand, hasLength(1));
  });

  testWidgets(
      'reset restores the initial state after draws plays and purchases', (
    WidgetTester tester,
  ) async {
    final DeckService service = DeckService(random: Random(7));
    await pumpDeckDrawApp(tester, deckService: service);

    await playUntilAffordable(tester, service, 'm4');
    final int handCountBeforePurchase = service.hand.length;
    final int playedCountBeforePurchase = service.playedCards.length;
    final int moneyBeforePurchase = service.availableMoney;
    await tapKey(tester, 'buy-card-m4');

    expect(_discardCount(1), findsOneWidget);
    expect(find.byKey(const ValueKey('market-card-m4')), findsNothing);
    expect(service.hand, hasLength(handCountBeforePurchase));
    expect(service.playedCards, hasLength(playedCountBeforePurchase));
    expect(_availableMoney(moneyBeforePurchase - 2), findsOneWidget);

    await tapKey(tester, 'reset-deck-button');

    expect(find.text('No cards in hand.'), findsOneWidget);
    expect(find.text('No cards played.'), findsOneWidget);
    expect(_deckCount(6), findsOneWidget);
    expect(_discardCount(0), findsOneWidget);
    expect(_availableMoney(0), findsOneWidget);
    expect(service.hand, isEmpty);
    expect(service.playedCards, isEmpty);
    expect(find.byKey(const ValueKey('market-card-m4')), findsOneWidget);
    expect(_marketCard('m5'), findsOneWidget);
  });

  testWidgets(
      'drawing 2 cards keeps using the discard pile before showing empty state',
      (
    WidgetTester tester,
  ) async {
    final DeckService service = DeckService(random: Random(7));
    await pumpDeckDrawApp(tester, deckService: service);

    await playUntilAffordable(tester, service, 'm4');
    await tapKey(tester, 'buy-card-m4');

    while (service.deckCount > 0 || service.discardCount > 0) {
      await tapKey(tester, 'draw-card-button');
      if (service.deckCount > 0 || service.discardCount > 0) {
        expect(find.text('Deck is empty!'), findsNothing);
      }
    }

    await tapKey(tester, 'draw-card-button');

    expect(find.text('Deck is empty!'), findsOneWidget);
    expect(_deckCount(0), findsOneWidget);
    expect(_discardCount(0), findsOneWidget);
    expect(find.byKey(const ValueKey('hand-card-m4')), findsOneWidget);
    expect(_availableMoney(service.availableMoney), findsOneWidget);
  });

  testWidgets(
      'playing Scout draws cards into hand immediately without adding money', (
    WidgetTester tester,
  ) async {
    final DeckService service = DeckService(random: ZeroRandom());
    await pumpDeckDrawApp(tester, deckService: service);

    await playUntilAffordable(tester, service, 'm5');
    await tapKey(tester, 'buy-card-m5');
    await tapKey(tester, 'shuffle-discard-button');
    await tapKey(tester, 'draw-card-button');

    expect(service.hand.map((card) => card.id).toList(), ['c2', 'm5']);
    expect(_availableMoney(2), findsOneWidget);

    await tapKey(tester, 'play-card-m5');

    expect(_playedCard('m5'), findsOneWidget);
    expect(service.hand.map((card) => card.id).toList(), ['c2', 'c5', 'c4']);
    expect(find.byKey(const ValueKey('hand-card-c5')), findsOneWidget);
    expect(find.byKey(const ValueKey('hand-card-c4')), findsOneWidget);
    expect(_availableMoney(2), findsOneWidget);
  });

  testWidgets(
      'shows an empty deck snackbar only when deck and discard are empty', (
    WidgetTester tester,
  ) async {
    final DeckService service = DeckService(random: Random(7));
    await pumpDeckDrawApp(tester, deckService: service);

    while (service.deckCount > 0) {
      await tapKey(tester, 'draw-card-button');
    }

    await tapKey(tester, 'draw-card-button');

    expect(find.text('Deck is empty!'), findsOneWidget);
    expect(_deckCount(0), findsOneWidget);
    expect(_discardCount(0), findsOneWidget);
  });

  testWidgets(
      'market buy buttons start disabled and only affordable cards enable after playing',
      (
    WidgetTester tester,
  ) async {
    final DeckService service = DeckService(random: Random(7));
    await pumpDeckDrawApp(tester, deckService: service);

    expect(_buyButton(tester, 'm1').onPressed, isNull);
    expect(_buyButton(tester, 'm2').onPressed, isNull);
    expect(_buyButton(tester, 'm3').onPressed, isNull);
    expect(_buyButton(tester, 'm4').onPressed, isNull);
    expect(_buyButton(tester, 'm5').onPressed, isNull);

    await tapKey(tester, 'draw-card-button');

    expect(_availableMoney(0), findsOneWidget);
    expect(_buyButton(tester, 'm1').onPressed, isNull);
    expect(_buyButton(tester, 'm2').onPressed, isNull);
    expect(_buyButton(tester, 'm3').onPressed, isNull);
    expect(_buyButton(tester, 'm4').onPressed, isNull);
    expect(_buyButton(tester, 'm5').onPressed, isNull);

    await playUntilAffordable(tester, service, 'm4');

    expect(_availableMoney(service.availableMoney), findsOneWidget);
    for (final card in service.marketRow) {
      final Matcher expectedState =
          service.canAffordCard(card) ? isNotNull : isNull;
      expect(_buyButton(tester, card.id).onPressed, expectedState);
    }
  });

  testWidgets('Scout buy button enables once exactly 3 money is available', (
    WidgetTester tester,
  ) async {
    final DeckService service = DeckService(random: MaxRandom());
    await pumpDeckDrawApp(tester, deckService: service);

    await tapKey(tester, 'draw-card-button');
    await tapKey(tester, 'play-card-c5');

    expect(_availableMoney(3), findsOneWidget);
    expect(_buyButton(tester, 'm1').onPressed, isNull);
    expect(_buyButton(tester, 'm2').onPressed, isNull);
    expect(_buyButton(tester, 'm3').onPressed, isNotNull);
    expect(_buyButton(tester, 'm4').onPressed, isNotNull);
    expect(_buyButton(tester, 'm5').onPressed, isNotNull);
  });

  testWidgets(
      'buying an affordable market card removes it and subtracts from played money',
      (
    WidgetTester tester,
  ) async {
    final DeckService service = DeckService(random: Random(7));
    await pumpDeckDrawApp(tester, deckService: service);

    await playUntilAffordable(tester, service, 'm4');
    final int handCountBeforePurchase = service.hand.length;
    final int playedCountBeforePurchase = service.playedCards.length;
    final int moneyBeforePurchase = service.availableMoney;
    await tapKey(tester, 'buy-card-m4');

    expect(find.byKey(const ValueKey('market-card-m4')), findsNothing);
    expect(find.text('Treasure +2'), findsNothing);
    expect(_discardCount(1), findsOneWidget);
    expect(_availableMoney(moneyBeforePurchase - 2), findsOneWidget);
    expect(service.hand, hasLength(handCountBeforePurchase));
    expect(service.playedCards, hasLength(playedCountBeforePurchase));
    expect(_buyButton(tester, 'm1').onPressed, isNull);
    for (final card in service.marketRow) {
      final Matcher expectedState =
          service.canAffordCard(card) ? isNotNull : isNull;
      expect(_buyButton(tester, card.id).onPressed, expectedState);
    }
  });

  testWidgets(
      'shuffle new cards mixes the discard pile back into the current deck', (
    WidgetTester tester,
  ) async {
    final DeckService service = DeckService(random: Random(7));
    await pumpDeckDrawApp(tester, deckService: service);

    expect(_shuffleDiscardButton(tester).onPressed, isNull);

    await playUntilAffordable(tester, service, 'm4');
    await tapKey(tester, 'buy-card-m4');
    final int deckCountBeforeShuffle = service.deckCount;

    expect(_discardCount(1), findsOneWidget);
    expect(_shuffleDiscardButton(tester).onPressed, isNotNull);

    await tapKey(tester, 'shuffle-discard-button');

    expect(_deckCount(deckCountBeforeShuffle + 1), findsOneWidget);
    expect(_discardCount(0), findsOneWidget);
    expect(service.deck.map((card) => card.id), contains('m4'));
    expect(_shuffleDiscardButton(tester).onPressed, isNull);
  });
}
