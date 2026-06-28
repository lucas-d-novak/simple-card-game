import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/card_definitions.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';

void main() {
  group('Test fixture card definitions', () {
    test('allTestFixtureCards has 17 cards', () {
      expect(allTestFixtureCards, hasLength(17));
    });

    test('all card IDs are unique', () {
      final ids = allTestFixtureCards.map((c) => c.id).toSet();
      expect(ids, hasLength(allTestFixtureCards.length));
    });

    test('covers all four factions', () {
      final factions = allTestFixtureCards.map((c) => c.faction).toSet();
      expect(factions, contains(Faction.homodeus));
      expect(factions, contains(Faction.wraethe));
      expect(factions, contains(Faction.order));
      expect(factions, contains(Faction.undergrowth));
    });

    test('has at least one guard champion', () {
      final guardChampions = allTestFixtureCards
          .where((c) => c.cardType == CardType.champion && c.hasGuard);
      expect(guardChampions.length, greaterThanOrEqualTo(1));
    });

    test('has at least one non-guard champion', () {
      final nonGuardChampions = allTestFixtureCards
          .where((c) => c.cardType == CardType.champion && !c.hasGuard);
      expect(nonGuardChampions.length, greaterThanOrEqualTo(1));
    });

    test('has at least one mercenary', () {
      final mercenaries =
          allTestFixtureCards.where((c) => c.cardType == CardType.mercenary);
      expect(mercenaries.length, greaterThanOrEqualTo(1));
    });

    test('has at least one card with mastery threshold', () {
      final masteryCards =
          allTestFixtureCards.where((c) => c.masteryThreshold != null);
      expect(masteryCards.length, greaterThanOrEqualTo(1));
    });

    test('has at least one card with ally ability', () {
      final allyCards =
          allTestFixtureCards.where((c) => c.allyAbility.isNotEmpty);
      expect(allyCards.length, greaterThanOrEqualTo(1));
    });

    test('has at least one multi-effect card', () {
      final multiEffect =
          allTestFixtureCards.where((c) => c.playEffects.length > 1);
      expect(multiEffect.length, greaterThanOrEqualTo(1));
    });

    test('Universal Soldier has countsAsAllFactions', () {
      expect(universalSoldier.countsAsAllFactions, true);
      expect(universalSoldier.cardType, CardType.champion);
    });

    test('Shard Reactor has ChooseOneEffect', () {
      expect(shardReactor.playEffects, hasLength(1));
      expect(shardReactor.playEffects.first, isA<ChooseOneEffect>());
      final choose = shardReactor.playEffects.first as ChooseOneEffect;
      expect(choose.choices, hasLength(2));
    });

    test('Blood Ritualist has OpponentLosesHealthEffect as mastery bonus', () {
      expect(bloodRitualist.masteryThreshold, 10);
      expect(bloodRitualist.masteryBonus, hasLength(1));
      expect(
        bloodRitualist.masteryBonus.first,
        isA<OpponentLosesHealthEffect>(),
      );
    });

    test('Shield Bearer and Radiant Protector are guard champions', () {
      expect(shieldBearer.hasGuard, true);
      expect(shieldBearer.cardType, CardType.champion);
      expect(radiantProtector.hasGuard, true);
      expect(radiantProtector.cardType, CardType.champion);
      expect(radiantProtector.shield, greaterThan(shieldBearer.shield));
    });

    test('Chaos Imp and Natures Bounty are mercenaries', () {
      expect(chaosImp.cardType, CardType.mercenary);
      expect(naturesBounty.cardType, CardType.mercenary);
    });

    test('Neural Relay has draw as ally ability', () {
      expect(neuralRelay.allyAbility, hasLength(1));
      expect(neuralRelay.allyAbility.first, isA<DrawCardsEffect>());
    });
  });
}
