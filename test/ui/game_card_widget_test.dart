import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';

Future<void> pumpCard(WidgetTester tester, CardModel card,
    {double? width, bool compact = false}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: GameCardWidget(card: card, width: width, compact: compact),
        ),
      ),
    ),
  );
}

void main() {
  group('GameCardWidget rules text', () {
    // Champion with EMPTY playEffects whose only text lives in an Exhaust-gated
    // activated ability + a mastery tier — mirrors isa_tel_tor_the_axe.
    const isaTelTor = CardModel(
      id: 'isa_tel_tor_the_axe',
      name: 'Isa Tel Tor, the Axe',
      cost: 3,
      playEffects: [],
      faction: Faction.wraethe,
      cardType: CardType.champion,
      shield: 5,
      activatedAbility: ActivatedAbility(
        effects: [
          GainPowerEffect(2),
          ScalingResourceEffect(
            resource: ScalingResource.power,
            condition: ScalingCondition.perFactionCardInDiscard,
            faction: Faction.wraethe,
          ),
        ],
        masteryThreshold: 20,
        masteryBonusEffects: [
          TreatFactionAsEffect(from: Faction.wraethe, to: Faction.wraethe),
        ],
      ),
    );

    testWidgets(
        'champion with only an activated ability shows its Exhaust text',
        (tester) async {
      // Wide, non-compact so up to 3 rules lines render.
      await pumpCard(tester, isaTelTor, width: 160);

      // The "Exhaust:" prefixed activated-ability line must be surfaced even
      // though playEffects is empty.
      expect(
        find.textContaining('Exhaust:', findRichText: true),
        findsOneWidget,
      );
      // And it carries the gained-power body, not a blank/misleading line.
      expect(
        find.textContaining('Gain 2 power', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('rulesLines() surfaces ability + mastery tier', (tester) async {
      final lines = const GameCardWidget(card: isaTelTor).rulesLines();

      // No play effects, so the first line is the Exhaust ability.
      expect(lines, isNotEmpty);
      expect(lines.first, startsWith('Exhaust:'));
      // The activated ability's own mastery tier is folded into its description.
      expect(lines.first, contains('mastery 20'));
    });

    testWidgets('masteryBonus effects render with "Mastery N:" prefix',
        (tester) async {
      const card = CardModel(
        id: 'masteryguy',
        name: 'Mastery Guy',
        cost: 2,
        playEffects: [GainGemsEffect(1)],
        masteryThreshold: 15,
        masteryBonus: [GainPowerEffect(3)],
      );

      final lines = const GameCardWidget(card: card).rulesLines();
      expect(lines, contains('Gain 1 gem'));
      expect(lines, contains('Mastery 15: Gain 3 power'));
    });

    testWidgets('activation cost is spliced into the Exhaust prefix',
        (tester) async {
      const card = CardModel(
        id: 'paidability',
        name: 'Paid Ability',
        cost: 4,
        playEffects: [],
        cardType: CardType.champion,
        activatedAbility: ActivatedAbility(
          effects: [GainPowerEffect(4)],
          cost: ActivationCost(mastery: 1),
        ),
      );

      final lines = const GameCardWidget(card: card).rulesLines();
      expect(lines.single, 'Exhaust, pay 1 mastery: Gain 4 power');
    });

    testWidgets('plain card still shows only its play effects', (tester) async {
      const card = CardModel(
        id: 'plain',
        name: 'Plain',
        cost: 1,
        playEffects: [GainGemsEffect(2)],
      );

      final lines = const GameCardWidget(card: card).rulesLines();
      expect(lines, ['Gain 2 gems']);
    });
  });

  group('GameCardWidget on-card text width gating', () {
    const card = CardModel(
      id: 'gemcard',
      name: 'Gem Card',
      cost: 2,
      playEffects: [GainGemsEffect(2)],
    );

    testWidgets('small board card suppresses on-card rules text',
        (tester) async {
      // Below GameCardWidget.rulesTextMinWidth — the cramped board size.
      await pumpCard(tester, card, width: 90);
      expect(find.textContaining('Gain 2 gems', findRichText: true),
          findsNothing);
    });

    testWidgets('large (zoom) card shows the full rules text', (tester) async {
      // At/above the threshold — the size the zoom modal renders at.
      await pumpCard(tester, card,
          width: GameCardWidget.rulesTextMinWidth + 20);
      expect(find.textContaining('Gain 2 gems', findRichText: true),
          findsOneWidget);
    });
  });
}
