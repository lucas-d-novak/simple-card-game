import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/effect_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_type.dart';
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

  group('effect_codec — scalingResource (Phase 2 wave 0)', () {
    test('decodes power + original condition with default perN/faction', () {
      final e = decodeEffect({
        'type': 'scalingResource',
        'resource': 'power',
        'condition': 'perChampionControlled',
      }) as ScalingResourceEffect;
      expect(e.resource, ScalingResource.power);
      expect(e.condition, ScalingCondition.perChampionControlled);
      expect(e.perN, 1);
      expect(e.faction, isNull);
    });

    test('decodes faction-filtered condition with perN + faction', () {
      final e = decodeEffect({
        'type': 'scalingResource',
        'resource': 'gems',
        'condition': 'perFactionCardInDiscard',
        'perN': 2,
        'faction': 'wraethe',
      }) as ScalingResourceEffect;
      expect(e.resource, ScalingResource.gems);
      expect(e.condition, ScalingCondition.perFactionCardInDiscard);
      expect(e.perN, 2);
      expect(e.faction, Faction.wraethe);
    });

    test('round-trips every (resource, condition) combo', () {
      for (final resource in ScalingResource.values) {
        for (final condition in ScalingCondition.values) {
          final effect = ScalingResourceEffect(
            resource: resource,
            condition: condition,
            perN: 3,
            faction: Faction.order,
          );
          final decoded =
              decodeEffect(encodeEffect(effect)) as ScalingResourceEffect;
          expect(decoded.resource, resource);
          expect(decoded.condition, condition);
          expect(decoded.perN, 3);
          expect(decoded.faction, Faction.order);
        }
      }
    });

    test('encode omits perN when 1 and faction when null', () {
      final encoded = encodeEffect(const ScalingResourceEffect(
        resource: ScalingResource.power,
        condition: ScalingCondition.perCardInDiscard,
      ));
      expect(encoded.containsKey('perN'), false);
      expect(encoded.containsKey('faction'), false);
    });

    test('unknown resource throws FormatException', () {
      expect(
        () => decodeEffect({
          'type': 'scalingResource',
          'resource': 'luck',
          'condition': 'perCardInDiscard',
        }),
        throwsFormatException,
      );
    });

    test('unknown scaling condition throws FormatException', () {
      expect(
        () => decodeEffect({
          'type': 'scalingResource',
          'resource': 'power',
          'condition': 'perBananaEaten',
        }),
        throwsFormatException,
      );
    });
  });

  group('effect_codec — conditional + GameCondition (Phase 2 wave 0)', () {
    test('decodes a minimal condition (kind only) + then effects', () {
      final e = decodeEffect({
        'type': 'conditional',
        'condition': {'kind': 'masteryAtLeast', 'threshold': 20},
        'then': [
          {'type': 'gainPower', 'amount': 5},
        ],
      }) as ConditionalEffect;
      expect(e.condition.kind, GameConditionKind.masteryAtLeast);
      expect(e.condition.threshold, 20);
      expect(e.then, hasLength(1));
      expect(e.then.first, isA<GainPowerEffect>());
    });

    test('round-trips a fully-populated condition', () {
      const effect = ConditionalEffect(
        condition: GameCondition(
          kind: GameConditionKind.filteredCardsPlayed,
          threshold: 2,
          faction: Faction.order,
          factions: [Faction.order, Faction.wraethe],
          parity: GemParity.odd,
          cardType: CardType.champion,
          maxCost: 3,
          character: Character.decima,
        ),
        then: [GainGemsEffect(1), GainMasteryEffect(2)],
      );
      final decoded =
          decodeEffect(encodeEffect(effect)) as ConditionalEffect;
      final c = decoded.condition;
      expect(c.kind, GameConditionKind.filteredCardsPlayed);
      expect(c.threshold, 2);
      expect(c.faction, Faction.order);
      expect(c.factions, [Faction.order, Faction.wraethe]);
      expect(c.parity, GemParity.odd);
      expect(c.cardType, CardType.champion);
      expect(c.maxCost, 3);
      expect(c.character, Character.decima);
      expect(decoded.then, hasLength(2));
    });

    test('round-trips every GameConditionKind (kind-only)', () {
      for (final kind in GameConditionKind.values) {
        final effect = ConditionalEffect(
          condition: GameCondition(kind: kind),
          then: const [GainPowerEffect(1)],
        );
        final decoded =
            decodeEffect(encodeEffect(effect)) as ConditionalEffect;
        expect(decoded.condition.kind, kind);
        expect(decoded.condition.threshold, 1);
      }
    });

    test('default threshold (omitted) decodes to 1', () {
      final e = decodeEffect({
        'type': 'conditional',
        'condition': {'kind': 'championsControlled'},
        'then': [
          {'type': 'gainPower', 'amount': 1},
        ],
      }) as ConditionalEffect;
      expect(e.condition.threshold, 1);
    });

    test('missing "then" array throws FormatException', () {
      expect(
        () => decodeEffect({
          'type': 'conditional',
          'condition': {'kind': 'championsControlled'},
        }),
        throwsFormatException,
      );
    });

    test('non-object condition throws FormatException', () {
      expect(
        () => decodeEffect({
          'type': 'conditional',
          'condition': 'championsControlled',
          'then': <dynamic>[],
        }),
        throwsFormatException,
      );
    });

    test('present-but-non-int maxCost throws FormatException', () {
      expect(
        () => decodeEffect({
          'type': 'conditional',
          'condition': {'kind': 'filteredCardsPlayed', 'maxCost': '3'},
          'then': <dynamic>[],
        }),
        throwsFormatException,
      );
    });

    test('unknown condition kind throws FormatException', () {
      expect(
        () => decodeEffect({
          'type': 'conditional',
          'condition': {'kind': 'youAreWinning'},
          'then': <dynamic>[],
        }),
        throwsFormatException,
      );
    });

    test('unknown parity throws FormatException', () {
      expect(
        () => decodeEffect({
          'type': 'conditional',
          'condition': {'kind': 'gemParityCardsPlayed', 'parity': 'prime'},
          'then': <dynamic>[],
        }),
        throwsFormatException,
      );
    });

    test('unknown character throws FormatException', () {
      expect(
        () => decodeEffect({
          'type': 'conditional',
          'condition': {'kind': 'isCharacter', 'character': 'nobody'},
          'then': <dynamic>[],
        }),
        throwsFormatException,
      );
    });
  });

  group('effect_codec — conditionalPower still decodes (back-compat)', () {
    test('conditionalPower JSON decodes to ConditionalPowerEffect, not scaling',
        () {
      final e = decodeEffect({
        'type': 'conditionalPower',
        'condition': 'perChampionControlled',
      });
      expect(e, isA<ConditionalPowerEffect>());
      expect(e, isNot(isA<ScalingResourceEffect>()));
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

  group('effect_codec — ActivatedAbility mastery tier (Wave 1)', () {
    test('decodes mastery replace fields', () {
      final ability = decodeActivatedAbility({
        'effects': [
          {'type': 'gainPower', 'amount': 2},
        ],
        'masteryThreshold': 15,
        'masteryBonusEffects': [
          {'type': 'gainPower', 'amount': 5},
        ],
        'masteryReplaces': true,
      })!;
      expect(ability.masteryThreshold, 15);
      expect(ability.masteryBonusEffects, hasLength(1));
      expect(ability.masteryBonusEffects.first, isA<GainPowerEffect>());
      expect(ability.replaces, true);
    });

    test('absent mastery fields default to null/empty/false', () {
      final ability = decodeActivatedAbility({
        'effects': [
          {'type': 'gainPower', 'amount': 2},
        ],
      })!;
      expect(ability.masteryThreshold, isNull);
      expect(ability.masteryBonusEffects, isEmpty);
      expect(ability.replaces, false);
    });

    test('present-but-empty masteryBonusEffects throws FormatException', () {
      expect(
        () => decodeActivatedAbility({
          'effects': [
            {'type': 'gainPower', 'amount': 2},
          ],
          'masteryBonusEffects': <dynamic>[],
        }),
        throwsFormatException,
      );
    });

    test('non-integer masteryThreshold throws FormatException', () {
      expect(
        () => decodeActivatedAbility({
          'effects': [
            {'type': 'gainPower', 'amount': 2},
          ],
          'masteryThreshold': 'fifteen',
        }),
        throwsFormatException,
      );
    });

    test('round-trips a mastery-replace ability', () {
      const ability = ActivatedAbility(
        effects: [GainPowerEffect(2), GainMasteryEffect(2)],
        masteryThreshold: 15,
        masteryBonusEffects: [GainPowerEffect(5), GainMasteryEffect(5)],
        replaces: true,
      );
      final encoded = encodeActivatedAbility(ability);
      expect(encoded['masteryThreshold'], 15);
      expect(encoded['masteryReplaces'], true);
      expect((encoded['masteryBonusEffects'] as List), hasLength(2));

      final decoded = decodeActivatedAbility(encoded)!;
      expect(decoded.masteryThreshold, 15);
      expect(decoded.replaces, true);
      expect(decoded.masteryBonusEffects, hasLength(2));
    });

    test('round-trips a plain ability (omits all mastery keys)', () {
      const ability = ActivatedAbility(effects: [GainPowerEffect(2)]);
      final encoded = encodeActivatedAbility(ability);
      expect(encoded.containsKey('masteryThreshold'), false);
      expect(encoded.containsKey('masteryBonusEffects'), false);
      expect(encoded.containsKey('masteryReplaces'), false);
    });
  });

  group('effect_codec — Wave 2 leaf effects', () {
    test('allPlayersLoseHealth decodes and round-trips', () {
      final e = decodeEffect({'type': 'allPlayersLoseHealth', 'amount': 4});
      expect(e, isA<AllPlayersLoseHealthEffect>());
      expect((e as AllPlayersLoseHealthEffect).amount, 4);

      final encoded = encodeEffect(const AllPlayersLoseHealthEffect(4));
      expect(encoded, {'type': 'allPlayersLoseHealth', 'amount': 4});
      final decoded = decodeEffect(encoded) as AllPlayersLoseHealthEffect;
      expect(decoded.amount, 4);
    });

    test('allPlayersLoseHealth without amount throws FormatException', () {
      expect(
        () => decodeEffect({'type': 'allPlayersLoseHealth'}),
        throwsFormatException,
      );
    });

    test('selfBanish decodes and round-trips', () {
      final e = decodeEffect({'type': 'selfBanish'});
      expect(e, isA<SelfBanishEffect>());
      expect(encodeEffect(const SelfBanishEffect()), {'type': 'selfBanish'});
      expect(decodeEffect(encodeEffect(const SelfBanishEffect())),
          isA<SelfBanishEffect>());
    });

    test('resetChampion decodes and round-trips', () {
      final e = decodeEffect({'type': 'resetChampion'});
      expect(e, isA<ResetChampionEffect>());
      expect(
          encodeEffect(const ResetChampionEffect()), {'type': 'resetChampion'});
      expect(decodeEffect(encodeEffect(const ResetChampionEffect())),
          isA<ResetChampionEffect>());
    });

    test('unblockedDamageAtLeast game condition round-trips', () {
      const cond = ConditionalEffect(
        condition: GameCondition(
          kind: GameConditionKind.unblockedDamageAtLeast,
          threshold: 5,
        ),
        then: [GainPowerEffect(3)],
      );
      final encoded = encodeEffect(cond);
      final decoded = decodeEffect(encoded) as ConditionalEffect;
      expect(decoded.condition.kind, GameConditionKind.unblockedDamageAtLeast);
      expect(decoded.condition.threshold, 5);
    });

    test('unknown game condition kind throws FormatException', () {
      expect(
        () => decodeEffect({
          'type': 'conditional',
          'condition': {'kind': 'bogusKind'},
          'then': <Map<String, dynamic>>[],
        }),
        throwsFormatException,
      );
    });

    test('unknown effect type still throws FormatException', () {
      expect(
        () => decodeEffect({'type': 'totallyMadeUpEffect'}),
        throwsFormatException,
      );
    });
  });

  group('effect_codec — Wave 3 deferred-selection effects', () {
    group('recruitFromCenter', () {
      test('decodes defaults (no flags)', () {
        final e = decodeEffect({'type': 'recruitFromCenter'})
            as RecruitFromCenterEffect;
        expect(e.maxCost, null);
        expect(e.free, false);
        expect(e.toHand, false);
        expect(e.toTopOfDeck, false);
      });

      test('round-trips a fully-populated recruit', () {
        const original = RecruitFromCenterEffect(
          maxCost: 4,
          free: true,
          toTopOfDeck: true,
        );
        final encoded = encodeEffect(original);
        expect(encoded, {
          'type': 'recruitFromCenter',
          'maxCost': 4,
          'free': true,
          'toTopOfDeck': true,
        });
        final decoded = decodeEffect(encoded) as RecruitFromCenterEffect;
        expect(decoded.maxCost, 4);
        expect(decoded.free, true);
        expect(decoded.toTopOfDeck, true);
        expect(decoded.toHand, false);
      });

      test('round-trips toHand', () {
        final encoded =
            encodeEffect(const RecruitFromCenterEffect(toHand: true));
        final decoded = decodeEffect(encoded) as RecruitFromCenterEffect;
        expect(decoded.toHand, true);
      });

      test('non-int maxCost throws FormatException', () {
        expect(
          () => decodeEffect(
              {'type': 'recruitFromCenter', 'maxCost': 'lots'}),
          throwsFormatException,
        );
      });
    });

    group('fastPlayFromCenter', () {
      test('decodes defaults', () {
        final e = decodeEffect({'type': 'fastPlayFromCenter'})
            as FastPlayFromCenterEffect;
        expect(e.maxCost, null);
        expect(e.alliesOnly, false);
      });

      test('round-trips maxCost + alliesOnly', () {
        const original =
            FastPlayFromCenterEffect(maxCost: 3, alliesOnly: true);
        final encoded = encodeEffect(original);
        expect(encoded, {
          'type': 'fastPlayFromCenter',
          'maxCost': 3,
          'alliesOnly': true,
        });
        final decoded = decodeEffect(encoded) as FastPlayFromCenterEffect;
        expect(decoded.maxCost, 3);
        expect(decoded.alliesOnly, true);
      });

      test('non-int maxCost throws FormatException', () {
        expect(
          () => decodeEffect(
              {'type': 'fastPlayFromCenter', 'maxCost': 'x'}),
          throwsFormatException,
        );
      });
    });

    group('scry', () {
      test('decodes defaults (count 1, drawOrDiscard)', () {
        final e = decodeEffect({'type': 'scry'}) as ScryEffect;
        expect(e.count, 1);
        expect(e.disposition, ScryDisposition.drawOrDiscard);
      });

      test('default round-trips to a bare object', () {
        final encoded = encodeEffect(const ScryEffect());
        expect(encoded, {'type': 'scry'});
      });

      test('round-trips every disposition + count', () {
        for (final d in ScryDisposition.values) {
          final original = ScryEffect(count: 2, disposition: d);
          final decoded =
              decodeEffect(encodeEffect(original)) as ScryEffect;
          expect(decoded.count, 2);
          expect(decoded.disposition, d);
        }
      });

      test('unknown disposition throws FormatException', () {
        expect(
          () => decodeEffect({'type': 'scry', 'disposition': 'nope'}),
          throwsFormatException,
        );
      });
    });

    group('treatFactionAs (Phase 2 wave 4)', () {
      test('decodes one-directional alias (no bidirectional field)', () {
        final e = decodeEffect({
          'type': 'treatFactionAs',
          'from': 'wraethe',
          'to': 'undergrowth',
        }) as TreatFactionAsEffect;
        expect(e.from, Faction.wraethe);
        expect(e.to, Faction.undergrowth);
        expect(e.bidirectional, false);
      });

      test('decodes bidirectional alias', () {
        final e = decodeEffect({
          'type': 'treatFactionAs',
          'from': 'wraethe',
          'to': 'undergrowth',
          'bidirectional': true,
        }) as TreatFactionAsEffect;
        expect(e.bidirectional, true);
      });

      test('round-trips one-directional (omits bidirectional)', () {
        const original = TreatFactionAsEffect(
          from: Faction.homodeus,
          to: Faction.order,
        );
        final encoded = encodeEffect(original);
        expect(encoded.containsKey('bidirectional'), false);
        final decoded = decodeEffect(encoded) as TreatFactionAsEffect;
        expect(decoded.from, Faction.homodeus);
        expect(decoded.to, Faction.order);
        expect(decoded.bidirectional, false);
      });

      test('round-trips bidirectional', () {
        const original = TreatFactionAsEffect(
          from: Faction.wraethe,
          to: Faction.undergrowth,
          bidirectional: true,
        );
        final decoded =
            decodeEffect(encodeEffect(original)) as TreatFactionAsEffect;
        expect(decoded.from, Faction.wraethe);
        expect(decoded.to, Faction.undergrowth);
        expect(decoded.bidirectional, true);
      });

      test('missing "from" throws FormatException', () {
        expect(
          () => decodeEffect({'type': 'treatFactionAs', 'to': 'order'}),
          throwsFormatException,
        );
      });

      test('unknown faction value throws FormatException', () {
        expect(
          () => decodeEffect(
              {'type': 'treatFactionAs', 'from': 'bogus', 'to': 'order'}),
          throwsFormatException,
        );
      });
    });

    group('ignoreShieldThisTurn (Phase 2 wave 4)', () {
      test('decodes', () {
        expect(
          decodeEffect({'type': 'ignoreShieldThisTurn'}),
          isA<IgnoreShieldThisTurnEffect>(),
        );
      });

      test('round-trips', () {
        const original = IgnoreShieldThisTurnEffect();
        final decoded = decodeEffect(encodeEffect(original));
        expect(decoded, isA<IgnoreShieldThisTurnEffect>());
      });
    });
  });

  group('effect_codec — Phase 2 wave 5a effects', () {
    group('addStaticModifier', () {
      test('round-trips every kind with filters', () {
        const mods = [
          StaticModifier(kind: StaticModifierKind.shieldBuff, amount: 2),
          StaticModifier(
            kind: StaticModifierKind.cardCostReduction,
            amount: 3,
            cardType: CardType.champion,
          ),
          StaticModifier(kind: StaticModifierKind.cannotBeAttacked),
          StaticModifier(
            kind: StaticModifierKind.recruitToTopOfDeck,
            faction: Faction.homodeus,
            cardType: CardType.champion,
          ),
        ];
        for (final m in mods) {
          final decoded =
              decodeEffect(encodeEffect(AddStaticModifierEffect(m)))
                  as AddStaticModifierEffect;
          expect(decoded.modifier.kind, m.kind);
          expect(decoded.modifier.amount, m.amount);
          expect(decoded.modifier.faction, m.faction);
          expect(decoded.modifier.cardType, m.cardType);
        }
      });

      test('unknown kind throws FormatException', () {
        expect(
          () => decodeEffect({'type': 'addStaticModifier', 'kind': 'bogus'}),
          throwsFormatException,
        );
      });
    });

    group('opponentDraws / opponentDiscards', () {
      test('round-trips with and without count', () {
        for (final c in [1, 2]) {
          final draws = decodeEffect(encodeEffect(OpponentDrawsEffect(count: c)))
              as OpponentDrawsEffect;
          expect(draws.count, c);
          final discards =
              decodeEffect(encodeEffect(OpponentDiscardsEffect(count: c)))
                  as OpponentDiscardsEffect;
          expect(discards.count, c);
        }
      });

      test('non-int count throws FormatException', () {
        expect(
          () => decodeEffect({'type': 'opponentDraws', 'count': 'x'}),
          throwsFormatException,
        );
      });
    });

    group('copyPlayedCard', () {
      test('round-trips both filters', () {
        for (final f in CopyFilter.values) {
          final decoded =
              decodeEffect(encodeEffect(CopyPlayedCardEffect(filter: f)))
                  as CopyPlayedCardEffect;
          expect(decoded.filter, f);
        }
      });

      test('unknown filter throws FormatException', () {
        expect(
          () => decodeEffect({'type': 'copyPlayedCard', 'filter': 'bogus'}),
          throwsFormatException,
        );
      });
    });

    group('centerDeckScry', () {
      test('round-trips both dispositions', () {
        for (final d in CenterScryDisposition.values) {
          final decoded =
              decodeEffect(encodeEffect(CenterDeckScryEffect(disposition: d)))
                  as CenterDeckScryEffect;
          expect(decoded.disposition, d);
        }
      });

      test('unknown disposition throws FormatException', () {
        expect(
          () =>
              decodeEffect({'type': 'centerDeckScry', 'disposition': 'bogus'}),
          throwsFormatException,
        );
      });
    });

    group('chooseOne pick (Phase 3 wave 5)', () {
      test('decodes default pick == 1 when absent', () {
        final e = decodeEffect({
          'type': 'chooseOne',
          'choices': [
            [
              {'type': 'gainGems', 'amount': 2}
            ],
            [
              {'type': 'gainPower', 'amount': 2}
            ],
          ],
        }) as ChooseOneEffect;
        expect(e.pick, 1);
      });

      test('round-trips pick:2', () {
        const original = ChooseOneEffect([
          [GainGemsEffect(2)],
          [GainPowerEffect(2)],
          [GainMasteryEffect(1)],
        ], pick: 2);
        final json = encodeEffect(original);
        expect(json['pick'], 2);
        final decoded = decodeEffect(json) as ChooseOneEffect;
        expect(decoded.pick, 2);
        expect(decoded.choices, hasLength(3));
      });

      test('omits pick on encode when it is the default 1', () {
        const original = ChooseOneEffect([
          [GainGemsEffect(2)],
          [GainPowerEffect(2)],
        ]);
        final json = encodeEffect(original);
        expect(json.containsKey('pick'), false);
      });
    });
  });
}
