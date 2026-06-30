import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/ui/widgets/scrollable_board.dart';

/// A board whose header + minimum field + footer is ~520px tall. We render it
/// once in a TALL viewport (everything fits, no scroll) and once in a SHORT /
/// wide LANDSCAPE viewport (content overflows → must scroll to reach footer).
Widget _board() => const ScrollableBoard(
      minFieldHeight: 200,
      header: [
        SizedBox(height: 120, child: ColoredBox(color: Color(0xFF111111))),
      ],
      field: ColoredBox(
        color: Color(0xFF222222),
        child: SizedBox.expand(child: Text('FIELD')),
      ),
      footer: [
        SizedBox(
          height: 200,
          child: ColoredBox(
            color: Color(0xFF333333),
            child: Center(child: Text('END TURN')),
          ),
        ),
      ],
    );

void main() {
  group('ScrollableBoard', () {
    testWidgets('tall viewport: fits without scrolling, footer visible',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: _board())),
      );

      // The footer's "END TURN" is laid out within the viewport (not scrolled).
      final footer = tester.getRect(find.text('END TURN'));
      expect(footer.bottom, lessThanOrEqualTo(1200),
          reason: 'footer should be on-screen without scrolling');

      // There is no scrollable extent (content <= viewport).
      final position =
          tester.state<ScrollableState>(find.byType(Scrollable)).position;
      expect(position.maxScrollExtent, 0.0,
          reason: 'nothing to scroll when the board fits');

      // The field expanded to fill the slack: viewport(1200) - header(120) -
      // footer(200) = 880, which exceeds minFieldHeight(200).
      final field = tester.getRect(find.text('FIELD'));
      expect(field.height, greaterThan(200));
    });

    testWidgets(
        'short landscape viewport: overflows, footer reachable by scrolling',
        (tester) async {
      // 360 tall x 800 wide — a phone rotated to landscape.
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: _board())),
      );

      // header(120) + minField(200) + footer(200) = 520 > 360 → must scroll.
      final position =
          tester.state<ScrollableState>(find.byType(Scrollable)).position;
      expect(position.maxScrollExtent, greaterThan(0.0),
          reason: 'content taller than viewport must be scrollable');

      // The footer starts off-screen (below the 360px fold)...
      expect(tester.getRect(find.text('END TURN')).top, greaterThan(360));

      // ...but scrolling to the bottom brings it into view.
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -400));
      await tester.pump();
      expect(tester.getRect(find.text('END TURN')).bottom,
          lessThanOrEqualTo(360 + 1));

      // The field never collapsed below its minimum height.
      expect(tester.getRect(find.text('FIELD')).height,
          greaterThanOrEqualTo(200 - 0.5));
    });
  });
}
