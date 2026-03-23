import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/main.dart';

Future<void> pumpDeckDrawApp(WidgetTester tester) async {
  await tester.pumpWidget(const DeckDrawApp());
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

void main() {
  testWidgets('DeckDrawApp renders the initial demo state', (
    WidgetTester tester,
  ) async {
    await pumpDeckDrawApp(tester);

    expect(find.text('Deck Draw Demo'), findsOneWidget);
    expect(find.text('Last drawn card:'), findsOneWidget);
    expect(find.text('No card drawn yet.'), findsOneWidget);
    expect(_deckCount(6), findsOneWidget);
    expect(_discardCount(0), findsOneWidget);
    expect(find.text('Draw card'), findsOneWidget);
    expect(find.text('Reset & Shuffle Deck'), findsOneWidget);
    expect(find.text('Market row'), findsOneWidget);
    expect(find.byKey(const ValueKey('market-card-m1')), findsOneWidget);
  });

  testWidgets('drawing a card updates the last drawn card and deck count', (
    WidgetTester tester,
  ) async {
    await pumpDeckDrawApp(tester);

    await tapKey(tester, 'draw-card-button');

    expect(find.text('No card drawn yet.'), findsNothing);
    expect(find.byKey(const ValueKey('last-drawn-card')), findsOneWidget);
    expect(_deckCount(5), findsOneWidget);
  });

  testWidgets('reset restores the initial state after draws and purchases', (
    WidgetTester tester,
  ) async {
    await pumpDeckDrawApp(tester);

    await tapKey(tester, 'draw-card-button');
    await tapKey(tester, 'buy-card-m1');

    expect(_discardCount(1), findsOneWidget);
    expect(find.byKey(const ValueKey('market-card-m1')), findsNothing);

    await tapKey(tester, 'reset-deck-button');

    expect(find.text('No card drawn yet.'), findsOneWidget);
    expect(_deckCount(6), findsOneWidget);
    expect(_discardCount(0), findsOneWidget);
    expect(find.byKey(const ValueKey('market-card-m1')), findsOneWidget);
  });

  testWidgets('drawing reshuffles the discard pile before showing empty state',
      (
    WidgetTester tester,
  ) async {
    await pumpDeckDrawApp(tester);

    await tapKey(tester, 'buy-card-m1');

    for (int i = 0; i < 7; i++) {
      await tapKey(tester, 'draw-card-button');
    }

    expect(find.text('Deck is empty!'), findsNothing);
    expect(find.text('Treasure +5'), findsOneWidget);
    expect(_deckCount(0), findsOneWidget);
    expect(_discardCount(0), findsOneWidget);
  });

  testWidgets(
      'shows an empty deck snackbar only when deck and discard are empty', (
    WidgetTester tester,
  ) async {
    await pumpDeckDrawApp(tester);

    for (int i = 0; i < 7; i++) {
      await tapKey(tester, 'draw-card-button');
    }

    expect(find.text('Deck is empty!'), findsOneWidget);
    expect(_deckCount(0), findsOneWidget);
    expect(_discardCount(0), findsOneWidget);
  });

  testWidgets(
      'buying a market card removes it from the market and adds it to discard',
      (
    WidgetTester tester,
  ) async {
    await pumpDeckDrawApp(tester);

    await tapKey(tester, 'buy-card-m2');

    expect(find.byKey(const ValueKey('market-card-m2')), findsNothing);
    expect(find.text('Treasure +4'), findsNothing);
    expect(_discardCount(1), findsOneWidget);
  });
}
