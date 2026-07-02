import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Engine Phase 2, wave 0 — coverage for the ConditionalEffect wrapper (a met /
/// not-met pair per GameConditionKind, plus a proof the wrapper works inside an
/// activated ability) and for the generalized ScalingResourceEffect.

CardModel _card({
  required String id,
  Faction faction = Faction.none,
  CardType cardType = CardType.regular,
  int cost = 0,
  int shield = 0,
  List<CardEffect> playEffects = const [],
  bool countsAsAllFactions = false,
  ActivatedAbility? activatedAbility,
}) =>
    CardModel(
      id: id,
      name: id,
      cost: cost,
      faction: faction,
      cardType: cardType,
      shield: shield,
      playEffects: playEffects,
      countsAsAllFactions: countsAsAllFactions,
      activatedAbility: activatedAbility,
    );

/// Plays [card] for the current player (adds to hand first) and returns the
/// resulting power pool gained from a `then: [GainPowerEffect(...)]` payload.
int _playAndReadPower(GameService game, CardModel card) {
  final player = game.currentPlayer;
  player.hand.add(card);
  game.playCard(card.id);
  return player.powerPool;
}

void main() {
  group('ConditionalEffect — per-kind met / not-met', () {
    // The wrapper grants 10 power when the condition holds.
    List<CardEffect> thenPower10() => const [GainPowerEffect(10)];

    test('alliesOfFactionPlayed (met when 1 ally of source faction already played)',
        () {
      // Not met: source is the only Order card played.
      final game = GameService(playerCount: 2, random: Random(7));
      final notMet = _card(
        id: 'cond_a',
        faction: Faction.order,
        playEffects: [
          ConditionalEffect(
            condition: const GameCondition(
                kind: GameConditionKind.alliesOfFactionPlayed),
            then: thenPower10(),
          ),
        ],
      );
      expect(_playAndReadPower(game, notMet), 0);

      // Met: an Order card was already played this turn.
      final game2 = GameService(playerCount: 2, random: Random(7));
      game2.currentPlayer.hand.add(_card(id: 'order_pre', faction: Faction.order));
      game2.playCard('order_pre');
      final met = _card(
        id: 'cond_a2',
        faction: Faction.order,
        playEffects: [
          ConditionalEffect(
            condition: const GameCondition(
                kind: GameConditionKind.alliesOfFactionPlayed),
            then: thenPower10(),
          ),
        ],
      );
      expect(_playAndReadPower(game2, met), 10);
    });

    test('factionsPlayedAll', () {
      const cond = GameCondition(
        kind: GameConditionKind.factionsPlayedAll,
        factions: [Faction.order, Faction.wraethe],
      );

      // Not met: only Order played.
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.hand.add(_card(id: 'o', faction: Faction.order));
      game.playCard('o');
      expect(
        _playAndReadPower(
            game,
            _card(id: 'c', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        0,
      );

      // Met: both Order and Wraethe played.
      final game2 = GameService(playerCount: 2, random: Random(7));
      game2.currentPlayer.hand.add(_card(id: 'o2', faction: Faction.order));
      game2.currentPlayer.hand.add(_card(id: 'w2', faction: Faction.wraethe));
      game2.playCard('o2');
      game2.playCard('w2');
      expect(
        _playAndReadPower(
            game2,
            _card(id: 'c2', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        10,
      );
    });

    test('distinctFactionsPlayed (threshold 2)', () {
      const cond = GameCondition(
        kind: GameConditionKind.distinctFactionsPlayed,
        threshold: 2,
      );

      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.hand.add(_card(id: 'o', faction: Faction.order));
      game.playCard('o');
      expect(
        _playAndReadPower(
            game,
            _card(id: 'c', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        0,
      );

      final game2 = GameService(playerCount: 2, random: Random(7));
      game2.currentPlayer.hand.add(_card(id: 'o2', faction: Faction.order));
      game2.currentPlayer.hand.add(_card(id: 'w2', faction: Faction.wraethe));
      game2.playCard('o2');
      game2.playCard('w2');
      expect(
        _playAndReadPower(
            game2,
            _card(id: 'c2', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        10,
      );
    });

    test('cardTypePlayed (champion, threshold 1)', () {
      const cond = GameCondition(
        kind: GameConditionKind.cardTypePlayed,
        cardType: CardType.champion,
      );

      final game = GameService(playerCount: 2, random: Random(7));
      expect(
        _playAndReadPower(
            game,
            _card(id: 'c', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        0,
      );

      final game2 = GameService(playerCount: 2, random: Random(7));
      game2.currentPlayer.hand
          .add(_card(id: 'champ', cardType: CardType.champion, shield: 3));
      game2.playCard('champ');
      expect(
        _playAndReadPower(
            game2,
            _card(id: 'c2', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        10,
      );
    });

    test('gemParityCardsPlayed (even)', () {
      const cond = GameCondition(
        kind: GameConditionKind.gemParityCardsPlayed,
        parity: GemParity.even,
      );

      // Play one card before the wrapper -> count seen by wrapper (excluding
      // self) is 1 -> odd -> not met.
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.hand.add(_card(id: 'pre'));
      game.playCard('pre');
      expect(
        _playAndReadPower(
            game,
            _card(id: 'c', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        0,
      );

      // No cards before -> count 0 -> even -> met.
      final game2 = GameService(playerCount: 2, random: Random(7));
      expect(
        _playAndReadPower(
            game2,
            _card(id: 'c2', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        10,
      );
    });

    test('filteredCardsPlayed (faction + maxCost)', () {
      const cond = GameCondition(
        kind: GameConditionKind.filteredCardsPlayed,
        faction: Faction.order,
        maxCost: 2,
        threshold: 1,
      );

      // Not met: the only Order card played costs 3 (> maxCost).
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.hand
          .add(_card(id: 'pricey', faction: Faction.order, cost: 3));
      game.playCard('pricey');
      expect(
        _playAndReadPower(
            game,
            _card(id: 'c', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        0,
      );

      // Met: an Order card costing 1 was played.
      final game2 = GameService(playerCount: 2, random: Random(7));
      game2.currentPlayer.hand
          .add(_card(id: 'cheap', faction: Faction.order, cost: 1));
      game2.playCard('cheap');
      expect(
        _playAndReadPower(
            game2,
            _card(id: 'c2', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        10,
      );
    });

    test('championsControlled (threshold 2)', () {
      const cond = GameCondition(
        kind: GameConditionKind.championsControlled,
        threshold: 2,
      );

      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.championsInPlay
          .add(_card(id: 'ch1', cardType: CardType.champion, shield: 2));
      expect(
        _playAndReadPower(
            game,
            _card(id: 'c', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        0,
      );

      final game2 = GameService(playerCount: 2, random: Random(7));
      game2.currentPlayer.championsInPlay
          .add(_card(id: 'ch1', cardType: CardType.champion, shield: 2));
      game2.currentPlayer.championsInPlay
          .add(_card(id: 'ch2', cardType: CardType.champion, shield: 2));
      expect(
        _playAndReadPower(
            game2,
            _card(id: 'c2', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        10,
      );
    });

    test('championsOfFactionControlled (homodeus)', () {
      const cond = GameCondition(
        kind: GameConditionKind.championsOfFactionControlled,
        faction: Faction.homodeus,
      );

      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.championsInPlay.add(_card(
          id: 'ch1', cardType: CardType.champion, faction: Faction.order));
      expect(
        _playAndReadPower(
            game,
            _card(id: 'c', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        0,
      );

      final game2 = GameService(playerCount: 2, random: Random(7));
      game2.currentPlayer.championsInPlay.add(_card(
          id: 'ch2', cardType: CardType.champion, faction: Faction.homodeus));
      expect(
        _playAndReadPower(
            game2,
            _card(id: 'c2', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        10,
      );
    });

    test('masteryAtLeast (threshold 20)', () {
      const cond = GameCondition(
        kind: GameConditionKind.masteryAtLeast,
        threshold: 20,
      );

      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.mastery = 19;
      expect(
        _playAndReadPower(
            game,
            _card(id: 'c', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        0,
      );

      final game2 = GameService(playerCount: 2, random: Random(7));
      game2.currentPlayer.mastery = 20;
      expect(
        _playAndReadPower(
            game2,
            _card(id: 'c2', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        10,
      );
    });

    test('sameFactionCountPlayed (threshold 2, counts self)', () {
      const cond = GameCondition(
        kind: GameConditionKind.sameFactionCountPlayed,
        threshold: 2,
      );

      // Not met: source is the only Wraethe card (count incl. self = 1).
      final game = GameService(playerCount: 2, random: Random(7));
      expect(
        _playAndReadPower(
            game,
            _card(id: 'c', faction: Faction.wraethe, playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        0,
      );

      // Met: one Wraethe ally already played + self = 2.
      final game2 = GameService(playerCount: 2, random: Random(7));
      game2.currentPlayer.hand
          .add(_card(id: 'w_pre', faction: Faction.wraethe));
      game2.playCard('w_pre');
      expect(
        _playAndReadPower(
            game2,
            _card(id: 'c2', faction: Faction.wraethe, playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        10,
      );
    });

    test('isCharacter (false when player has no character, true when matching)',
        () {
      const cond = GameCondition(
        kind: GameConditionKind.isCharacter,
        character: Character.decima,
      );

      // Not met: PlayerState.character defaults to null.
      final game = GameService(playerCount: 2, random: Random(7));
      expect(
        _playAndReadPower(
            game,
            _card(id: 'c', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        0,
      );

      // Met: player IS Decima.
      final game2 = GameService(playerCount: 2, random: Random(7));
      game2.currentPlayer.character = Character.decima;
      expect(
        _playAndReadPower(
            game2,
            _card(id: 'c2', playEffects: [
              ConditionalEffect(condition: cond, then: thenPower10())
            ])),
        10,
      );
    });
  });

  group('ConditionalEffect inside an activated ability', () {
    test('useActivatedAbility resolves the wrapper only when condition holds',
        () {
      // Champion whose Exhaust ability grants 10 power if mastery >= 5.
      const ability = ActivatedAbility(
        effects: [
          ConditionalEffect(
            condition: GameCondition(
                kind: GameConditionKind.masteryAtLeast, threshold: 5),
            then: [GainPowerEffect(10)],
          ),
        ],
      );

      // Not met (mastery 4).
      final game = GameService(playerCount: 2, random: Random(7));
      final champ = _card(
        id: 'exh_champ',
        cardType: CardType.champion,
        shield: 3,
        activatedAbility: ability,
      );
      game.currentPlayer.championsInPlay.add(champ);
      game.currentPlayer.mastery = 4;
      expect(game.useActivatedAbility('exh_champ'), true);
      expect(game.currentPlayer.powerPool, 0);

      // Met (mastery 5).
      final game2 = GameService(playerCount: 2, random: Random(7));
      game2.currentPlayer.championsInPlay.add(champ);
      game2.currentPlayer.mastery = 5;
      expect(game2.useActivatedAbility('exh_champ'), true);
      expect(game2.currentPlayer.powerPool, 10);
    });
  });

  group('ScalingResourceEffect', () {
    test('regression: 4 original conditions match ConditionalPowerEffect', () {
      for (final pair in const [
        [
          ScalingCondition.perChampionControlled,
          PowerCondition.perChampionControlled,
        ],
        [
          ScalingCondition.perAllyPlayedThisTurn,
          PowerCondition.perAllyPlayedThisTurn,
        ],
        [
          ScalingCondition.perFactionPlayedThisTurn,
          PowerCondition.perFactionPlayedThisTurn,
        ],
        [
          ScalingCondition.perCardInDiscard,
          PowerCondition.perCardInDiscard,
        ],
      ]) {
        final scalingCond = pair[0] as ScalingCondition;
        final powerCond = pair[1] as PowerCondition;

        // Build identical board state for both effects.
        GameService build() {
          final g = GameService(playerCount: 2, random: Random(7));
          final p = g.currentPlayer;
          p.championsInPlay.add(_card(
              id: 'ch', cardType: CardType.champion, faction: Faction.order));
          p.discardPile.add(_card(id: 'd1'));
          p.discardPile.add(_card(id: 'd2'));
          // Play two Order allies before the source.
          p.hand.add(_card(id: 'a1', faction: Faction.order));
          p.hand.add(_card(id: 'a2', faction: Faction.order));
          g.playCard('a1');
          g.playCard('a2');
          return g;
        }

        final gOld = build();
        final oldPower = _playAndReadPower(
          gOld,
          _card(
            id: 'old',
            faction: Faction.order,
            playEffects: [ConditionalPowerEffect(powerCond)],
          ),
        );

        final gNew = build();
        final newPower = _playAndReadPower(
          gNew,
          _card(
            id: 'new',
            faction: Faction.order,
            playEffects: [
              ScalingResourceEffect(
                resource: ScalingResource.power,
                condition: scalingCond,
              ),
            ],
          ),
        );

        expect(newPower, oldPower,
            reason: 'scaling $scalingCond should equal power $powerCond');
      }
    });

    test('perFactionCardInDiscard counts only matching faction, x perN', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.discardPile.add(_card(id: 'd1', faction: Faction.wraethe));
      player.discardPile.add(_card(id: 'd2', faction: Faction.wraethe));
      player.discardPile.add(_card(id: 'd3', faction: Faction.order));

      final power = _playAndReadPower(
        game,
        _card(
          id: 'src',
          faction: Faction.wraethe,
          playEffects: [
            const ScalingResourceEffect(
              resource: ScalingResource.power,
              condition: ScalingCondition.perFactionCardInDiscard,
              perN: 2,
            ),
          ],
        ),
      );
      // 2 Wraethe cards x perN 2 = 4.
      expect(power, 4);
    });

    test('perFactionChampionControlled routes into gems pool', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.championsInPlay.add(_card(
          id: 'ch1', cardType: CardType.champion, faction: Faction.homodeus));
      player.championsInPlay.add(_card(
          id: 'ch2', cardType: CardType.champion, faction: Faction.homodeus));
      player.championsInPlay.add(_card(
          id: 'ch3', cardType: CardType.champion, faction: Faction.order));

      player.hand.add(_card(
        id: 'src',
        playEffects: [
          const ScalingResourceEffect(
            resource: ScalingResource.gems,
            condition: ScalingCondition.perFactionChampionControlled,
            faction: Faction.homodeus,
          ),
        ],
      ));
      game.playCard('src');
      // 2 Homodeus champions -> 2 gems (explicit faction filter, not source).
      expect(player.gemPool, 2);
      expect(player.powerPool, 0);
    });

    test('perFactionCardPlayedThisTurn (excludes the source card itself)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.hand.add(_card(id: 'u1', faction: Faction.undergrowth));
      player.hand.add(_card(id: 'u2', faction: Faction.undergrowth));
      game.playCard('u1');
      game.playCard('u2');

      final power = _playAndReadPower(
        game,
        _card(
          id: 'src',
          faction: Faction.undergrowth,
          playEffects: [
            const ScalingResourceEffect(
              resource: ScalingResource.power,
              condition: ScalingCondition.perFactionCardPlayedThisTurn,
            ),
          ],
        ),
      );
      // 2 undergrowth allies played before source; source excluded -> 2.
      expect(power, 2);
    });

    test('perAllyWithShieldPlayedThisTurn counts only shielded same-faction', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      // A shielded Order champion and a non-shield Order regular.
      player.hand.add(_card(
          id: 'champ',
          faction: Faction.order,
          cardType: CardType.champion,
          shield: 4));
      player.hand.add(_card(id: 'reg', faction: Faction.order));
      game.playCard('champ');
      game.playCard('reg');

      final power = _playAndReadPower(
        game,
        _card(
          id: 'src',
          faction: Faction.order,
          playEffects: [
            const ScalingResourceEffect(
              resource: ScalingResource.power,
              condition: ScalingCondition.perAllyWithShieldPlayedThisTurn,
              perN: 2,
            ),
          ],
        ),
      );
      // Only the shielded champion counts -> 1 x perN 2 = 2.
      expect(power, 2);
    });
  });

  // Wave-0 review follow-ups: close the test gaps the per-mechanic reviewers
  // flagged (source-faction inclusion, explicit-faction precedence, edge cases,
  // and end-to-end health/mastery resource routing).
  group('ConditionalEffect — review-gap coverage', () {
    List<CardEffect> thenPower10() => const [GainPowerEffect(10)];

    test('distinctFactionsPlayed counts the source card\'s own faction', () {
      // One prior faction played; the source (a second, distinct faction)
      // pushes the distinct count to 2 on its own.
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.hand.add(_card(id: 'pre_order', faction: Faction.order));
      game.playCard('pre_order');
      final src = _card(
        id: 'src_wraethe',
        faction: Faction.wraethe,
        playEffects: [
          ConditionalEffect(
            condition: const GameCondition(
              kind: GameConditionKind.distinctFactionsPlayed,
              threshold: 2,
            ),
            then: thenPower10(),
          ),
        ],
      );
      // Source's Wraethe + prior Order = 2 distinct -> met.
      expect(_playAndReadPower(game, src), 10);
    });

    test('explicit condition faction is honored over the source faction', () {
      // Source is Order, but the condition asks for Wraethe allies. A prior
      // Wraethe card should satisfy it; the source\'s own Order should not.
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.hand.add(_card(id: 'pre_w', faction: Faction.wraethe));
      game.playCard('pre_w');
      final src = _card(
        id: 'order_src',
        faction: Faction.order,
        playEffects: [
          ConditionalEffect(
            condition: const GameCondition(
              kind: GameConditionKind.alliesOfFactionPlayed,
              faction: Faction.wraethe,
            ),
            then: thenPower10(),
          ),
        ],
      );
      expect(_playAndReadPower(game, src), 10);

      // Control: same source, condition faction = Homodeus (none played) -> 0.
      final game2 = GameService(playerCount: 2, random: Random(7));
      game2.currentPlayer.hand.add(_card(id: 'pre_w2', faction: Faction.wraethe));
      game2.playCard('pre_w2');
      final src2 = _card(
        id: 'order_src2',
        faction: Faction.order,
        playEffects: [
          ConditionalEffect(
            condition: const GameCondition(
              kind: GameConditionKind.alliesOfFactionPlayed,
              faction: Faction.homodeus,
            ),
            then: thenPower10(),
          ),
        ],
      );
      expect(_playAndReadPower(game2, src2), 0);
    });

    test('empty factions list -> factionsPlayedAll is false', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final src = _card(
        id: 'empty_factions',
        playEffects: [
          ConditionalEffect(
            condition: const GameCondition(
              kind: GameConditionKind.factionsPlayedAll,
              factions: [],
            ),
            then: thenPower10(),
          ),
        ],
      );
      expect(_playAndReadPower(game, src), 0);
    });

    test('threshold 0 makes a count-based kind trivially true', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final src = _card(
        id: 'thresh0',
        faction: Faction.order,
        playEffects: [
          ConditionalEffect(
            condition: const GameCondition(
              kind: GameConditionKind.alliesOfFactionPlayed,
              threshold: 0,
            ),
            then: thenPower10(),
          ),
        ],
      );
      expect(_playAndReadPower(game, src), 10);
    });
  });

  group('ScalingResourceEffect — health and mastery routing (end-to-end)', () {
    test('health resource adds to the controlling player\'s health', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      player.health = 40; // below the 50 cap so the +2 heal registers
      final before = player.health;
      // 2 cards in discard, gain 1 health per discard card.
      player.discardPile.add(_card(id: 'd1'));
      player.discardPile.add(_card(id: 'd2'));
      player.hand.add(_card(
        id: 'heal_src',
        playEffects: const [
          ScalingResourceEffect(
            resource: ScalingResource.health,
            condition: ScalingCondition.perCardInDiscard,
          ),
        ],
      ));
      game.playCard('heal_src');
      expect(player.health, before + 2);
    });

    test('mastery resource adds to the controlling player\'s mastery', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final player = game.currentPlayer;
      final before = player.mastery;
      player.discardPile.add(_card(id: 'm1'));
      player.discardPile.add(_card(id: 'm2'));
      player.discardPile.add(_card(id: 'm3'));
      player.hand.add(_card(
        id: 'mastery_src',
        playEffects: const [
          ScalingResourceEffect(
            resource: ScalingResource.mastery,
            condition: ScalingCondition.perCardInDiscard,
          ),
        ],
      ));
      game.playCard('mastery_src');
      expect(player.mastery, before + 3);
    });
  });

  // -------------------------------------------------------------------------
  // Engine Phase 3 — new GameConditionKind values.
  // -------------------------------------------------------------------------
  group('Phase 3 conditions', () {
    List<CardEffect> thenPower10() => const [GainPowerEffect(10)];

    group('factionAllyPlayedOrInHand (Unify)', () {
      CardModel unifyCard(String id) => _card(
            id: id,
            faction: Faction.undergrowth,
            playEffects: [
              ConditionalEffect(
                condition: const GameCondition(
                    kind: GameConditionKind.factionAllyPlayedOrInHand),
                then: thenPower10(),
              ),
            ],
          );

      test('not met: no matching ally played and none in hand', () {
        final game = GameService(playerCount: 2, random: Random(7));
        game.currentPlayer.hand
            .removeWhere((c) => c.faction == Faction.undergrowth);
        expect(_playAndReadPower(game, unifyCard('u_none')), 0);
      });

      test('met via PLAYED: another undergrowth ally already played this turn',
          () {
        final game = GameService(playerCount: 2, random: Random(7));
        game.currentPlayer.hand
            .removeWhere((c) => c.faction == Faction.undergrowth);
        game.currentPlayer.hand
            .add(_card(id: 'ug_pre', faction: Faction.undergrowth));
        game.playCard('ug_pre');
        expect(_playAndReadPower(game, unifyCard('u_played')), 10);
      });

      test('met via REVEAL: a matching ally is in hand (optional reveal)', () {
        final game = GameService(playerCount: 2, random: Random(7));
        game.currentPlayer.hand
            .removeWhere((c) => c.faction == Faction.undergrowth);
        game.currentPlayer.hand
            .add(_card(id: 'ug_inhand', faction: Faction.undergrowth));
        expect(_playAndReadPower(game, unifyCard('u_reveal')), 10);
      });
    });

    group('factionCardInDiscard (Echo)', () {
      CardModel echoCard(String id) => _card(
            id: id,
            faction: Faction.wraethe,
            playEffects: [
              ConditionalEffect(
                condition: const GameCondition(
                    kind: GameConditionKind.factionCardInDiscard,
                    faction: Faction.wraethe),
                then: thenPower10(),
              ),
            ],
          );

      test('not met: no wraethe card in discard', () {
        final game = GameService(playerCount: 2, random: Random(7));
        game.currentPlayer.discardPile
            .removeWhere((c) => c.faction == Faction.wraethe);
        expect(_playAndReadPower(game, echoCard('e_none')), 0);
      });

      test('met: a wraethe card is in the discard pile', () {
        final game = GameService(playerCount: 2, random: Random(7));
        game.currentPlayer.discardPile
            .add(_card(id: 'wr_disc', faction: Faction.wraethe));
        expect(_playAndReadPower(game, echoCard('e_yes')), 10);
      });

      test('boolean, not scaling: two wraethe cards still grant the flat bonus',
          () {
        final game = GameService(playerCount: 2, random: Random(7));
        game.currentPlayer.discardPile
            .add(_card(id: 'wr_d1', faction: Faction.wraethe));
        game.currentPlayer.discardPile
            .add(_card(id: 'wr_d2', faction: Faction.wraethe));
        expect(_playAndReadPower(game, echoCard('e_two')), 10);
      });
    });

    group('odd/even cost cards played', () {
      CardModel costCond(String id, GameConditionKind kind, int threshold) =>
          _card(
            id: id,
            cost: 0, // even source so it doesn't perturb an odd count
            playEffects: [
              ConditionalEffect(
                condition: GameCondition(kind: kind, threshold: threshold),
                then: thenPower10(),
              ),
            ],
          );

      test('oddCostCardsPlayed: counts odd-cost cards played (excl. source)',
          () {
        final game = GameService(playerCount: 2, random: Random(7));
        game.currentPlayer.hand.add(_card(id: 'odd1', cost: 3));
        game.currentPlayer.hand.add(_card(id: 'odd2', cost: 5));
        game.currentPlayer.hand.add(_card(id: 'even1', cost: 4));
        game.playCard('odd1');
        game.playCard('odd2');
        game.playCard('even1');
        expect(
            _playAndReadPower(game,
                costCond('odd_src', GameConditionKind.oddCostCardsPlayed, 2)),
            10);
      });

      test('oddCostCardsPlayed: one odd card is not enough for threshold 2', () {
        final game = GameService(playerCount: 2, random: Random(7));
        game.currentPlayer.hand.add(_card(id: 'odd_only', cost: 7));
        game.playCard('odd_only');
        expect(
            _playAndReadPower(game,
                costCond('odd_src2', GameConditionKind.oddCostCardsPlayed, 2)),
            0);
      });

      test('evenCostCardsPlayed: counts even-cost cards played', () {
        final game = GameService(playerCount: 2, random: Random(7));
        game.currentPlayer.hand.add(_card(id: 'ev1', cost: 2));
        game.currentPlayer.hand.add(_card(id: 'ev2', cost: 6));
        game.currentPlayer.hand.add(_card(id: 'od1', cost: 3));
        game.playCard('ev1');
        game.playCard('ev2');
        game.playCard('od1');
        expect(
            _playAndReadPower(game,
                costCond('even_src', GameConditionKind.evenCostCardsPlayed, 2)),
            10);
      });
    });
  });
}
