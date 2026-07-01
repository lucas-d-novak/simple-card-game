import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/card_art_map.dart';
import 'package:simple_card_game/data/starter_deck.dart';

void main() {
  group('starter cards resolve to their real printed art', () {
    // The four factionless starter cards now use their real card scans (the old
    // stock-photo placeholders were replaced at these paths), so they resolve to
    // an art asset rather than falling through to procedural [CardArt].
    const expected = {
      'Crystal': 'assets/cards/crystal.jpg',
      'Blaster': 'assets/cards/blaster.jpg',
      'Infinity Shard': 'assets/cards/infinity-shard.jpg',
      'Shard Reactor': 'assets/cards/shard-reactor.jpg',
    };

    expected.forEach((name, path) {
      test('$name resolves to $path', () {
        expect(getCardArtAsset(name), path);
      });
    });

    test('every starter in the built deck resolves to a real art asset', () {
      for (final card in buildStarterDeck('p1')) {
        expect(getCardArtAsset(card.name), isNotNull,
            reason: '${card.name} should resolve to its real card art');
      }
    });
  });

  group('real DB-card art still resolves (no regression)', () {
    test('underscore-named real art still resolves', () {
      // infinity-engine-fragment was repointed off the misleading
      // infinity-shard.jpg onto the real infinity-engine.jpg.
      expect(getCardArtAsset('Infinity Engine Fragment'),
          'assets/cards/infinity-engine.jpg');
    });

    test('a sampling of faction cards still resolve to their art', () {
      expect(getCardArtAsset('Shadow Fiend'), 'assets/cards/shadow-fiend.jpg');
      expect(getCardArtAsset('Vine Guardian'), 'assets/cards/vine-guardian.jpg');
      expect(
          getCardArtAsset('Universal Soldier'),
          'assets/cards/universal-soldier.jpg');
    });
  });
}
