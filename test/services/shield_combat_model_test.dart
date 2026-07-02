import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/game_state_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/player_state.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Owner combat model (backlog §E): PLAYER damage reduction each hit =
/// Σ(shield of cards in HAND) + Σ(shieldBuff from champions in play). A card's
/// own shield only protects while in hand; a champion in play contributes only
/// an explicit shieldBuff it grants (its own value is HEALTH). Global 50-HP cap.
CardModel _shieldCard(String id, int shield,
        {CardType type = CardType.regular}) =>
    CardModel(
      id: id,
      name: id,
      cost: 0,
      playEffects: const [],
      cardType: type,
      shield: shield,
    );

void main() {
  group('Player damage reduction from HAND shields', () {
    test('sum of hand-card shields reduces each incoming attack', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      target.hand
        ..clear()
        ..addAll([_shieldCard('a', 2), _shieldCard('b', 3), _shieldCard('c', 0)]);

      attacker.powerPool = 20;
      final before = target.health;
      // 10 damage - (2 + 3) = 5 lands.
      expect(game.attackPlayer('p1', 10), true);
      expect(target.health, before - 5);
    });

    test('reduction floors at 0 — an over-shielded player takes no damage', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      target.hand
        ..clear()
        ..add(_shieldCard('wall', 9));

      attacker.powerPool = 20;
      final before = target.health;
      expect(game.attackPlayer('p1', 4), true);
      expect(target.health, before, reason: 'shield 9 fully absorbs 4 damage');
      // The (post-reduction) unblocked damage is 0.
      expect(attacker.unblockedDamageThisTurn, 0);
    });

    test('a shielded card contributes while IN HAND but not once played OUT',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      final champ = _shieldCard('bulwark', 4, type: CardType.champion);
      target.hand
        ..clear()
        ..add(champ);
      attacker.powerPool = 40;

      // In hand: shield 4 reduces the hit.
      var before = target.health;
      expect(game.attackPlayer('p1', 10), true);
      expect(target.health, before - 6);

      // Play it OUT (now a champion with HEALTH in play): its own shield no
      // longer protects the player.
      target.hand.remove(champ);
      target.championsInPlay.add(champ);
      before = target.health;
      expect(game.attackPlayer('p1', 10), true);
      expect(target.health, before - 10,
          reason: 'a champion in play does not contribute its own shield');
    });

    test('ignoresShieldThisTurn lets the attacker ignore the per-hit reduction',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];

      target.hand
        ..clear()
        ..add(_shieldCard('wall', 8));
      attacker.powerPool = 20;
      attacker.ignoresShieldThisTurn = true;

      final before = target.health;
      expect(game.attackPlayer('p1', 10), true);
      expect(target.health, before - 10, reason: 'shield ignored, full damage');
    });
  });

  group('Champion HEALTH (destroy threshold = printed value)', () {
    test('champion destroyed only when power >= its health', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];
      target.championsInPlay.add(_shieldCard('c', 5, type: CardType.champion));

      attacker.powerPool = 4;
      expect(game.attackChampion('c', 'p1'), false);
      expect(target.championsInPlay, hasLength(1));

      attacker.powerPool = 5;
      expect(game.attackChampion('c', 'p1'), true);
      expect(target.championsInPlay, isEmpty);
    });

    test('guard still blocks direct attacks regardless of reduction', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];
      target.championsInPlay.add(const CardModel(
        id: 'g',
        name: 'g',
        cost: 0,
        playEffects: [],
        cardType: CardType.champion,
        shield: 1,
        hasGuard: true,
      ));
      attacker.powerPool = 20;
      final before = target.health;
      expect(game.attackPlayer('p1', 5), false);
      expect(target.health, before);
    });

    test('cannotBeAttacked still blocks direct attacks', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];
      target.staticModifiers.add(
          const StaticModifier(kind: StaticModifierKind.cannotBeAttacked));
      target.hand
        ..clear()
        ..add(_shieldCard('a', 2));
      attacker.powerPool = 20;
      final before = target.health;
      expect(game.attackPlayer('p1', 5), false);
      expect(target.health, before);
    });
  });

  group('Global 50-HP cap', () {
    test('heal never pushes health above 50', () {
      final p = PlayerState(id: 'x', name: 'x');
      p.health = 48;
      p.heal(10);
      expect(p.health, 50);
      p.heal(5);
      expect(p.health, 50);
    });

    test('GainHealthEffect clamps at 50', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.health = 47;
      me.hand.add(const CardModel(
        id: 'lifegain',
        name: 'lifegain',
        cost: 0,
        playEffects: [GainHealthEffect(10)],
      ));
      game.playCard('lifegain');
      expect(me.health, 50);
    });

    test('scaling health gain clamps at 50', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.health = 49;
      me.hand.add(const CardModel(
        id: 'scaler',
        name: 'scaler',
        cost: 0,
        playEffects: [
          ScalingResourceEffect(
            resource: ScalingResource.health,
            condition: ScalingCondition.perCardInDiscard,
          ),
        ],
      ));
      // Stack the discard so the scaled amount is large.
      me.discardPile.addAll([
        for (var i = 0; i < 8; i++) _shieldCard('d$i', 0),
      ]);
      game.playCard('scaler');
      expect(me.health, 50);
    });
  });

  group('Codec round-trip preserves the reduction inputs', () {
    test('hand shields + champion shieldBuff reduce identically post-decode',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final target = game.players[1];
      target.hand
        ..clear()
        ..add(_shieldCard('h', 2));
      target.championsInPlay
          .add(_shieldCard('prae', 3, type: CardType.champion));
      target.staticModifiers.add(const StaticModifier(
        kind: StaticModifierKind.shieldBuff,
        amount: 3,
        sourceChampionId: 'prae',
      ));

      final restored = GameStateCodec.decode(
          GameStateCodec.encode(game));
      final rAttacker = restored.currentPlayer;
      final rTarget = restored.players[1];
      rAttacker.powerPool = 20;

      final before = rTarget.health;
      // 10 - (2 hand + 3 shieldBuff) = 5 lands.
      expect(restored.attackPlayer('p1', 10), true);
      expect(rTarget.health, before - 5);
    });
  });
}
