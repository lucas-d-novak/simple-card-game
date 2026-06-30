import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/card_art_map.dart';
import 'package:simple_card_game/data/starter_deck.dart';

void main() {
  group('starter cards no longer resolve to misleading placeholder photos', () {
    // The four factionless starter cards previously mapped to stock-photo
    // placeholders (crystal.jpg = rocky coastline, infinity-shard.jpg = garden
    // path, etc.). They must now fall through to procedural [CardArt] so the
    // board shows a themed glyph instead of the wrong photo.
    const starters = ['Crystal', 'Blaster', 'Infinity Shard', 'Shard Reactor'];

    for (final name in starters) {
      test('$name has no art asset (falls to procedural art)', () {
        expect(getCardArtAsset(name), isNull,
            reason: '$name should fall through to procedural CardArt, not a '
                'placeholder photo');
      });
    }

    test('the misleading placeholder jpgs are never returned for any starter',
        () {
      const placeholders = {
        'assets/cards/crystal.jpg',
        'assets/cards/blaster.jpg',
        'assets/cards/shard-reactor.jpg',
        'assets/cards/infinity-shard.jpg',
      };
      for (final card in buildStarterDeck('p1')) {
        final asset = getCardArtAsset(card.name);
        expect(placeholders.contains(asset), isFalse,
            reason: '${card.name} must not resolve to a placeholder photo');
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
