import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/starter_deck.dart';
import 'package:simple_card_game/models/card_effect.dart';

void main() {
  group('buildStarterDeck', () {
    test('returns exactly 10 cards', () {
      final deck = buildStarterDeck('p1');
      expect(deck, hasLength(10));
    });

    test('contains 7 Crystals, 1 Blaster, 1 Infinity Shard, 1 Shard Reactor',
        () {
      final deck = buildStarterDeck('p1');
      final crystals = deck.where((c) => c.name == 'Crystal');
      final blasters = deck.where((c) => c.name == 'Blaster');
      final shards = deck.where((c) => c.name == 'Infinity Shard');
      final reactors = deck.where((c) => c.name == 'Shard Reactor');

      expect(crystals, hasLength(7));
      expect(blasters, hasLength(1));
      expect(shards, hasLength(1));
      expect(reactors, hasLength(1));
    });

    test('Crystals provide 1 gem each', () {
      final deck = buildStarterDeck('p1');
      for (final crystal in deck.where((c) => c.name == 'Crystal')) {
        expect(crystal.playEffects, hasLength(1));
        expect(crystal.playEffects.first, isA<GainGemsEffect>());
        expect((crystal.playEffects.first as GainGemsEffect).amount, 1);
      }
    });

    test('Blaster provides 1 power', () {
      final deck = buildStarterDeck('p1');
      final blaster = deck.firstWhere((c) => c.name == 'Blaster');
      expect(blaster.playEffects, hasLength(1));
      expect(blaster.playEffects.first, isA<GainPowerEffect>());
      expect((blaster.playEffects.first as GainPowerEffect).amount, 1);
    });

    test('Infinity Shard has InfinityShardEffect', () {
      final deck = buildStarterDeck('p1');
      final shard = deck.firstWhere((c) => c.name == 'Infinity Shard');
      expect(shard.playEffects, hasLength(1));
      expect(shard.playEffects.first, isA<InfinityShardEffect>());
    });

    test('Shard Reactor gains gems scaling with mastery (2 / 3 at 5 / 4 at 15)',
        () {
      final deck = buildStarterDeck('p1');
      final reactor = deck.firstWhere((c) => c.name == 'Shard Reactor');
      // Base gem gain + two mastery-threshold conditionals (no power option).
      expect(reactor.playEffects.first, isA<GainGemsEffect>());
      expect((reactor.playEffects.first as GainGemsEffect).amount, 2);
      final conditionals =
          reactor.playEffects.whereType<ConditionalEffect>().toList();
      expect(conditionals, hasLength(2));
      final thresholds =
          conditionals.map((c) => c.condition.threshold).toSet();
      expect(thresholds, {5, 15});
      // No power option anymore (real card is gems-only).
      expect(reactor.playEffects.whereType<ChooseOneEffect>(), isEmpty);
    });

    test('all card IDs are unique within a deck', () {
      final deck = buildStarterDeck('p1');
      final ids = deck.map((c) => c.id).toSet();
      expect(ids, hasLength(10));
    });

    test('card IDs are prefixed with player ID', () {
      final deck = buildStarterDeck('player_42');
      for (final card in deck) {
        expect(card.id, startsWith('player_42_'));
      }
    });

    test('different players get different card IDs', () {
      final deck1 = buildStarterDeck('p1');
      final deck2 = buildStarterDeck('p2');
      final ids1 = deck1.map((c) => c.id).toSet();
      final ids2 = deck2.map((c) => c.id).toSet();
      expect(ids1.intersection(ids2), isEmpty);
    });

    test('all starter cards have cost 0', () {
      final deck = buildStarterDeck('p1');
      for (final card in deck) {
        expect(card.cost, 0);
      }
    });
  });
}
