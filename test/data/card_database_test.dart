import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';

void main() {
  group('CardDatabase.fromJsonString', () {
    test('parses a minimal record (id only) with sensible defaults', () {
      final db = CardDatabase.fromJsonString('''
        {"version":1,"cards":[{"id":"mystery"}]}
      ''');

      expect(db.records, hasLength(1));
      final r = db.records.single;
      expect(r.id, 'mystery');
      expect(r.name, 'mystery'); // falls back to id
      expect(r.verified, isFalse);
      expect(r.copies, 1);
      expect(r.set, CardSet.unknown);
      expect(r.model.cost, 0);
      expect(r.model.faction, Faction.none);
      expect(r.model.cardType, CardType.regular);
      expect(r.model.playEffects, isEmpty);
    });

    test('projects a full record into a CardModel', () {
      final db = CardDatabase.fromJsonString('''
      {"version":1,"cards":[{
        "id":"kor_arbiter","name":"Kor Arbiter","set":"base",
        "faction":"homodeus","cardType":"champion","cost":2,"copies":3,
        "shield":3,"masteryThreshold":5,
        "playEffects":[{"type":"gainMastery","amount":1}],
        "masteryBonus":[{"type":"gainPower","amount":2}]
      }]}
      ''');

      final r = db.byId('kor_arbiter')!;
      expect(r.set, CardSet.base);
      expect(r.copies, 3);
      expect(r.model.faction, Faction.homodeus);
      expect(r.model.cardType, CardType.champion);
      expect(r.model.shield, 3);
      expect(r.model.masteryThreshold, 5);
      expect(r.model.playEffects.single, isA<GainMasteryEffect>());
      expect(r.model.masteryBonus.single, isA<GainPowerEffect>());
    });

    test('decodes a chooseOne effect with nested groups', () {
      final db = CardDatabase.fromJsonString('''
      {"version":1,"cards":[{
        "id":"shard_reactor","name":"Shard Reactor","set":"starter",
        "playEffects":[{"type":"chooseOne","choices":[
          [{"type":"gainGems","amount":2}],
          [{"type":"gainPower","amount":2}]
        ]}]
      }]}
      ''');

      final effect = db.byId('shard_reactor')!.model.playEffects.single;
      expect(effect, isA<ChooseOneEffect>());
      expect((effect as ChooseOneEffect).choices, hasLength(2));
    });

    test('throws on an unknown effect type', () {
      expect(
        () => CardDatabase.fromJsonString(
          '{"version":1,"cards":[{"id":"x","playEffects":[{"type":"bogus"}]}]}',
        ),
        throwsFormatException,
      );
    });

    test('verifiedCards filters to verified records only', () {
      final db = CardDatabase.fromJsonString('''
      {"version":1,"cards":[
        {"id":"a","verified":true},
        {"id":"b","verified":false},
        {"id":"c"}
      ]}
      ''');

      expect(db.records, hasLength(3));
      expect(db.verifiedCards.map((r) => r.id), ['a']);
    });

    test('allModels returns a model per record', () {
      final db = CardDatabase.fromJsonString(
        '{"version":1,"cards":[{"id":"a"},{"id":"b"}]}',
      );
      expect(db.allModels.map((m) => m.id), ['a', 'b']);
    });
  });
}
