import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/ui/widgets/card_detail_modal.dart';

void main() {
  const card = CardModel(
    id: 'champ',
    name: 'Champ',
    cost: 3,
    playEffects: [],
    cardType: CardType.champion,
  );

  Future<void> openModal(
    WidgetTester tester, {
    CardDetailAction? Function(CardModel)? actionFor,
    CardDetailAction? Function(CardModel)? secondaryActionFor,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showCardDetailModal(
                  ctx,
                  cards: const [card],
                  initialIndex: 0,
                  actionFor: actionFor,
                  secondaryActionFor: secondaryActionFor,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders both primary and secondary action buttons',
      (tester) async {
    await openModal(
      tester,
      actionFor: (_) => CardDetailAction(label: 'Activate', onPressed: () {}),
      secondaryActionFor: (_) =>
          CardDetailAction(label: 'Exhaust', onPressed: () {}),
    );

    expect(find.text('Activate'), findsOneWidget);
    expect(find.text('Exhaust'), findsOneWidget);
  });

  testWidgets('no secondary button when secondaryActionFor returns null',
      (tester) async {
    await openModal(
      tester,
      actionFor: (_) => CardDetailAction(label: 'Play', onPressed: () {}),
      secondaryActionFor: (_) => null,
    );

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Exhaust'), findsNothing);
  });

  testWidgets('tapping the secondary action fires it and closes the modal',
      (tester) async {
    var fired = false;
    await openModal(
      tester,
      actionFor: (_) => CardDetailAction(label: 'Activate', onPressed: () {}),
      secondaryActionFor: (_) =>
          CardDetailAction(label: 'Exhaust', onPressed: () => fired = true),
    );

    await tester.tap(find.text('Exhaust'));
    await tester.pumpAndSettle();

    expect(fired, isTrue);
    // Modal popped — the action label is gone.
    expect(find.text('Exhaust'), findsNothing);
  });

  testWidgets('a disabled secondary action does not fire', (tester) async {
    var fired = false;
    await openModal(
      tester,
      actionFor: (_) => CardDetailAction(label: 'Activate', onPressed: () {}),
      secondaryActionFor: (_) => CardDetailAction(
        label: 'Exhaust',
        enabled: false,
        onPressed: () => fired = true,
      ),
    );

    await tester.tap(find.text('Exhaust'));
    await tester.pumpAndSettle();

    expect(fired, isFalse);
  });
}
