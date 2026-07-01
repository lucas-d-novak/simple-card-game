import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/models/card_effect.dart';

/// Regression coverage for the 2026-07-01 resource-transcription sweep +
/// encode/reorder pass on the authoritative card DB. Each assertion locks in a
/// corrected effect (verified against the printed card art in assets/cards/).
void main() {
  final db = CardDatabase.fromJsonString(
    File('assets/card_db/cards.json').readAsStringSync(),
  );

  group('resource-type corrections (art-verified)', () {
    test('Order Initiate Dominion trigger grants MASTERY, not gems', () {
      final effects = db.byId('order_initiate')!.model.playEffects;
      // Base gain stays gems (2).
      expect(effects.whereType<GainGemsEffect>().single.amount, 2);
      final conditional = effects.whereType<ConditionalEffect>().single;
      expect(conditional.then.whereType<GainMasteryEffect>().single.amount, 2);
      expect(conditional.then.whereType<GainGemsEffect>(), isEmpty);
    });

    test('Shard Abstractor grants MASTERY, not gems', () {
      final effects = db.byId('shard_abstractor')!.model.playEffects;
      expect(effects.whereType<GainMasteryEffect>().single.amount, 2);
      expect(effects.whereType<GainGemsEffect>(), isEmpty);
    });

    test('The Grand Architect grants 5 MASTERY, not gems', () {
      final effects = db.byId('the_grand_architect')!.model.playEffects;
      expect(effects.whereType<GainMasteryEffect>().single.amount, 5);
      expect(effects.whereType<GainGemsEffect>(), isEmpty);
    });

    test('Fungal Hermit base grants MASTERY, mastery bonus grants HEALTH', () {
      final record = db.byId('fungal_hermit')!;
      final base = record.model.playEffects;
      expect(base.whereType<GainMasteryEffect>().single.amount, 1);
      expect(base.whereType<GainGemsEffect>(), isEmpty);
      final bonus = record.model.masteryBonus;
      expect(bonus.whereType<GainHealthEffect>().single.amount, 5);
      expect(bonus.whereType<GainGemsEffect>(), isEmpty);
      expect(bonus.whereType<GainMasteryEffect>(), isEmpty);
    });

    test('Root of the Forest base grants HEALTH, Unify grants POWER (not gems)',
        () {
      final effects = db.byId('root_of_the_forest')!.model.playEffects;
      expect(effects.whereType<GainHealthEffect>().single.amount, 10);
      expect(effects.whereType<GainGemsEffect>(), isEmpty);
      final conditional = effects.whereType<ConditionalEffect>().single;
      expect(conditional.then.whereType<GainPowerEffect>().single.amount, 10);
      expect(conditional.then.whereType<GainGemsEffect>(), isEmpty);
    });

    test('Umbral Scourge grants MASTERY, not gems', () {
      final effects = db.byId('umbral_scourge')!.model.playEffects;
      final gain = effects.whereType<GainMasteryEffect>().single;
      expect(gain.amount, 1);
      expect(effects.whereType<GainGemsEffect>(), isEmpty);
    });

    test('Arach Devotees Unify grants HEALTH, not gems', () {
      final conditional =
          db.byId('arach_devotees')!.model.playEffects.whereType<ConditionalEffect>().single;
      final gain = conditional.then.whereType<GainHealthEffect>().single;
      expect(gain.amount, 3);
    });

    test('Shardwood Guardian Unify grants HEALTH (base stays power)', () {
      final effects = db.byId('shardwood_guardian')!.model.playEffects;
      // Base gain is still power.
      expect(effects.whereType<GainPowerEffect>().single.amount, 2);
      final conditional = effects.whereType<ConditionalEffect>().single;
      expect(conditional.then.whereType<GainHealthEffect>().single.amount, 6);
    });

    test('Evokatus Exhaust scales POWER, not gems', () {
      final ability = db.byId('evokatus')!.model.activatedAbility!;
      final scaling = ability.effects.whereType<ScalingResourceEffect>().single;
      expect(scaling.resource, ScalingResource.power);
    });

    test('Orm Madu Exhaust gates on HEALTH >= 50 (the HP cap), not mastery', () {
      final ability = db.byId('orm_madu')!.model.activatedAbility!;
      final conditional = ability.effects.whereType<ConditionalEffect>().single;
      expect(conditional.condition.kind, GameConditionKind.healthAtLeast);
      expect(conditional.condition.threshold, 50);
      expect(conditional.then.whereType<GainMasteryEffect>().single.amount, 1);
    });
  });

  group('reorder + newly-encoded abilities', () {
    test('Pall Shades resolves the Echo clause BEFORE the draw', () {
      final effects = db.byId('pall_shades')!.model.playEffects;
      expect(effects.first, isA<ConditionalEffect>());
      expect(effects[1], isA<DrawCardsEffect>());
    });

    test('Kiln Drone encodes the Inspire +2 gems (champion in play)', () {
      final conditional =
          db.byId('kiln_drone')!.model.playEffects.whereType<ConditionalEffect>().single;
      expect(conditional.condition.kind, GameConditionKind.championsControlled);
      expect(conditional.then.whereType<GainGemsEffect>().single.amount, 2);
    });

    test('Venator encodes the Inspire opponent-MASTERY-loss (champion in play)',
        () {
      // OWNER-CONFIRMED 2026-07-01: Venator's Inspire drains MASTERY, not health.
      final conditional =
          db.byId('venator_of_the_wastes')!.model.playEffects.whereType<ConditionalEffect>().single;
      expect(conditional.condition.kind, GameConditionKind.championsControlled);
      expect(conditional.then.whereType<OpponentLosesMasteryEffect>().single.amount, 2);
      expect(conditional.then.whereType<OpponentLosesHealthEffect>(), isEmpty);
    });
  });
}
