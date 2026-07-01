import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/game_state_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_service.dart';

/// RedirectNextRecruitEffect — "put the next … you recruit this turn directly
/// into play / into your hand" (numeri_drones, anomaly_cleric).
///
/// Reproduces the reported bug (a recruited Homodeus Champion went to the
/// discard pile instead of directly into play) and locks in the fix, plus the
/// non-matching, single-use, end-of-turn-expiry, and to-hand (anomaly_cleric)
/// behaviours, on both recruit paths (buyCard + recruitFromCenter), and the
/// serialization round-trip of the pending redirect.
void main() {
  // A numeri_drones-shaped champion: Exhaust gains a gem AND installs a
  // redirect so the next Homodeus Champion recruited this turn deploys directly
  // into play.
  const numeriDrones = CardModel(
    id: 'numeri_drones',
    name: 'Numeri Drones',
    cost: 3,
    faction: Faction.homodeus,
    cardType: CardType.champion,
    shield: 5,
    playEffects: [],
    activatedAbility: ActivatedAbility(
      effects: [
        GainGemsEffect(1),
        RedirectNextRecruitEffect(
          destination: RecruitRedirect.intoPlay,
          faction: Faction.homodeus,
          cardType: CardType.champion,
        ),
      ],
    ),
  );

  // A Homodeus Champion in the market with an on-deploy effect, so we can prove
  // it truly ENTERS PLAY (deploy effect fires) rather than landing in discard.
  const homodeusChamp = CardModel(
    id: 'homodeus_champ',
    name: 'Homodeus Champ',
    cost: 4,
    faction: Faction.homodeus,
    cardType: CardType.champion,
    shield: 3,
    playEffects: [GainPowerEffect(2)],
  );

  const wraetheChamp = CardModel(
    id: 'wraethe_champ',
    name: 'Wraethe Champ',
    cost: 4,
    faction: Faction.wraethe,
    cardType: CardType.champion,
    shield: 3,
    playEffects: [],
  );

  const homodeusAlly = CardModel(
    id: 'homodeus_ally',
    name: 'Homodeus Ally',
    cost: 2,
    faction: Faction.homodeus,
    cardType: CardType.regular,
    playEffects: [],
  );

  /// Play Numeri Drones' Exhaust so its redirect is installed on the current
  /// player, and clear the gem it granted so buy-cost assertions stay simple.
  GameService gameWithNumeriExhausted() {
    final game = GameService(playerCount: 2, random: Random(7));
    final player = game.currentPlayer;
    player.championsInPlay.add(numeriDrones);
    expect(game.useActivatedAbility('numeri_drones'), isTrue);
    expect(player.pendingRecruitRedirect, isNotNull,
        reason: 'Exhaust should install the pending recruit redirect');
    player.gemPool = 0; // discard the gem granted by the Exhaust
    return game;
  }

  group('RedirectNextRecruitEffect — into play (numeri_drones, the bug)', () {
    test('recruited Homodeus Champion enters play, NOT the discard pile', () {
      final game = gameWithNumeriExhausted();
      final player = game.currentPlayer;
      game.centerRow.insert(0, homodeusChamp);
      player.gemPool = 4;

      expect(game.buyCard('homodeus_champ'), isTrue);

      expect(player.championsInPlay.any((c) => c.id == 'homodeus_champ'), isTrue,
          reason: 'the champion should deploy directly into play');
      expect(player.discardPile.any((c) => c.id == 'homodeus_champ'), isFalse,
          reason: 'it must NOT go to the discard pile (the bug)');
      expect(player.pendingRecruitRedirect, isNull,
          reason: 'the single-use redirect is consumed');
      // Proves it was PLAYED into play (deploy effect resolved), not just moved.
      expect(player.powerPool, 2,
          reason: 'the entering champion\'s on-deploy effect should resolve');
    });

    test('a NON-Homodeus champion recruit is unaffected (goes to discard)', () {
      final game = gameWithNumeriExhausted();
      final player = game.currentPlayer;
      game.centerRow.insert(0, wraetheChamp);
      player.gemPool = 4;

      expect(game.buyCard('wraethe_champ'), isTrue);

      expect(player.discardPile.any((c) => c.id == 'wraethe_champ'), isTrue,
          reason: 'wrong-faction recruit is not redirected');
      expect(player.championsInPlay.any((c) => c.id == 'wraethe_champ'), isFalse);
      expect(player.pendingRecruitRedirect, isNotNull,
          reason: 'redirect is NOT consumed by a non-matching recruit');
    });

    test('a Homodeus non-champion (ally) recruit is unaffected', () {
      final game = gameWithNumeriExhausted();
      final player = game.currentPlayer;
      game.centerRow.insert(0, homodeusAlly);
      player.gemPool = 2;

      expect(game.buyCard('homodeus_ally'), isTrue);

      expect(player.discardPile.any((c) => c.id == 'homodeus_ally'), isTrue,
          reason: 'an ally cannot enter play; the intoPlay redirect skips it');
      expect(player.pendingRecruitRedirect, isNotNull);
    });

    test('redirect is SINGLE-USE — only the first matching recruit enters play',
        () {
      final game = gameWithNumeriExhausted();
      final player = game.currentPlayer;
      game.centerRow.insert(0, homodeusChamp);
      const secondChamp = CardModel(
        id: 'homodeus_champ_2',
        name: 'Homodeus Champ 2',
        cost: 4,
        faction: Faction.homodeus,
        cardType: CardType.champion,
        shield: 3,
        playEffects: [],
      );
      game.centerRow.insert(1, secondChamp);
      player.gemPool = 8;

      expect(game.buyCard('homodeus_champ'), isTrue);
      expect(game.buyCard('homodeus_champ_2'), isTrue);

      expect(player.championsInPlay.any((c) => c.id == 'homodeus_champ'), isTrue);
      expect(player.discardPile.any((c) => c.id == 'homodeus_champ_2'), isTrue,
          reason: 'the SECOND champion is not redirected (redirect consumed)');
    });

    test('an unconsumed redirect EXPIRES at end of turn', () {
      final game = gameWithNumeriExhausted();
      final player = game.currentPlayer;
      expect(player.pendingRecruitRedirect, isNotNull);

      game.endTurn();

      expect(player.pendingRecruitRedirect, isNull,
          reason: 'the redirect is scoped to "this turn"');
    });

    test('redirect also applies on the recruitFromCenter path', () {
      final game = gameWithNumeriExhausted();
      final player = game.currentPlayer;
      game.centerRow.insert(0, homodeusChamp);
      player.gemPool = 4;

      expect(
          game.recruitFromCenter('homodeus_champ', free: false), isTrue);

      expect(player.championsInPlay.any((c) => c.id == 'homodeus_champ'), isTrue);
      expect(player.discardPile.any((c) => c.id == 'homodeus_champ'), isFalse);
      expect(player.pendingRecruitRedirect, isNull);
    });
  });

  group('RedirectNextRecruitEffect — to hand (anomaly_cleric)', () {
    test('next recruited card of ANY faction/type goes to hand', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      // anomaly_cleric Mastery-10: no faction/type filter, destination toHand.
      player.pendingRecruitRedirect = const RedirectNextRecruitEffect(
        destination: RecruitRedirect.toHand,
      );
      game.centerRow.insert(0, wraetheChamp);
      player.gemPool = 4;

      expect(game.buyCard('wraethe_champ'), isTrue);

      expect(player.hand.any((c) => c.id == 'wraethe_champ'), isTrue,
          reason: 'the recruited card goes to hand');
      expect(player.discardPile.any((c) => c.id == 'wraethe_champ'), isFalse);
      expect(player.championsInPlay.any((c) => c.id == 'wraethe_champ'), isFalse,
          reason: 'to-hand does NOT deploy — it is played later');
      expect(player.pendingRecruitRedirect, isNull);
    });
  });

  group('RedirectNextRecruitEffect — serialization', () {
    test('a pending redirect round-trips through GameStateCodec', () {
      final game = gameWithNumeriExhausted();
      final restored = GameStateCodec.decode(GameStateCodec.encode(game));
      final redirect = restored.currentPlayer.pendingRecruitRedirect;

      expect(redirect, isNotNull);
      expect(redirect!.destination, RecruitRedirect.intoPlay);
      expect(redirect.faction, Faction.homodeus);
      expect(redirect.cardType, CardType.champion);
    });
  });
}
