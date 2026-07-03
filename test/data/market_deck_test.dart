import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/data/market_deck.dart';

/// A small in-memory database covering the relevant cases: a normal center-deck
/// card, a Destiny, a DestinyDeck card, an Aion-group card, a starter card, and
/// an out-of-scope card.
CardDatabase _db() => CardDatabase.fromJsonString('''
{
  "cards": [
    {"id": "kiln_drone", "name": "Kiln Drone", "cost": 1, "copies": 3,
     "playEffects": [{"type": "gainGems", "amount": 1}]},
    {"id": "datic_secrets", "name": "Datic Secrets", "group": "Destiny",
     "playEffects": [{"type": "gainMastery", "amount": 1}]},
    {"id": "synthesis", "name": "Synthesis", "group": "DestinyDeck",
     "playEffects": [{"type": "drawCards", "count": 1}]},
    {"id": "swyft", "name": "Swyft", "group": "Aion", "cost": 6, "copies": 1,
     "cardType": "champion", "shield": 3,
     "playEffects": [{"type": "gainPower", "amount": 2}]},
    {"id": "crystal", "name": "Crystal", "cost": 0,
     "playEffects": [{"type": "gainGems", "amount": 1}]},
    {"id": "praetorian_01", "name": "Praetorian-01", "cost": 4, "copies": 1,
     "playEffects": [{"type": "gainPower", "amount": 3}]},
    {"id": "boss_thing", "name": "Boss", "outOfScope": true,
     "playEffects": [{"type": "gainPower", "amount": 9}]},
    {"id": "power_struggle", "name": "Power Struggle", "group": "Destiny",
     "outOfScope": true, "playEffects": []}
  ]
}
''');

void main() {
  group('market vs Destiny supply separation', () {
    test('the market EXCLUDES Destinies, starters, off-scope, and Aion/Prism',
        () {
      final market = buildMarketDeckFromDatabase(_db());
      final ids = market.map((m) => m.template.id).toSet();

      expect(ids, contains('kiln_drone'),
          reason: 'a normal center-deck card is in the market');
      expect(ids, isNot(contains('datic_secrets')),
          reason: 'Destinies must NOT be in the center deck');
      expect(ids, isNot(contains('synthesis')),
          reason: 'DestinyDeck cards must NOT be in the center deck');
      expect(ids, isNot(contains('swyft')),
          reason: 'Aion-group cards are a separate supply, not the market');
      expect(ids, isNot(contains('crystal')),
          reason: 'starter cards are never in the market');
      expect(ids, isNot(contains('praetorian_01')),
          reason: 'relics are recruited at Mastery 10, never in the market');
      expect(ids, isNot(contains('boss_thing')),
          reason: 'out-of-scope cards are excluded');
    });

    test('buildRelicCardsFromDatabase returns only relic cards, keyed by id',
        () {
      final relics = buildRelicCardsFromDatabase(_db());
      expect(relics.keys, contains('praetorian_01'));
      expect(relics['praetorian_01']!.name, 'Praetorian-01');
      expect(relics.keys, isNot(contains('kiln_drone')));
      expect(relics.length, 1, reason: 'only the one relic in this test DB');
    });

    test('the Destiny supply contains Destiny/DestinyDeck cards + the inert 30th',
        () {
      final supply = buildDestinySupplyFromDatabase(_db());
      final ids = supply.map((c) => c.id).toSet();

      expect(ids, containsAll(['datic_secrets', 'synthesis']));
      expect(ids, isNot(contains('kiln_drone')));
      expect(ids, isNot(contains('swyft')));
      expect(ids, contains('power_struggle'),
          reason:
              'power_struggle is included as the inert 30th Destiny despite '
              'outOfScope (owner ruling)');
      expect(ids.length, 3,
          reason: 'the two normal Destinies plus the inert power_struggle');
    });

    test('other out-of-scope Destiny-group cards would still be excluded', () {
      // The inert allow-list is a specific id, not a blanket "include OOS
      // destinies" — a hypothetical other OOS Destiny must not leak in.
      final db = CardDatabase.fromJsonString('''
{
  "cards": [
    {"id": "power_struggle", "name": "Power Struggle", "group": "Destiny",
     "outOfScope": true, "playEffects": []},
    {"id": "some_other_oos_destiny", "name": "Other", "group": "Destiny",
     "outOfScope": true, "playEffects": []}
  ]
}
''');
      final ids =
          buildDestinySupplyFromDatabase(db).map((c) => c.id).toSet();
      expect(ids, contains('power_struggle'));
      expect(ids, isNot(contains('some_other_oos_destiny')));
    });

    test('market copies come from the database copies field', () {
      final market = buildMarketDeckFromDatabase(_db());
      final kiln = market.firstWhere((m) => m.template.id == 'kiln_drone');
      expect(kiln.copies, 3);
    });
  });
}
