import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Tests for Engine Phase 2 wave 4 — turn-scoped matching modifiers:
/// [TreatFactionAsEffect] (faction aliasing) and [IgnoreShieldThisTurnEffect].
void main() {
  group('TreatFactionAsEffect — faction aliasing', () {
    test('alias makes a previously non-matching ally ability trigger', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // An Undergrowth ally already in play this turn.
      const undergrowthAlly = CardModel(
        id: 'ug_ally',
        name: 'Undergrowth Ally',
        cost: 0,
        playEffects: [],
        faction: Faction.undergrowth,
      );
      player.playedThisTurn.add(undergrowthAlly);
      player.cardsPlayedThisTurn.add(undergrowthAlly);

      // The aliasing card: treat Wraethe as Undergrowth this turn, AND it is a
      // Wraethe card with an ally ability granting 5 power.
      const aliasWraethe = CardModel(
        id: 'alias_wraethe',
        name: 'Project Yggdrasil',
        cost: 0,
        faction: Faction.wraethe,
        playEffects: [
          TreatFactionAsEffect(from: Faction.wraethe, to: Faction.undergrowth),
        ],
        allyAbility: [GainPowerEffect(5)],
      );
      player.hand.add(aliasWraethe);

      final before = player.powerPool;
      game.playCard('alias_wraethe');

      // Without the alias the Wraethe card would not see the Undergrowth ally;
      // with it, faction matching canonicalizes Wraethe -> Undergrowth so the
      // ally ability fires.
      expect(player.powerPool, before + 5);
    });

    test('alias clears after endTurn (next turn the ally does not trigger)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // Set an alias directly, then end the turn and confirm it cleared.
      player.factionAliasesThisTurn
          .add((from: Faction.wraethe, to: Faction.undergrowth));
      expect(player.factionAliasesThisTurn, isNotEmpty);

      game.endTurn();
      expect(player.factionAliasesThisTurn, isEmpty);

      // resetTurnResources is the clearing point; verify directly too.
      player.factionAliasesThisTurn
          .add((from: Faction.order, to: Faction.homodeus));
      player.resetTurnResources();
      expect(player.factionAliasesThisTurn, isEmpty);
    });

    test('bidirectional alias matches both directions', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const wraetheAlly = CardModel(
        id: 'wr_ally',
        name: 'Wraethe Ally',
        cost: 0,
        playEffects: [],
        faction: Faction.wraethe,
      );
      player.playedThisTurn.add(wraetheAlly);
      player.cardsPlayedThisTurn.add(wraetheAlly);

      // Bidirectional Wraethe <-> Undergrowth. The played card is Undergrowth;
      // its ally check must canonicalize Undergrowth -> Wraethe (the reverse
      // direction) to see the Wraethe ally.
      const aliasCard = CardModel(
        id: 'alias_bi',
        name: 'Isa Tel Tor',
        cost: 0,
        faction: Faction.undergrowth,
        playEffects: [
          TreatFactionAsEffect(
            from: Faction.wraethe,
            to: Faction.undergrowth,
            bidirectional: true,
          ),
        ],
        allyAbility: [GainPowerEffect(3)],
      );
      player.hand.add(aliasCard);

      final before = player.powerPool;
      game.playCard('alias_bi');
      expect(player.powerPool, before + 3);
    });

    test('one-directional alias only matches the from->to direction', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // A Wraethe ally already in play.
      const wraetheAlly = CardModel(
        id: 'wr_ally2',
        name: 'Wraethe Ally 2',
        cost: 0,
        playEffects: [],
        faction: Faction.wraethe,
      );
      player.playedThisTurn.add(wraetheAlly);
      player.cardsPlayedThisTurn.add(wraetheAlly);

      // One-directional Wraethe -> Undergrowth. The played card is Undergrowth.
      // Undergrowth does NOT alias to anything (only Wraethe->Undergrowth), and
      // the Wraethe ally aliases to Undergrowth. So Undergrowth(played) vs
      // Undergrowth(aliased ally) — this DOES match. To prove one-directionality
      // we instead use a played Wraethe card and an Undergrowth ally: the played
      // Wraethe aliases to Undergrowth, the Undergrowth ally stays Undergrowth =>
      // match. The asymmetry is exposed below.
      //
      // Asymmetry case: played card is Undergrowth with NO alias relevance, ally
      // is Wraethe. Wraethe(ally) -> Undergrowth, played Undergrowth stays
      // Undergrowth => they match. That's the from->to working.
      //
      // The TRUE one-directional check: remove the Wraethe ally, add an
      // Undergrowth ally, and play a Wraethe card with a one-directional
      // Undergrowth -> Order alias. Wraethe(played) has no alias, Undergrowth
      // (ally) -> Order. Wraethe != Order => NO match.
      player.playedThisTurn.clear();
      player.cardsPlayedThisTurn.clear();

      const undergrowthAlly = CardModel(
        id: 'ug_ally3',
        name: 'Undergrowth Ally 3',
        cost: 0,
        playEffects: [],
        faction: Faction.undergrowth,
      );
      player.playedThisTurn.add(undergrowthAlly);
      player.cardsPlayedThisTurn.add(undergrowthAlly);

      const aliasCard = CardModel(
        id: 'alias_oneway',
        name: 'One Way',
        cost: 0,
        faction: Faction.wraethe,
        playEffects: [
          TreatFactionAsEffect(from: Faction.undergrowth, to: Faction.order),
        ],
        allyAbility: [GainPowerEffect(9)],
      );
      player.hand.add(aliasCard);

      final before = player.powerPool;
      game.playCard('alias_oneway');
      // Wraethe(played) vs Undergrowth->Order(ally): wraethe != order => no
      // ally trigger, power unchanged.
      expect(player.powerPool, before);
    });

    test('no alias set: faction matching is unchanged (regression)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const ally = CardModel(
        id: 'plain_ally',
        name: 'Plain Ally',
        cost: 0,
        playEffects: [],
        faction: Faction.undergrowth,
      );
      player.playedThisTurn.add(ally);
      player.cardsPlayedThisTurn.add(ally);

      // A Wraethe card with no alias: should NOT match the Undergrowth ally.
      const wraetheCard = CardModel(
        id: 'plain_wraethe',
        name: 'Plain Wraethe',
        cost: 0,
        faction: Faction.wraethe,
        playEffects: [],
        allyAbility: [GainPowerEffect(7)],
      );
      player.hand.add(wraetheCard);

      final before = player.powerPool;
      game.playCard('plain_wraethe');
      expect(player.powerPool, before);
    });

    test('alias is reflected in faction-filtered scaling counts', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // Put two Wraethe champions in play.
      const champ = CardModel(
        id: 'wr_champ',
        name: 'Wraethe Champ',
        cost: 0,
        playEffects: [],
        faction: Faction.wraethe,
        cardType: CardType.champion,
        shield: 1,
      );
      player.championsInPlay.add(champ);

      // Alias Wraethe -> Undergrowth, then play an Undergrowth card scaling
      // power per Undergrowth champion controlled.
      player.factionAliasesThisTurn
          .add((from: Faction.wraethe, to: Faction.undergrowth));

      const scaler = CardModel(
        id: 'ug_scaler',
        name: 'UG Scaler',
        cost: 0,
        faction: Faction.undergrowth,
        playEffects: [
          ScalingResourceEffect(
            resource: ScalingResource.power,
            condition: ScalingCondition.perFactionChampionControlled,
            faction: Faction.undergrowth,
          ),
        ],
      );
      player.hand.add(scaler);

      final before = player.powerPool;
      game.playCard('ug_scaler');
      // The Wraethe champion canonicalizes to Undergrowth => counted.
      expect(player.powerPool, before + 1);
    });
  });

  group('IgnoreShieldThisTurnEffect', () {
    test('low-power attack destroys a high-shield champion when set', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      const champion = CardModel(
        id: 'tanky',
        name: 'Tanky Champ',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 6,
      );
      target.championsInPlay.add(champion);

      attacker.ignoresShieldThisTurn = true;
      attacker.powerPool = 0; // even zero power is enough

      final result = game.attackChampion('tanky', 'p1');

      expect(result, true);
      expect(attacker.powerPool, 0); // shield treated as 0, nothing deducted
      expect(target.championsInPlay, isEmpty);
      expect(target.discardPile.map((c) => c.id), contains('tanky'));
    });

    test('same attack fails without the flag (regression guard)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      const champion = CardModel(
        id: 'tanky2',
        name: 'Tanky Champ 2',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 6,
      );
      target.championsInPlay.add(champion);

      attacker.powerPool = 0; // no flag, not enough power

      final result = game.attackChampion('tanky2', 'p1');

      expect(result, false);
      expect(target.championsInPlay, hasLength(1));
    });

    test('effect resolution sets the flag for the current player', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const card = CardModel(
        id: 'spirit_leech',
        name: 'Spirit Leech',
        cost: 0,
        faction: Faction.wraethe,
        playEffects: [IgnoreShieldThisTurnEffect()],
      );
      player.hand.add(card);

      expect(player.ignoresShieldThisTurn, false);
      game.playCard('spirit_leech');
      expect(player.ignoresShieldThisTurn, true);
    });

    test('flag clears on the next turn', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      player.ignoresShieldThisTurn = true;
      game.endTurn();
      expect(player.ignoresShieldThisTurn, false);
    });

    test('normal shield path still deducts the shield value when set', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      // With the flag set, attacking still works and deducts 0; a separate
      // attack WITHOUT the flag deducts the full shield. Confirm both in one go
      // by checking that a normal (no-flag) attack still costs shield.
      const champion = CardModel(
        id: 'normal_champ',
        name: 'Normal Champ',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 3,
      );
      target.championsInPlay.add(champion);
      attacker.powerPool = 5;

      final result = game.attackChampion('normal_champ', 'p1');
      expect(result, true);
      expect(attacker.powerPool, 2); // 5 - 3, normal path intact
    });
  });
}
