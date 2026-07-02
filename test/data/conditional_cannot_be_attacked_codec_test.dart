import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/data/database/effect_codec.dart';
import 'package:simple_card_game/data/database/game_state_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Round-trips the new conditional-cannotBeAttacked descriptor through the effect
/// codec, the game-state codec, and the authoritative card DB.
void main() {
  group('effect_codec — conditional cannotBeAttacked', () {
    test('round-trips scope / condition / conditionCardName', () {
      const effect = AddStaticModifierEffect(StaticModifier(
        kind: StaticModifierKind.cannotBeAttacked,
        cannotBeAttackedScope: CannotBeAttackedScope.selfChampion,
        cannotBeAttackedCondition:
            CannotBeAttackedCondition.controlsNamedChampion,
        conditionCardName: 'General Decurion',
      ));

      final json = encodeEffect(effect);
      expect(json['cannotBeAttackedScope'], 'selfChampion');
      expect(json['cannotBeAttackedCondition'], 'controlsNamedChampion');
      expect(json['conditionCardName'], 'General Decurion');

      final decoded = decodeEffect(json) as AddStaticModifierEffect;
      final m = decoded.modifier;
      expect(m.cannotBeAttackedScope, CannotBeAttackedScope.selfChampion);
      expect(m.cannotBeAttackedCondition,
          CannotBeAttackedCondition.controlsNamedChampion);
      expect(m.conditionCardName, 'General Decurion');
    });

    test('omits defaults (Zetta aura encodes without the new keys)', () {
      const effect = AddStaticModifierEffect(
          StaticModifier(kind: StaticModifierKind.cannotBeAttacked));
      final json = encodeEffect(effect);
      expect(json.containsKey('cannotBeAttackedScope'), false);
      expect(json.containsKey('cannotBeAttackedCondition'), false);
      expect(json.containsKey('conditionCardName'), false);

      final decoded = decodeEffect(json) as AddStaticModifierEffect;
      expect(decoded.modifier.cannotBeAttackedScope,
          CannotBeAttackedScope.playerAndOtherChampions);
      expect(decoded.modifier.cannotBeAttackedCondition,
          CannotBeAttackedCondition.always);
    });

    test('attacker-mastery variant round-trips', () {
      const effect = AddStaticModifierEffect(StaticModifier(
        kind: StaticModifierKind.cannotBeAttacked,
        cannotBeAttackedScope: CannotBeAttackedScope.selfChampion,
        cannotBeAttackedCondition:
            CannotBeAttackedCondition.attackerMasteryLessThanOwner,
      ));
      final decoded = decodeEffect(encodeEffect(effect)) as AddStaticModifierEffect;
      expect(decoded.modifier.cannotBeAttackedCondition,
          CannotBeAttackedCondition.attackerMasteryLessThanOwner);
    });
  });

  group('game_state_codec — StaticModifier round-trip', () {
    test('preserves scope / condition / conditionCardName on a live snapshot', () {
      final game = GameService(playerCount: 2, random: null);
      game.players[0].staticModifiers.add(const StaticModifier(
        kind: StaticModifierKind.cannotBeAttacked,
        sourceChampionId: 'drakonarius_0',
        cannotBeAttackedScope: CannotBeAttackedScope.selfChampion,
        cannotBeAttackedCondition:
            CannotBeAttackedCondition.controlsNamedChampion,
        conditionCardName: 'General Decurion',
      ));

      final restored =
          GameStateCodec.decode(GameStateCodec.encode(game));
      final m = restored.players[0].staticModifiers.single;
      expect(m.sourceChampionId, 'drakonarius_0');
      expect(m.cannotBeAttackedScope, CannotBeAttackedScope.selfChampion);
      expect(m.cannotBeAttackedCondition,
          CannotBeAttackedCondition.controlsNamedChampion);
      expect(m.conditionCardName, 'General Decurion');
    });
  });

  group('card DB — the three cards decode to the intended modifiers', () {
    late CardDatabase db;

    setUpAll(() {
      db = CardDatabase.fromJsonString(
          File('assets/card_db/cards.json').readAsStringSync());
    });

    StaticModifier modifierFor(String id) {
      final record = db.byId(id)!;
      final effect = record.model.playEffects
          .whereType<AddStaticModifierEffect>()
          .single;
      return effect.modifier;
    }

    test('drakonarius: self / controlsNamedChampion / General Decurion', () {
      final m = modifierFor('drakonarius');
      expect(m.kind, StaticModifierKind.cannotBeAttacked);
      expect(m.cannotBeAttackedScope, CannotBeAttackedScope.selfChampion);
      expect(m.cannotBeAttackedCondition,
          CannotBeAttackedCondition.controlsNamedChampion);
      expect(m.conditionCardName, 'General Decurion');
    });

    test('raidian: self / attackerMasteryLessThanOwner', () {
      final m = modifierFor('raidian_cloud_master');
      expect(m.cannotBeAttackedScope, CannotBeAttackedScope.selfChampion);
      expect(m.cannotBeAttackedCondition,
          CannotBeAttackedCondition.attackerMasteryLessThanOwner);
    });

    test('li_hin: self / always', () {
      final m = modifierFor('li_hin_the_shattered');
      expect(m.cannotBeAttackedScope, CannotBeAttackedScope.selfChampion);
      expect(m.cannotBeAttackedCondition, CannotBeAttackedCondition.always);
    });

    test('zetta: player+other-champions / always (unchanged)', () {
      final m = modifierFor('zetta_the_encryptor');
      expect(m.cannotBeAttackedScope,
          CannotBeAttackedScope.playerAndOtherChampions);
      expect(m.cannotBeAttackedCondition, CannotBeAttackedCondition.always);
    });
  });
}
