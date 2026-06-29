import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/faction.dart';

void main() {
  group('Original effects (unchanged)', () {
    test('GainMoneyEffect has correct amount and description', () {
      const effect = GainMoneyEffect(3);
      expect(effect.amount, 3);
      expect(effect.description, 'Gain 3 money');
    });

    test('DrawCardsEffect has correct count and description', () {
      const effect = DrawCardsEffect(2);
      expect(effect.count, 2);
      expect(effect.description, 'Draw 2 cards');
    });

    test('DrawCardsEffect uses singular for count of 1', () {
      const effect = DrawCardsEffect(1);
      expect(effect.description, 'Draw 1 card');
    });
  });

  group('Resource effects', () {
    test('GainGemsEffect has correct amount and description', () {
      const effect = GainGemsEffect(4);
      expect(effect.amount, 4);
      expect(effect.description, 'Gain 4 gems');
    });

    test('GainGemsEffect uses singular for 1 gem', () {
      const effect = GainGemsEffect(1);
      expect(effect.description, 'Gain 1 gem');
    });

    test('GainPowerEffect has correct amount and description', () {
      const effect = GainPowerEffect(5);
      expect(effect.amount, 5);
      expect(effect.description, 'Gain 5 power');
    });

    test('GainMasteryEffect has correct amount and description', () {
      const effect = GainMasteryEffect(2);
      expect(effect.amount, 2);
      expect(effect.description, 'Gain 2 mastery');
    });

    test('GainHealthEffect has correct amount and description', () {
      const effect = GainHealthEffect(10);
      expect(effect.amount, 10);
      expect(effect.description, 'Gain 10 health');
    });
  });

  group('Opponent interaction effects', () {
    test('OpponentLosesHealthEffect has correct amount and description', () {
      const effect = OpponentLosesHealthEffect(3);
      expect(effect.amount, 3);
      expect(effect.description, 'Target opponent loses 3 health');
    });
  });

  group('Banish and scrap effects', () {
    test('BanishCardEffect from hand has correct description', () {
      const effect = BanishCardEffect(BanishSource.hand);
      expect(effect.source, BanishSource.hand);
      expect(effect.description, 'Banish a card from your hand');
    });

    test('BanishCardEffect from discard has correct description', () {
      const effect = BanishCardEffect(BanishSource.discard);
      expect(effect.source, BanishSource.discard);
      expect(effect.description, 'Banish a card from your discard pile');
    });

    test('BanishCardEffect from hand or discard has correct description', () {
      const effect = BanishCardEffect(BanishSource.handOrDiscard);
      expect(effect.source, BanishSource.handOrDiscard);
      expect(
        effect.description,
        'Banish a card from your hand or discard pile',
      );
    });

    test('ScrapFromCenterRowEffect has correct description', () {
      const effect = ScrapFromCenterRowEffect();
      expect(effect.description, 'Scrap a card from the center row');
    });
  });

  group('Complex effects', () {
    test('ChooseOneEffect constructs with multiple choice branches', () {
      const effect = ChooseOneEffect([
        [GainGemsEffect(2)],
        [GainPowerEffect(2)],
      ]);

      expect(effect.choices, hasLength(2));
      expect(effect.choices[0], hasLength(1));
      expect(effect.choices[1], hasLength(1));
      expect(effect.description, 'Gain 2 gems OR Gain 2 power');
    });

    test('ChooseOneEffect handles multi-effect branches', () {
      const effect = ChooseOneEffect([
        [GainGemsEffect(1), GainMasteryEffect(1)],
        [GainPowerEffect(3)],
      ]);

      expect(effect.description, 'Gain 1 gem and Gain 1 mastery OR Gain 3 power');
    });

    test('ConditionalPowerEffect constructs with perChampionControlled', () {
      const effect =
          ConditionalPowerEffect(PowerCondition.perChampionControlled);

      expect(effect.condition, PowerCondition.perChampionControlled);
      expect(
        effect.description,
        'Gain 1 power for each champion you control',
      );
    });

    test('InfinityShardEffect constructs with scaling description', () {
      const effect = InfinityShardEffect();
      expect(effect.description, '+1 mastery, power scales with mastery');
    });

    test('ConditionalPowerEffect descriptions for new conditions', () {
      expect(
        const ConditionalPowerEffect(PowerCondition.perAllyPlayedThisTurn)
            .description,
        'Gain 1 power for each ally played this turn',
      );
      expect(
        const ConditionalPowerEffect(PowerCondition.perFactionPlayedThisTurn)
            .description,
        'Gain 1 power for each faction played this turn',
      );
      expect(
        const ConditionalPowerEffect(PowerCondition.perCardInDiscard)
            .description,
        'Gain 1 power for each card in your discard pile',
      );
    });
  });

  group('DestroyChampionEffect (Phase 1)', () {
    test('single-target default has all == false and description', () {
      const effect = DestroyChampionEffect();
      expect(effect.all, false);
      expect(effect.description, 'Destroy a target enemy champion');
    });

    test('all variant has all == true and description', () {
      const effect = DestroyChampionEffect(all: true);
      expect(effect.all, true);
      expect(effect.description, 'Destroy all enemy champions');
    });
  });

  group('ReturnFromDiscardEffect (Phase 1)', () {
    test('any filter is the default with description', () {
      const effect = ReturnFromDiscardEffect();
      expect(effect.filter, ReturnFilter.any);
      expect(effect.faction, isNull);
      expect(
        effect.description,
        'Return a card from your discard pile to your hand',
      );
    });

    test('champion filter description', () {
      const effect = ReturnFromDiscardEffect(filter: ReturnFilter.champion);
      expect(
        effect.description,
        'Return a champion from your discard pile to your hand',
      );
    });

    test('mercenary filter description', () {
      const effect = ReturnFromDiscardEffect(filter: ReturnFilter.mercenary);
      expect(
        effect.description,
        'Return a mercenary from your discard pile to your hand',
      );
    });

    test('faction filter carries faction and description', () {
      const effect = ReturnFromDiscardEffect(
        filter: ReturnFilter.faction,
        faction: Faction.order,
      );
      expect(effect.faction, Faction.order);
      expect(
        effect.description,
        'Return a order card from your discard pile to your hand',
      );
    });
  });

  group('ScalingResourceEffect (Phase 2 wave 0)', () {
    test('carries resource, condition, perN, faction', () {
      const effect = ScalingResourceEffect(
        resource: ScalingResource.gems,
        condition: ScalingCondition.perFactionCardInDiscard,
        perN: 2,
        faction: Faction.wraethe,
      );
      expect(effect.resource, ScalingResource.gems);
      expect(effect.condition, ScalingCondition.perFactionCardInDiscard);
      expect(effect.perN, 2);
      expect(effect.faction, Faction.wraethe);
      expect(effect.description, isNotEmpty);
    });

    test('defaults perN to 1 and faction to null', () {
      const effect = ScalingResourceEffect(
        resource: ScalingResource.power,
        condition: ScalingCondition.perCardInDiscard,
      );
      expect(effect.perN, 1);
      expect(effect.faction, isNull);
    });
  });

  group('ConditionalEffect + GameCondition (Phase 2 wave 0)', () {
    test('wrapper carries condition and then list', () {
      const effect = ConditionalEffect(
        condition: GameCondition(
          kind: GameConditionKind.masteryAtLeast,
          threshold: 20,
        ),
        then: [GainPowerEffect(5)],
      );
      expect(effect.condition.kind, GameConditionKind.masteryAtLeast);
      expect(effect.condition.threshold, 20);
      expect(effect.then, hasLength(1));
      expect(effect.description, isNotEmpty);
    });

    test('GameCondition defaults: threshold 1, empty factions, null optionals',
        () {
      const c = GameCondition(kind: GameConditionKind.championsControlled);
      expect(c.threshold, 1);
      expect(c.factions, isEmpty);
      expect(c.faction, isNull);
      expect(c.parity, isNull);
      expect(c.cardType, isNull);
      expect(c.maxCost, isNull);
      expect(c.character, isNull);
    });

    test('every GameConditionKind yields a non-empty description', () {
      for (final kind in GameConditionKind.values) {
        expect(GameCondition(kind: kind).description, isNotEmpty);
      }
    });
  });

  group('All effects are CardEffect subtypes', () {
    test('every effect is a CardEffect with a description', () {
      const List<CardEffect> effects = [
        GainMoneyEffect(1),
        GainGemsEffect(1),
        GainPowerEffect(1),
        GainMasteryEffect(1),
        GainHealthEffect(1),
        DrawCardsEffect(1),
        OpponentLosesHealthEffect(1),
        BanishCardEffect(BanishSource.handOrDiscard),
        ScrapFromCenterRowEffect(),
        ChooseOneEffect([[GainGemsEffect(1)]]),
        ConditionalPowerEffect(PowerCondition.perChampionControlled),
        InfinityShardEffect(),
      ];

      expect(effects, hasLength(12));
      for (final effect in effects) {
        expect(effect, isA<CardEffect>());
        expect(effect.description, isNotEmpty);
      }
    });
  });
}
