import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/effect_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/faction.dart';

void main() {
  group('effect_codec — Phase 1 effects', () {
    group('destroyChampion', () {
      test('decodes single-target (no all field) to all == false', () {
        final effect = decodeEffect({'type': 'destroyChampion'});
        expect(effect, isA<DestroyChampionEffect>());
        expect((effect as DestroyChampionEffect).all, false);
      });

      test('decodes all == true', () {
        final effect =
            decodeEffect({'type': 'destroyChampion', 'all': true});
        expect((effect as DestroyChampionEffect).all, true);
      });

      test('encodes round-trip for both variants', () {
        for (final all in [false, true]) {
          final encoded = encodeEffect(DestroyChampionEffect(all: all));
          expect(encoded, {'type': 'destroyChampion', 'all': all});
          final decoded = decodeEffect(encoded) as DestroyChampionEffect;
          expect(decoded.all, all);
        }
      });
    });

    group('returnFromDiscard', () {
      test('decodes default filter (missing) to any', () {
        final effect = decodeEffect({'type': 'returnFromDiscard'});
        expect(effect, isA<ReturnFromDiscardEffect>());
        final r = effect as ReturnFromDiscardEffect;
        expect(r.filter, ReturnFilter.any);
        expect(r.faction, isNull);
      });

      test('decodes champion / mercenary filters', () {
        expect(
          (decodeEffect({'type': 'returnFromDiscard', 'filter': 'champion'})
                  as ReturnFromDiscardEffect)
              .filter,
          ReturnFilter.champion,
        );
        expect(
          (decodeEffect({'type': 'returnFromDiscard', 'filter': 'mercenary'})
                  as ReturnFromDiscardEffect)
              .filter,
          ReturnFilter.mercenary,
        );
      });

      test('decodes faction filter with faction param', () {
        final r = decodeEffect({
          'type': 'returnFromDiscard',
          'filter': 'faction',
          'faction': 'wraethe',
        }) as ReturnFromDiscardEffect;
        expect(r.filter, ReturnFilter.faction);
        expect(r.faction, Faction.wraethe);
      });

      test('non-faction filter ignores faction param (null)', () {
        final r = decodeEffect({
          'type': 'returnFromDiscard',
          'filter': 'champion',
          'faction': 'order',
        }) as ReturnFromDiscardEffect;
        expect(r.faction, isNull);
      });

      test('encode round-trips faction filter (faction key present)', () {
        const effect = ReturnFromDiscardEffect(
          filter: ReturnFilter.faction,
          faction: Faction.order,
        );
        final encoded = encodeEffect(effect);
        expect(encoded, {
          'type': 'returnFromDiscard',
          'filter': 'faction',
          'faction': 'order',
        });
        final decoded = decodeEffect(encoded) as ReturnFromDiscardEffect;
        expect(decoded.filter, ReturnFilter.faction);
        expect(decoded.faction, Faction.order);
      });

      test('encode omits faction key when null', () {
        final encoded =
            encodeEffect(const ReturnFromDiscardEffect(filter: ReturnFilter.any));
        expect(encoded.containsKey('faction'), false);
      });

      test('unknown filter throws FormatException', () {
        expect(
          () => decodeEffect({'type': 'returnFromDiscard', 'filter': 'bogus'}),
          throwsFormatException,
        );
      });
    });

    group('conditionalPower new conditions', () {
      test('decodes all new power conditions', () {
        final pairs = {
          'perAllyPlayedThisTurn': PowerCondition.perAllyPlayedThisTurn,
          'perFactionPlayedThisTurn': PowerCondition.perFactionPlayedThisTurn,
          'perCardInDiscard': PowerCondition.perCardInDiscard,
        };
        pairs.forEach((raw, expected) {
          final effect = decodeEffect(
                  {'type': 'conditionalPower', 'condition': raw})
              as ConditionalPowerEffect;
          expect(effect.condition, expected);
        });
      });

      test('round-trips every power condition', () {
        for (final condition in PowerCondition.values) {
          final encoded = encodeEffect(ConditionalPowerEffect(condition));
          final decoded = decodeEffect(encoded) as ConditionalPowerEffect;
          expect(decoded.condition, condition);
        }
      });
    });
  });

  group('effect_codec — activatedAbility (Exhaust)', () {
    test('decodes null to null', () {
      expect(decodeActivatedAbility(null), isNull);
    });

    test('decodes Exhaust-only ability (no cost) with free cost', () {
      final ability = decodeActivatedAbility({
        'effects': [
          {'type': 'gainPower', 'amount': 3},
        ],
      })!;
      expect(ability.effects, hasLength(1));
      expect(ability.effects.first, isA<GainPowerEffect>());
      expect(ability.cost.isFree, true);
    });

    test('decodes ability with a multi-field cost', () {
      final ability = decodeActivatedAbility({
        'effects': [
          {'type': 'gainMastery', 'amount': 1},
        ],
        'cost': {'gems': 2, 'mastery': 1, 'health': 3},
      })!;
      expect(ability.cost.gems, 2);
      expect(ability.cost.mastery, 1);
      expect(ability.cost.health, 3);
    });

    test('missing cost keys default to 0', () {
      final ability = decodeActivatedAbility({
        'effects': [
          {'type': 'gainGems', 'amount': 1},
        ],
        'cost': {'gems': 2},
      })!;
      expect(ability.cost.gems, 2);
      expect(ability.cost.mastery, 0);
      expect(ability.cost.health, 0);
    });

    test('empty effects array throws FormatException', () {
      expect(
        () => decodeActivatedAbility({'effects': <dynamic>[]}),
        throwsFormatException,
      );
    });

    test('non-object activatedAbility throws FormatException', () {
      expect(
        () => decodeActivatedAbility('nope'),
        throwsFormatException,
      );
    });

    test('non-integer cost value throws FormatException', () {
      expect(
        () => decodeActivatedAbility({
          'effects': [
            {'type': 'gainGems', 'amount': 1},
          ],
          'cost': {'gems': 'two'},
        }),
        throwsFormatException,
      );
    });

    test('round-trips an Exhaust-only ability (omits cost)', () {
      const ability =
          ActivatedAbility(effects: [GainPowerEffect(2), DrawCardsEffect(1)]);
      final encoded = encodeActivatedAbility(ability);
      expect(encoded.containsKey('cost'), false);

      final decoded = decodeActivatedAbility(encoded)!;
      expect(decoded.effects, hasLength(2));
      expect(decoded.effects[0], isA<GainPowerEffect>());
      expect(decoded.effects[1], isA<DrawCardsEffect>());
      expect(decoded.cost.isFree, true);
    });

    test('round-trips an ability with a cost (omits zero sub-fields)', () {
      const ability = ActivatedAbility(
        effects: [GainGemsEffect(2)],
        cost: ActivationCost(mastery: 1),
      );
      final encoded = encodeActivatedAbility(ability);
      expect(encoded['cost'], {'mastery': 1});

      final decoded = decodeActivatedAbility(encoded)!;
      expect(decoded.cost.mastery, 1);
      expect(decoded.cost.gems, 0);
      expect(decoded.cost.health, 0);
    });
  });
}
