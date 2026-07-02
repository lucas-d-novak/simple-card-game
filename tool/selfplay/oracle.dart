// The differential oracle — dev-only. See ai-docs/self_play_bots_design.md §3.
//
// Two layers:
//   * Invariants (§3a) — cheap assertions true after EVERY action. A violation
//     is always a bug (impossible scalar, mastery dropped mid-turn, a card
//     vanished/duplicated, game-over inconsistency).
//   * Per-effect oracle (§3b) — for a PLAYED card, independently re-derive the
//     expected resource delta from the card's declared CardEffects and diff it
//     against what the engine actually did. A mismatch on a dimension the card
//     touches is a semantic bug ("the card didn't do what its text says").
//
// DESIGN: the oracle is a PARALLEL, independent re-implementation written
// separately from the engine, so an engine bug doesn't hide behind the same bug
// in the oracle. It is deliberately CONSERVATIVE: when an effect's magnitude is
// genuinely state-dependent in a way the oracle can't re-derive from pre-state
// alone (e.g. a draw that reshuffles, a deferred selection), the oracle marks
// that dimension "unverifiable for this action" and does NOT assert on it —
// favouring zero false positives over total coverage. Flat-amount drift (the
// GainPowerEffect(2)-should-be-3 class), which is what we're hunting, is fully
// covered.

import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/services/game_service.dart';

/// A flat, comparable snapshot of one player's own visible resources + zone
/// sizes — enough for the invariant + resource-delta checks without holding a
/// reference to the live (mutating) PlayerState.
class PlayerSnapshot {
  PlayerSnapshot({
    required this.id,
    required this.health,
    required this.mastery,
    required this.gems,
    required this.power,
    required this.handCount,
    required this.drawCount,
    required this.discardCount,
    required this.championCount,
    required this.playedThisTurnCount,
    required this.underChampionCount,
    required this.isEliminated,
  });

  final String id;
  final int health;
  final int mastery;
  final int gems;
  final int power;
  final int handCount;
  final int drawCount;
  final int discardCount;
  final int championCount;

  /// Regular/mercenary cards played this turn — they live in `playedThisTurn`
  /// from play until end-of-turn cleanup, so they must be counted for card
  /// conservation (a played card hasn't left the game).
  final int playedThisTurnCount;

  /// Cards tucked under champions (`cardsUnderChampion`). These are still "in the
  /// game" — they persist with their champion — so conservation must count them.
  final int underChampionCount;

  final bool isEliminated;

  /// Total cards this player "owns" across ALL their personal zones (hand + draw
  /// + discard + champions + played-this-turn + tucked-under). Used by the
  /// card-conservation invariant — every zone a card can sit in must be here, or
  /// the invariant fires spuriously when a card merely MOVES between zones.
  int get ownedCards =>
      handCount +
      drawCount +
      discardCount +
      championCount +
      playedThisTurnCount +
      underChampionCount;
}

/// A whole-game snapshot: every player + the shared center row / decks. Captured
/// before and after each action.
class GameSnapshot {
  GameSnapshot({
    required this.players,
    required this.centerRowCount,
    required this.infinityDeckCount,
    required this.removedCount,
    required this.destinyRowCount,
    required this.destinyDeckCount,
    required this.claimedDestinyCount,
    required this.isGameOver,
    required this.winnerId,
    required this.winType,
    required this.currentPlayerId,
  });

  final Map<String, PlayerSnapshot> players;
  final int centerRowCount;
  final int infinityDeckCount;
  final int removedCount;

  /// The shared Destiny supply zones (Into the Horizon). These hold real cards
  /// that move (claim → claimedDestinies; cascade → removed) so conservation
  /// must count them, or claiming/banishing a Destiny fires a spurious change.
  final int destinyRowCount;
  final int destinyDeckCount;

  /// Sum of every player's claimedDestinies (a persistent per-player zone that
  /// is NEVER part of hand/draw/discard).
  final int claimedDestinyCount;

  final bool isGameOver;
  final String? winnerId;
  final String? winType;
  final String currentPlayerId;

  /// Total cards everywhere — all players' owned cards + center row + center
  /// deck + removed-from-game + the Destiny supply (row + deck + claimed).
  /// Should be constant for the whole game (cards are neither created nor
  /// destroyed; they only move between zones).
  int get totalCards {
    var sum = centerRowCount +
        infinityDeckCount +
        removedCount +
        destinyRowCount +
        destinyDeckCount +
        claimedDestinyCount;
    for (final p in players.values) {
      sum += p.ownedCards;
    }
    return sum;
  }

  static GameSnapshot capture(GameService game) {
    final players = <String, PlayerSnapshot>{};
    for (final p in game.players) {
      players[p.id] = PlayerSnapshot(
        id: p.id,
        health: p.health,
        mastery: p.mastery,
        gems: p.gemPool,
        power: p.powerPool,
        handCount: p.hand.length,
        drawCount: p.drawPile.length,
        discardCount: p.discardPile.length,
        championCount: p.championsInPlay.length,
        playedThisTurnCount: p.playedThisTurn.length,
        underChampionCount: p.cardsUnderChampion.values
            .fold(0, (sum, list) => sum + list.length),
        isEliminated: p.isEliminated,
      );
    }
    return GameSnapshot(
      players: players,
      centerRowCount: game.centerRow.length,
      infinityDeckCount: game.infinityDeck.length,
      removedCount: game.removedFromGame.length,
      destinyRowCount: game.destinyRow.length,
      destinyDeckCount: game.destinyDeck.length,
      claimedDestinyCount: game.players
          .fold(0, (sum, p) => sum + p.claimedDestinies.length),
      isGameOver: game.isGameOver,
      winnerId: game.winnerId,
      winType: game.winType,
      currentPlayerId: game.currentPlayer.id,
    );
  }
}

/// A single finding from the oracle. Kind is one of: invariant, semantic-mismatch.
class OracleFinding {
  OracleFinding({
    required this.kind,
    required this.message,
    this.card,
    this.effect,
    this.expectedDelta,
    this.actualDelta,
  });

  final String kind; // 'invariant' | 'semantic-mismatch'
  final String message;
  final String? card; // implicated card id
  final String? effect;
  final Map<String, int>? expectedDelta;
  final Map<String, int>? actualDelta;
}

/// The resource dimensions the flat oracle reasons about for the acting player.
class ResourceDelta {
  int gems = 0;
  int power = 0;
  int mastery = 0;
  int health = 0;
  int hand = 0; // net hand-size change (draw adds, play removes)

  void add(ResourceDelta o) {
    gems += o.gems;
    power += o.power;
    mastery += o.mastery;
    health += o.health;
    hand += o.hand;
  }

  Map<String, int> toMap() => {
        'gems': gems,
        'power': power,
        'mastery': mastery,
        'health': health,
        'hand': hand,
      };
}

/// The oracle. Stateless except for a small config; call [checkInvariants] after
/// every action and [checkPlay] after a play action.
class Oracle {
  /// Run the always-on invariants. Returns any violations.
  List<OracleFinding> checkInvariants(
    GameSnapshot pre,
    GameSnapshot post,
    String actionLabel,
  ) {
    final findings = <OracleFinding>[];

    // 1. No impossible scalars (gems/power/mastery never negative; health may
    //    go <= 0 but that means eliminated).
    for (final p in post.players.values) {
      if (p.gems < 0) {
        findings.add(OracleFinding(
          kind: 'invariant',
          message: 'Player ${p.id} has negative gems (${p.gems}) after '
              '$actionLabel',
        ));
      }
      if (p.power < 0) {
        findings.add(OracleFinding(
          kind: 'invariant',
          message: 'Player ${p.id} has negative power (${p.power}) after '
              '$actionLabel',
        ));
      }
      if (p.mastery < 0) {
        findings.add(OracleFinding(
          kind: 'invariant',
          message: 'Player ${p.id} has negative mastery (${p.mastery}) after '
              '$actionLabel',
        ));
      }
    }

    // 2. Mastery is monotonic non-decreasing (no effect should ever LOWER a
    //    player's mastery — there is no "lose mastery" mechanic). An activated
    //    ability can COST mastery, so we only flag a drop for players who are
    //    NOT the actor (the actor may legitimately pay mastery as an ability
    //    cost). Cross-player mastery loss is always a bug.
    for (final id in pre.players.keys) {
      final before = pre.players[id]!;
      final after = post.players[id]!;
      if (after.mastery < before.mastery && id != pre.currentPlayerId) {
        findings.add(OracleFinding(
          kind: 'invariant',
          message: 'Non-acting player $id lost mastery '
              '(${before.mastery} -> ${after.mastery}) after $actionLabel',
        ));
      }
    }

    // 3. Card conservation — the global card total is constant. Cards move
    //    between zones but are never created or destroyed.
    if (pre.totalCards != post.totalCards) {
      findings.add(OracleFinding(
        kind: 'invariant',
        message: 'Card count changed ${pre.totalCards} -> ${post.totalCards} '
            'after $actionLabel (a card was created or destroyed)',
      ));
    }

    // 4. Win-condition consistency — game-over implies a win type is set, and a
    //    winner implies game-over. A DRAW (mutual knockout) is a legitimate
    //    terminal state: winType == 'draw' with winnerId == null. Any OTHER
    //    win type with a null winner is a bug.
    if (post.isGameOver) {
      if (post.winType == null) {
        findings.add(OracleFinding(
          kind: 'invariant',
          message: 'Game is over but winType is null after $actionLabel',
        ));
      } else if (post.winnerId == null && post.winType != 'draw') {
        findings.add(OracleFinding(
          kind: 'invariant',
          message: 'Game is over (winType=${post.winType}) but winnerId is null '
              'after $actionLabel',
        ));
      }
    } else if (post.winnerId != null) {
      findings.add(OracleFinding(
        kind: 'invariant',
        message: 'winnerId is set (${post.winnerId}) but game is not over '
            'after $actionLabel',
      ));
    }

    return findings;
  }

  /// Run the per-effect resource oracle for a PLAYED card. [pre]/[post] are the
  /// whole-game snapshots straddling the play; [card] is the card played;
  /// [masteryThresholdMet], [allyTriggered] describe which effect sets resolved
  /// (computed by the runner from pre-state, since both gate on it).
  ///
  /// Returns a semantic-mismatch finding when the actor's actual flat-resource
  /// delta disagrees with the independently-computed expected delta on a
  /// dimension the card's effects touch. Returns an empty list when the play is
  /// consistent OR when the card has any effect whose magnitude the oracle can't
  /// re-derive from pre-state (conservative: no false positives).
  List<OracleFinding> checkPlay({
    required GameSnapshot pre,
    required GameSnapshot post,
    required CardModel card,
    required bool masteryThresholdMet,
    required bool allyTriggered,
  }) {
    final actorId = pre.currentPlayerId;
    final preP = pre.players[actorId];
    final postP = post.players[actorId];
    if (preP == null || postP == null) return const [];

    // If the game ended on this play, the comparison is unreliable (elimination
    // cleanup moves many cards). Skip — invariants still ran.
    if (post.isGameOver) return const [];

    // Which effect lists resolved, mirroring _resolvePlayOrMastery:
    //   * masteryReplaces + threshold met  -> masteryBonus ONLY
    //   * else                             -> playEffects + (masteryBonus if met)
    //   * plus allyAbility if it triggered
    final effects = <CardEffect>[];
    if (card.masteryReplaces && masteryThresholdMet) {
      effects.addAll(card.masteryBonus);
    } else {
      effects.addAll(card.playEffects);
      if (masteryThresholdMet) effects.addAll(card.masteryBonus);
    }
    if (allyTriggered) effects.addAll(card.allyAbility);

    final expected = _expectedDelta(effects);
    if (expected == null) {
      // Contains an effect we can't re-derive — stay silent (conservative).
      return const [];
    }

    // The actual delta for the actor. Note: playing the card itself removed it
    // from hand (hand -1), so the "hand" expectation must account for the play.
    // A champion goes to championsInPlay (hand -1, not a discard); a regular/
    // mercenary goes to playedThisTurn (still out of hand). Either way the card
    // left the hand, so baseline hand delta = -1, plus any draw effects.
    const baselineHand = -1;
    final actual = ResourceDelta()
      ..gems = postP.gems - preP.gems
      ..power = postP.power - preP.power
      ..mastery = postP.mastery - preP.mastery
      ..health = postP.health - preP.health
      ..hand = postP.handCount - preP.handCount;

    expected.hand += baselineHand;

    final findings = <OracleFinding>[];
    void cmp(String dim, int exp, int act) {
      if (exp != act) {
        findings.add(OracleFinding(
          kind: 'semantic-mismatch',
          message: '${card.id}: $dim expected $exp, engine gave $act '
              '(text: "${_effectsText(effects)}")',
          card: card.id,
          effect: _effectsText(effects),
          expectedDelta: expected.toMap(),
          actualDelta: actual.toMap(),
        ));
      }
    }

    cmp('gems', expected.gems, actual.gems);
    cmp('power', expected.power, actual.power);
    cmp('mastery', expected.mastery, actual.mastery);
    // Health: opponent-loss / all-players-loss can change the ACTOR's health
    // only via AllPlayersLoseHealthEffect, which _expectedDelta accounts for.
    cmp('health', expected.health, actual.health);
    cmp('hand', expected.hand, actual.hand);

    return findings;
  }

  /// Independently compute the expected ACTOR-resource delta for a flat list of
  /// effects, or null if ANY effect's magnitude isn't re-derivable from a card's
  /// static declaration alone (we then decline to assert — see class docs).
  ResourceDelta? _expectedDelta(List<CardEffect> effects) {
    final d = ResourceDelta();
    for (final e in effects) {
      switch (e) {
        case GainGemsEffect():
          d.gems += e.amount;
        case GainPowerEffect():
          d.power += e.amount;
        case GainMasteryEffect():
          d.mastery += e.amount;
        case GainHealthEffect():
          d.health += e.amount;
        case DrawCardsEffect():
          // Net +count to hand (draw pulls from draw pile, possibly reshuffling
          // discard — but hand SIZE still rises by count unless the player has
          // fewer than count total cards, which we can detect upstream; treat
          // the common case as +count and let the conservation invariant catch
          // the pathological one).
          d.hand += e.count;
        case AllPlayersLoseHealthEffect():
          // Hits the actor too — actor health -= amount.
          d.health -= e.amount;

        // --- Effects that touch the actor's resources but NOT in a way that is
        //     a fixed amount, OR that target opponents / zones rather than the
        //     actor's flat resources. We can't (or needn't) put a fixed number
        //     on the actor delta, so the WHOLE play becomes unverifiable for the
        //     flat oracle. Returning null = "decline to assert" (conservative).
        case ScalingResourceEffect():
        case ConditionalPowerEffect():
        case ConditionalEffect():
        case ChooseOneEffect():
        case InfinityShardEffect():
        case DoublePowerEffect():
        case CopyAllPlayedCardsEffect():
          return null;

        // --- Deferred-selection / zone effects that DON'T change the actor's
        //     flat gems/power/mastery/health at play time (they resolve on a
        //     follow-up engine call). They contribute zero to the play-time
        //     delta, so we can keep verifying the flat dimensions around them.
        case BanishCardEffect():
        case ScrapFromCenterRowEffect():
        case SelfBanishEffect():
        case ResetChampionEffect():
        case DestroyChampionEffect():
        case ReturnFromDiscardEffect():
        case ReturnFromDiscardToDeckTopEffect():
        case MillEffect():
        case RecruitToHandEffect():
        case ReturnSelfWhenChampionPlayedEffect():
        case AcquireCostReductionPerChampionEffect():
        case BonusDrawNextTurnOnUnblockedDamageEffect():
        case RecruitFromCenterEffect():
        case FastPlayFromCenterEffect():
        case ScryEffect():
        case CenterDeckScryEffect():
        case TreatFactionAsEffect():
        case IgnoreShieldThisTurnEffect():
        case IgnoreGuardThisTurnEffect():
        case AddStaticModifierEffect():
        case TuckUnderChampionEffect():
        case CopyUnderCardsEffect():
        case CopyPlayedCardEffect():
        case RedirectNextRecruitEffect():
          // No actor flat-resource delta at play time. BUT some of these move
          // cards between the actor's own zones (return-from-discard adds to
          // hand on a follow-up call; recruit/fast-play affect center). At PLAY
          // time none of them change hand size, so they're safe to skip here.
          break;

        // --- Opponent-targeting effects: zero actor delta, but they CHANGE
        //     opponent state, which the conservation/health invariants cover.
        case OpponentLosesHealthEffect():
        case OpponentLosesMasteryEffect():
        case OpponentDrawsEffect():
        case OpponentDiscardsEffect():
          break;

        case GainMoneyEffect():
          break; // legacy, unused in GameService
      }
    }
    return d;
  }

  String _effectsText(List<CardEffect> effects) =>
      effects.map((e) => e.description).join('; ');
}

/// Helper: does a card's mastery threshold apply for a player at [mastery]?
bool masteryThresholdMetFor(CardModel card, int mastery) =>
    card.masteryThreshold != null &&
    card.masteryBonus.isNotEmpty &&
    mastery >= card.masteryThreshold!;

/// Helper exposed for the runner: is this card a champion (so the runner knows
/// the post-play zone)? Kept here to avoid importing CardType at the call site.
bool isChampionCard(CardModel card) => card.cardType == CardType.champion;
