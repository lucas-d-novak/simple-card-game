import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Engine Phase 2 wave 5a — Family 11 (static board-wide modifiers).
void main() {
  group('AddStaticModifierEffect — shield buff (player damage reduction)', () {
    // Owner combat model (backlog §E): a champion-granted shieldBuff (e.g.
    // praetorian_02) is a standing buff to the PLAYER's per-hit damage
    // reduction while that champion is in play — NOT a buff to any champion's
    // destroy threshold. Champions have HEALTH = their printed `shield` value.
    test('a champion-sourced shield buff does NOT raise a champion destroy '
        'threshold (champion health is its printed value only)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      const champion = CardModel(
        id: 'guard',
        name: 'Guard',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 2,
      );
      const praetorian = CardModel(
        id: 'praetorian',
        name: 'Praetorian',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 5,
      );
      target.championsInPlay.addAll([champion, praetorian]);
      // Praetorian grants a +3 shield buff to the PLAYER while in play.
      target.staticModifiers.add(const StaticModifier(
          kind: StaticModifierKind.shieldBuff,
          amount: 3,
          sourceChampionId: 'praetorian'));

      // The guard champion's health is just its printed value (2). The buff does
      // NOT add to it — 2 power destroys it.
      attacker.powerPool = 2;
      expect(game.attackChampion('guard', 'p1'), true);
      expect(attacker.powerPool, 0);
      expect(target.championsInPlay.any((c) => c.id == 'guard'), false);
    });

    test('a champion-sourced shield buff reduces direct damage to the PLAYER, '
        'and stops the moment the champion leaves play', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      const praetorian = CardModel(
        id: 'praetorian',
        name: 'Praetorian',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 3,
      );
      target.championsInPlay.add(praetorian);
      target.staticModifiers.add(const StaticModifier(
          kind: StaticModifierKind.shieldBuff,
          amount: 4,
          sourceChampionId: 'praetorian'));

      // A 10-damage attack is reduced by 4 → 6 lands.
      attacker.powerPool = 40;
      final before = target.health;
      expect(game.attackPlayer('p1', 10), true);
      expect(target.health, before - 6);

      // Destroy the Praetorian (health 3): its shield buff is dropped.
      expect(game.attackChampion('praetorian', 'p1'), true);
      // Now a 10-damage attack lands in full.
      final before2 = target.health;
      expect(game.attackPlayer('p1', 10), true);
      expect(target.health, before2 - 10);
    });

    test('effect resolution appends the modifier to the player', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const card = CardModel(
        id: 'one_mind_one_army',
        name: 'One Mind One Army',
        cost: 0,
        cardType: CardType.champion,
        shield: 4,
        playEffects: [
          AddStaticModifierEffect(StaticModifier(
            kind: StaticModifierKind.shieldBuff,
            amount: 1,
          )),
        ],
      );
      player.hand.add(card);

      expect(player.staticModifiers, isEmpty);
      game.playCard('one_mind_one_army');
      expect(player.staticModifiers, hasLength(1));
      expect(player.staticModifiers.first.kind, StaticModifierKind.shieldBuff);
    });

    test(
        'champion re-activation does NOT duplicate its static modifier '
        '(no unbounded buff growth)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const champ = CardModel(
        id: 'buff_champ',
        name: 'Buff Champ',
        cost: 0,
        cardType: CardType.champion,
        shield: 4,
        playEffects: [
          AddStaticModifierEffect(StaticModifier(
            kind: StaticModifierKind.shieldBuff,
            amount: 1,
          )),
        ],
      );
      player.hand.add(champ);

      // Deploy: modifier added once.
      game.playCard('buff_champ');
      expect(player.staticModifiers, hasLength(1));

      // Simulate later turns: the champion's free activation re-resolves its
      // playEffects. The modifier must NOT be re-appended each time.
      game.currentPlayer.activatedChampions.clear();
      game.activateChampion('buff_champ');
      expect(player.staticModifiers, hasLength(1),
          reason: 'modifier deduped on re-activation');

      game.currentPlayer.activatedChampions.clear();
      game.activateChampion('buff_champ');
      expect(player.staticModifiers, hasLength(1),
          reason: 'still exactly one after a second re-activation');
    });

    test('static modifier is NOT cleared by endTurn (rest-of-game lifetime)',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.staticModifiers.add(
          const StaticModifier(kind: StaticModifierKind.cannotBeAttacked));
      game.endTurn();
      expect(player.staticModifiers, hasLength(1));
    });
  });

  group('AddStaticModifierEffect — card cost reduction', () {
    test('cost reduction lowers buy cost, floored at 1', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      // Inject a known card into the center row.
      const market = CardModel(
        id: 'expensive',
        name: 'Expensive',
        cost: 5,
        playEffects: [],
      );
      game.centerRow.insert(0, market);
      player.staticModifiers.add(const StaticModifier(
        kind: StaticModifierKind.cardCostReduction,
        amount: 3,
      ));

      player.gemPool = 2; // 5 - 3 = 2 effective cost
      expect(game.buyCard('expensive'), true);
      expect(player.gemPool, 0);
    });

    test('cost reduction never drops below 1', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const market = CardModel(
        id: 'cheap',
        name: 'Cheap',
        cost: 2,
        playEffects: [],
      );
      game.centerRow.insert(0, market);
      player.staticModifiers.add(const StaticModifier(
        kind: StaticModifierKind.cardCostReduction,
        amount: 10,
      ));

      // Effective cost floored at 1: 0 gems can't buy.
      player.gemPool = 0;
      expect(game.buyCard('cheap'), false);
      player.gemPool = 1;
      expect(game.buyCard('cheap'), true);
      expect(player.gemPool, 0);
    });

    test('cost reduction applies to recruitFromCenter (non-free)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const market = CardModel(
        id: 'rec',
        name: 'Rec',
        cost: 4,
        playEffects: [],
      );
      game.centerRow.insert(0, market);
      player.staticModifiers.add(const StaticModifier(
        kind: StaticModifierKind.cardCostReduction,
        amount: 2,
      ));

      player.gemPool = 2; // 4 - 2
      expect(game.recruitFromCenter('rec', free: false), true);
      expect(player.gemPool, 0);
    });
  });

  group('AddStaticModifierEffect — cannotBeAttacked', () {
    test('blocks direct attack on the protected player', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      target.staticModifiers.add(
          const StaticModifier(kind: StaticModifierKind.cannotBeAttacked));
      attacker.powerPool = 10;

      final before = target.health;
      expect(game.attackPlayer('p1', 5), false);
      expect(target.health, before);
      expect(attacker.powerPool, 10);
    });

    test('blocks attacking the protected player\'s champions too', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      const champ = CardModel(
        id: 'protected_champ',
        name: 'Protected Champ',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 1,
      );
      target.championsInPlay.add(champ);
      target.staticModifiers.add(
          const StaticModifier(kind: StaticModifierKind.cannotBeAttacked));
      attacker.powerPool = 5;

      expect(game.attackChampion('protected_champ', 'p1'), false);
      expect(target.championsInPlay, hasLength(1));
    });

    test('the SOURCE champion (Zetta) is itself attackable; its OTHER champions '
        'are protected', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      const zetta = CardModel(
        id: 'zetta',
        name: 'Zetta',
        cost: 5,
        playEffects: [],
        cardType: CardType.champion,
        shield: 1,
      );
      const other = CardModel(
        id: 'other_champ',
        name: 'Other',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 1,
      );
      target.championsInPlay.addAll([zetta, other]);
      // Zetta's modifier is stamped with its own champion id (as the engine does
      // when a champion source applies it).
      target.staticModifiers.add(const StaticModifier(
        kind: StaticModifierKind.cannotBeAttacked,
        sourceChampionId: 'zetta',
      ));
      attacker.powerPool = 5;

      // The OTHER champion is protected...
      expect(game.attackChampion('other_champ', 'p1'), false);
      // ...but Zetta ITSELF can be attacked ("your OTHER champions").
      expect(game.attackChampion('zetta', 'p1'), true);
      expect(target.championsInPlay.any((c) => c.id == 'zetta'), false,
          reason: 'Zetta was destroyed by the attack');
    });

    test('when the source champion (Zetta) leaves play, its cannotBeAttacked '
        'aura is removed from the owner AND their other champions', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      const zetta = CardModel(
        id: 'zetta',
        name: 'Zetta',
        cost: 5,
        playEffects: [],
        cardType: CardType.champion,
        shield: 1,
      );
      const other = CardModel(
        id: 'other_champ',
        name: 'Other',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 1,
      );
      target.championsInPlay.addAll([zetta, other]);
      target.staticModifiers.add(const StaticModifier(
        kind: StaticModifierKind.cannotBeAttacked,
        sourceChampionId: 'zetta',
      ));
      attacker.powerPool = 30;

      // While Zetta is in play the aura is active: the OTHER champion and the
      // player are both protected.
      expect(game.attackChampion('other_champ', 'p1'), false,
          reason: 'other champion protected while Zetta is in play');
      final healthBefore = target.health;
      expect(game.attackPlayer('p1', 5), false,
          reason: 'player protected while Zetta is in play');
      expect(target.health, healthBefore);

      // Destroy Zetta (it is itself attackable).
      expect(game.attackChampion('zetta', 'p1'), true);
      expect(target.championsInPlay.any((c) => c.id == 'zetta'), false);

      // The aura must vanish with its source — nothing keyed to Zetta lingers.
      expect(
        target.staticModifiers
            .any((m) => m.kind == StaticModifierKind.cannotBeAttacked),
        false,
        reason: 'cannotBeAttacked aura removed when Zetta left play',
      );
      // ...so the other champion and the player are attackable again.
      expect(game.attackChampion('other_champ', 'p1'), true,
          reason: 'other champion attackable after Zetta gone');
      expect(target.championsInPlay.any((c) => c.id == 'other_champ'), false);
      expect(game.attackPlayer('p1', 5), true,
          reason: 'player attackable after Zetta gone');
      expect(target.health, lessThan(healthBefore));
    });

    test('eliminating a player all-at-once clears their champion-sourced static '
        'modifiers (elimination path, not champion-by-champion)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      // A champion granting a NON-attack-blocking modifier (so the lethal attack
      // is not itself blocked), keyed to its source champion.
      const auraChamp = CardModel(
        id: 'aura_champ',
        name: 'Aura Champ',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 0,
      );
      target.championsInPlay.add(auraChamp);
      target.staticModifiers.add(const StaticModifier(
        kind: StaticModifierKind.cardCostReduction,
        amount: 1,
        sourceChampionId: 'aura_champ',
      ));

      // Reduce the target to 0 health in one blow → elimination cleanup runs
      // without ever destroying the champion individually.
      attacker.powerPool = target.health;
      expect(game.attackPlayer('p1', target.health), true);
      expect(target.isEliminated, true);

      // The eliminated player's board state — including champion-sourced static
      // modifiers — must be fully cleared, not left dangling.
      expect(target.championsInPlay, isEmpty);
      expect(target.staticModifiers, isEmpty,
          reason: 'eliminated player retained a stale champion-sourced modifier');
    });

    test('a PASSIVE-only champion applies its cannotBeAttacked aura on '
        'enter-play — no activateChampion call needed', () {
      // Underpins the UI change (passive-only champions show NO Activate/Exhaust
      // button): the aura must already be live the moment the champion enters
      // play, since there is no button to activate it.
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const zetta = CardModel(
        id: 'zetta_the_encryptor',
        name: 'Zetta the Encryptor',
        cost: 5,
        cardType: CardType.champion,
        shield: 2,
        playEffects: [
          AddStaticModifierEffect(
              StaticModifier(kind: StaticModifierKind.cannotBeAttacked)),
        ],
        // No activatedAbility — this is a pure passive aura champion.
      );
      player.hand.add(zetta);

      expect(player.staticModifiers, isEmpty);
      // Deploy from hand — NO activateChampion / useActivatedAbility call.
      expect(game.playCard('zetta_the_encryptor'), true);
      expect(
        player.staticModifiers
            .where((m) => m.kind == StaticModifierKind.cannotBeAttacked),
        hasLength(1),
        reason: 'passive aura applied on enter-play, without any activation',
      );
      expect(player.activatedChampions, isEmpty,
          reason: 'the champion was never manually activated');
    });
  });

  group('AddStaticModifierEffect — recruitToTopOfDeck', () {
    test('matching recruit goes to top of deck instead of discard', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const champ = CardModel(
        id: 'homo_champ',
        name: 'Homodeus Champ',
        cost: 0,
        playEffects: [],
        faction: Faction.homodeus,
        cardType: CardType.champion,
        shield: 1,
      );
      game.centerRow.insert(0, champ);
      player.staticModifiers.add(const StaticModifier(
        kind: StaticModifierKind.recruitToTopOfDeck,
        faction: Faction.homodeus,
        cardType: CardType.champion,
      ));

      final discardBefore = player.discardPile.length;
      expect(game.recruitFromCenter('homo_champ', free: true), true);
      // Went to top of deck (end of drawPile), not discard.
      expect(player.discardPile.length, discardBefore);
      expect(player.drawPile.last.id, 'homo_champ');
    });

    test('non-matching recruit still goes to discard', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;

      const ally = CardModel(
        id: 'wr_ally_card',
        name: 'Wraethe Ally',
        cost: 0,
        playEffects: [],
        faction: Faction.wraethe,
      );
      game.centerRow.insert(0, ally);
      player.staticModifiers.add(const StaticModifier(
        kind: StaticModifierKind.recruitToTopOfDeck,
        faction: Faction.homodeus,
      ));

      expect(game.recruitFromCenter('wr_ally_card', free: true), true);
      expect(player.discardPile.map((c) => c.id), contains('wr_ally_card'));
    });
  });
}
