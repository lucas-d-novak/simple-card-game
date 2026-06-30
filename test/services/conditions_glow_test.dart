import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_service.dart';
import 'package:simple_card_game/services/redacted_condition_evaluator.dart';

/// Coverage for the "conditions satisfied" glow evaluators that drive the
/// yellow card-glow UI feature on both boards:
///   * [GameService.conditionsSatisfied] — the local/engine path.
///   * [redactedConditionsSatisfied] — the networked client-side mirror.

CardModel _card({
  required String id,
  Faction faction = Faction.none,
  CardType cardType = CardType.regular,
  int cost = 0,
  List<CardEffect> playEffects = const [],
}) =>
    CardModel(
      id: id,
      name: id,
      cost: cost,
      faction: faction,
      cardType: cardType,
      playEffects: playEffects,
    );

/// A card carrying a single ConditionalEffect wrapping the given condition.
CardModel _conditionalCard(String id, GameCondition condition,
        {Faction faction = Faction.order}) =>
    _card(
      id: id,
      faction: faction,
      playEffects: [
        ConditionalEffect(condition: condition, then: const [GainPowerEffect(5)]),
      ],
    );

void main() {
  group('GameService.conditionsSatisfied', () {
    test('false for a card with no ConditionalEffect', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final plain = _card(
        id: 'plain',
        faction: Faction.order,
        playEffects: const [GainGemsEffect(2)],
      );
      expect(game.conditionsSatisfied(plain), isFalse);
    });

    test('factionAllyPlayedOrInHand: false when no same-faction support', () {
      final game = GameService(playerCount: 2, random: Random(7));
      // Clear hand so no Order card is held (starter hand has none anyway, but
      // be explicit/deterministic).
      game.currentPlayer.hand.clear();
      final card = _conditionalCard(
        'undergrowth_unify',
        const GameCondition(
            kind: GameConditionKind.factionAllyPlayedOrInHand),
      );
      expect(game.conditionsSatisfied(card), isFalse);
    });

    test('factionAllyPlayedOrInHand: true when a same-faction card is in hand',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.hand
        ..clear()
        ..add(_card(id: 'order_friend', faction: Faction.order));
      final card = _conditionalCard(
        'order_unify',
        const GameCondition(
            kind: GameConditionKind.factionAllyPlayedOrInHand),
      );
      expect(game.conditionsSatisfied(card), isTrue);
    });

    test('masteryAtLeast: flips with the player mastery', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final card = _conditionalCard(
        'mastery_gate',
        const GameCondition(
            kind: GameConditionKind.masteryAtLeast, threshold: 10),
      );
      expect(game.conditionsSatisfied(card), isFalse);
      game.currentPlayer.mastery = 10;
      expect(game.conditionsSatisfied(card), isTrue);
    });

    test('championsControlled: true once enough champions are in play', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final card = _conditionalCard(
        'champ_gate',
        const GameCondition(
            kind: GameConditionKind.championsControlled, threshold: 1),
      );
      expect(game.conditionsSatisfied(card), isFalse);
      game.currentPlayer.championsInPlay
          .add(_card(id: 'a_champ', cardType: CardType.champion));
      expect(game.conditionsSatisfied(card), isTrue);
    });
  });

  group('redactedConditionsSatisfied (client-side mirror)', () {
    RedactedConditionContext ctx({
      Map<String, CardModel> cards = const {},
      List<String> hand = const [],
      List<String> played = const [],
      List<String> discard = const [],
      List<String> champions = const [],
      int mastery = 0,
      int unblockedDamage = 0,
    }) =>
        RedactedConditionContext(
          cards: cards,
          handIds: hand,
          playedThisTurnIds: played,
          discardIds: discard,
          championIds: champions,
          mastery: mastery,
          unblockedDamageThisTurn: unblockedDamage,
        );

    test('factionAllyPlayedOrInHand: true when same-faction card in hand', () {
      final source = _conditionalCard(
        'undergrowth_unify',
        const GameCondition(
            kind: GameConditionKind.factionAllyPlayedOrInHand),
        faction: Faction.undergrowth,
      );
      final friend = _card(id: 'leaf', faction: Faction.undergrowth);
      final c = ctx(
        cards: {source.id: source, friend.id: friend},
        hand: [friend.id],
      );
      expect(redactedConditionsSatisfied(source, c), isTrue);
    });

    test('factionAllyPlayedOrInHand: false when only an off-faction card held',
        () {
      final source = _conditionalCard(
        'undergrowth_unify',
        const GameCondition(
            kind: GameConditionKind.factionAllyPlayedOrInHand),
        faction: Faction.undergrowth,
      );
      final stranger = _card(id: 'gold', faction: Faction.homodeus);
      final c = ctx(
        cards: {source.id: source, stranger.id: stranger},
        hand: [stranger.id],
      );
      expect(redactedConditionsSatisfied(source, c), isFalse);
    });

    test('factionCardInDiscard: true when matching card is in discard', () {
      final source = _conditionalCard(
        'echo',
        const GameCondition(
            kind: GameConditionKind.factionCardInDiscard),
        faction: Faction.wraethe,
      );
      final dead = _card(id: 'fiend', faction: Faction.wraethe);
      final c = ctx(
        cards: {source.id: source, dead.id: dead},
        discard: [dead.id],
      );
      expect(redactedConditionsSatisfied(source, c), isTrue);
    });

    test('masteryAtLeast mirrors the threshold', () {
      final source = _conditionalCard(
        'mastery_gate',
        const GameCondition(
            kind: GameConditionKind.masteryAtLeast, threshold: 15),
      );
      expect(
        redactedConditionsSatisfied(
            source, ctx(cards: {source.id: source}, mastery: 14)),
        isFalse,
      );
      expect(
        redactedConditionsSatisfied(
            source, ctx(cards: {source.id: source}, mastery: 15)),
        isTrue,
      );
    });

    test('isCharacter is not evaluable from redacted data → false', () {
      final source = _conditionalCard(
        'char_gate',
        const GameCondition(
            kind: GameConditionKind.isCharacter, character: Character.tetra),
      );
      expect(
        redactedConditionsSatisfied(source, ctx(cards: {source.id: source})),
        isFalse,
      );
    });

    test('engine and client agree on factionAllyPlayedOrInHand in hand', () {
      // Same scenario, both evaluators → true.
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.hand
        ..clear()
        ..add(_card(id: 'order_friend', faction: Faction.order));
      final source = _conditionalCard(
        'order_unify',
        const GameCondition(
            kind: GameConditionKind.factionAllyPlayedOrInHand),
      );
      expect(game.conditionsSatisfied(source), isTrue);

      final friend = _card(id: 'order_friend', faction: Faction.order);
      final c = ctx(
        cards: {source.id: source, friend.id: friend},
        hand: [friend.id],
      );
      expect(redactedConditionsSatisfied(source, c), isTrue);
    });
  });
}
