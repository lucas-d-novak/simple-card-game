import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/widgets/animated_value.dart';
import 'package:simple_card_game/ui/widgets/animated_zone.dart';

/// A tiny harness that lets a test flip [AnimatedCounter.value] between builds.
class _CounterHost extends StatefulWidget {
  const _CounterHost({super.key, required this.initial});
  final int initial;

  @override
  State<_CounterHost> createState() => _CounterHostState();
}

class _CounterHostState extends State<_CounterHost> {
  late int _value = widget.initial;

  void setValue(int v) => setState(() => _value = v);

  @override
  Widget build(BuildContext context) {
    return AnimatedCounter(
      value: _value,
      style: const TextStyle(fontSize: 14),
    );
  }
}

void main() {
  group('AnimatedCounter', () {
    testWidgets(
      'instant mode (no AnimationSettings): shows final value immediately, '
      'no timer leak, pumpAndSettle clean',
      (tester) async {
        final hostKey = GlobalKey<_CounterHostState>();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: _CounterHost(key: hostKey, initial: 2)),
            ),
          ),
        );

        expect(find.text('2'), findsOneWidget);

        // Change the value; in instant mode it must snap to the new number with
        // no pending flash/tween timer (else pumpAndSettle would hang).
        hostKey.currentState!.setValue(5);
        await tester.pump();
        expect(find.text('5'), findsOneWidget);
        expect(find.text('2'), findsNothing);

        // pumpAndSettle proves there are no lingering timers/animations.
        await tester.pumpAndSettle();
        expect(find.text('5'), findsOneWidget);
      },
    );

    testWidgets(
      'fast mode: tweens toward the new value over time (does not jump)',
      (tester) async {
        final hostKey = GlobalKey<_CounterHostState>();

        await tester.pumpWidget(
          MaterialApp(
            home: AnimationSettings(
              initialSpeed: AnimationSpeed.fast,
              child: Scaffold(
                body: Center(child: _CounterHost(key: hostKey, initial: 0)),
              ),
            ),
          ),
        );

        expect(find.text('0'), findsOneWidget);

        hostKey.currentState!.setValue(10);
        await tester.pump(); // start the tween
        // Advance partway through the counterTick (fast = 200ms). The shown
        // number should be mid-flight — strictly between the old and new value
        // (proving it TWEENS rather than jumping straight to the target).
        await tester.pump(const Duration(milliseconds: 120));

        final midText = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => int.tryParse(t.data ?? ''))
            .whereType<int>()
            .first;
        expect(midText, greaterThan(0));
        expect(midText, lessThan(10));

        // Let it finish; it must land exactly on the target with no leak.
        await tester.pumpAndSettle();
        expect(find.text('10'), findsOneWidget);
      },
    );

    testWidgets('builder variant renders the tweened integer', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AnimatedCounter(
                value: 7,
                builder: (context, shown) => Text('HP $shown'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('HP 7'), findsOneWidget);
    });
  });

  group('AnimatedZone', () {
    testWidgets(
      'zone add/remove pumps+settles clean in instant mode',
      (tester) async {
        final ids = ValueNotifier<List<String>>(['a', 'b']);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<List<String>>(
                valueListenable: ids,
                builder: (context, list, _) => Wrap(
                  children: [
                    for (final id in list)
                      AnimatedZoneList.wrap(
                        id: id,
                        child: SizedBox(
                          key: ValueKey('box-$id'),
                          width: 20,
                          height: 20,
                          child: Text(id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );

        expect(find.text('a'), findsOneWidget);
        expect(find.text('b'), findsOneWidget);

        // Add a card (c) and remove one (b) at once — the switcher must animate
        // in/out without leaking a timer in instant mode.
        ids.value = ['a', 'c'];
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('a'), findsOneWidget);
        expect(find.text('c'), findsOneWidget);
        expect(find.text('b'), findsNothing);

        ids.dispose();
      },
    );
  });
}
