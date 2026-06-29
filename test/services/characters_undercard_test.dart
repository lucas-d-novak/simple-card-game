import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/effect_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Engine Phase 2 wave 5b — structural board-state systems:
/// Family 4 (Characters) + Family 13 (under-card stacking).
void main() {
  // ===========================================================================
  // Characters (Family 4)
  // ===========================================================================
  group('Characters — assignment + isCharacter condition', () {
    test('null character (default): isCharacter resolves false', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      expect(player.character, isNull);

      const card = CardModel(
        id: 'rez_bonus',
        name: 'Rez Bonus',
        cost: 0,
        playEffects: [
          ConditionalEffect(
            condition: GameCondition(
                kind: GameConditionKind.isCharacter,
                character: Character.rez),
            then: [GainPowerEffect(3)],
          ),
        ],
      );
      player.hand.add(card);
      game.playCard('rez_bonus');
      // No character set → condition false → no power.
      expect(player.powerPool, 0);
    });

    test('matching character via constructor: isCharacter resolves true', () {
      final game = GameService(
        playerCount: 2,
        random: Random(7),
        characters: [Character.rez, null],
      );
      final player = game.currentPlayer;
      expect(player.character, Character.rez);

      const card = CardModel(
        id: 'rez_bonus',
        name: 'Rez Bonus',
        cost: 0,
        playEffects: [
          ConditionalEffect(
            condition: GameCondition(
                kind: GameConditionKind.isCharacter,
                character: Character.rez),
            then: [GainPowerEffect(3)],
          ),
        ],
      );
      player.hand.add(card);
      game.playCard('rez_bonus');
      expect(player.powerPool, 3);
    });

    test('non-matching character: isCharacter resolves false', () {
      final game = GameService(
        playerCount: 2,
        random: Random(7),
        characters: [Character.tetra, null],
      );
      final player = game.currentPlayer;

      const card = CardModel(
        id: 'rez_bonus',
        name: 'Rez Bonus',
        cost: 0,
        playEffects: [
          ConditionalEffect(
            condition: GameCondition(
                kind: GameConditionKind.isCharacter,
                character: Character.rez),
            then: [GainPowerEffect(3)],
          ),
        ],
      );
      player.hand.add(card);
      game.playCard('rez_bonus');
      expect(player.powerPool, 0);
    });

    test('setCharacter setter assigns + clears, returns false for unknown id',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      expect(game.setCharacter('p0', Character.chroma), true);
      expect(game.players[0].character, Character.chroma);

      expect(game.setCharacter('p0', null), true);
      expect(game.players[0].character, isNull);

      expect(game.setCharacter('nope', Character.volos), false);
    });

    test('constructor asserts characters length matches playerCount', () {
      expect(
        () => GameService(
          playerCount: 2,
          characters: [Character.rez], // wrong length
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('default (no characters): every player has null character', () {
      final game = GameService(playerCount: 3, random: Random(7));
      for (final p in game.players) {
        expect(p.character, isNull);
      }
    });
  });

  // ===========================================================================
  // Under-card stacking (Family 13)
  // ===========================================================================
  group('Under-card stacking — tuck + shield-per-card', () {
    const champion = CardModel(
      id: 'carmine',
      name: 'Carmine Eclipse',
      cost: 2,
      playEffects: [],
      cardType: CardType.champion,
      shield: 6,
    );

    CardModel ally(String id) => CardModel(
          id: id,
          name: id,
          cost: 1,
          playEffects: const [],
          faction: Faction.wraethe,
        );

    test('tuckUnderChampion moves a hand card under the champion', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.championsInPlay.add(champion);
      player.hand.add(ally('a1'));

      expect(game.tuckUnderChampion('carmine', 'a1'), true);
      expect(player.hand.any((c) => c.id == 'a1'), false);
      expect(player.cardsUnderCount('carmine'), 1);
    });

    test('tuck fails for champion not controlled / card not in hand', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.championsInPlay.add(champion);
      player.hand.add(ally('a1'));

      expect(game.tuckUnderChampion('missing_champ', 'a1'), false);
      expect(game.tuckUnderChampion('carmine', 'not_in_hand'), false);
      expect(player.cardsUnderCount('carmine'), 0);
    });

    test('alliesOnly tuck rejects a champion card from hand', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.championsInPlay.add(champion);
      const champInHand = CardModel(
        id: 'champ_hand',
        name: 'Champ',
        cost: 3,
        playEffects: [],
        cardType: CardType.champion,
      );
      player.hand.add(champInHand);

      expect(game.tuckUnderChampion('carmine', 'champ_hand', alliesOnly: true),
          false);
      expect(player.cardsUnderCount('carmine'), 0);
    });

    test('_effectiveShield reflects +shield per card under (harder to destroy)',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      target.championsInPlay.add(champion); // base shield 6
      // carmine: +2 shield per card under this (self-scoped, sourced from this
      // champion's id).
      target.staticModifiers.add(const StaticModifier(
        kind: StaticModifierKind.shieldPerCardUnder,
        amount: 2,
        sourceChampionId: 'carmine',
      ));
      // Tuck two cards under it: effective shield = 6 + 2*2 = 10.
      target.cardsUnderChampion['carmine'] = [ally('u1'), ally('u2')];

      // 9 power < 10: attack fails.
      attacker.powerPool = 9;
      expect(game.attackChampion('carmine', 'p1'), false);
      expect(target.championsInPlay, hasLength(1));

      // 10 power == effective shield: succeeds.
      attacker.powerPool = 10;
      expect(game.attackChampion('carmine', 'p1'), true);
      expect(target.championsInPlay, isEmpty);
    });

    test('AddStaticModifierEffect stamps sourceChampionId from the champion',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      const carmine = CardModel(
        id: 'carmine2',
        name: 'Carmine',
        cost: 2,
        playEffects: [
          AddStaticModifierEffect(StaticModifier(
            kind: StaticModifierKind.shieldPerCardUnder,
            amount: 2,
          )),
        ],
        cardType: CardType.champion,
        shield: 6,
      );
      player.hand.add(carmine);
      game.playCard('carmine2'); // champion → in play, effect resolves

      final mod = player.staticModifiers.single;
      expect(mod.kind, StaticModifierKind.shieldPerCardUnder);
      expect(mod.sourceChampionId, 'carmine2');
    });

    test('destroying a champion releases under-cards to discard + clears buff',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      target.championsInPlay.add(champion);
      target.staticModifiers.add(const StaticModifier(
        kind: StaticModifierKind.shieldPerCardUnder,
        amount: 2,
        sourceChampionId: 'carmine',
      ));
      target.cardsUnderChampion['carmine'] = [ally('u1'), ally('u2')];

      attacker.powerPool = 10;
      expect(game.attackChampion('carmine', 'p1'), true);

      // Under-cards moved to discard; tuck state + buff cleared.
      expect(target.cardsUnderChampion.containsKey('carmine'), false);
      expect(target.discardPile.where((c) => c.id == 'u1'), hasLength(1));
      expect(target.discardPile.where((c) => c.id == 'u2'), hasLength(1));
      expect(
        target.staticModifiers
            .where((m) => m.kind == StaticModifierKind.shieldPerCardUnder),
        isEmpty,
      );
    });

    // Wave-5b reviewer follow-up: self-banish is a fifth champion-removal path
    // and must also release under-cards, or they orphan + the buff dangles.
    test('a self-banishing champion releases its under-cards + clears buff', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      // A champion that, when played, tucks nothing but self-banishes. We
      // pre-seed under-cards + buff (as if it had tucked earlier), then play it
      // so its SelfBanishEffect resolves through the real engine path.
      const sbChamp = CardModel(
        id: 'sb_champ',
        name: 'Self-Banish Champ',
        cost: 2,
        cardType: CardType.champion,
        shield: 4,
        playEffects: [SelfBanishEffect()],
      );
      player.hand.add(sbChamp);
      // playCard moves it into championsInPlay before resolving effects; pre-seed
      // its under-state keyed by the champion id so self-banish must release it.
      player.staticModifiers.add(const StaticModifier(
        kind: StaticModifierKind.shieldPerCardUnder,
        amount: 2,
        sourceChampionId: 'sb_champ',
      ));
      player.cardsUnderChampion['sb_champ'] = [ally('u1'), ally('u2')];

      game.playCard('sb_champ');

      expect(player.championsInPlay.any((c) => c.id == 'sb_champ'), false);
      expect(game.removedFromGame.any((c) => c.id == 'sb_champ'), true);
      // Under-cards released to discard; dangling buff cleared.
      expect(player.cardsUnderChampion.containsKey('sb_champ'), false);
      expect(player.discardPile.where((c) => c.id == 'u1'), hasLength(1));
      expect(
        player.staticModifiers
            .where((m) => m.kind == StaticModifierKind.shieldPerCardUnder),
        isEmpty,
      );
    });

    test('copyUnderCards re-resolves each under-card play effect', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      const paradigm = CardModel(
        id: 'paradigm',
        name: 'Paradigm',
        cost: 6,
        playEffects: [],
        cardType: CardType.champion,
        shield: 5,
      );
      player.championsInPlay.add(paradigm);
      player.cardsUnderChampion['paradigm'] = const [
        CardModel(id: 'g1', name: 'G1', cost: 1, playEffects: [GainGemsEffect(2)]),
        CardModel(
            id: 'p1', name: 'P1', cost: 1, playEffects: [GainPowerEffect(3)]),
      ];

      expect(game.copyUnderCards('paradigm'), true);
      expect(player.gemPool, 2);
      expect(player.powerPool, 3);
      // Under-cards are NOT consumed.
      expect(player.cardsUnderCount('paradigm'), 2);
    });

    test('copyUnderCards skips InfinityShard (no spurious mastery)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      const paradigm = CardModel(
        id: 'paradigm',
        name: 'Paradigm',
        cost: 6,
        playEffects: [],
        cardType: CardType.champion,
        shield: 5,
      );
      player.championsInPlay.add(paradigm);
      player.cardsUnderChampion['paradigm'] = const [
        CardModel(
            id: 'shard',
            name: 'Shard',
            cost: 0,
            playEffects: [InfinityShardEffect()]),
      ];
      game.copyUnderCards('paradigm');
      expect(player.mastery, 0);
    });

    test('copyUnderCards returns false when champion has no under-cards', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      const paradigm = CardModel(
        id: 'paradigm',
        name: 'Paradigm',
        cost: 6,
        playEffects: [],
        cardType: CardType.champion,
        shield: 5,
      );
      player.championsInPlay.add(paradigm);
      expect(game.copyUnderCards('paradigm'), false);
    });

    test('TuckUnderChampionEffect(centerDeck) tucks top of infinity deck', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      const gene = CardModel(
        id: 'gene_scavs',
        name: 'Gene Scavs',
        cost: 3,
        playEffects: [
          TuckUnderChampionEffect(source: TuckSource.centerDeck),
        ],
        cardType: CardType.champion,
        shield: 8,
      );
      final beforeDeck = game.infinityDeck.length;
      player.hand.add(gene);
      game.playCard('gene_scavs');

      expect(player.cardsUnderCount('gene_scavs'), 1);
      expect(game.infinityDeck.length, beforeDeck - 1);
    });
  });

  // ===========================================================================
  // Codec round-trips + malformed input
  // ===========================================================================
  group('Codec — tuck/copy-under + shieldPerCardUnder', () {
    void roundTrips(CardEffect effect) {
      final json = encodeEffect(effect);
      final back = decodeEffect(json);
      expect(encodeEffect(back), json);
    }

    test('tuckUnderChampion (hand, default) round-trips', () {
      roundTrips(const TuckUnderChampionEffect());
    });

    test('tuckUnderChampion (centerDeck) round-trips', () {
      roundTrips(
          const TuckUnderChampionEffect(source: TuckSource.centerDeck));
    });

    test('tuckUnderChampion (alliesOnly) round-trips', () {
      roundTrips(const TuckUnderChampionEffect(alliesOnly: true));
    });

    test('copyUnderCards round-trips', () {
      roundTrips(const CopyUnderCardsEffect());
    });

    test('shieldPerCardUnder static modifier round-trips with sourceChampionId',
        () {
      roundTrips(const AddStaticModifierEffect(StaticModifier(
        kind: StaticModifierKind.shieldPerCardUnder,
        amount: 2,
        sourceChampionId: 'carmine',
      )));
    });

    test('isCharacter condition with chroma round-trips', () {
      roundTrips(const ConditionalEffect(
        condition: GameCondition(
          kind: GameConditionKind.isCharacter,
          character: Character.chroma,
        ),
        then: [GainGemsEffect(1)],
      ));
    });

    test('unknown tuck source throws FormatException', () {
      expect(
        () => decodeEffect({'type': 'tuckUnderChampion', 'source': 'bogus'}),
        throwsFormatException,
      );
    });

    test('unknown static modifier kind throws FormatException', () {
      expect(
        () => decodeEffect({'type': 'addStaticModifier', 'kind': 'bogus'}),
        throwsFormatException,
      );
    });
  });
}
