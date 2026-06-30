import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/widgets/shard_win_overlay.dart';

void main() {
  group('ShardWinOverlay', () {
    testWidgets('instant mode skips: calls onDone and renders nothing', (
      tester,
    ) async {
      // With no AnimationSettings above it, timing falls back to instant, so the
      // overlay must skip straight to onDone (never blocking a fast/headless
      // flow) and render no flourish.
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ShardWinOverlay(
            winnerName: 'Ada',
            onDone: () => done = true,
          ),
        ),
      );
      await tester.pump(); // let the post-frame callback fire

      expect(done, isTrue, reason: 'instant mode calls onDone immediately');
      expect(find.text('INFINITY ACHIEVED'), findsNothing);
    });

    testWidgets('animated mode renders the local-winner title after the spin', (
      tester,
    ) async {
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AnimationSettings(
            initialSpeed: AnimationSpeed.fast,
            child: ShardWinOverlay(
              winnerName: 'Ada',
              isLocalWinner: true,
              onDone: () => done = true,
            ),
          ),
        ),
      );

      // Drive the 2s timeline to completion.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2100));

      expect(find.text('INFINITY ACHIEVED'), findsOneWidget);
      expect(find.text('Ada reached Mastery 30'), findsOneWidget);
      // The sequence holds on the final frame; onDone fires on tap.
      expect(done, isFalse);
      await tester.tap(find.byType(ShardWinOverlay));
      await tester.pump();
      expect(done, isTrue, reason: 'tap skips/continues');
    });

    testWidgets('opponent win shows the ASCENDS title, not ACHIEVED', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AnimationSettings(
            initialSpeed: AnimationSpeed.fast,
            child: ShardWinOverlay(
              winnerName: 'Volos',
              isLocalWinner: false,
              onDone: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2100));

      expect(find.text('VOLOS ASCENDS'), findsOneWidget);
      expect(find.text('INFINITY ACHIEVED'), findsNothing);

      // Avoid a pending-timer failure from the held controller.
      await tester.tap(find.byType(ShardWinOverlay));
      await tester.pump();
    });
  });
}
