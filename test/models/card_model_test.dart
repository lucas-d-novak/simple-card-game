import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';

void main() {
  group('CardModel backward compatibility', () {
    test('existing card definitions still work with default new fields', () {
      const card = CardModel(
        id: 'c1',
        name: 'Coin +1',
        cost: 1,
        playEffects: [GainMoneyEffect(1)],
      );

      expect(card.id, 'c1');
      expect(card.name, 'Coin +1');
      expect(card.cost, 1);
      expect(card.playEffects, hasLength(1));
      expect(card.faction, Faction.none);
      expect(card.cardType, CardType.regular);
      expect(card.shield, 0);
      expect(card.hasGuard, false);
      expect(card.allyAbility, isEmpty);
      expect(card.masteryThreshold, isNull);
      expect(card.masteryBonus, isEmpty);
      expect(card.countsAsAllFactions, false);
    });
  });

  group('CardModel Shards of Infinity fields', () {
    test('faction card with ally ability constructs correctly', () {
      const card = CardModel(
        id: 'h1',
        name: 'Reactor Monk',
        cost: 3,
        playEffects: [GainGemsEffect(2)],
        faction: Faction.homodeus,
        allyAbility: [GainMasteryEffect(1)],
      );

      expect(card.faction, Faction.homodeus);
      expect(card.allyAbility, hasLength(1));
      expect(card.allyAbility.first, isA<GainMasteryEffect>());
    });

    test('champion with guard and shield constructs correctly', () {
      const card = CardModel(
        id: 'o1',
        name: 'Sentinel',
        cost: 4,
        playEffects: [GainPowerEffect(2)],
        faction: Faction.order,
        cardType: CardType.champion,
        shield: 5,
        hasGuard: true,
      );

      expect(card.cardType, CardType.champion);
      expect(card.shield, 5);
      expect(card.hasGuard, true);
      expect(card.faction, Faction.order);
    });

    test('card with mastery threshold and bonus constructs correctly', () {
      const card = CardModel(
        id: 'w1',
        name: 'Blood Ritualist',
        cost: 3,
        playEffects: [GainPowerEffect(2)],
        faction: Faction.wraethe,
        masteryThreshold: 10,
        masteryBonus: [OpponentLosesHealthEffect(3)],
      );

      expect(card.masteryThreshold, 10);
      expect(card.masteryBonus, hasLength(1));
      expect(card.masteryBonus.first, isA<OpponentLosesHealthEffect>());
    });

    test('mercenary card constructs correctly', () {
      const card = CardModel(
        id: 'n1',
        name: 'Mercenary Fighter',
        cost: 2,
        playEffects: [GainPowerEffect(3)],
        cardType: CardType.mercenary,
      );

      expect(card.cardType, CardType.mercenary);
      expect(card.faction, Faction.none);
    });

    test('countsAsAllFactions card constructs correctly', () {
      const card = CardModel(
        id: 'u1',
        name: 'Universal Soldier',
        cost: 5,
        playEffects: [GainPowerEffect(2)],
        cardType: CardType.champion,
        countsAsAllFactions: true,
      );

      expect(card.countsAsAllFactions, true);
      expect(card.faction, Faction.none);
    });

    test('card with multiple play effects and ally ability', () {
      const card = CardModel(
        id: 'g1',
        name: 'Forest Shaman',
        cost: 4,
        playEffects: [GainGemsEffect(1), GainMasteryEffect(1)],
        faction: Faction.undergrowth,
        allyAbility: [DrawCardsEffect(1)],
      );

      expect(card.playEffects, hasLength(2));
      expect(card.allyAbility, hasLength(1));
      expect(card.faction, Faction.undergrowth);
    });

    test('card with banish effect constructs correctly', () {
      const card = CardModel(
        id: 'b1',
        name: 'Purifier',
        cost: 2,
        playEffects: [
          GainGemsEffect(1),
          BanishCardEffect(BanishSource.handOrDiscard),
        ],
        faction: Faction.homodeus,
      );

      expect(card.playEffects, hasLength(2));
      expect(card.playEffects[1], isA<BanishCardEffect>());
    });

    test('card with choose-one effect constructs correctly', () {
      const card = CardModel(
        id: 'sr1',
        name: 'Shard Reactor',
        cost: 3,
        playEffects: [
          ChooseOneEffect([
            [GainGemsEffect(2)],
            [GainPowerEffect(2)],
          ]),
        ],
      );

      expect(card.playEffects, hasLength(1));
      expect(card.playEffects.first, isA<ChooseOneEffect>());
    });

    test('infinity shard card constructs correctly', () {
      const card = CardModel(
        id: 'is1',
        name: 'Infinity Shard',
        cost: 0,
        playEffects: [InfinityShardEffect()],
      );

      expect(card.playEffects.first, isA<InfinityShardEffect>());
      expect(card.cost, 0);
    });
  });
}
