import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Engine behaviour for the four mastery abilities wired 2026-07-01:
/// - Fa Cu Tul (Mastery 20: double your power) — [DoublePowerEffect]
/// - Rue Bo Vai (Mastery 10: you ignore Guard this turn) — [IgnoreGuardThisTurnEffect]
/// - General Decurion (Mastery 20: copy each Homodeus Ally played this turn) —
///   [CopyAllPlayedCardsEffect]
/// - Querry Monk (Mastery 10: also counts as Homodeus/Wraethe/Undergrowth) —
///   [CardModel.countsAsFactions] / [CardModel.countsAsFactionsMasteryThreshold]
void main() {
  group('DoublePowerEffect (Fa Cu Tul)', () {
    const faCuTul = CardModel(
      id: 'fa_cu_tul_the_formless',
      name: 'Fa Cu Tul, The Formless',
      cost: 4,
      faction: Faction.wraethe,
      cardType: CardType.champion,
      shield: 4,
      playEffects: [],
      masteryThreshold: 20,
      activatedAbility: ActivatedAbility(
        effects: [GainPowerEffect(2)],
        masteryThreshold: 20,
        masteryBonusEffects: [DoublePowerEffect()],
      ),
    );

    test('resolving the effect multiplies the power pool by two', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.powerPool = 7;
      const card = CardModel(
        id: 'dbl', name: 'Dbl', cost: 0, playEffects: [DoublePowerEffect()]);
      player.hand.add(card);
      game.playCard('dbl');
      expect(player.powerPool, 14);
    });

    test('doubling a zero pool is a no-op', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.powerPool = 0;
      const card = CardModel(
        id: 'dbl0', name: 'Dbl0', cost: 0, playEffects: [DoublePowerEffect()]);
      player.hand.add(card);
      game.playCard('dbl0');
      expect(player.powerPool, 0);
    });

    test('Exhaust at Mastery 20 gains 2 power THEN doubles the pool', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.championsInPlay.add(faCuTul);
      player.mastery = 20;
      player.powerPool = 3;

      expect(game.useActivatedAbility('fa_cu_tul_the_formless'), true);
      // (3 + 2) * 2 = 10 — the double resolves AFTER the flat +2.
      expect(player.powerPool, 10);
    });

    test('below Mastery 20 the Exhaust only gains 2 power (no double)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.championsInPlay.add(faCuTul);
      player.mastery = 19;
      player.powerPool = 3;

      expect(game.useActivatedAbility('fa_cu_tul_the_formless'), true);
      expect(player.powerPool, 5); // 3 + 2, not doubled
    });
  });

  group('IgnoreGuardThisTurnEffect (Rue Bo Vai)', () {
    const rueBoVai = CardModel(
      id: 'rue_bo_vai_the_transcendent',
      name: 'Rue Bo Vai, The Transcendent',
      cost: 5,
      faction: Faction.wraethe,
      cardType: CardType.champion,
      shield: 4,
      playEffects: [],
      masteryThreshold: 10,
      activatedAbility: ActivatedAbility(
        effects: [GainPowerEffect(4)],
        masteryThreshold: 10,
        masteryBonusEffects: [IgnoreGuardThisTurnEffect()],
      ),
    );

    const guardChampion = CardModel(
      id: 'guard', name: 'Guard', cost: 0, playEffects: [],
      cardType: CardType.champion, shield: 3, hasGuard: true);

    test('effect resolution sets the flag for the current player', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      const card = CardModel(
        id: 'ig', name: 'Ig', cost: 0, playEffects: [IgnoreGuardThisTurnEffect()]);
      player.hand.add(card);
      expect(player.ignoresGuardThisTurn, false);
      game.playCard('ig');
      expect(player.ignoresGuardThisTurn, true);
    });

    test('attackPlayer bypasses an enemy Guard champion when the flag is set', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];
      target.championsInPlay.add(guardChampion);
      attacker.powerPool = 6;
      attacker.ignoresGuardThisTurn = true;

      final before = target.health;
      expect(game.attackPlayer('p1', 6), true);
      expect(target.health, before - 6);
    });

    test('attackPlayer is still blocked by Guard without the flag (regression)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];
      target.championsInPlay.add(guardChampion);
      attacker.powerPool = 6;

      final before = target.health;
      expect(game.attackPlayer('p1', 6), false);
      expect(target.health, before);
    });

    test('Exhaust at Mastery 10 gains 4 power AND sets ignore-Guard', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];
      target.championsInPlay.add(guardChampion);
      attacker.championsInPlay.add(rueBoVai);
      attacker.mastery = 10;

      expect(game.useActivatedAbility('rue_bo_vai_the_transcendent'), true);
      expect(attacker.powerPool, 4);
      expect(attacker.ignoresGuardThisTurn, true);

      final before = target.health;
      expect(game.attackPlayer('p1', 4), true);
      expect(target.health, before - 4);
    });

    test('below Mastery 10 the Exhaust only gains 4 power (Guard still blocks)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      attacker.championsInPlay.add(rueBoVai);
      attacker.mastery = 9;

      expect(game.useActivatedAbility('rue_bo_vai_the_transcendent'), true);
      expect(attacker.powerPool, 4);
      expect(attacker.ignoresGuardThisTurn, false);
    });

    test('the flag clears on the next turn', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.ignoresGuardThisTurn = true;
      game.endTurn();
      expect(player.ignoresGuardThisTurn, false);
    });
  });

  group('CopyAllPlayedCardsEffect (General Decurion)', () {
    const decurion = CardModel(
      id: 'general_decurion',
      name: 'General Decurion',
      cost: 7,
      faction: Faction.homodeus,
      cardType: CardType.champion,
      shield: 7,
      playEffects: [],
      masteryThreshold: 20,
      activatedAbility: ActivatedAbility(
        effects: [GainGemsEffect(3)],
        masteryThreshold: 20,
        masteryBonusEffects: [
          CopyAllPlayedCardsEffect(
            filter: CopyFilter.nonChampion, faction: Faction.homodeus),
        ],
      ),
    );

    const homoAlly1 = CardModel(
      id: 'ha1', name: 'HA1', cost: 0, faction: Faction.homodeus,
      playEffects: [GainGemsEffect(2)]);
    const homoAlly2 = CardModel(
      id: 'ha2', name: 'HA2', cost: 0, faction: Faction.homodeus,
      playEffects: [GainPowerEffect(3)]);
    const orderAlly = CardModel(
      id: 'oa', name: 'OA', cost: 0, faction: Faction.order,
      playEffects: [GainGemsEffect(5)]);

    void seedPlayed(GameService game) {
      final p = game.currentPlayer;
      for (final c in [homoAlly1, homoAlly2, orderAlly]) {
        p.playedThisTurn.add(c);
        p.cardsPlayedThisTurn.add(c);
      }
    }

    test('Mastery 20 Exhaust copies EACH Homodeus ally, not other factions', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      seedPlayed(game);
      player.championsInPlay.add(decurion);
      player.mastery = 20;

      expect(game.useActivatedAbility('general_decurion'), true);
      // Exhaust: +3 gems. Copy HA1 (+2 gems) + HA2 (+3 power). OA (Order) skipped.
      expect(player.gemPool, 5);
      expect(player.powerPool, 3);
    });

    test('a Homodeus CHAMPION played this turn is NOT copied (allies only)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      // A Homodeus CHAMPION (not an ally) with a big play effect, played this turn.
      const homoChamp = CardModel(
        id: 'homo_champ',
        name: 'Homo Champ',
        cost: 0,
        faction: Faction.homodeus,
        cardType: CardType.champion,
        playEffects: [GainGemsEffect(9)],
      );
      player.cardsPlayedThisTurn.add(homoChamp);
      player.championsInPlay.add(homoChamp);
      player.championsInPlay.add(decurion);
      player.mastery = 20;

      expect(game.useActivatedAbility('general_decurion'), true);
      // Only the Exhaust's +3 gems; the Homodeus CHAMPION's +9 is NOT copied
      // (the nonChampion filter excludes it).
      expect(player.gemPool, 3);
    });

    test('below Mastery 20 the Exhaust only gains 3 gems (no copies)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      seedPlayed(game);
      player.championsInPlay.add(decurion);
      player.mastery = 19;

      expect(game.useActivatedAbility('general_decurion'), true);
      expect(player.gemPool, 3);
      expect(player.powerPool, 0);
    });

    test('copying excludes InfinityShardEffect (no spurious mastery/win)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      const shardAlly = CardModel(
        id: 'shard_ally', name: 'Shard Ally', cost: 0, faction: Faction.homodeus,
        playEffects: [InfinityShardEffect()]);
      player.playedThisTurn.add(shardAlly);
      player.cardsPlayedThisTurn.add(shardAlly);
      player.championsInPlay.add(decurion);
      player.mastery = 20; // would be an instant win if the shard were copied

      expect(game.useActivatedAbility('general_decurion'), true);
      expect(game.isGameOver, false);
      expect(player.gemPool, 3); // only the Exhaust's own gems
    });

    test('a matched card that itself copies is skipped (no copy-of-a-copy)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      const copierAlly = CardModel(
        id: 'copier', name: 'Copier', cost: 0, faction: Faction.homodeus,
        playEffects: [
          GainGemsEffect(1),
          CopyPlayedCardEffect(filter: CopyFilter.nonChampion),
        ]);
      player.playedThisTurn.add(copierAlly);
      player.cardsPlayedThisTurn.add(copierAlly);
      player.championsInPlay.add(decurion);
      player.mastery = 20;

      expect(game.useActivatedAbility('general_decurion'), true);
      // Copier is skipped entirely, so its +1 gem is NOT re-applied.
      expect(player.gemPool, 3);
    });
  });

  group('Querry Monk — mastery-gated multi-faction', () {
    const querryMonk = CardModel(
      id: 'querry_monk',
      name: 'Querry Monk',
      cost: 4,
      faction: Faction.order,
      shield: 3,
      playEffects: [DrawCardsEffect(1)],
      masteryThreshold: 10,
      countsAsFactions: [Faction.homodeus, Faction.wraethe, Faction.undergrowth],
      countsAsFactionsMasteryThreshold: 10,
    );

    CardModel trigger(Faction f) => CardModel(
          id: 'trig_${f.name}',
          name: 'Trigger ${f.name}',
          cost: 0,
          faction: f,
          playEffects: const [],
          allyAbility: const [GainPowerEffect(5)],
        );

    test('at Mastery 10 it satisfies a Homodeus ally trigger', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 10;
      player.playedThisTurn.add(querryMonk);
      player.cardsPlayedThisTurn.add(querryMonk);

      final t = trigger(Faction.homodeus);
      player.hand.add(t);
      final before = player.powerPool;
      game.playCard(t.id);
      expect(player.powerPool, before + 5);
    });

    test('at Mastery 10 it also counts as Undergrowth', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 10;
      player.playedThisTurn.add(querryMonk);
      player.cardsPlayedThisTurn.add(querryMonk);

      final t = trigger(Faction.undergrowth);
      player.hand.add(t);
      final before = player.powerPool;
      game.playCard(t.id);
      expect(player.powerPool, before + 5);
    });

    test('below Mastery 10 it is ONLY Order (no Homodeus trigger)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 9;
      player.playedThisTurn.add(querryMonk);
      player.cardsPlayedThisTurn.add(querryMonk);

      final t = trigger(Faction.homodeus);
      player.hand.add(t);
      final before = player.powerPool;
      game.playCard(t.id);
      expect(player.powerPool, before); // no trigger
    });

    test('its own Order faction always triggers Order allies (any mastery)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 0;
      player.playedThisTurn.add(querryMonk);
      player.cardsPlayedThisTurn.add(querryMonk);

      final t = trigger(Faction.order);
      player.hand.add(t);
      final before = player.powerPool;
      game.playCard(t.id);
      expect(player.powerPool, before + 5);
    });

    test('at Mastery 10 it counts toward a Homodeus faction-scaling effect', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 10;
      player.playedThisTurn.add(querryMonk);
      player.cardsPlayedThisTurn.add(querryMonk);

      // Scale power per Homodeus card played this turn.
      const scaler = CardModel(
        id: 'homo_scaler',
        name: 'Homo Scaler',
        cost: 0,
        faction: Faction.homodeus,
        playEffects: [
          ScalingResourceEffect(
            resource: ScalingResource.power,
            condition: ScalingCondition.perFactionCardPlayedThisTurn,
            faction: Faction.homodeus,
          ),
        ],
      );
      player.hand.add(scaler);
      final before = player.powerPool;
      game.playCard('homo_scaler');
      // Querry Monk counts as Homodeus at mastery 10 → +1 (the scaler itself is
      // excluded as the in-flight source).
      expect(player.powerPool, before + 1);
    });

    test('below Mastery 10 it does NOT count toward Homodeus scaling', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 0;
      player.playedThisTurn.add(querryMonk);
      player.cardsPlayedThisTurn.add(querryMonk);

      const scaler = CardModel(
        id: 'homo_scaler2',
        name: 'Homo Scaler 2',
        cost: 0,
        faction: Faction.homodeus,
        playEffects: [
          ScalingResourceEffect(
            resource: ScalingResource.power,
            condition: ScalingCondition.perFactionCardPlayedThisTurn,
            faction: Faction.homodeus,
          ),
        ],
      );
      player.hand.add(scaler);
      final before = player.powerPool;
      game.playCard('homo_scaler2');
      expect(player.powerPool, before); // Querry Monk is Order-only here
    });

    test('an ordinary Order card does NOT gain the multi-faction (regression)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.mastery = 10;
      const plainOrder = CardModel(
        id: 'plain_order', name: 'Plain Order', cost: 0, faction: Faction.order,
        playEffects: []);
      player.playedThisTurn.add(plainOrder);
      player.cardsPlayedThisTurn.add(plainOrder);

      final t = trigger(Faction.homodeus);
      player.hand.add(t);
      final before = player.powerPool;
      game.playCard(t.id);
      expect(player.powerPool, before); // plain Order never counts as Homodeus
    });
  });

  // Regression lock for the market/relic instance builders (_instanceOf /
  // _relicInstanceFor), which previously rebuilt CardModel field-by-field and
  // SILENTLY DROPPED newly-added fields — so the querry_monk a player actually
  // recruited from the market never counted as its multi-faction, and a
  // recruited Datic Robes lost its dynamic shield. copyWith must carry them all.
  group('CardModel.copyWith preserves gameplay fields (instance-builder safety)',
      () {
    test('copyWith carries countsAsFactions/threshold + shieldEqualsMastery', () {
      const template = CardModel(
        id: 'querry_monk',
        name: 'Querry Monk',
        cost: 3,
        shield: 3,
        shieldEqualsMastery: true,
        faction: Faction.order,
        countsAsFactions: [
          Faction.homodeus,
          Faction.wraethe,
          Faction.undergrowth,
        ],
        countsAsFactionsMasteryThreshold: 10,
        playEffects: [],
      );
      final inst = template.copyWith(id: 'querry_monk_1');
      expect(inst.id, 'querry_monk_1');
      expect(inst.countsAsFactions,
          [Faction.homodeus, Faction.wraethe, Faction.undergrowth]);
      expect(inst.countsAsFactionsMasteryThreshold, 10);
      expect(inst.shieldEqualsMastery, isTrue);
      expect(inst.shield, 3);
    });
  });
}
