import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/widgets/faction_flame_backdrop.dart';

Future<void> _pump(WidgetTester tester, Faction faction,
    {bool animated = false}) async {
  Widget tree = Directionality(
    textDirection: TextDirection.ltr,
    child: FactionFlameBackdrop(
      faction: faction,
      child: const SizedBox(width: 44, height: 52),
    ),
  );
  if (animated) {
    // Non-instant speed makes the flame flicker on a repeating controller.
    tree = AnimationSettings(
      initialSpeed: AnimationSpeed.fast,
      child: tree,
    );
  }
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: tree))));
}

void main() {
  group('FactionFlameBackdrop', () {
    testWidgets('renders its deck child and a flame CustomPaint', (tester) async {
      await _pump(tester, Faction.undergrowth);
      // The child (deck placeholder) is present…
      expect(find.byType(SizedBox), findsWidgets);
      // …behind a CustomPaint that draws the flame.
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('is static (no pending timers) in instant/test mode',
        (tester) async {
      // No AnimationSettings in the tree → instant fallback → the controller
      // must NOT be repeating, so pumpAndSettle returns immediately.
      await _pump(tester, Faction.wraethe);
      // If a repeating animation were running, this would time out.
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('animates (schedules frames) when motion is enabled',
        (tester) async {
      await _pump(tester, Faction.homodeus, animated: true);
      // A repeating controller keeps scheduling frames.
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets('renders for every faction including none', (tester) async {
      for (final f in Faction.values) {
        await _pump(tester, f);
        expect(find.byType(FactionFlameBackdrop), findsOneWidget);
      }
    });
  });
}
