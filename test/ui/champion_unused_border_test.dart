import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';

/// The blue border colour a card paints when it has an unused action (same as
/// the affordable-market prompt). Gold synergy uses 0xFFFFD666 instead.
const _blueBorder = Color(0xFF6FD0FF);

/// An in-play champion with an ACTIVE action: a free play-effect activation.
/// `championHasUnusedAction` returns true when it hasn't been activated yet.
const _activeChampion = CardModel(
  id: 'giga',
  name: 'Giga',
  cost: 4,
  playEffects: [GainPowerEffect(2)],
  faction: Faction.homodeus,
  cardType: CardType.champion,
  shield: 4,
);

/// A champion whose ONLY action is an Exhaust-gated activated ability (empty
/// playEffects) — mirrors isa_tel_tor_the_axe.
const _exhaustChampion = CardModel(
  id: 'isa_tel_tor',
  name: 'Isa Tel Tor',
  cost: 3,
  playEffects: [],
  faction: Faction.wraethe,
  cardType: CardType.champion,
  shield: 5,
  activatedAbility: ActivatedAbility(effects: [GainPowerEffect(2)]),
);

/// A passive-only aura champion (zetta_the_encryptor): no activated ability and
/// its only play-effect is a persistent `cannotBeAttacked` static modifier.
/// It carries NO action, so it must NEVER glow.
const _passiveChampion = CardModel(
  id: 'zetta_the_encryptor',
  name: 'Zetta the Encryptor',
  cost: 5,
  playEffects: [
    AddStaticModifierEffect(
      StaticModifier(kind: StaticModifierKind.cannotBeAttacked),
    ),
  ],
  faction: Faction.order,
  cardType: CardType.champion,
  shield: 6,
);

Future<BoxDecoration> _pumpAndDecoration(
  WidgetTester tester,
  GameCardWidget widget,
) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: widget))),
  );
  final container =
      tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
  return container.decoration! as BoxDecoration;
}

bool _hasBlueBorder(BoxDecoration d) {
  final border = d.border;
  if (border is! Border) return false;
  return border.top.color == _blueBorder;
}

void main() {
  group('championHasUnusedAction predicate (the SINGLE "unused" definition)',
      () {
    test('active champion with an unspent free activation is unused', () {
      expect(
        championHasUnusedAction(_activeChampion,
            activated: false, exhausted: false),
        isTrue,
      );
    });

    test('champion whose only action is an unspent Exhaust ability is unused',
        () {
      expect(
        championHasUnusedAction(_exhaustChampion,
            activated: false, exhausted: false),
        isTrue,
      );
    });

    test('a used/exhausted champion is NOT unused', () {
      // Free-activation champion whose activation is spent.
      expect(
        championHasUnusedAction(_activeChampion,
            activated: true, exhausted: false),
        isFalse,
      );
      // Exhaust-only champion whose ability is spent.
      expect(
        championHasUnusedAction(_exhaustChampion,
            activated: false, exhausted: true),
        isFalse,
      );
    });

    test('a passive-only aura champion is NEVER unused (no action to spend)',
        () {
      expect(
        championHasUnusedAction(_passiveChampion,
            activated: false, exhausted: false),
        isFalse,
      );
    });
  });

  group('GameCardWidget blue "unused action" border', () {
    testWidgets('an in-play champion with an available action shows blue border',
        (tester) async {
      final d = await _pumpAndDecoration(
        tester,
        GameCardWidget(
          card: _activeChampion,
          hasUnusedAction: championHasUnusedAction(_activeChampion,
              activated: false, exhausted: false),
        ),
      );
      expect(_hasBlueBorder(d), isTrue);
    });

    testWidgets('an exhausted/used champion shows NO blue border',
        (tester) async {
      final d = await _pumpAndDecoration(
        tester,
        GameCardWidget(
          card: _activeChampion,
          hasUnusedAction: championHasUnusedAction(_activeChampion,
              activated: true, exhausted: true),
        ),
      );
      expect(_hasBlueBorder(d), isFalse);
      expect(d.border, isNull);
    });

    testWidgets('a passive-only champion (Zetta) shows NO blue border',
        (tester) async {
      final d = await _pumpAndDecoration(
        tester,
        GameCardWidget(
          card: _passiveChampion,
          // Even though the caller "would" mark it, the predicate refuses.
          hasUnusedAction: championHasUnusedAction(_passiveChampion,
              activated: false, exhausted: false),
        ),
      );
      expect(_hasBlueBorder(d), isFalse);
      expect(d.border, isNull);
    });

    testWidgets(
        "an opponent's champion (rendered without the flag) shows NO blue "
        'border even with an available action', (tester) async {
      // The screens only pass hasUnusedAction for the CURRENT player's own
      // champions; opponent champions are rendered without it (default false),
      // so a would-be-unused enemy champion never glows.
      final d = await _pumpAndDecoration(
        tester,
        const GameCardWidget(card: _activeChampion),
      );
      expect(_hasBlueBorder(d), isFalse);
      expect(d.border, isNull);
    });
  });
}
