import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/ui/widgets/game_log_line.dart';
import 'package:simple_card_game/ui/widgets/resource_icons.dart';

/// The shared action-log line renderer (`GameLogLine`) is the single source of
/// truth used by BOTH boards, so it is tested board-agnostically with the two
/// name-resolution styles:
///  - "networked": seat id → lobby username (a names map).
///  - "local": seat id → PlayerState.name ("Player 2").
void main() {
  // Pump a single line under a minimal Directionality so `find.byType(RichText)`
  // resolves to exactly the line's own rich text.
  Future<void> pumpLine(WidgetTester tester, GameLogLine line) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(alignment: Alignment.topLeft, child: line),
    ));
  }

  // The line's plain text WITHOUT placeholder chars, so an iconified resource
  // (a WidgetSpan) contributes nothing — proving the WORD was replaced by an
  // icon, not left as text.
  String plainText(WidgetTester tester) => tester
      .widget<RichText>(find.byType(RichText))
      .text
      .toPlainText(includePlaceholders: false);

  List<ResourceIcon> icons(WidgetTester tester) => tester
      .widgetList<ResourceIconWidget>(find.byType(ResourceIconWidget))
      .map((w) => w.icon)
      .toList();

  String networked(String seatId) =>
      const {'p0': 'tritri', 'p1': 'tetra'}[seatId] ?? seatId;
  String local(String seatId) =>
      const {'p0': 'Player 1', 'p1': 'Player 2'}[seatId] ?? seatId;

  testWidgets(
      'recruit COST renders an inline gem icon (word gone, single line, no break)',
      (tester) async {
    await pumpLine(
      tester,
      GameLogLine(
        message: 'recruited chlorophyte guardian for 4 gems',
        actorId: 'p0',
        nameOf: networked,
      ),
    );

    // Exactly ONE rich text line — the grant/cost icons are inline, not on a
    // separate row (the newline bug).
    expect(find.byType(RichText), findsOneWidget);
    final text = plainText(tester);
    expect(text, contains('tritri recruited chlorophyte guardian for 4×'));
    expect(text, isNot(contains('gems')),
        reason: 'the cost word should be replaced by an icon');
    expect(icons(tester), [ResourceIcon.gem]);
  });

  testWidgets('focus renders (gem -> mastery) as icons', (tester) async {
    await pumpLine(
      tester,
      GameLogLine(
        message: 'focused (1 gem → 1 mastery)',
        actorId: 'p0',
        nameOf: networked,
      ),
    );

    final text = plainText(tester);
    // amount == 1 so no "1×" prefix; just the two icons around the arrow.
    expect(text, contains('tritri focused ( → )'));
    expect(text, isNot(contains('gem')));
    expect(text, isNot(contains('mastery')));
    expect(icons(tester), [ResourceIcon.gem, ResourceIcon.mastery]);
  });

  testWidgets('structured grants render inline after a played card',
      (tester) async {
    await pumpLine(
      tester,
      GameLogLine(
        message: 'played Crystal',
        actorId: 'p0',
        grants: const [LogGrant('gem', 1)],
        nameOf: networked,
      ),
    );

    expect(find.byType(RichText), findsOneWidget);
    expect(plainText(tester), contains('tritri played Crystal'));
    expect(icons(tester), [ResourceIcon.gem]);
  });

  testWidgets('turn-header entry resolves the player NAME (networked + local)',
      (tester) async {
    // Networked: seat id → username.
    await pumpLine(
      tester,
      GameLogLine(message: '— Turn 1: p1 —', nameOf: networked),
    );
    expect(plainText(tester), '— Turn 1: tetra —');

    // Local: seat id → PlayerState.name.
    await pumpLine(
      tester,
      GameLogLine(message: '— Turn 1: p1 —', nameOf: local),
    );
    expect(plainText(tester), '— Turn 1: Player 2 —');
  });

  testWidgets('action line inserts NAMES for both actor and target',
      (tester) async {
    await pumpLine(
      tester,
      GameLogLine(
        message: 'dealt 3 damage to p1',
        actorId: 'p0',
        nameOf: networked,
      ),
    );
    // Actor prefix (p0) and embedded target seat id (p1) both become names.
    expect(plainText(tester), 'tritri dealt 3 damage to tetra');
  });

  testWidgets('win line resolves the winner seat id to a name', (tester) async {
    await pumpLine(
      tester,
      GameLogLine(message: 'p0 wins!', nameOf: local),
    );
    expect(plainText(tester), 'Player 1 wins!');
  });
}
