import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/data/database/effect_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/faction.dart';

/// Codec round-trips for the 2026-07-01 new effect types + condition kind, and
/// assertions that the wired cards in cards.json decode to the intended shapes.

final CardDatabase _db = CardDatabase.fromJsonString(
  File('assets/card_db/cards.json').readAsStringSync(),
);

void main() {
  group('new-effect codec round-trips', () {
    void roundTrip(CardEffect effect) {
      final json = encodeEffect(effect);
      final decoded = decodeEffect(json);
      expect(encodeEffect(decoded), json,
          reason: 'stable re-encode for ${effect.runtimeType}');
    }

    test('opponentLosesMastery', () {
      final e = decodeEffect({'type': 'opponentLosesMastery', 'amount': 2});
      expect(e, isA<OpponentLosesMasteryEffect>());
      expect((e as OpponentLosesMasteryEffect).amount, 2);
      roundTrip(e);
    });

    test('mill', () {
      final e = decodeEffect({'type': 'mill', 'count': 3});
      expect(e, isA<MillEffect>());
      expect((e as MillEffect).count, 3);
      roundTrip(e);
    });

    test('recruitToHand with and without character gate', () {
      final bare = decodeEffect({'type': 'recruitToHand'});
      expect(bare, isA<RecruitToHandEffect>());
      expect((bare as RecruitToHandEffect).character, isNull);
      roundTrip(bare);

      final gated =
          decodeEffect({'type': 'recruitToHand', 'character': 'tetra'});
      expect((gated as RecruitToHandEffect).character, Character.tetra);
      roundTrip(gated);
    });

    test('returnFromDiscardToDeckTop', () {
      final e = decodeEffect({'type': 'returnFromDiscardToDeckTop'});
      expect(e, isA<ReturnFromDiscardToDeckTopEffect>());
      expect((e as ReturnFromDiscardToDeckTopEffect).filter, ReturnFilter.any);
      roundTrip(e);
    });

    test('returnFromDiscard self + all flags', () {
      final self = decodeEffect(
          {'type': 'returnFromDiscard', 'filter': 'any', 'self': true});
      expect((self as ReturnFromDiscardEffect).self, isTrue);
      roundTrip(self);

      final all = decodeEffect(
          {'type': 'returnFromDiscard', 'filter': 'mercenary', 'all': true});
      expect((all as ReturnFromDiscardEffect).all, isTrue);
      expect(all.filter, ReturnFilter.mercenary);
      roundTrip(all);

      // Legacy shape (no flags) still decodes with both false.
      final plain = decodeEffect({'type': 'returnFromDiscard'})
          as ReturnFromDiscardEffect;
      expect(plain.self, isFalse);
      expect(plain.all, isFalse);
    });

    test('sameNamePlayedThisTurn condition round-trips', () {
      const cond = ConditionalEffect(
        condition: GameCondition(
            kind: GameConditionKind.sameNamePlayedThisTurn),
        then: [GainPowerEffect(3)],
      );
      final json = encodeEffect(cond);
      final decoded = decodeEffect(json) as ConditionalEffect;
      expect(decoded.condition.kind, GameConditionKind.sameNamePlayedThisTurn);
      expect(encodeEffect(decoded), json);
    });
  });

  group('cards.json wiring', () {
    test('Venator: conditional -> opponentLosesMastery 2', () {
      final effects = _db.byId('venator_of_the_wastes')!.model.playEffects;
      final cond = effects.whereType<ConditionalEffect>().single;
      expect(cond.then.whereType<OpponentLosesMasteryEffect>().single.amount, 2);
      expect(cond.then.whereType<OpponentLosesHealthEffect>(), isEmpty);
    });

    test('Skry-77 Mastery-20: gainMastery 2 + opponentLosesMastery 2', () {
      final bonus = _db.byId('skry_77')!.model.masteryBonus;
      expect(bonus.whereType<GainMasteryEffect>().single.amount, 2);
      expect(bonus.whereType<OpponentLosesMasteryEffect>().single.amount, 2);
      expect(bonus.whereType<GainHealthEffect>(), isEmpty);
    });

    test('Hounds of Volos: Volos branch grants POWER not gems', () {
      final effects = _db.byId('hounds_of_volos')!.model.playEffects;
      expect(effects.whereType<GainGemsEffect>().single.amount, 5);
      final cond = effects.whereType<ConditionalEffect>().single;
      expect(cond.condition.character, Character.volos);
      expect(cond.then.whereType<GainPowerEffect>().single.amount, 5);
      expect(cond.then.whereType<GainGemsEffect>(), isEmpty);
    });

    test('Nexus: on-recruit-to-hand gated on Tetra', () {
      final effects = _db.byId('nexus_datic_hunter')!.model.playEffects;
      expect(effects.whereType<RecruitToHandEffect>().single.character,
          Character.tetra);
    });

    test('Breaker: unconditional on-recruit-to-hand', () {
      final effects = _db.byId('breaker')!.model.playEffects;
      expect(effects.whereType<RecruitToHandEffect>().single.character, isNull);
      expect(effects.whereType<FastPlayFromCenterEffect>().single.alliesOnly,
          isTrue);
    });

    test('Cinder Scars: sameNamePlayedThisTurn -> +3 power', () {
      final effects = _db.byId('cinder_scars')!.model.playEffects;
      final cond = effects.whereType<ConditionalEffect>().single;
      expect(cond.condition.kind, GameConditionKind.sameNamePlayedThisTurn);
      expect(cond.then.whereType<GainPowerEffect>().single.amount, 3);
    });

    test('Legion Carrier: mill 3', () {
      final effects = _db.byId('legion_carrier')!.model.playEffects;
      expect(effects.whereType<MillEffect>().single.count, 3);
    });

    test('The Dispossessed: conditional self-return', () {
      final effects = _db.byId('the_dispossessed')!.model.playEffects;
      final cond = effects.whereType<ConditionalEffect>().single;
      final ret = cond.then.whereType<ReturnFromDiscardEffect>().single;
      expect(ret.self, isTrue);
    });

    test('The World Piercer: Mastery-20 return-all mercenaries (replaces)', () {
      final record = _db.byId('the_world_piercer')!;
      expect(record.model.masteryReplaces, isTrue);
      final ret =
          record.model.masteryBonus.whereType<ReturnFromDiscardEffect>().single;
      expect(ret.all, isTrue);
      expect(ret.filter, ReturnFilter.mercenary);
    });

    test('Dash: return-to-deck-top BEFORE draw', () {
      final effects = _db.byId('dash')!.model.playEffects;
      expect(effects.first, isA<ReturnFromDiscardToDeckTopEffect>());
      expect(effects.whereType<DrawCardsEffect>().single.count, 1);
    });
  });

  group('batch-2 codec round-trips (Axia / Heart / Talons / Ferrata)', () {
    void roundTrip(CardEffect effect) {
      final json = encodeEffect(effect);
      final decoded = decodeEffect(json);
      expect(encodeEffect(decoded), json,
          reason: 'stable re-encode for ${effect.runtimeType}');
    }

    test('acquireCostReductionPerChampion (default amountPer)', () {
      final e = decodeEffect({
        'type': 'acquireCostReductionPerChampion',
        'faction': 'homodeus',
      });
      expect(e, isA<AcquireCostReductionPerChampionEffect>());
      final a = e as AcquireCostReductionPerChampionEffect;
      expect(a.faction, Faction.homodeus);
      expect(a.amountPer, 1);
      roundTrip(e);
    });

    test('acquireCostReductionPerChampion (explicit amountPer)', () {
      final e = decodeEffect({
        'type': 'acquireCostReductionPerChampion',
        'faction': 'wraethe',
        'amountPer': 2,
      });
      final a = e as AcquireCostReductionPerChampionEffect;
      expect(a.faction, Faction.wraethe);
      expect(a.amountPer, 2);
      roundTrip(e);
    });

    test('bonusDrawNextTurnOnUnblockedDamage', () {
      final e = decodeEffect({
        'type': 'bonusDrawNextTurnOnUnblockedDamage',
        'threshold': 10,
        'count': 3,
      });
      expect(e, isA<BonusDrawNextTurnOnUnblockedDamageEffect>());
      final b = e as BonusDrawNextTurnOnUnblockedDamageEffect;
      expect(b.threshold, 10);
      expect(b.count, 3);
      roundTrip(e);
    });

    test('bonusDrawNextTurnOnUnblockedDamage defaults', () {
      final e = decodeEffect(
              {'type': 'bonusDrawNextTurnOnUnblockedDamage'})
          as BonusDrawNextTurnOnUnblockedDamageEffect;
      expect(e.threshold, 10);
      expect(e.count, 3);
    });

    test('scalingResource perHealthGainedThisTurn', () {
      final e = decodeEffect({
        'type': 'scalingResource',
        'resource': 'power',
        'condition': 'perHealthGainedThisTurn',
      }) as ScalingResourceEffect;
      expect(e.condition, ScalingCondition.perHealthGainedThisTurn);
      expect(e.resource, ScalingResource.power);
      roundTrip(e);
    });

    test('Axia wires the self acquire-cost reduction (homodeus)', () {
      final effects = _db.byId('axia')!.model.playEffects;
      final r =
          effects.whereType<AcquireCostReductionPerChampionEffect>().single;
      expect(r.faction, Faction.homodeus);
      expect(r.amountPer, 1);
    });

    test('The Heart of Nothing wires the next-turn draw marker (10 / 3)', () {
      final effects = _db.byId('the_heart_of_nothing')!.model.playEffects;
      final b = effects
          .whereType<BonusDrawNextTurnOnUnblockedDamageEffect>()
          .single;
      expect(b.threshold, 10);
      expect(b.count, 3);
    });

    test('Entropic Talons wires power per health gained this turn', () {
      final effects = _db.byId('entropic_talons')!.model.playEffects;
      final s = effects
          .whereType<ScalingResourceEffect>()
          .singleWhere((e) =>
              e.condition == ScalingCondition.perHealthGainedThisTurn);
      expect(s.resource, ScalingResource.power);
    });

    test('Ferrata Guard wires the Decima-gated power branch', () {
      final effects = _db.byId('ferrata_guard')!.model.playEffects;
      final cond = effects.whereType<ConditionalEffect>().single;
      expect(cond.condition.kind, GameConditionKind.isCharacter);
      expect(cond.condition.character, Character.decima);
      final scale = cond.then.whereType<ScalingResourceEffect>().single;
      expect(scale.resource, ScalingResource.power);
      expect(scale.condition, ScalingCondition.perChampionControlled);
      expect(scale.perN, 2);
    });
  });
}
