import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/ui/widgets/opponent_bar_strip.dart';
import 'package:simple_card_game/ui/widgets/resource_icons.dart';

/// Direct widget coverage for [OpponentBarStrip] — no server / fixture needed,
/// the strip is decoupled from the board via the [OpponentBarData] value class.
void main() {
  const opponents = <OpponentBarData>[
    OpponentBarData(
      id: 'p1',
      name: 'Alice',
      championCount: 2,
      mastery: 12,
      health: 20,
      guardShield: 4,
    ),
    OpponentBarData(
      id: 'p2',
      name: 'Bob',
      championCount: 0,
      mastery: 5,
      health: 15,
    ),
    OpponentBarData(
      id: 'p3',
      name: 'Cara',
      championCount: 1,
      mastery: 30,
      health: 8,
    ),
  ];

  Future<void> pumpStrip(
    WidgetTester tester, {
    required Size physicalSize,
    String? selectedId,
    ValueChanged<String>? onSelect,
    List<OpponentBarData> bars = opponents,
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: OpponentBarStrip(
              opponents: bars,
              selectedId: selectedId,
              onSelect: onSelect ?? (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The number of shield glyphs rendered (one per bar with a guardShield).
  int shieldChipCount(WidgetTester tester) => tester
      .widgetList<ResourceIconWidget>(find.byType(ResourceIconWidget))
      .where((w) => w.icon == ResourceIcon.shield)
      .length;

  testWidgets('renders one keyed bar per opponent with their stat values',
      (tester) async {
    // A comfortable (desktop-class) width so names render and nothing overlaps.
    await pumpStrip(tester, physicalSize: const Size(1200, 800));

    // The strip and each opponent bar are findable by their keys.
    expect(find.byKey(const ValueKey('opponentBarStrip')), findsOneWidget);
    expect(find.byKey(const ValueKey('opponentBar_p1')), findsOneWidget);
    expect(find.byKey(const ValueKey('opponentBar_p2')), findsOneWidget);
    expect(find.byKey(const ValueKey('opponentBar_p3')), findsOneWidget);

    // Names show at this width (not compact).
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Cara'), findsOneWidget);

    // Stat values render (values chosen distinct so each appears exactly once).
    expect(find.text('12'), findsOneWidget); // Alice mastery
    expect(find.text('20'), findsOneWidget); // Alice health
    expect(find.text('30'), findsOneWidget); // Cara mastery
    expect(find.text('8'), findsOneWidget); // Cara health
    expect(find.text('0'), findsOneWidget); // Bob champion count

    expect(tester.takeException(), isNull);
  });

  testWidgets('shield chip appears only for bars with a guardShield',
      (tester) async {
    await pumpStrip(tester, physicalSize: const Size(1200, 800));

    // Only Alice (guardShield: 4) has a shield glyph; Bob & Cara are null.
    expect(shieldChipCount(tester), 1);
    expect(find.text('4'), findsOneWidget); // Alice guard shield value
  });

  testWidgets('lays out 3 bars on a ~390px phone without overflow',
      (tester) async {
    await pumpStrip(tester, physicalSize: const Size(390, 844));

    // All three bars still render (shrunk via FittedBox / dropped to initials).
    expect(find.byKey(const ValueKey('opponentBar_p1')), findsOneWidget);
    expect(find.byKey(const ValueKey('opponentBar_p2')), findsOneWidget);
    expect(find.byKey(const ValueKey('opponentBar_p3')), findsOneWidget);

    // No layout overflow was thrown at mobile width.
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a bar invokes onSelect with that opponent id',
      (tester) async {
    String? tapped;
    await pumpStrip(
      tester,
      physicalSize: const Size(1200, 800),
      onSelect: (id) => tapped = id,
    );

    await tester.tap(find.byKey(const ValueKey('opponentBar_p2')));
    await tester.pump();
    expect(tapped, 'p2');

    await tester.tap(find.byKey(const ValueKey('opponentBar_p3')));
    await tester.pump();
    expect(tapped, 'p3');
  });

  testWidgets('selected bar highlights (gold border) without error',
      (tester) async {
    await pumpStrip(
      tester,
      physicalSize: const Size(1200, 800),
      selectedId: 'p2',
    );
    // Smoke: the selected id renders fine (border styling is visual).
    expect(find.byKey(const ValueKey('opponentBar_p2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
