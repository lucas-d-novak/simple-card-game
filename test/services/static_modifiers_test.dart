import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Engine Phase 2 wave 5a — Family 11 (static board-wide modifiers).
void main() {
  group('AddStaticModifierEffect — shield buff', () {
    test('shield buff raises effective shield (champion harder to destroy)', () {
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
      target.championsInPlay.add(champion);
      // The target owns a +3 shield buff for their champions.
      target.staticModifiers
          .add(const StaticModifier(kind: StaticModifierKind.shieldBuff, amount: 3));

      // 4 power < effective shield (2 + 3 = 5): attack fails, nothing deducted.
      attacker.powerPool = 4;
      expect(game.attackChampion('guard', 'p1'), false);
      expect(attacker.powerPool, 4);
      expect(target.championsInPlay, hasLength(1));

      // 5 power == effective shield: succeeds, deducts 5.
      attacker.powerPool = 5;
      expect(game.attackChampion('guard', 'p1'), true);
      expect(attacker.powerPool, 0);
      expect(target.championsInPlay, isEmpty);
    });

    test('faction-filtered shield buff only applies to matching champions', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      const orderChamp = CardModel(
        id: 'order_c',
        name: 'Order Champ',
        cost: 0,
        playEffects: [],
        faction: Faction.order,
        cardType: CardType.champion,
        shield: 1,
      );
      const wraetheChamp = CardModel(
        id: 'wr_c',
        name: 'Wraethe Champ',
        cost: 0,
        playEffects: [],
        faction: Faction.wraethe,
        cardType: CardType.champion,
        shield: 1,
      );
      target.championsInPlay.addAll([orderChamp, wraetheChamp]);
      target.staticModifiers.add(const StaticModifier(
        kind: StaticModifierKind.shieldBuff,
        amount: 4,
        faction: Faction.order,
      ));

      // Wraethe champion unbuffed: 1 power destroys it.
      attacker.powerPool = 1;
      expect(game.attackChampion('wr_c', 'p1'), true);

      // Order champion buffed to shield 5: 4 power not enough.
      attacker.powerPool = 4;
      expect(game.attackChampion('order_c', 'p1'), false);
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
