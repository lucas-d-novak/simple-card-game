import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/services/game_service.dart';
import 'package:simple_card_game/ui/screens/game_screen.dart';
import 'package:simple_card_game/ui/widgets/card_detail_modal.dart';

/// Passive-only champions (their ONLY on-play behaviour is a persistent aura —
/// every playEffect is an [AddStaticModifierEffect] — and they have no
/// Exhaust-gated [CardModel.activatedAbility]) must NOT show an Activate/Exhaust
/// button: the aura already applies on enter-play. Everything else keeps its
/// button ("Exhaust" for an ability, "Activate" for an active play-effect).
void main() {
  // A Zetta-like pure-aura champion: single cannotBeAttacked static modifier.
  const passiveAura = CardModel(
    id: 'zetta_like',
    name: 'Zetta-like',
    cost: 5,
    cardType: CardType.champion,
    shield: 2,
    playEffects: [
      AddStaticModifierEffect(
          StaticModifier(kind: StaticModifierKind.cannotBeAttacked)),
    ],
  );

  // An active play-effect champion (gains gems on activation), no ability.
  const activeChamp = CardModel(
    id: 'active_like',
    name: 'Active-like',
    cost: 3,
    cardType: CardType.champion,
    shield: 3,
    playEffects: [GainGemsEffect(2)],
  );

  // A Giga-like champion: a play effect AND an Exhaust-gated ability.
  const exhaustChamp = CardModel(
    id: 'giga_like',
    name: 'Giga-like',
    cost: 4,
    cardType: CardType.champion,
    shield: 4,
    playEffects: [DrawCardsEffect(1)],
    activatedAbility: ActivatedAbility(effects: [GainMasteryEffect(3)]),
  );

  group('isPassiveOnlyChampion predicate', () {
    test('true for a champion whose only playEffect is a static modifier', () {
      expect(isPassiveOnlyChampion(passiveAura), isTrue);
    });

    test('true for a Carmine-like multi-aura champion (all static, no ability)',
        () {
      const carmineLike = CardModel(
        id: 'carmine_like',
        name: 'Carmine-like',
        cost: 6,
        cardType: CardType.champion,
        playEffects: [
          AddStaticModifierEffect(StaticModifier(
              kind: StaticModifierKind.shieldPerCardUnder, amount: 1)),
        ],
      );
      expect(isPassiveOnlyChampion(carmineLike), isTrue);
    });

    test('false when it ALSO has a non-passive play effect', () {
      const mixed = CardModel(
        id: 'mixed',
        name: 'Mixed',
        cost: 5,
        cardType: CardType.champion,
        playEffects: [
          AddStaticModifierEffect(
              StaticModifier(kind: StaticModifierKind.cannotBeAttacked)),
          DrawCardsEffect(1),
        ],
      );
      expect(isPassiveOnlyChampion(mixed), isFalse);
    });

    test('false when it has an activated (Exhaust) ability, even if every '
        'playEffect is a passive aura', () {
      const auraPlusAbility = CardModel(
        id: 'aura_ability',
        name: 'Aura+Ability',
        cost: 5,
        cardType: CardType.champion,
        playEffects: [
          AddStaticModifierEffect(
              StaticModifier(kind: StaticModifierKind.cannotBeAttacked)),
        ],
        activatedAbility: ActivatedAbility(effects: [GainMasteryEffect(1)]),
      );
      expect(isPassiveOnlyChampion(auraPlusAbility), isFalse);
    });

    test('false for a vanilla champion with no play effects (keeps its button)',
        () {
      const vanilla = CardModel(
        id: 'vanilla',
        name: 'Vanilla',
        cost: 2,
        cardType: CardType.champion,
        shield: 3,
        playEffects: [],
      );
      expect(isPassiveOnlyChampion(vanilla), isFalse);
    });

    test('false for active / exhaust champions', () {
      expect(isPassiveOnlyChampion(activeChamp), isFalse);
      expect(isPassiveOnlyChampion(exhaustChamp), isFalse);
    });
  });

  group('local board champion zoom button', () {
    Future<void> pumpWithChampion(WidgetTester tester, CardModel champ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final game = GameService(playerCount: 2, random: Random(42));
      // The champion under test is the FIRST in play — debugOpenModal 'exhaust'
      // auto-opens the detail modal for championsInPlay.first.
      game.currentPlayer.championsInPlay.add(champ);

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(gameService: game, debugOpenModal: 'exhaust'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('passive-only champion shows NO Activate/Exhaust button',
        (tester) async {
      await pumpWithChampion(tester, passiveAura);
      // The zoom modal IS open (its scaled card is present)...
      expect(find.byKey(const ValueKey('detail_zetta_like')), findsOneWidget);
      // ...but there is no champion action button at all.
      expect(find.text('Exhaust'), findsNothing);
      expect(find.text('Activate'), findsNothing);
    });

    testWidgets('active play-effect champion shows an "Activate" button',
        (tester) async {
      await pumpWithChampion(tester, activeChamp);
      expect(find.text('Activate'), findsOneWidget);
      expect(find.text('Exhaust'), findsNothing);
    });

    testWidgets('Exhaust-ability champion shows an "Exhaust" button',
        (tester) async {
      await pumpWithChampion(tester, exhaustChamp);
      expect(find.text('Exhaust'), findsOneWidget);
    });
  });
}
