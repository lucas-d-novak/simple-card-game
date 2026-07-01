import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/card_serialization.dart';
import 'package:simple_card_game/data/database/game_state_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/models/player_state.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Multiplayer serialization — GameService + PlayerState round-trip fidelity.

/// Snapshot of a player's observable state for structural comparison.
Map<String, dynamic> _playerSig(PlayerState p) => {
      'id': p.id,
      'name': p.name,
      'character': p.character?.name,
      'health': p.health,
      'mastery': p.mastery,
      'gemPool': p.gemPool,
      'powerPool': p.powerPool,
      'unblockedDamageThisTurn': p.unblockedDamageThisTurn,
      'ignoresShieldThisTurn': p.ignoresShieldThisTurn,
      'relicOptions': p.relicOptions.map((c) => c.id).toList(),
      'relicRecruited': p.relicRecruited,
      'hand': p.hand.map((c) => c.id).toList(),
      'drawPile': p.drawPile.map((c) => c.id).toList(),
      'discardPile': p.discardPile.map((c) => c.id).toList(),
      'playedThisTurn': p.playedThisTurn.map((c) => c.id).toList(),
      'fastPlayedThisTurn': p.fastPlayedThisTurn.map((c) => c.id).toList(),
      'championsInPlay': p.championsInPlay.map((c) => c.id).toList(),
      'cardsUnderChampion': {
        for (final e in p.cardsUnderChampion.entries)
          e.key: e.value.map((c) => c.id).toList(),
      },
      'activatedChampions': p.activatedChampions.toList()..sort(),
      'exhaustedChampions': p.exhaustedChampions.toList()..sort(),
      'cardsPlayedThisTurn': p.cardsPlayedThisTurn.map((c) => c.id).toList(),
      'claimedDestinies': p.claimedDestinies.map((c) => c.id).toList(),
      'exhaustedDestinies': p.exhaustedDestinies.toList()..sort(),
      'destinyClaimCount': p.destinyClaimCount,
      'destinyClaimGrants': p.destinyClaimGrants,
      'staticModifiers': p.staticModifiers
          .map((m) => '${m.kind.name}:${m.amount}:${m.faction?.name}:'
              '${m.cardType?.name}:${m.sourceChampionId}')
          .toList(),
      'factionAliasesThisTurn': p.factionAliasesThisTurn
          .map((a) => '${a.from.name}->${a.to.name}')
          .toList(),
    };

Map<String, dynamic> _gameSig(GameService g) => {
      'players': g.players.map(_playerSig).toList(),
      'centerRow': g.centerRow.map((c) => c.id).toList(),
      'infinityDeck': g.infinityDeck.map((c) => c.id).toList(),
      'removedFromGame': g.removedFromGame.map((c) => c.id).toList(),
      'destinyRow': g.destinyRow.map((c) => c.id).toList(),
      'destinyDeck': g.destinyDeck.map((c) => c.id).toList(),
      'currentPlayerIndex': g.currentPlayerIndex,
      'turnNumber': g.turnNumber,
      'isGameOver': g.isGameOver,
      'winnerId': g.winnerId,
    };

void main() {
  group('CardModel serialization', () {
    test('round-trips a complex card through JSON', () {
      const card = CardModel(
        id: 'complex',
        name: 'Complex Card',
        cost: 5,
        faction: Faction.wraethe,
        cardType: CardType.champion,
        shield: 4,
        hasGuard: true,
        countsAsAllFactions: true,
        masteryThreshold: 15,
        masteryReplaces: true,
        playEffects: [GainPowerEffect(2), DrawCardsEffect(1)],
        allyAbility: [GainGemsEffect(1)],
        masteryBonus: [GainPowerEffect(5)],
        activatedAbility: ActivatedAbility(
          effects: [GainGemsEffect(2)],
          masteryThreshold: 20,
          masteryBonusEffects: [DrawCardsEffect(2)],
        ),
      );
      final back = cardModelFromJson(cardModelToJson(card));
      expect(back.id, card.id);
      expect(back.name, card.name);
      expect(back.cost, card.cost);
      expect(back.faction, card.faction);
      expect(back.cardType, card.cardType);
      expect(back.shield, card.shield);
      expect(back.hasGuard, true);
      expect(back.countsAsAllFactions, true);
      expect(back.masteryThreshold, 15);
      expect(back.masteryReplaces, true);
      expect(back.playEffects, hasLength(2));
      expect(back.allyAbility, hasLength(1));
      expect(back.masteryBonus, hasLength(1));
      expect(back.activatedAbility, isNotNull);
      expect(back.activatedAbility!.masteryThreshold, 20);
      expect(back.activatedAbility!.masteryBonusEffects, hasLength(1));
    });
  });

  group('GameStateCodec full round-trip', () {
    test('fresh game survives encode -> JSON string -> decode unchanged', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final before = _gameSig(game);

      final json = jsonEncode(GameStateCodec.encode(game));
      final restored =
          GameStateCodec.decode(jsonDecode(json) as Map<String, dynamic>);

      expect(_gameSig(restored), before);
    });

    test('mid-game state (plays, buys, champion, exhaust, end turn) round-trips',
        () {
      final game = GameService(playerCount: 3, random: Random(7));

      // Player 0 takes a varied turn.
      game.playAllCards();
      // Buy whatever is affordable in the center row.
      for (final c in List.of(game.centerRow)) {
        if (game.currentPlayer.gemPool >= c.cost) {
          game.buyCard(c.id);
          break;
        }
      }
      // Inject + deploy a champion with an activated ability, then exhaust it.
      const champ = CardModel(
        id: 'inject_champ',
        name: 'Inject Champ',
        cost: 0,
        cardType: CardType.champion,
        shield: 3,
        playEffects: [],
        activatedAbility: ActivatedAbility(effects: [GainPowerEffect(2)]),
      );
      game.currentPlayer.hand.add(champ);
      game.playCard('inject_champ');
      game.useActivatedAbility('inject_champ');
      // Give the player a persistent modifier + a turn-scoped alias to exercise
      // those fields.
      game.currentPlayer.staticModifiers.add(const StaticModifier(
          kind: StaticModifierKind.shieldBuff, amount: 2));
      game.currentPlayer.factionAliasesThisTurn
          .add((from: Faction.wraethe, to: Faction.undergrowth));
      // Tuck a card under the champion.
      game.currentPlayer.cardsUnderChampion['inject_champ'] = [
        const CardModel(id: 'tucked', name: 'Tucked', cost: 1, playEffects: []),
      ];
      // Warp a card from the center row so fastPlayedThisTurn is non-empty and
      // its round-trip is exercised.
      game.centerRow.add(const CardModel(
          id: 'warp_me', name: 'Warp Me', cost: 1, playEffects: []));
      game.fastPlayFromCenter('warp_me');

      final before = _gameSig(game);

      final json = jsonEncode(GameStateCodec.encode(game));
      final restored =
          GameStateCodec.decode(jsonDecode(json) as Map<String, dynamic>);

      expect(_gameSig(restored), before,
          reason: 'every zone + per-turn + persistent field must round-trip');
      // The exhausted champion survived.
      expect(restored.players[0].exhaustedChampions, contains('inject_champ'));
      // The under-card survived.
      expect(restored.players[0].cardsUnderChampion['inject_champ']!.single.id,
          'tucked');
      // The fast-played/warped card survived (kept visible this turn).
      expect(restored.players[0].fastPlayedThisTurn.map((c) => c.id),
          contains('warp_me'));
      // The static modifier survived.
      expect(restored.players[0].staticModifiers.single.kind,
          StaticModifierKind.shieldBuff);

      // The action log — including each entry's optional cardId (used by the
      // networked playback overlay) — round-trips through the codec.
      final origWithCard =
          game.actionLog.where((e) => e.cardId != null).toList();
      expect(origWithCard, isNotEmpty,
          reason: 'playing/buying cards should log entries carrying a cardId');
      expect(restored.actionLog.length, game.actionLog.length);
      for (var i = 0; i < game.actionLog.length; i++) {
        expect(restored.actionLog[i].cardId, game.actionLog[i].cardId,
            reason: 'log entry $i cardId must round-trip');
        expect(restored.actionLog[i].message, game.actionLog[i].message);
      }
    });

    test('relic options + recruited flag round-trip (set aside and recruited)',
        () {
      final relicCards = {
        'praetorian_01': const CardModel(
            id: 'praetorian_01', name: 'praetorian_01', cost: 0, playEffects: []),
        'praetorian_02': const CardModel(
            id: 'praetorian_02', name: 'praetorian_02', cost: 0, playEffects: []),
        'datic_robes': const CardModel(
            id: 'datic_robes', name: 'datic_robes', cost: 0, playEffects: []),
        'terminal_crescents': const CardModel(
            id: 'terminal_crescents',
            name: 'terminal_crescents',
            cost: 0,
            playEffects: []),
      };
      final game = GameService(
        playerCount: 2,
        random: Random(7),
        characters: [Character.decima, Character.tetra],
        relicCards: relicCards,
      );
      // p0 still has both options set aside; p1 recruits one.
      game.currentPlayerIndex = 1;
      game.players[1].mastery = 12;
      game.recruitRelic(game.players[1].relicOptions.first.id);
      game.currentPlayerIndex = 0;

      final before = _gameSig(game);
      final restored = GameStateCodec.decode(
          jsonDecode(jsonEncode(GameStateCodec.encode(game)))
              as Map<String, dynamic>);

      expect(_gameSig(restored), before);
      expect(restored.players[0].relicOptions, hasLength(2));
      expect(restored.players[0].relicRecruited, isFalse);
      expect(restored.players[1].relicOptions, isEmpty);
      expect(restored.players[1].relicRecruited, isTrue);
    });

    test('restored game can continue playing (endTurn advances correctly)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.playAllCards();

      final restored = GameStateCodec.decode(
          jsonDecode(jsonEncode(GameStateCodec.encode(game)))
              as Map<String, dynamic>);

      final idxBefore = restored.currentPlayerIndex;
      restored.endTurn();
      expect(restored.currentPlayerIndex, (idxBefore + 1) % 2);
      // The next player can draw/act — hand was dealt on endTurn.
      expect(restored.currentPlayer.hand, isNotEmpty);
    });

    test('card dictionary de-duplicates: payload references shared cards by id',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final encoded = GameStateCodec.encode(game);
      final dict = (encoded['cards'] as Map);
      // The starter deck has 7 identical-named Crystals per player but each has
      // a UNIQUE id, so every distinct card appears exactly once in the dict.
      final allRefIds = <String>{
        for (final p in (encoded['players'] as List))
          ...((p as Map)['drawPile'] as List).cast<String>(),
      };
      for (final id in allRefIds) {
        expect(dict.containsKey(id), true,
            reason: 'every referenced id must exist once in the card dict');
      }
    });

    test('destiny state (claimed zone, supply rows, counters) round-trips', () {
      const passive = CardModel(
        id: 'one_mind_one_army',
        name: 'One Mind, One Army',
        cost: 5,
        playEffects: [
          AddStaticModifierEffect(
            StaticModifier(
              kind: StaticModifierKind.shieldBuff,
              amount: 2,
              cardType: CardType.champion,
            ),
          ),
        ],
      );
      const activated = CardModel(
        id: 'war_bound',
        name: 'War Bound',
        cost: 5,
        playEffects: [],
        activatedAbility: ActivatedAbility(
          effects: [GainPowerEffect(4)],
        ),
      );
      const spare = CardModel(
          id: 'spare_destiny', name: 'Spare', cost: 5, playEffects: []);

      final game = GameService(
        playerCount: 2,
        random: Random(7),
        destinySupply: [passive, activated, spare],
      );
      final p = game.currentPlayer;
      p.mastery = 10;
      // Claim the passive (applies a static modifier) and grant + use the
      // activated one so every destiny field is exercised.
      expect(game.claimDestiny('one_mind_one_army'), isTrue);
      p.destinyClaimGrants += 1; // simulate a cascade grant
      expect(game.claimDestiny('war_bound'), isTrue);
      expect(game.useDestinyAbility('war_bound'), isTrue);

      expect(p.claimedDestinies, hasLength(2));
      expect(p.exhaustedDestinies, contains('war_bound'));
      expect(game.destinyRow, hasLength(1)); // spare remains face-up

      final json = jsonEncode(GameStateCodec.encode(game));
      final restored =
          GameStateCodec.decode(jsonDecode(json) as Map<String, dynamic>);

      expect(_gameSig(restored), _gameSig(game));
      // Spot-check the destiny-specific fields survived.
      final rp = restored.currentPlayer;
      expect(rp.claimedDestinies.map((c) => c.id),
          ['one_mind_one_army', 'war_bound']);
      expect(rp.exhaustedDestinies, contains('war_bound'));
      expect(rp.destinyClaimCount, 2);
      expect(rp.destinyClaimGrants, 1);
      expect(restored.destinyRow.map((c) => c.id), ['spare_destiny']);
      // The claimed activated destiny is still usable after restore (next turn).
      restored.currentPlayer.exhaustedDestinies.clear();
      restored.currentPlayer.powerPool = 0;
      expect(restored.useDestinyAbility('war_bound'), isTrue);
      expect(restored.currentPlayer.powerPool, 4);
    });
  });
}
