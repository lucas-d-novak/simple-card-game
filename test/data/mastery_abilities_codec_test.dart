import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/data/database/card_serialization.dart';
import 'package:simple_card_game/data/database/effect_codec.dart';
import 'package:simple_card_game/data/database/game_state_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Codec round-trips for the 2026-07-01 mastery abilities: the three new effect
/// types, the mastery-gated multi-faction CardModel fields, the
/// `ignoresGuardThisTurn` player flag, and the wired shapes in cards.json.

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

    test('ignoreGuardThisTurn', () {
      final e = decodeEffect({'type': 'ignoreGuardThisTurn'});
      expect(e, isA<IgnoreGuardThisTurnEffect>());
      roundTrip(e);
    });

    test('doublePower', () {
      final e = decodeEffect({'type': 'doublePower'});
      expect(e, isA<DoublePowerEffect>());
      roundTrip(e);
    });

    test('copyAllPlayedCards with filter + faction', () {
      final e = decodeEffect({
        'type': 'copyAllPlayedCards',
        'filter': 'nonChampion',
        'faction': 'homodeus',
      });
      expect(e, isA<CopyAllPlayedCardsEffect>());
      final c = e as CopyAllPlayedCardsEffect;
      expect(c.filter, CopyFilter.nonChampion);
      expect(c.faction, Faction.homodeus);
      roundTrip(e);
    });

    test('copyAllPlayedCards defaults to nonChampion / any faction', () {
      final e = decodeEffect({'type': 'copyAllPlayedCards'})
          as CopyAllPlayedCardsEffect;
      expect(e.filter, CopyFilter.nonChampion);
      expect(e.faction, isNull);
    });

    test('activatedAbility with new masteryBonusEffects round-trips', () {
      const ability = ActivatedAbility(
        effects: [GainPowerEffect(2)],
        masteryThreshold: 20,
        masteryBonusEffects: [DoublePowerEffect()],
      );
      final json = encodeActivatedAbility(ability);
      final decoded = decodeActivatedAbility(json)!;
      expect(decoded.masteryThreshold, 20);
      expect(decoded.masteryBonusEffects.single, isA<DoublePowerEffect>());
      expect(encodeActivatedAbility(decoded), json);
    });
  });

  group('CardModel.countsAsFactions serialization', () {
    test('round-trips the multi-faction fields', () {
      const card = CardModel(
        id: 'querry_monk',
        name: 'Querry Monk',
        cost: 4,
        faction: Faction.order,
        shield: 3,
        playEffects: [DrawCardsEffect(1)],
        masteryThreshold: 10,
        countsAsFactions: [
          Faction.homodeus,
          Faction.wraethe,
          Faction.undergrowth
        ],
        countsAsFactionsMasteryThreshold: 10,
      );
      final json = cardModelToJson(card);
      expect(json['countsAsFactions'], ['homodeus', 'wraethe', 'undergrowth']);
      expect(json['countsAsFactionsMasteryThreshold'], 10);

      final decoded = cardModelFromJson(json);
      expect(decoded.countsAsFactions,
          [Faction.homodeus, Faction.wraethe, Faction.undergrowth]);
      expect(decoded.countsAsFactionsMasteryThreshold, 10);
    });

    test('ordinary card omits the multi-faction keys', () {
      const card = CardModel(id: 'plain', name: 'Plain', cost: 1, playEffects: []);
      final json = cardModelToJson(card);
      expect(json.containsKey('countsAsFactions'), false);
      expect(json.containsKey('countsAsFactionsMasteryThreshold'), false);
      final decoded = cardModelFromJson(json);
      expect(decoded.countsAsFactions, isEmpty);
      expect(decoded.countsAsFactionsMasteryThreshold, isNull);
    });
  });

  group('GameStateCodec ignoresGuardThisTurn', () {
    test('round-trips the flag', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.ignoresGuardThisTurn = true;
      final restored = GameStateCodec.decode(
          jsonDecode(jsonEncode(GameStateCodec.encode(game)))
              as Map<String, dynamic>);
      expect(restored.players[0].ignoresGuardThisTurn, true);
      expect(restored.players[1].ignoresGuardThisTurn, false);
    });
  });

  group('cards.json wired shapes', () {
    test('fa_cu_tul_the_formless: Exhaust +2 power, Mastery 20 doublePower', () {
      final model = _db.byId('fa_cu_tul_the_formless')!.model;
      final ability = model.activatedAbility!;
      expect(ability.effects.single, isA<GainPowerEffect>());
      expect(ability.masteryThreshold, 20);
      expect(ability.masteryBonusEffects.single, isA<DoublePowerEffect>());
      expect(ability.replaces, false); // additive
    });

    test('rue_bo_vai_the_transcendent: Exhaust +4 power, Mastery 10 ignore Guard',
        () {
      final model = _db.byId('rue_bo_vai_the_transcendent')!.model;
      final ability = model.activatedAbility!;
      expect((ability.effects.single as GainPowerEffect).amount, 4);
      expect(ability.masteryThreshold, 10);
      expect(
          ability.masteryBonusEffects.single, isA<IgnoreGuardThisTurnEffect>());
    });

    test('general_decurion: Exhaust +3 gems, Mastery 20 copy Homodeus allies',
        () {
      final model = _db.byId('general_decurion')!.model;
      final ability = model.activatedAbility!;
      expect((ability.effects.single as GainGemsEffect).amount, 3);
      expect(ability.masteryThreshold, 20);
      final copy = ability.masteryBonusEffects.single as CopyAllPlayedCardsEffect;
      expect(copy.filter, CopyFilter.nonChampion);
      expect(copy.faction, Faction.homodeus);
    });

    test('querry_monk: multi-faction gated at Mastery 10, keeps shield 3', () {
      final model = _db.byId('querry_monk')!.model;
      expect(model.faction, Faction.order);
      expect(model.cardType, CardType.regular);
      expect(model.shield, 3);
      expect(model.countsAsFactions,
          [Faction.homodeus, Faction.wraethe, Faction.undergrowth]);
      expect(model.countsAsFactionsMasteryThreshold, 10);
      expect(model.playEffects.single, isA<DrawCardsEffect>());
    });
  });
}
