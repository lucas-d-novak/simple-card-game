import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Coverage for the FLEXIBLE conditional `cannotBeAttacked` (backlog §B3):
/// Drakonarius (controls-named-champion), Raidian (attacker-mastery-relative),
/// Li Hin (self-scoped, always, but still destroyable), plus a regression that
/// Zetta's unconditional player+other-champions aura is unchanged.
void main() {
  CardModel champion(String id, String name, {int shield = 1}) => CardModel(
        id: id,
        name: name,
        cost: 0,
        playEffects: const [],
        cardType: CardType.champion,
        shield: shield,
      );

  StaticModifier selfCannotBeAttacked({
    required String sourceId,
    CannotBeAttackedCondition condition = CannotBeAttackedCondition.always,
    String? conditionCardName,
  }) =>
      StaticModifier(
        kind: StaticModifierKind.cannotBeAttacked,
        sourceChampionId: sourceId,
        cannotBeAttackedScope: CannotBeAttackedScope.selfChampion,
        cannotBeAttackedCondition: condition,
        conditionCardName: conditionCardName,
      );

  group('Drakonarius — cannotBeAttacked while controlling General Decurion', () {
    test('unattackable ONLY while General Decurion is in play', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      target.championsInPlay.add(champion('drakonarius_0', 'Drakonarius', shield: 2));
      target.championsInPlay.add(champion('general_decurion_0', 'General Decurion', shield: 7));
      target.staticModifiers.add(selfCannotBeAttacked(
        sourceId: 'drakonarius_0',
        condition: CannotBeAttackedCondition.controlsNamedChampion,
        conditionCardName: 'General Decurion',
      ));
      attacker.powerPool = 30;

      // Decurion is in play → Drakonarius is protected.
      expect(game.attackChampion('drakonarius_0', 'p1'), false,
          reason: 'protected while General Decurion controlled');
      expect(target.championsInPlay.any((c) => c.id == 'drakonarius_0'), true);
    });

    test('attackable normally when General Decurion is NOT in play', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      target.championsInPlay.add(champion('drakonarius_0', 'Drakonarius', shield: 2));
      target.staticModifiers.add(selfCannotBeAttacked(
        sourceId: 'drakonarius_0',
        condition: CannotBeAttackedCondition.controlsNamedChampion,
        conditionCardName: 'General Decurion',
      ));
      attacker.powerPool = 30;

      // No General Decurion → the condition is inactive → Drakonarius is a
      // normal champion (power 30 >= health 2).
      expect(game.attackChampion('drakonarius_0', 'p1'), true,
          reason: 'attackable when General Decurion absent');
      expect(target.championsInPlay.any((c) => c.id == 'drakonarius_0'), false);
    });

    test('self-scope does NOT protect the owning player', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      target.championsInPlay.add(champion('drakonarius_0', 'Drakonarius', shield: 2));
      target.championsInPlay.add(champion('general_decurion_0', 'General Decurion', shield: 7));
      target.staticModifiers.add(selfCannotBeAttacked(
        sourceId: 'drakonarius_0',
        condition: CannotBeAttackedCondition.controlsNamedChampion,
        conditionCardName: 'General Decurion',
      ));
      attacker.powerPool = 30;

      final before = target.health;
      // General Decurion has no guard here, so the player is directly attackable
      // — a self-scoped champion protection never shields the player.
      expect(game.attackPlayer('p1', 5), true);
      expect(target.health, lessThan(before));
    });

    test('playing Drakonarius stamps the conditional modifier with all fields',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final p = game.currentPlayer;
      p.hand.add(const CardModel(
        id: 'drakonarius',
        name: 'Drakonarius',
        cost: 6,
        cardType: CardType.champion,
        shield: 2,
        playEffects: [
          AddStaticModifierEffect(StaticModifier(
            kind: StaticModifierKind.cannotBeAttacked,
            cannotBeAttackedScope: CannotBeAttackedScope.selfChampion,
            cannotBeAttackedCondition:
                CannotBeAttackedCondition.controlsNamedChampion,
            conditionCardName: 'General Decurion',
          )),
        ],
      ));

      expect(game.playCard('drakonarius'), true);
      final m = p.staticModifiers
          .singleWhere((m) => m.kind == StaticModifierKind.cannotBeAttacked);
      expect(m.sourceChampionId, 'drakonarius',
          reason: 'stamped with the source champion id');
      expect(m.cannotBeAttackedScope, CannotBeAttackedScope.selfChampion);
      expect(m.cannotBeAttackedCondition,
          CannotBeAttackedCondition.controlsNamedChampion);
      expect(m.conditionCardName, 'General Decurion');
    });
  });

  group('Raidian — cannotBeAttacked by lower-mastery players', () {
    GameService setup({required int ownerMastery}) {
      final game = GameService(playerCount: 2, random: Random(7));
      final target = game.players[1];
      target.mastery = ownerMastery;
      target.championsInPlay.add(champion('raidian_0', 'Raidian', shield: 3));
      target.staticModifiers.add(selfCannotBeAttacked(
        sourceId: 'raidian_0',
        condition: CannotBeAttackedCondition.attackerMasteryLessThanOwner,
      ));
      return game;
    }

    test('blocked when the attacker has LESS mastery', () {
      final game = setup(ownerMastery: 10);
      final attacker = game.currentPlayer;
      attacker.mastery = 5;
      attacker.powerPool = 30;

      expect(game.attackChampion('raidian_0', 'p1'), false,
          reason: 'attacker mastery 5 < owner mastery 10');
      expect(game.players[1].championsInPlay.any((c) => c.id == 'raidian_0'),
          true);
    });

    test('attackable by an EQUAL-mastery attacker', () {
      final game = setup(ownerMastery: 10);
      final attacker = game.currentPlayer;
      attacker.mastery = 10;
      attacker.powerPool = 30;

      expect(game.attackChampion('raidian_0', 'p1'), true,
          reason: 'equal mastery is not "less than"');
      expect(game.players[1].championsInPlay.any((c) => c.id == 'raidian_0'),
          false);
    });

    test('attackable by a HIGHER-mastery attacker', () {
      final game = setup(ownerMastery: 10);
      final attacker = game.currentPlayer;
      attacker.mastery = 20;
      attacker.powerPool = 30;

      expect(game.attackChampion('raidian_0', 'p1'), true);
      expect(game.players[1].championsInPlay.any((c) => c.id == 'raidian_0'),
          false);
    });
  });

  group('Li Hin — cannot be attacked, but can still be destroyed', () {
    test('a normal attackChampion is blocked', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      target.championsInPlay.add(champion('li_hin_0', 'Li Hin', shield: 1));
      target.staticModifiers.add(selfCannotBeAttacked(sourceId: 'li_hin_0'));
      attacker.powerPool = 30;

      expect(game.attackChampion('li_hin_0', 'p1'), false);
      expect(target.championsInPlay.any((c) => c.id == 'li_hin_0'), true);
    });

    test('DestroyChampionEffect (destroyChampion) STILL destroys it', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final target = game.players[1];

      target.championsInPlay.add(champion('li_hin_0', 'Li Hin', shield: 1));
      target.staticModifiers.add(selfCannotBeAttacked(sourceId: 'li_hin_0'));

      // No power spent; the cannotBeAttacked gate does not apply to effect-based
      // destruction.
      expect(game.destroyChampion('li_hin_0', 'p1'), true);
      expect(target.championsInPlay.any((c) => c.id == 'li_hin_0'), false);
      expect(target.discardPile.any((c) => c.id == 'li_hin_0'), true);
    });

    test('self-scope does not shield the owning player from direct attacks', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      target.championsInPlay.add(champion('li_hin_0', 'Li Hin', shield: 1));
      target.staticModifiers.add(selfCannotBeAttacked(sourceId: 'li_hin_0'));
      attacker.powerPool = 30;

      final before = target.health;
      expect(game.attackPlayer('p1', 5), true);
      expect(target.health, lessThan(before));
    });
  });

  group('Zetta — unconditional aura unchanged (regression)', () {
    test('default cannotBeAttacked modifier is player+other-champions / always',
        () {
      const m = StaticModifier(kind: StaticModifierKind.cannotBeAttacked);
      expect(m.cannotBeAttackedScope,
          CannotBeAttackedScope.playerAndOtherChampions);
      expect(m.cannotBeAttackedCondition, CannotBeAttackedCondition.always);
      expect(m.conditionCardName, isNull);
    });

    test('protects the player AND other champions, source stays attackable', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      target.championsInPlay.add(champion('zetta', 'Zetta', shield: 1));
      target.championsInPlay.add(champion('other', 'Other', shield: 1));
      target.staticModifiers.add(const StaticModifier(
        kind: StaticModifierKind.cannotBeAttacked,
        sourceChampionId: 'zetta',
      ));
      attacker.powerPool = 30;

      expect(game.attackPlayer('p1', 5), false, reason: 'player protected');
      expect(game.attackChampion('other', 'p1'), false,
          reason: 'other champion protected');
      expect(game.attackChampion('zetta', 'p1'), true,
          reason: 'source champion itself stays attackable');
    });
  });
}
