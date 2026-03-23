import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/main.dart';
import 'package:simple_card_game/services/deck_service.dart';

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

OutlinedButton _buyButton(WidgetTester tester, String cardId) {
  return tester.widget<OutlinedButton>(find.byKey(ValueKey('buy-card-$cardId')));
}

Future<void> drawUntilAffordable(
  WidgetTester tester,
  DeckService service,
  String cardId,
) async {
  while (service.deckCount > 0) {
    final marketCard = service.marketRow.firstWhere((card) => card.id == cardId);
    if (service.canAffordCard(marketCard)) {
      return;
    }

    await tapKey(tester, 'draw-card-button');
  }
}

void main() {
  testWidgets('DeckDrawApp renders the initial demo state', (
    WidgetTester tester,
  ) async {
    await pumpDeckDrawApp(tester);

    expect(find.text('Deck Draw Demo'), findsOneWidget);
    expect(find.text('Your hand'), findsOneWidget);
    expect(find.text('No cards in hand.'), findsOneWidget);
    expect(_deckCount(6), findsOneWidget);
    expect(_discardCount(0), findsOneWidget);
    expect(_availableMoney(0), findsOneWidget);
    expect(find.text('Draw 2 cards'), findsOneWidget);
    expect(find.text('Reset & Shuffle Deck'), findsOneWidget);
    expect(find.text('Market row'), findsOneWidget);
    expect(find.byKey(const ValueKey('market-card-m1')), findsOneWidget);
  });

  testWidgets('drawing 2 cards shows both cards in hand and updates the deck', (
    WidgetTester tester,
  ) async {
    final DeckService service = DeckService(random: Random(7));
    await pumpDeckDrawApp(tester, deckService: service);

    await tapKey(tester, 'draw-card-button');

    expect(find.text('No cards in hand.'), findsNothing);
    expect(_deckCount(4), findsOneWidget);
    expect(_availableMoney(service.availableMoney), findsOneWidget);
    expect(service.hand, hasLength(2));
    for (final card in service.hand) {
      expect(find.byKey(ValueKey('hand-card-${card.id}')), findsOneWidget);
    }
  });

  testWidgets('reset restores the initial state after draws and purchases', (
    WidgetTester tester,
  ) async {
    final DeckService service = DeckService(random: Random(7));
    await pumpDeckDrawApp(tester, deckService: service);

    await drawUntilAffordable(tester, service, 'm4');
    final int handCountBeforePurchase = service.hand.length;
    final int moneyBeforePurchase = service.availableMoney;
    await tapKey(tester, 'buy-card-m4');

    expect(_discardCount(1), findsOneWidget);
    expect(find.byKey(const ValueKey('market-card-m4')), findsNothing);
    expect(find.text('No cards in hand.'), findsNothing);
    expect(_availableMoney(moneyBeforePurchase - 2), findsOneWidget);
    expect(service.hand, hasLength(handCountBeforePurchase));

    await tapKey(tester, 'reset-deck-button');

    expect(find.text('No cards in hand.'), findsOneWidget);
    expect(_deckCount(6), findsOneWidget);
    expect(_discardCount(0), findsOneWidget);
    expect(_availableMoney(0), findsOneWidget);
    expect(find.byKey(const ValueKey('market-card-m4')), findsOneWidget);
  });

  testWidgets(
      'drawing 2 cards keeps using the discard pile before showing empty state',
      (
    WidgetTester tester,
  ) async {
    final DeckService service = DeckService(random: Random(7));
    await pumpDeckDrawApp(tester, deckService: service);

    await drawUntilAffordable(tester, service, 'm4');
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
      'market buy buttons start disabled and only affordable cards enable after drawing',
      (
    WidgetTester tester,
  ) async {
    final DeckService service = DeckService(random: Random(7));
    await pumpDeckDrawApp(tester, deckService: service);

    expect(_buyButton(tester, 'm1').onPressed, isNull);
    expect(_buyButton(tester, 'm2').onPressed, isNull);
    expect(_buyButton(tester, 'm3').onPressed, isNull);
    expect(_buyButton(tester, 'm4').onPressed, isNull);

    await drawUntilAffordable(tester, service, 'm4');

    expect(_availableMoney(service.availableMoney), findsOneWidget);
    for (final card in service.marketRow) {
      final Matcher expectedState = service.canAffordCard(card)
          ? isNotNull
          : isNull;
      expect(_buyButton(tester, card.id).onPressed, expectedState);
    }
  });

  testWidgets(
      'buying an affordable market card removes it and subtracts from remaining money',
      (
    WidgetTester tester,
  ) async {
    final DeckService service = DeckService(random: Random(7));
    await pumpDeckDrawApp(tester, deckService: service);

    await drawUntilAffordable(tester, service, 'm4');
    final int handCountBeforePurchase = service.hand.length;
    final int moneyBeforePurchase = service.availableMoney;
    await tapKey(tester, 'buy-card-m4');

    expect(find.byKey(const ValueKey('market-card-m4')), findsNothing);
    expect(find.text('Treasure +2'), findsNothing);
    expect(_discardCount(1), findsOneWidget);
    expect(_availableMoney(moneyBeforePurchase - 2), findsOneWidget);
    expect(find.text('No cards in hand.'), findsNothing);
    expect(service.hand, hasLength(handCountBeforePurchase));
    expect(_buyButton(tester, 'm1').onPressed, isNull);
    for (final card in service.marketRow) {
      final Matcher expectedState = service.canAffordCard(card)
          ? isNotNull
          : isNull;
      expect(_buyButton(tester, card.id).onPressed, expectedState);
    }
  });
}
