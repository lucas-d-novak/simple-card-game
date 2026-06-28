import 'dart:math';

import 'package:simple_card_game/data/card_definitions.dart';
import 'package:simple_card_game/data/starter_deck.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/models/player_state.dart';

/// Orchestrates a Shards of Infinity game: turn lifecycle, effect resolution,
/// market management, and multi-player turn rotation.
class GameService {
  GameService({
    required int playerCount,
    Random? random,
  })  : _random = random ?? Random(),
        assert(playerCount >= 2 && playerCount <= 4) {
    _initializeGame(playerCount);
  }

  final Random _random;
  final List<PlayerState> players = [];
  final List<CardModel> centerRow = [];
  final List<CardModel> infinityDeck = [];
  final List<CardModel> removedFromGame = [];
  int currentPlayerIndex = 0;
  int turnNumber = 1;
  bool _gameOver = false;

  /// The ID of the player who won, or null if the game is still in progress.
  String? winnerId;

  PlayerState get currentPlayer => players[currentPlayerIndex];
  bool get isGameOver => _gameOver;

  // -------------------------------------------------------------------------
  // Initialization
  // -------------------------------------------------------------------------

  void _initializeGame(int playerCount) {
    // Create players with starter decks
    for (int i = 0; i < playerCount; i++) {
      final player = PlayerState(id: 'p$i', name: 'Player ${i + 1}');
      final deck = buildStarterDeck('p$i');
      player.drawPile.addAll(deck);
      player.drawPile.shuffle(_random);
      players.add(player);
    }

    // Build and shuffle infinity deck, deal center row
    infinityDeck.addAll(_buildInfinityDeck());
    infinityDeck.shuffle(_random);
    _refillCenterRow();

    // Draw initial hands: all players start with 5 cards
    for (int i = 0; i < players.length; i++) {
      _drawCards(players[i], 5);
    }
  }

  // -------------------------------------------------------------------------
  // Turn lifecycle
  // -------------------------------------------------------------------------

  /// Start of turn — no longer auto-triggers champions.
  /// Champions must be manually activated by the player via [activateChampion].
  void startTurn() {
    // Champions are now manually activated — nothing to auto-trigger.
  }

  /// Manually activate a champion's effects for this turn.
  /// Each champion can only be activated once per turn.
  /// Returns true if the champion was found and activated.
  bool activateChampion(String championId) {
    if (_gameOver) return false;
    final player = currentPlayer;

    final champion = player.championsInPlay
        .where((c) => c.id == championId)
        .firstOrNull;
    if (champion == null) return false;

    // Already activated this turn
    if (player.activatedChampions.contains(championId)) return false;

    player.activatedChampions.add(championId);
    _resolveEffects(champion.playEffects, player);
    _checkMasteryBonus(champion, player);
    _checkAllyAbility(champion, player);
    return true;
  }

  /// Play a card from the current player's hand.
  ///
  /// [choiceIndex] selects which option for ChooseOneEffect cards (default 0).
  /// Returns true if the card was found and played.
  bool playCard(String cardId, {int choiceIndex = 0}) {
    final player = currentPlayer;
    final handIndex = player.hand.indexWhere((c) => c.id == cardId);
    if (handIndex == -1) return false;

    final card = player.hand.removeAt(handIndex);

    // Step 13a: champions go to championsInPlay, not playedThisTurn
    if (card.cardType == CardType.champion) {
      player.championsInPlay.add(card);
    } else {
      player.playedThisTurn.add(card);
    }

    // Resolve play effects
    _resolveEffects(card.playEffects, player, choiceIndex: choiceIndex);

    // Step 11: check mastery threshold bonus
    _checkMasteryBonus(card, player);

    // Step 9: check ally ability
    _checkAllyAbility(card, player);

    return true;
  }

  /// Play all cards in the current player's hand, left to right.
  /// Returns the number of cards played.
  int playAllCards() {
    int played = 0;
    while (currentPlayer.hand.isNotEmpty) {
      if (playCard(currentPlayer.hand.first.id)) {
        played++;
      } else {
        break;
      }
    }
    return played;
  }

  /// Buy a card from the center row using gems.
  /// Returns true if the purchase succeeded.
  bool buyCard(String cardId) {
    final rowIndex = centerRow.indexWhere((c) => c.id == cardId);
    if (rowIndex == -1) return false;

    final card = centerRow[rowIndex];
    if (currentPlayer.gemPool < card.cost) return false;

    currentPlayer.gemPool -= card.cost;
    centerRow.removeAt(rowIndex);
    currentPlayer.discardPile.add(card);
    _refillCenterRow();

    return true;
  }

  /// End the current player's turn: cleanup, draw, advance.
  void endTurn() {
    final player = currentPlayer;

    // Discard remaining hand cards (unplayed cards go to discard)
    player.discardPile.addAll(player.hand);
    player.hand.clear();

    // Cleanup: move played cards to discard, separate mercenaries
    final mercenaries = player.cleanupTurn();
    removedFromGame.addAll(mercenaries);

    // Reset per-turn resources
    player.resetTurnResources();

    // Draw 5 cards for end-of-turn (mechanics doc Section 4d)
    _drawCards(player, 5);

    // Advance to next non-eliminated player
    _advanceTurn();
  }

  // -------------------------------------------------------------------------
  // Combat system (Steps 10, 13b)
  // -------------------------------------------------------------------------

  /// Attack a champion controlled by another player.
  ///
  /// Spends power from the current player's powerPool equal to the champion's
  /// shield value. The destroyed champion goes to its owner's discard pile.
  /// Returns true if the attack succeeded.
  bool attackChampion(String championId, String targetPlayerId) {
    if (_gameOver) return false;

    final target = players.firstWhere(
      (p) => p.id == targetPlayerId,
      orElse: () => currentPlayer, // fallback, will fail below
    );
    if (target.id == currentPlayer.id) return false;

    final champIndex =
        target.championsInPlay.indexWhere((c) => c.id == championId);
    if (champIndex == -1) return false;

    final champion = target.championsInPlay[champIndex];
    if (currentPlayer.powerPool < champion.shield) return false;

    currentPlayer.powerPool -= champion.shield;
    target.championsInPlay.removeAt(champIndex);
    target.discardPile.add(champion);

    return true;
  }

  /// Attack a player directly, spending power to deal damage.
  ///
  /// Fails if the target has any guard champions in play (they must be
  /// destroyed first). Deducts from powerPool and calls target.takeDamage().
  /// Returns true if the attack succeeded.
  bool attackPlayer(String targetPlayerId, int amount) {
    if (_gameOver) return false;
    if (amount <= 0) return false;

    final target = players.firstWhere(
      (p) => p.id == targetPlayerId,
      orElse: () => currentPlayer,
    );
    if (target.id == currentPlayer.id) return false;
    if (target.isEliminated) return false;

    // Guard check: target must have no guard champions
    final hasGuard = target.championsInPlay.any((c) => c.hasGuard);
    if (hasGuard) return false;

    if (currentPlayer.powerPool < amount) return false;

    currentPlayer.powerPool -= amount;
    target.takeDamage(amount);

    // Check elimination and clean up zones if the target was just eliminated
    if (target.isEliminated) {
      _cleanupEliminatedPlayer(target);
      _checkGameOver();
    }

    return true;
  }

  // -------------------------------------------------------------------------
  // Banish & Scrap (Step 8)
  // -------------------------------------------------------------------------

  /// Banish a card from the current player's hand or discard pile.
  ///
  /// The card is permanently removed from the game.
  /// Returns true if the card was found and banished.
  bool banishCard(String cardId, BanishSource source) {
    final player = currentPlayer;

    switch (source) {
      case BanishSource.hand:
        return _banishFromZone(player.hand, cardId);
      case BanishSource.discard:
        return _banishFromZone(player.discardPile, cardId);
      case BanishSource.handOrDiscard:
        // Try hand first, then discard
        if (_banishFromZone(player.hand, cardId)) return true;
        return _banishFromZone(player.discardPile, cardId);
    }
  }

  bool _banishFromZone(List<CardModel> zone, String cardId) {
    final index = zone.indexWhere((c) => c.id == cardId);
    if (index == -1) return false;
    final card = zone.removeAt(index);
    removedFromGame.add(card);
    return true;
  }

  /// Scrap a card from the center row (remove without buying).
  ///
  /// The card is permanently removed from the game and the center row refills.
  /// Returns true if the card was found and scrapped.
  bool scrapFromCenterRow(String cardId) {
    final index = centerRow.indexWhere((c) => c.id == cardId);
    if (index == -1) return false;

    final card = centerRow.removeAt(index);
    removedFromGame.add(card);
    _refillCenterRow();
    return true;
  }

  // -------------------------------------------------------------------------
  // Effect resolution
  // -------------------------------------------------------------------------

  void _resolveEffects(
    List<CardEffect> effects,
    PlayerState player, {
    int choiceIndex = 0,
  }) {
    for (final effect in effects) {
      switch (effect) {
        case GainGemsEffect():
          player.gemPool += effect.amount;
        case GainPowerEffect():
          player.powerPool += effect.amount;
        case GainMasteryEffect():
          player.addMastery(effect.amount);
        case GainHealthEffect():
          player.heal(effect.amount);
        case DrawCardsEffect():
          _drawCards(player, effect.count);
        case OpponentLosesHealthEffect():
          _applyOpponentHealthLoss(player, effect.amount);
        case ChooseOneEffect():
          final idx = choiceIndex.clamp(0, effect.choices.length - 1);
          _resolveEffects(effect.choices[idx], player);
        case ConditionalPowerEffect():
          player.powerPool += _evaluateCondition(effect.condition, player);
        case BanishCardEffect():
          // Requires card selection — auto-banish not possible without target.
          // The player should call banishCard() separately after this effect.
          break;
        case ScrapFromCenterRowEffect():
          // Requires card selection — the player should call
          // scrapFromCenterRow() separately after this effect.
          break;
        case InfinityShardEffect():
          _resolveInfinityShard(player);
        case GainMoneyEffect():
          // Legacy effect from DeckService — not used in GameService
          break;
      }
    }
  }

  // -------------------------------------------------------------------------
  // Infinity Shard scaling (Step 12)
  // -------------------------------------------------------------------------

  void _resolveInfinityShard(PlayerState player) {
    // Always gain 1 Mastery first
    player.addMastery(1);
    final m = player.mastery;

    // Check win AFTER adding mastery (playing at 29 → 30 = win)
    if (m >= 30) {
      _gameOver = true;
      winnerId = player.id;
      return;
    }

    // Power scales with mastery tier (evaluated after mastery gain)
    int power;
    if (m >= 25) {
      power = 20;
    } else if (m >= 20) {
      power = 15;
    } else if (m >= 15) {
      power = 10;
    } else if (m >= 10) {
      power = 6;
    } else if (m >= 5) {
      power = 3;
    } else {
      power = 0;
    }
    player.powerPool += power;
  }

  // -------------------------------------------------------------------------
  // Ally abilities (Step 9)
  // -------------------------------------------------------------------------

  /// Check if the played card's ally ability should trigger.
  ///
  /// An ally ability triggers if the player already has another card of the
  /// same faction in play (playedThisTurn or championsInPlay).
  /// Cards with countsAsAllFactions count as every faction.
  void _checkAllyAbility(CardModel card, PlayerState player) {
    if (card.allyAbility.isEmpty) return;
    if (card.faction == Faction.none && !card.countsAsAllFactions) return;

    if (_hasAllyInPlay(card, player)) {
      _resolveEffects(card.allyAbility, player);
    }
  }

  /// Returns true if the player has another card of the same faction already
  /// in play (playedThisTurn or championsInPlay).
  bool _hasAllyInPlay(CardModel card, PlayerState player) {
    final cardFaction = card.faction;

    // Check playedThisTurn for same-faction cards (excluding the card itself)
    for (final other in player.playedThisTurn) {
      if (other.id == card.id) continue;
      if (_factionsMatch(cardFaction, card.countsAsAllFactions,
          other.faction, other.countsAsAllFactions)) {
        return true;
      }
    }

    // Check championsInPlay for same-faction cards (excluding the card itself)
    for (final other in player.championsInPlay) {
      if (other.id == card.id) continue;
      if (_factionsMatch(cardFaction, card.countsAsAllFactions,
          other.faction, other.countsAsAllFactions)) {
        return true;
      }
    }

    return false;
  }

  /// Returns true if two cards' factions match for ally ability purposes.
  /// A card with countsAsAllFactions matches any non-none faction.
  bool _factionsMatch(
    Faction factionA, bool allFactionsA,
    Faction factionB, bool allFactionsB,
  ) {
    // If either is factionless and doesn't count as all factions, no match
    if (factionA == Faction.none && !allFactionsA) return false;
    if (factionB == Faction.none && !allFactionsB) return false;

    // If either counts as all factions, it matches any non-none faction
    if (allFactionsA || allFactionsB) return true;

    return factionA == factionB;
  }

  // -------------------------------------------------------------------------
  // Mastery threshold (Step 11)
  // -------------------------------------------------------------------------

  void _checkMasteryBonus(CardModel card, PlayerState player) {
    if (card.masteryThreshold == null) return;
    if (card.masteryBonus.isEmpty) return;
    if (player.mastery >= card.masteryThreshold!) {
      _resolveEffects(card.masteryBonus, player);
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  void _applyOpponentHealthLoss(PlayerState attacker, int amount) {
    // Damage all living opponents (per mechanics doc Section 18: multiplayer
    // eliminates all opponents on Infinity Shard win; direct health-loss effects
    // like Blood Ritualist hit every opponent).
    for (final player in players) {
      if (player.id != attacker.id && !player.isEliminated) {
        player.takeDamage(amount);
        if (player.isEliminated) {
          _cleanupEliminatedPlayer(player);
        }
      }
    }
    _checkGameOver();
  }

  int _evaluateCondition(PowerCondition condition, PlayerState player) {
    switch (condition) {
      case PowerCondition.perChampionControlled:
        return player.championsInPlay.length;
    }
  }

  // -------------------------------------------------------------------------
  // Drawing
  // -------------------------------------------------------------------------

  void _drawCards(PlayerState player, int count) {
    for (int i = 0; i < count; i++) {
      if (player.drawPile.isEmpty && player.discardPile.isNotEmpty) {
        player.drawPile.addAll(player.discardPile);
        player.discardPile.clear();
        player.drawPile.shuffle(_random);
      }
      if (player.drawPile.isEmpty) break;
      player.hand.add(player.drawPile.removeLast());
    }
  }

  // -------------------------------------------------------------------------
  // Market / Center Row
  // -------------------------------------------------------------------------

  void _refillCenterRow() {
    while (centerRow.length < 6 && infinityDeck.isNotEmpty) {
      centerRow.add(infinityDeck.removeLast());
    }
  }

  /// Builds the infinity deck from the full card catalog with realistic copy
  /// counts based on card cost:
  ///   Cost 1-2: 4 copies each
  ///   Cost 3-4: 3 copies each
  ///   Cost 5-6: 2 copies each
  ///   Cost 7-8: 1 copy each
  ///   Neutral (faction == none): 3 copies each (overrides cost-based rule)
  List<CardModel> _buildInfinityDeck() {
    final List<CardModel> deck = [];
    for (final template in allInfinityDeckCards) {
      int copies;
      if (template.faction == Faction.none) {
        copies = 3;
      } else if (template.cost <= 2) {
        copies = 4;
      } else if (template.cost <= 4) {
        copies = 3;
      } else if (template.cost <= 6) {
        copies = 2;
      } else {
        copies = 1;
      }
      for (int copy = 0; copy < copies; copy++) {
        deck.add(CardModel(
          id: '${template.id}_$copy',
          name: template.name,
          cost: template.cost,
          playEffects: template.playEffects,
          faction: template.faction,
          cardType: template.cardType,
          shield: template.shield,
          hasGuard: template.hasGuard,
          allyAbility: template.allyAbility,
          masteryThreshold: template.masteryThreshold,
          masteryBonus: template.masteryBonus,
          countsAsAllFactions: template.countsAsAllFactions,
        ));
      }
    }
    return deck;
  }

  // -------------------------------------------------------------------------
  // Turn management
  // -------------------------------------------------------------------------

  void _advanceTurn() {
    final startIndex = currentPlayerIndex;
    do {
      currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
      if (currentPlayerIndex == 0) {
        turnNumber++;
      }
    } while (players[currentPlayerIndex].isEliminated &&
        currentPlayerIndex != startIndex);

    // Check if only one player remains
    _checkGameOver();
    if (_gameOver) return;

    startTurn();
  }

  void _checkGameOver() {
    final alive = players.where((p) => !p.isEliminated).toList();
    if (alive.length <= 1) {
      _gameOver = true;
      if (alive.length == 1) {
        winnerId = alive.first.id;
      }
    }
  }

  /// Clear all card zones for an eliminated player and move those cards to
  /// [removedFromGame]. Per mechanics doc Section 18: "The eliminated player
  /// removes all their cards from the game (hand, deck, discard pile, and any
  /// Champions in play)."
  void _cleanupEliminatedPlayer(PlayerState player) {
    removedFromGame.addAll(player.hand);
    player.hand.clear();

    removedFromGame.addAll(player.drawPile);
    player.drawPile.clear();

    removedFromGame.addAll(player.discardPile);
    player.discardPile.clear();

    removedFromGame.addAll(player.playedThisTurn);
    player.playedThisTurn.clear();

    removedFromGame.addAll(player.championsInPlay);
    player.championsInPlay.clear();
  }
}
