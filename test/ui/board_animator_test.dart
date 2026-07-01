import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/widgets/board_animator.dart';
import 'package:simple_card_game/ui/widgets/resource_icons.dart';

void main() {
  group('BoardAnimator instant-skip', () {
    testWidgets(
      'no AnimationSettings (instant fallback): flyCard/flyResource are no-ops '
      'and complete synchronously, spawning nothing',
      (tester) async {
        // With no AnimationSettings above the scope, AnimationTiming.of falls
        // back to instant — so BoardAnimator must spawn NO overlay entries and
        // call onComplete immediately (mirrors ShardWinOverlay's instant skip).
        final fromKey = GlobalKey();
        final toKey = GlobalKey();
        late BoardAnimator animator;
        var cardDone = false;
        var resourceDone = false;

        await tester.pumpWidget(
          MaterialApp(
            home: BoardAnimatorScope(
              child: Scaffold(
                body: Builder(
                  builder: (context) {
                    animator = BoardAnimator.of(context);
                    return Row(
                      children: [
                        SizedBox(key: fromKey, width: 20, height: 20),
                        SizedBox(key: toKey, width: 20, height: 20),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );

        expect(animator.isNoop, isTrue,
            reason: 'instant timing → animator is a no-op');

        animator.flyCard(
          fromKey: fromKey,
          toKey: toKey,
          onComplete: () => cardDone = true,
        );
        animator.flyResource(
          fromKey: fromKey,
          toKey: toKey,
          icon: ResourceIcon.gem,
          count: 3,
          onComplete: () => resourceDone = true,
        );

        // Completion is synchronous — no pump needed, no pending timers.
        expect(cardDone, isTrue);
        expect(resourceDone, isTrue);

        // Pumping again must not surface any leaked timers.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      },
    );

    testWidgets(
      'animated mode: flyResource spawns a flight then removes it, calling '
      'onComplete',
      (tester) async {
        final fromKey = GlobalKey();
        final toKey = GlobalKey();
        late BoardAnimator animator;
        var done = false;

        await tester.pumpWidget(
          MaterialApp(
            home: AnimationSettings(
              initialSpeed: AnimationSpeed.fast,
              child: BoardAnimatorScope(
                child: Scaffold(
                  body: Builder(
                    builder: (context) {
                      animator = BoardAnimator.of(context);
                      return Padding(
                        padding: const EdgeInsets.all(40),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SizedBox(key: fromKey, width: 20, height: 20),
                            SizedBox(key: toKey, width: 20, height: 20),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );

        expect(animator.isNoop, isFalse,
            reason: 'fast timing with a scope → animator animates');

        animator.flyResource(
          fromKey: fromKey,
          toKey: toKey,
          icon: ResourceIcon.gem,
          onComplete: () => done = true,
        );

        // Let the staggered spawn + flight play out fully, then settle so no
        // timers leak.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        expect(done, isTrue, reason: 'the flight completes and calls onComplete');
      },
    );

    testWidgets('missing anchors: no-op completion, no crash', (tester) async {
      final present = GlobalKey();
      final absent = GlobalKey(); // never mounted
      late BoardAnimator animator;
      var done = false;

      await tester.pumpWidget(
        MaterialApp(
          home: AnimationSettings(
            initialSpeed: AnimationSpeed.fast,
            child: BoardAnimatorScope(
              child: Scaffold(
                body: Builder(
                  builder: (context) {
                    animator = BoardAnimator.of(context);
                    return SizedBox(key: present, width: 20, height: 20);
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Destination unresolved → completes immediately, spawns nothing.
      animator.flyCard(
        fromKey: present,
        toKey: absent,
        onComplete: () => done = true,
      );
      expect(done, isTrue);
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
