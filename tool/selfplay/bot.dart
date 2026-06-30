// Self-play bot brain — dev-only.
//
// Two modes, both driving an in-process [GameService] (Tier A — see
// ai-docs/self_play_bots_design.md §0/§2):
//
//   * greedy   — reuses [AiService] verbatim. Sane, repeatable games; good
//                baseline data, reaches normal end states.
//   * explorer — among the LEGAL actions each step, pick a random one (weighted
//                so games still terminate). Deliberately reaches rare orderings
//                a greedy bot never would (activate-before-play, banish-your-own
//                key card, claim-Destiny-mid-combat, ...). This is the bug-hunter.
//
// The bot does NOT need to be good. It needs to (a) only attempt legal moves,
// (b) eventually end games, and (c) cover variety. Skill is a non-goal.

import 'dart:math';

import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/services/game_service.dart';

/// One legal action the bot can take this step, as a closure over the engine.
/// `apply` performs it and returns whether the engine accepted it.
class BotAction {
  BotAction(this.label, this.apply, {this.card});

  final String label;
  final bool Function() apply;

  /// The card implicated by this action (for the oracle / bug reports), if any.
  final CardModel? card;
}

enum BotMode { greedy, explorer }

/// Drives one player's full turn against an in-process [GameService].
///
/// A [SelfPlayBot] does not own the game — the runner owns it and hands the bot
/// the turn when `game.currentPlayer.id == playerId`. The bot acts one action at
/// a time so the runner can interleave the oracle/checker between actions.
class SelfPlayBot {
  SelfPlayBot({
    required this.game,
    required this.playerId,
    required this.mode,
    required this.random,
  });

  final GameService game;
  final String playerId;
  final BotMode mode;
  final Random random;

  bool get _isMyTurn =>
      !game.isGameOver && game.currentPlayer.id == playerId;

  /// Plays the bot's whole turn. Each [step] does exactly one engine action so
  /// the runner can snapshot + check around it; we loop until [step] reports the
  /// turn is over (it ends the turn itself).
  ///
  /// [onAction] is invoked AFTER each accepted action with the [BotAction] that
  /// produced it, so the runner can run the oracle against the resulting delta.
  Future<void> takeTurn({
    required void Function(BotAction action) onAction,
  }) async {
    if (!_isMyTurn) return;

    switch (mode) {
      case BotMode.greedy:
        // Greedy reproduces AiService's phase order (play → activate → buy →
        // attack → end) via the shared legal-move enumerator, always taking the
        // GREEDY-preferred action — so the runner gets per-action oracle hooks
        // that AiService.takeTurn can't provide.
        await _drivenTurn(onAction: onAction, greedy: true);
      case BotMode.explorer:
        await _drivenTurn(onAction: onAction, greedy: false);
    }
  }

  /// One self-driven turn: repeatedly enumerate legal actions and take one until
  /// the turn ends. Guards against runaway loops with a hard action cap.
  Future<void> _drivenTurn({
    required void Function(BotAction action) onAction,
    required bool greedy,
  }) async {
    const maxActionsPerTurn = 200; // safety: a turn should never need this many
    var taken = 0;

    while (_isMyTurn && taken < maxActionsPerTurn) {
      final actions = enumerateLegalActions();
      if (actions.isEmpty) break; // nothing left but to end the turn

      final BotAction chosen =
          greedy ? _greedyPick(actions) : _explorerPick(actions);

      final accepted = chosen.apply();
      taken++;
      if (accepted) {
        onAction(chosen);
      }
      // If the action ended the turn (endTurn), the loop guard `_isMyTurn`
      // catches it on the next iteration.
      if (chosen.label == 'endTurn') break;
    }

    // Safety net: if we somehow exhausted the cap without ending the turn, end
    // it so the game can progress.
    if (_isMyTurn) {
      game.endTurn();
    }
  }

  // ---------------------------------------------------------------------------
  // Legal-move enumeration (read straight off GameService — Tier A)
  // ---------------------------------------------------------------------------

  /// All actions the bot may legally attempt right now. The engine is the final
  /// arbiter (each `apply` returns false if rejected), but we only enumerate
  /// moves we believe legal so the bot makes progress.
  List<BotAction> enumerateLegalActions() {
    final p = game.currentPlayer;
    final actions = <BotAction>[];

    // Play any card from hand. Deferred-selection effects (banish/destroy/etc.)
    // resolve to a no-op at play time and complete on a follow-up engine call;
    // the runner's checker treats those as deferred-pending. We do not attempt
    // the follow-up selection here (the greedy AiService also leaves them), so
    // those effects exercise the play path but not the selection path in Tier A.
    for (final card in List<CardModel>.from(p.hand)) {
      final choice = _choiceIndexFor(card);
      actions.add(BotAction(
        'play:${card.id}',
        () => game.playCard(card.id, choiceIndex: choice),
        card: card,
      ));
    }

    // Activate champions that haven't used their free play-effect activation.
    for (final champ in List<CardModel>.from(p.championsInPlay)) {
      if (!p.activatedChampions.contains(champ.id)) {
        actions.add(BotAction(
          'activate:${champ.id}',
          () => game.activateChampion(champ.id),
          card: champ,
        ));
      }
      // Use a champion's Exhaust-gated activated ability if available + payable.
      if (champ.activatedAbility != null &&
          !p.exhaustedChampions.contains(champ.id)) {
        actions.add(BotAction(
          'ability:${champ.id}',
          () => game.useActivatedAbility(champ.id),
          card: champ,
        ));
      }
    }

    // Buy any affordable center-row card.
    for (final card in List<CardModel>.from(game.centerRow)) {
      if (card.cost <= p.gemPool) {
        actions.add(BotAction(
          'buy:${card.id}',
          () => game.buyCard(card.id),
          card: card,
        ));
      }
    }

    // Focus (spend 1 gem → 1 mastery), once per turn.
    if (!p.focusedThisTurn && p.gemPool >= 1) {
      actions.add(BotAction('focus', () => game.focus()));
    }

    // Claim a face-up Destiny (free, at mastery >= 5, under the per-game limit).
    if (p.canClaimAnotherDestiny && p.mastery >= 5) {
      for (final destiny in List<CardModel>.from(game.destinyRow)) {
        actions.add(BotAction(
          'claimDestiny:${destiny.id}',
          () => game.claimDestiny(destiny.id),
          card: destiny,
        ));
      }
    }

    // Use a claimed Destiny's per-turn ability.
    for (final destiny in List<CardModel>.from(p.claimedDestinies)) {
      if (game.canUseDestinyAbility(destiny.id)) {
        actions.add(BotAction(
          'useDestiny:${destiny.id}',
          () => game.useDestinyAbility(destiny.id),
          card: destiny,
        ));
      }
    }

    // Attacks (only when we have power). Attack a champion or a player.
    if (p.powerPool > 0) {
      final opponents =
          game.players.where((o) => o.id != playerId && !o.isEliminated);
      for (final opp in opponents) {
        for (final champ in List<CardModel>.from(opp.championsInPlay)) {
          if (p.powerPool >= champ.shield) {
            actions.add(BotAction(
              'attackChampion:${champ.id}',
              () => game.attackChampion(champ.id, opp.id),
              card: champ,
            ));
          }
        }
        // Attack the player directly (blocked by guard inside the engine — if
        // rejected, `apply` returns false and the runner ignores it).
        final hasGuard = opp.championsInPlay.any((c) => c.hasGuard);
        if (!hasGuard) {
          actions.add(BotAction(
            'attackPlayer:${opp.id}',
            () => game.attackPlayer(opp.id, p.powerPool),
          ));
        }
      }
    }

    // Always offer to end the turn.
    actions.add(BotAction('endTurn', () {
      game.endTurn();
      return true;
    }));

    return actions;
  }

  // ---------------------------------------------------------------------------
  // Action selection
  // ---------------------------------------------------------------------------

  /// Public selection entry points so an external driver (the runner) can pick
  /// the bot's action for a step while still owning the pre/post snapshotting.
  BotAction pickGreedy(List<BotAction> actions) => _greedyPick(actions);
  BotAction pickExplorer(List<BotAction> actions) => _explorerPick(actions);

  /// Greedy: prefer to drain the hand, then activate, then buy the most
  /// expensive affordable card, then attack, and only end the turn when nothing
  /// else productive remains — mirroring AiService's phase order.
  BotAction _greedyPick(List<BotAction> actions) {
    BotAction? best;
    int bestScore = -1;
    for (final a in actions) {
      final score = _greedyScore(a);
      if (score > bestScore) {
        bestScore = score;
        best = a;
      }
    }
    return best ?? actions.last;
  }

  int _greedyScore(BotAction a) {
    final label = a.label;
    if (label.startsWith('play:')) return 100;
    if (label.startsWith('activate:')) return 90;
    if (label.startsWith('ability:')) return 85;
    if (label.startsWith('useDestiny:')) return 80;
    if (label == 'focus') return 70;
    if (label.startsWith('buy:')) {
      // Prefer the most expensive affordable card (cost is a decent proxy).
      return 50 + (a.card?.cost ?? 0);
    }
    if (label.startsWith('claimDestiny:')) return 40;
    if (label.startsWith('attackChampion:')) return 30;
    if (label.startsWith('attackPlayer:')) return 20;
    if (label == 'endTurn') return 0;
    return 10;
  }

  /// Explorer: pick a random legal action, but BIAS away from ending the turn
  /// early (so games still progress and the bot exercises mid-turn orderings)
  /// and bias toward play/recruit so the board actually develops.
  BotAction _explorerPick(List<BotAction> actions) {
    final nonEnd = actions.where((a) => a.label != 'endTurn').toList();
    if (nonEnd.isEmpty) {
      return actions.firstWhere((a) => a.label == 'endTurn');
    }

    // Weighted reservoir: give productive actions higher weight, but keep a
    // small chance of ending the turn so turns don't run to the safety cap.
    final weighted = <BotAction>[];
    for (final a in actions) {
      final w = _explorerWeight(a);
      for (var i = 0; i < w; i++) {
        weighted.add(a);
      }
    }
    return weighted[random.nextInt(weighted.length)];
  }

  int _explorerWeight(BotAction a) {
    final label = a.label;
    if (label.startsWith('play:')) return 6;
    if (label.startsWith('buy:')) return 5;
    if (label.startsWith('activate:')) return 4;
    if (label.startsWith('ability:')) return 4;
    if (label.startsWith('claimDestiny:')) return 3;
    if (label.startsWith('useDestiny:')) return 3;
    if (label == 'focus') return 3;
    if (label.startsWith('attackChampion:')) return 3;
    if (label.startsWith('attackPlayer:')) return 3;
    if (label == 'endTurn') return 1; // small but nonzero — lets turns end
    return 2;
  }

  /// Pick the better ChooseOneEffect branch (reuses AiService's heuristic spirit:
  /// gems when low, else power). Returns 0 for cards without a choice.
  int _choiceIndexFor(CardModel card) {
    final choose = card.playEffects.whereType<ChooseOneEffect>().firstOrNull;
    if (choose == null) return 0;
    // Explorer mode: random branch (more coverage). Greedy: gem/power heuristic.
    if (mode == BotMode.explorer) {
      return random.nextInt(choose.choices.length);
    }
    final gems = game.currentPlayer.gemPool;
    var bestIndex = 0;
    var bestScore = -1;
    for (var i = 0; i < choose.choices.length; i++) {
      var score = 0;
      for (final e in choose.choices[i]) {
        if (e is GainGemsEffect) {
          score += gems < 3 ? e.amount * 3 : e.amount;
        } else if (e is GainPowerEffect) {
          score += gems >= 3 ? e.amount * 3 : e.amount;
        } else if (e is GainMasteryEffect) {
          score += e.amount * 2;
        } else if (e is DrawCardsEffect) {
          score += e.count * 2;
        } else {
          score += 1;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }
    return bestIndex;
  }
}
