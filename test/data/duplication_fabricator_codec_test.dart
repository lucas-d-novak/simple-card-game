import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/effect_codec.dart';
import 'package:simple_card_game/data/database/game_state_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Wave-B Group 4b — Duplication Fabricator codec coverage:
/// the RevealAndCopyTopOfDecksEffect round-trips through effect_codec, and
/// GameService.pendingDeckReveal round-trips through GameStateCodec mid-choice.

void main() {
  group('effect_codec — revealAndCopyTopOfDecks', () {
    test('decodes from json', () {
      final effect = decodeEffect({'type': 'revealAndCopyTopOfDecks'});
      expect(effect, isA<RevealAndCopyTopOfDecksEffect>());
    });

    test('encodes round-trip', () {
      final encoded = encodeEffect(const RevealAndCopyTopOfDecksEffect());
      expect(encoded, {'type': 'revealAndCopyTopOfDecks'});
      expect(decodeEffect(encoded), isA<RevealAndCopyTopOfDecksEffect>());
    });
  });

  group('GameStateCodec — pendingDeckReveal', () {
    test('omits pendingDeckReveal when empty', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final json = GameStateCodec.encode(game);
      expect(json.containsKey('pendingDeckReveal'), false);
    });

    test('round-trips a mid-choice pending reveal (ownerId + card)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      const gemAlly = CardModel(
        id: 'gem_ally',
        name: 'Gem Ally',
        cost: 0,
        faction: Faction.undergrowth,
        cardType: CardType.regular,
        playEffects: [GainGemsEffect(3)],
      );
      const powerAlly = CardModel(
        id: 'power_ally',
        name: 'Power Ally',
        cost: 0,
        faction: Faction.wraethe,
        cardType: CardType.regular,
        playEffects: [GainPowerEffect(2)],
      );
      game.players[0].drawPile
        ..clear()
        ..add(gemAlly);
      game.players[1].drawPile
        ..clear()
        ..add(powerAlly);
      game.revealTopOfAllDecks();
      expect(game.pendingDeckReveal.length, 2);

      // Full JSON round-trip (encode → string → decode).
      final restored = GameStateCodec.decode(
        jsonDecode(jsonEncode(GameStateCodec.encode(game)))
            as Map<String, dynamic>,
      );

      expect(restored.pendingDeckReveal.length, 2);
      final byOwner = {
        for (final e in restored.pendingDeckReveal) e.ownerId: e.card.id,
      };
      expect(byOwner[game.players[0].id], 'gem_ally');
      expect(byOwner[game.players[1].id], 'power_ally');
      // The restored effect on the copied card survives too.
      final restoredCard = restored.pendingDeckReveal
          .firstWhere((e) => e.card.id == 'gem_ally')
          .card;
      expect(restoredCard.playEffects.single, isA<GainGemsEffect>());
    });
  });
}
