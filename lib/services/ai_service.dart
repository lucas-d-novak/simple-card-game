import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/services/game_service.dart';

/// AI opponent that plays a full turn automatically using reasonable heuristics.
///
/// The AI follows a simple "normal" difficulty strategy:
/// 1. Play all hand cards (choosing gems if low, else power for ChooseOneEffect)
/// 2. Activate all champions
/// 3. Buy the most expensive affordable card, repeating until broke
/// 4. Attack guard champions first, then the weakest opponent
/// 5. End turn
class AiService {
  AiService({required this.game, required this.aiPlayerId});

  final GameService game;
  final String aiPlayerId;

  /// Small delay between phases so the UI can update visually.
  Duration phaseDelay = const Duration(milliseconds: 300);

  /// Plays an entire turn for the AI player.
  ///
  /// Assumes it is currently this AI player's turn (i.e.
  /// `game.currentPlayer.id == aiPlayerId`).
  Future<void> takeTurn() async {
    if (game.isGameOver) return;
    if (game.currentPlayer.id != aiPlayerId) return;

    // Phase 1: Play all hand cards
    await _playPhase();
    await Future.delayed(phaseDelay);

    // Phase 2: Activate champions
    await _activateChampionsPhase();
    await Future.delayed(phaseDelay);

    // Phase 3: Buy cards
    await _buyPhase();
    await Future.delayed(phaseDelay);

    // Phase 4: Attack
    await _attackPhase();
    await Future.delayed(phaseDelay);

    // Phase 5: End turn
    if (!game.isGameOver) {
      game.endTurn();
    }
  }

  // ---------------------------------------------------------------------------
  // Play phase
  // ---------------------------------------------------------------------------

  Future<void> _playPhase() async {
    // Play cards one at a time so we can make choices for ChooseOneEffect cards
    while (game.currentPlayer.hand.isNotEmpty && !game.isGameOver) {
      final card = game.currentPlayer.hand.first;
      final choiceIndex = _pickChoiceIndex(card);
      game.playCard(card.id, choiceIndex: choiceIndex);
    }
  }

  /// For ChooseOneEffect cards, pick the better option.
  /// Prefer gems if gems < 3, otherwise prefer power.
  int _pickChoiceIndex(CardModel card) {
    final chooseEffect =
        card.playEffects.whereType<ChooseOneEffect>().firstOrNull;
    if (chooseEffect == null) return 0;

    final currentGems = game.currentPlayer.gemPool;
    int bestIndex = 0;
    int bestScore = -1;

    for (int i = 0; i < chooseEffect.choices.length; i++) {
      int score = 0;
      for (final effect in chooseEffect.choices[i]) {
        if (effect is GainGemsEffect) {
          // Prefer gems when we have few
          score += currentGems < 3 ? effect.amount * 3 : effect.amount;
        } else if (effect is GainPowerEffect) {
          // Prefer power when we have enough gems
          score += currentGems >= 3 ? effect.amount * 3 : effect.amount;
        } else if (effect is GainHealthEffect) {
          score += effect.amount;
        } else if (effect is GainMasteryEffect) {
          score += effect.amount * 2;
        } else if (effect is DrawCardsEffect) {
          score += effect.count * 2;
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

  // ---------------------------------------------------------------------------
  // Activate champions phase
  // ---------------------------------------------------------------------------

  Future<void> _activateChampionsPhase() async {
    final champions = List<CardModel>.from(game.currentPlayer.championsInPlay);
    for (final champion in champions) {
      if (!game.currentPlayer.activatedChampions.contains(champion.id)) {
        game.activateChampion(champion.id);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Buy phase
  // ---------------------------------------------------------------------------

  Future<void> _buyPhase() async {
    while (!game.isGameOver) {
      final affordable = game.centerRow
          .where((card) => card.cost <= game.currentPlayer.gemPool)
          .toList();
      if (affordable.isEmpty) break;

      // Buy the most expensive affordable card
      affordable.sort((a, b) => b.cost.compareTo(a.cost));
      game.buyCard(affordable.first.id);
    }
  }

  // ---------------------------------------------------------------------------
  // Attack phase
  // ---------------------------------------------------------------------------

  Future<void> _attackPhase() async {
    if (game.isGameOver) return;

    final opponents = game.players
        .where((p) => p.id != aiPlayerId && !p.isEliminated)
        .toList();
    if (opponents.isEmpty) return;

    // Attack guard champions first across all opponents
    for (final opponent in opponents) {
      // Prioritize guard champions
      final guardChampions =
          opponent.championsInPlay.where((c) => c.hasGuard).toList();
      for (final champion in guardChampions) {
        if (game.currentPlayer.powerPool >= champion.health) {
          game.attackChampion(champion.id, opponent.id);
        }
      }
      // Then non-guard champions
      final otherChampions = List<CardModel>.from(
          opponent.championsInPlay.where((c) => !c.hasGuard));
      for (final champion in otherChampions) {
        if (game.currentPlayer.powerPool >= champion.health) {
          game.attackChampion(champion.id, opponent.id);
        }
      }
    }

    // Attack the player with the lowest health using remaining power
    if (game.currentPlayer.powerPool > 0) {
      final attackableOpponents = opponents
          .where(
              (p) => !p.isEliminated && !p.championsInPlay.any((c) => c.hasGuard))
          .toList();
      if (attackableOpponents.isNotEmpty) {
        attackableOpponents.sort((a, b) => a.health.compareTo(b.health));
        final target = attackableOpponents.first;
        game.attackPlayer(target.id, game.currentPlayer.powerPool);
      }
    }
  }
}
