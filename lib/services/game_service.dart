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

  /// Whether the current player may take an action. False once the game is over
  /// or the current player has been eliminated — the latter can happen mid-turn
  /// via [AllPlayersLoseHealthEffect], which is the only effect that can reduce
  /// the acting player to 0. A dead player must not keep acting; they recover
  /// the game by calling [endTurn], which advances past eliminated players.
  bool get _currentPlayerCanAct => !_gameOver && !currentPlayer.isEliminated;

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
    if (!_currentPlayerCanAct) return false;
    final player = currentPlayer;

    final champion = player.championsInPlay
        .where((c) => c.id == championId)
        .firstOrNull;
    if (champion == null) return false;

    // Already activated this turn
    if (player.activatedChampions.contains(championId)) return false;

    player.activatedChampions.add(championId);
    _resolvePlayOrMastery(champion, player);
    _checkAllyAbility(champion, player);
    return true;
  }

  /// Use a champion's Exhaust-gated activated ability.
  ///
  /// This is a SEPARATE action from [activateChampion]. [activateChampion]
  /// re-resolves the champion's normal [CardModel.playEffects] (free, once per
  /// turn). This method resolves the champion's [CardModel.activatedAbility] —
  /// an additional ability that costs an Exhaust (and optionally resources) and
  /// leaves the champion **exhausted** (tapped) until the start of the owner's
  /// next turn (the [PlayerState.exhaustedChampions] set is cleared in
  /// [PlayerState.resetTurnResources] during [endTurn]).
  ///
  /// Fails (returns false, with no state change) if: the game is over, the
  /// champion is not in play, it has no activated ability, it is already
  /// exhausted this turn, or the cost is unpayable. On success it pays the cost,
  /// resolves the ability's effects, marks the champion exhausted, and returns
  /// true. The free [activateChampion] activation remains independently
  /// available — exhausting does not consume it (and vice versa).
  bool useActivatedAbility(String championId) {
    if (!_currentPlayerCanAct) return false;
    final player = currentPlayer;

    final champion =
        player.championsInPlay.where((c) => c.id == championId).firstOrNull;
    if (champion == null) return false;

    final ability = champion.activatedAbility;
    if (ability == null) return false;

    // Already exhausted this turn — cannot reuse until next turn.
    if (player.exhaustedChampions.contains(championId)) return false;

    // Validate the cost is fully payable BEFORE mutating any state, so a
    // rejected activation is a no-op (mirrors buyCard / attackChampion).
    if (!_canPayActivationCost(player, ability.cost)) return false;

    _payActivationCost(player, ability.cost);
    player.exhaustedChampions.add(championId);
    _resolveActivatedAbility(ability, player, sourceCard: champion);
    return true;
  }

  /// Resolves an [ActivatedAbility]'s effects, honouring its optional mastery
  /// tier. When the ability has a [ActivatedAbility.masteryThreshold] the owner
  /// has reached: if [ActivatedAbility.replaces] is true the mastery effects
  /// resolve INSTEAD OF the base effects; otherwise they resolve ADDITIVELY on
  /// top. With no mastery threshold (the default), only [effects] resolve.
  void _resolveActivatedAbility(
    ActivatedAbility ability,
    PlayerState player, {
    required CardModel sourceCard,
  }) {
    final tierMet = ability.masteryThreshold != null &&
        ability.masteryBonusEffects.isNotEmpty &&
        player.mastery >= ability.masteryThreshold!;

    if (tierMet && ability.replaces) {
      _resolveEffects(ability.masteryBonusEffects, player,
          sourceCard: sourceCard);
      return;
    }

    _resolveEffects(ability.effects, player, sourceCard: sourceCard);
    if (tierMet) {
      _resolveEffects(ability.masteryBonusEffects, player,
          sourceCard: sourceCard);
    }
  }

  /// Whether [player] can afford [cost] (gems, mastery, and health are all
  /// available). Mastery and health costs must not drop the player to/below the
  /// floor that would be illegal (health must stay > 0; mastery cannot go
  /// negative).
  bool _canPayActivationCost(PlayerState player, ActivationCost cost) {
    if (cost.isFree) return true;
    if (player.gemPool < cost.gems) return false;
    if (player.mastery < cost.mastery) return false;
    // Paying health may not be lethal to oneself.
    if (cost.health > 0 && player.health <= cost.health) return false;
    return true;
  }

  void _payActivationCost(PlayerState player, ActivationCost cost) {
    player.gemPool -= cost.gems;
    player.mastery -= cost.mastery;
    if (cost.health > 0) player.takeDamage(cost.health);
  }

  /// Play a card from the current player's hand.
  ///
  /// [choiceIndex] selects which option for ChooseOneEffect cards (default 0).
  /// Returns true if the card was found and played.
  bool playCard(String cardId, {int choiceIndex = 0}) {
    if (!_currentPlayerCanAct) return false;
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

    // Record for per-turn scaling effects (ConditionalPowerEffect). Includes
    // champions and mercenaries, in play order.
    player.cardsPlayedThisTurn.add(card);

    // Resolve play effects (or, for masteryReplaces cards at threshold, the
    // mastery bonus INSTEAD; otherwise the additive mastery bonus on top).
    _resolvePlayOrMastery(card, player, choiceIndex: choiceIndex);

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
    if (!_currentPlayerCanAct) return false;
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
    if (!_currentPlayerCanAct) return false;

    final target = players.firstWhere(
      (p) => p.id == targetPlayerId,
      orElse: () => currentPlayer, // fallback, will fail below
    );
    if (target.id == currentPlayer.id) return false;

    final champIndex =
        target.championsInPlay.indexWhere((c) => c.id == championId);
    if (champIndex == -1) return false;

    final champion = target.championsInPlay[champIndex];
    // spirit_leech: while the attacker ignores shield this turn, the shield
    // value required to destroy a champion is treated as 0 (any power, including
    // 0, destroys it). The normal path is untouched when the flag is false.
    final shieldNeeded =
        currentPlayer.ignoresShieldThisTurn ? 0 : champion.shield;
    if (currentPlayer.powerPool < shieldNeeded) return false;

    currentPlayer.powerPool -= shieldNeeded;
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
    if (!_currentPlayerCanAct) return false;
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

    // Record unblocked damage dealt this turn (guard already ruled out above),
    // for GameConditionKind.unblockedDamageAtLeast (e.g. blood_for_blood).
    currentPlayer.unblockedDamageThisTurn += amount;

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

  /// Banish the in-flight source card itself ("Then, banish this"). Removes it
  /// from whichever zone it currently occupies (playedThisTurn for regular/
  /// mercenary cards, championsInPlay for champions, and always the
  /// cardsPlayedThisTurn history) so end-of-turn cleanup does not also discard
  /// it, then moves it to [removedFromGame]. A no-op if [source] is null.
  void _selfBanish(PlayerState player, CardModel? source) {
    if (source == null) return;
    player.playedThisTurn.removeWhere((c) => identical(c, source));
    player.championsInPlay.removeWhere((c) => identical(c, source));
    player.cardsPlayedThisTurn.removeWhere((c) => identical(c, source));
    removedFromGame.add(source);
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
  // Champion destruction by effect (Phase 1: DestroyChampionEffect)
  // -------------------------------------------------------------------------

  /// Destroy a specific enemy champion via a card effect (no power cost).
  ///
  /// Resolves like the destruction half of [attackChampion]: the champion is
  /// removed from its owner's [championsInPlay] and placed in their discard
  /// pile, but no power is spent and the champion's shield is irrelevant.
  /// Used to fulfil a single-target [DestroyChampionEffect] after the player
  /// has selected a target (mirrors the banishCard() deferral pattern).
  /// Returns true if the champion was found and destroyed.
  bool destroyChampion(String championId, String targetPlayerId) {
    if (!_currentPlayerCanAct) return false;

    final target =
        players.where((p) => p.id == targetPlayerId).firstOrNull;
    if (target == null) return false;
    if (target.id == currentPlayer.id) return false;

    final champIndex =
        target.championsInPlay.indexWhere((c) => c.id == championId);
    if (champIndex == -1) return false;

    final champion = target.championsInPlay.removeAt(champIndex);
    target.discardPile.add(champion);
    return true;
  }

  /// Reset (un-exhaust) one of the current player's champions, clearing it from
  /// [PlayerState.exhaustedChampions] so it can use its Exhaust-gated activated
  /// ability again this turn. Fulfils a [ResetChampionEffect] after the player
  /// selects a target (deferred-selection, like [banishCard]).
  ///
  /// Returns false (no state change) unless [championId] names a champion the
  /// current player controls that is currently exhausted.
  bool resetChampion(String championId) {
    if (!_currentPlayerCanAct) return false;
    final player = currentPlayer;

    final controls =
        player.championsInPlay.any((c) => c.id == championId);
    if (!controls) return false;
    if (!player.exhaustedChampions.contains(championId)) return false;

    player.exhaustedChampions.remove(championId);
    return true;
  }

  // -------------------------------------------------------------------------
  // Deferred-selection action effects (Engine Phase 2, wave 3)
  // -------------------------------------------------------------------------

  /// Recruit (acquire) a card from the center row, fulfilling a
  /// [RecruitFromCenterEffect] after the player selects a target.
  ///
  /// Validates the card is in [centerRow] and within [maxCost] (when set). When
  /// [free] is false the player must afford the card's gem cost (it is charged).
  /// The acquired card is routed to: the discard pile (default), the player's
  /// hand ([toHand]), or the TOP of the draw pile ([toTopOfDeck] — it becomes
  /// the next draw). [toHand] takes precedence over [toTopOfDeck] if both set.
  /// Refills the center row. Returns false (no state change) on any failure.
  bool recruitFromCenter(
    String cardId, {
    required bool free,
    int? maxCost,
    bool toHand = false,
    bool toTopOfDeck = false,
  }) {
    if (!_currentPlayerCanAct) return false;
    final player = currentPlayer;

    final index = centerRow.indexWhere((c) => c.id == cardId);
    if (index == -1) return false;

    final card = centerRow[index];
    if (maxCost != null && card.cost > maxCost) return false;

    final price = free ? 0 : card.cost;
    if (player.gemPool < price) return false;

    player.gemPool -= price;
    centerRow.removeAt(index);

    if (toHand) {
      player.hand.add(card);
    } else if (toTopOfDeck) {
      // _drawCards draws via removeLast(), so the TOP of the deck (next draw) is
      // the END of the drawPile list. Append so this card is drawn next.
      player.drawPile.add(card);
    } else {
      player.discardPile.add(card);
    }

    _refillCenterRow();
    return true;
  }

  /// Fast-play ("warp") a card from the center row, fulfilling a
  /// [FastPlayFromCenterEffect] after the player selects a target.
  ///
  /// Validates the card is in [centerRow], within [maxCost] (when set), and —
  /// when [alliesOnly] — is not a champion ("ally" = any non-champion card; the
  /// engine treats allies as cards that are not champions). The card is removed
  /// from the center row, PLAYED immediately (its play effects resolve and it is
  /// recorded in playedThisTurn + cardsPlayedThisTurn, and its ally ability is
  /// checked), then BANISHED to [removedFromGame] per Shards warp rules. The
  /// center row refills. Returns false (no state change) on any failure.
  bool fastPlayFromCenter(
    String cardId, {
    int? maxCost,
    bool alliesOnly = false,
  }) {
    if (!_currentPlayerCanAct) return false;
    final player = currentPlayer;

    final index = centerRow.indexWhere((c) => c.id == cardId);
    if (index == -1) return false;

    final card = centerRow[index];
    if (maxCost != null && card.cost > maxCost) return false;
    // "Allies only" — exclude champions. (An ally is a non-champion card; the
    // engine has no separate Ally type, so champions are the excluded case.)
    if (alliesOnly && card.cardType == CardType.champion) return false;

    centerRow.removeAt(index);

    // Play it immediately (without going through hand). Record in the same
    // zones playCard() uses for a non-champion regular/mercenary card so
    // per-turn scaling and ally checks see it.
    player.playedThisTurn.add(card);
    player.cardsPlayedThisTurn.add(card);
    _resolvePlayOrMastery(card, player);
    _checkAllyAbility(card, player);

    // Per warp rules: banish the card after it resolves. Remove it from
    // playedThisTurn so end-of-turn cleanup does not also move it to discard,
    // then move it to removedFromGame. NOTE: it deliberately STAYS in
    // cardsPlayedThisTurn — the ally was genuinely played this turn, so later
    // cards' play-history scaling/conditions (perAllyPlayedThisTurn, etc.)
    // should still count it even though the physical card is now banished.
    player.playedThisTurn.removeWhere((c) => identical(c, card));
    removedFromGame.add(card);

    _refillCenterRow();
    return true;
  }

  /// Peek at the top [count] card(s) of the current player's draw pile WITHOUT
  /// removing them (for UI display before a [ScryEffect] resolution). Triggers a
  /// reshuffle of the discard pile when the draw pile is empty, mirroring
  /// [_drawCards]. The returned list is ordered top-of-deck first (the next card
  /// that would be drawn is element 0).
  List<CardModel> scryReveal({int count = 1}) {
    final player = currentPlayer;
    if (player.drawPile.isEmpty && player.discardPile.isNotEmpty) {
      player.drawPile.addAll(player.discardPile);
      player.discardPile.clear();
      player.drawPile.shuffle(_random);
    }
    final revealed = <CardModel>[];
    // Top of deck (next draw) is the END of drawPile; iterate from the end.
    for (int i = player.drawPile.length - 1;
        i >= 0 && revealed.length < count;
        i--) {
      revealed.add(player.drawPile[i]);
    }
    return revealed;
  }

  /// Resolve a single revealed scry card (keeper_of_datic_vessels-style),
  /// fulfilling a [ScryEffect] after the player chooses. [cardId] must name a
  /// card currently on top of the draw pile (within the revealed window — here,
  /// simply present in the draw pile). The disposition decides what [keep] does:
  ///
  /// - [ScryDisposition.drawOrDiscard]: keep → draw to hand; else → discard.
  /// - [ScryDisposition.drawOrBanish]:  keep → draw to hand; else → banish.
  /// - [ScryDisposition.toHand]:        keep → take to hand; else → leave on top
  ///   (no state change).
  ///
  /// Returns false (no state change) if the card is not in the draw pile.
  bool scryResolve(
    String cardId, {
    required bool keep,
    ScryDisposition disposition = ScryDisposition.drawOrDiscard,
  }) {
    if (!_currentPlayerCanAct) return false;
    final player = currentPlayer;

    final index = player.drawPile.indexWhere((c) => c.id == cardId);
    if (index == -1) return false;

    switch (disposition) {
      case ScryDisposition.drawOrDiscard:
        final card = player.drawPile.removeAt(index);
        if (keep) {
          player.hand.add(card);
        } else {
          player.discardPile.add(card);
        }
        return true;
      case ScryDisposition.drawOrBanish:
        final card = player.drawPile.removeAt(index);
        if (keep) {
          player.hand.add(card);
        } else {
          removedFromGame.add(card);
        }
        return true;
      case ScryDisposition.toHand:
        if (!keep) return true; // leave on top, no change
        final card = player.drawPile.removeAt(index);
        player.hand.add(card);
        return true;
    }
  }

  /// Destroy every enemy champion (the [DestroyChampionEffect.all] variant).
  /// Each destroyed champion goes to its owner's discard pile. No power cost.
  void _destroyAllEnemyChampions(PlayerState source) {
    for (final player in players) {
      if (player.id == source.id) continue;
      if (player.championsInPlay.isEmpty) continue;
      player.discardPile.addAll(player.championsInPlay);
      player.championsInPlay.clear();
    }
  }

  // -------------------------------------------------------------------------
  // Return from discard (Phase 1: ReturnFromDiscardEffect)
  // -------------------------------------------------------------------------

  /// Return a card from the current player's discard pile to their hand.
  ///
  /// Requires target selection (the effect defers to this method, like
  /// banishCard). The [filter]/[faction] must be supplied by the caller from
  /// the [ReturnFromDiscardEffect] so the selection can be validated.
  /// Returns true if the card was found, matched the filter, and was returned.
  bool returnFromDiscard(
    String cardId, {
    ReturnFilter filter = ReturnFilter.any,
    Faction? faction,
  }) {
    final player = currentPlayer;
    final index = player.discardPile.indexWhere((c) => c.id == cardId);
    if (index == -1) return false;

    final card = player.discardPile[index];
    if (!_matchesReturnFilter(card, filter, faction)) return false;

    player.discardPile.removeAt(index);
    player.hand.add(card);
    return true;
  }

  bool _matchesReturnFilter(
    CardModel card,
    ReturnFilter filter,
    Faction? faction,
  ) {
    switch (filter) {
      case ReturnFilter.any:
        return true;
      case ReturnFilter.champion:
        return card.cardType == CardType.champion;
      case ReturnFilter.mercenary:
        return card.cardType == CardType.mercenary;
      case ReturnFilter.faction:
        if (faction == null) return false;
        return card.faction == faction;
    }
  }

  // -------------------------------------------------------------------------
  // Effect resolution
  // -------------------------------------------------------------------------

  void _resolveEffects(
    List<CardEffect> effects,
    PlayerState player, {
    int choiceIndex = 0,
    CardModel? sourceCard,
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
        case AllPlayersLoseHealthEffect():
          _applyAllPlayersHealthLoss(player, effect.amount);
        case ChooseOneEffect():
          final idx = choiceIndex.clamp(0, effect.choices.length - 1);
          _resolveEffects(effect.choices[idx], player, sourceCard: sourceCard);
        case ConditionalPowerEffect():
          player.powerPool +=
              _evaluateCondition(effect.condition, player, sourceCard);
        case ScalingResourceEffect():
          final count = _evaluateScalingCount(
            effect.condition,
            effect.faction,
            player,
            sourceCard,
          );
          _gainResource(player, effect.resource, count * effect.perN);
        case ConditionalEffect():
          if (_evaluateGameCondition(effect.condition, player, sourceCard)) {
            _resolveEffects(
              effect.then,
              player,
              choiceIndex: choiceIndex,
              sourceCard: sourceCard,
            );
          }
        case DestroyChampionEffect():
          if (effect.all) {
            _destroyAllEnemyChampions(player);
          }
          // Single-target destruction requires target selection — the player
          // should call destroyChampion() separately after this effect, the
          // same way BanishCardEffect defers to banishCard().
          break;
        case ReturnFromDiscardEffect():
          // Requires card selection — the player should call
          // returnFromDiscard() separately after this effect.
          break;
        case BanishCardEffect():
          // Requires card selection — auto-banish not possible without target.
          // The player should call banishCard() separately after this effect.
          break;
        case ScrapFromCenterRowEffect():
          // Requires card selection — the player should call
          // scrapFromCenterRow() separately after this effect.
          break;
        case SelfBanishEffect():
          _selfBanish(player, sourceCard);
        case ResetChampionEffect():
          // Requires champion selection — the player should call
          // resetChampion() separately after this effect (deferred-selection).
          break;
        case RecruitFromCenterEffect():
          // Requires center-row selection — the player should call
          // recruitFromCenter() separately after this effect.
          break;
        case FastPlayFromCenterEffect():
          // Requires center-row selection — the player should call
          // fastPlayFromCenter() separately after this effect.
          break;
        case ScryEffect():
          // Requires UI peek + per-card choice — the player should call
          // scryReveal() then scryResolve() separately after this effect.
          break;
        case TreatFactionAsEffect():
          // Turn-scoped: register the alias on the current player so faction
          // matching (ally checks + faction-filtered scaling/conditions) treats
          // `from` as `to` for the rest of this turn. Bidirectional adds the
          // reverse mapping too. Cleared by resetTurnResources.
          player.factionAliasesThisTurn
              .add((from: effect.from, to: effect.to));
          if (effect.bidirectional) {
            player.factionAliasesThisTurn
                .add((from: effect.to, to: effect.from));
          }
        case IgnoreShieldThisTurnEffect():
          // Turn-scoped: this player's attacks ignore enemy champion shield for
          // the destroy threshold this turn (see attackChampion). Cleared by
          // resetTurnResources.
          player.ignoresShieldThisTurn = true;
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
      _resolveEffects(card.allyAbility, player, sourceCard: card);
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
          other.faction, other.countsAsAllFactions, aliasPlayer: player)) {
        return true;
      }
    }

    // Check championsInPlay for same-faction cards (excluding the card itself)
    for (final other in player.championsInPlay) {
      if (other.id == card.id) continue;
      if (_factionsMatch(cardFaction, card.countsAsAllFactions,
          other.faction, other.countsAsAllFactions, aliasPlayer: player)) {
        return true;
      }
    }

    return false;
  }

  /// Returns true if two cards' factions match for ally ability purposes.
  /// A card with countsAsAllFactions matches any non-none faction.
  ///
  /// [aliasPlayer], when supplied AND holding turn-scoped faction aliases
  /// (set by [TreatFactionAsEffect]), canonicalizes both factions through that
  /// player's [PlayerState.factionAliasesThisTurn] before comparing. When no
  /// alias player is passed, or the player has no aliases (the common case),
  /// behaviour is IDENTICAL to the un-aliased comparison — every existing call
  /// site that omits [aliasPlayer] is unaffected.
  bool _factionsMatch(
    Faction factionA, bool allFactionsA,
    Faction factionB, bool allFactionsB, {
    PlayerState? aliasPlayer,
  }) {
    // If either is factionless and doesn't count as all factions, no match.
    // (countsAsAllFactions and the none-faction guard are evaluated on the
    // RAW factions, before aliasing — an alias only redirects a real faction
    // to another real faction, it never grants/removes "all factions".)
    if (factionA == Faction.none && !allFactionsA) return false;
    if (factionB == Faction.none && !allFactionsB) return false;

    // If either counts as all factions, it matches any non-none faction
    if (allFactionsA || allFactionsB) return true;

    // Fast path: identical factions always match (also the common no-alias
    // case), with zero allocation.
    if (factionA == factionB) return true;

    // Alias-aware path. A `from -> to` alias means a `from` card ALSO counts as
    // `to` (it keeps its own faction too). Two factions therefore match when
    // their alias-expanded faction sets intersect. With no alias player / no
    // aliases this loop is skipped entirely and we've already returned for the
    // equal-faction case, so behaviour is identical to the original.
    if (aliasPlayer == null || aliasPlayer.factionAliasesThisTurn.isEmpty) {
      return false;
    }
    final setA = _aliasExpand(factionA, aliasPlayer);
    final setB = _aliasExpand(factionB, aliasPlayer);
    return setA.any(setB.contains);
  }

  /// The set of factions [faction] counts as given [player]'s turn-scoped
  /// aliases: always itself, plus the `to` of any alias whose `from` is
  /// [faction]. A single hop (aliases are not transitively chained); a
  /// bidirectional alias already records both directions explicitly.
  Set<Faction> _aliasExpand(Faction faction, PlayerState player) {
    final set = {faction};
    for (final alias in player.factionAliasesThisTurn) {
      if (alias.from == faction) set.add(alias.to);
    }
    return set;
  }

  // -------------------------------------------------------------------------
  // Mastery threshold (Step 11)
  // -------------------------------------------------------------------------

  /// Resolves a card's [CardModel.playEffects] together with its mastery
  /// threshold, used by both [playCard] and [activateChampion].
  ///
  /// - When [CardModel.masteryReplaces] is true AND the card has a
  ///   [CardModel.masteryThreshold] the player has reached, the
  ///   [CardModel.masteryBonus] resolves INSTEAD OF [CardModel.playEffects].
  /// - Otherwise (the legacy default), [CardModel.playEffects] resolve and the
  ///   mastery bonus is checked ADDITIVELY on top via [_checkMasteryBonus].
  void _resolvePlayOrMastery(
    CardModel card,
    PlayerState player, {
    int choiceIndex = 0,
  }) {
    final thresholdMet = card.masteryThreshold != null &&
        card.masteryBonus.isNotEmpty &&
        player.mastery >= card.masteryThreshold!;

    if (card.masteryReplaces && thresholdMet) {
      // REPLACE: resolve the mastery bonus instead of the normal play effects,
      // and do NOT additively check mastery again.
      _resolveEffects(card.masteryBonus, player, sourceCard: card);
      return;
    }

    // Default / additive path — unchanged from prior behavior.
    _resolveEffects(
      card.playEffects,
      player,
      choiceIndex: choiceIndex,
      sourceCard: card,
    );
    _checkMasteryBonus(card, player);
  }

  void _checkMasteryBonus(CardModel card, PlayerState player) {
    if (card.masteryThreshold == null) return;
    if (card.masteryBonus.isEmpty) return;
    if (player.mastery >= card.masteryThreshold!) {
      _resolveEffects(card.masteryBonus, player, sourceCard: card);
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

  /// Apply [amount] of direct health loss to EVERY player including [source]
  /// (the controlling player). Bypasses guard/shield — a raw subtraction.
  /// Mirrors the elimination/cleanup/game-over handling of
  /// [_applyOpponentHealthLoss]. Used by [AllPlayersLoseHealthEffect].
  void _applyAllPlayersHealthLoss(PlayerState source, int amount) {
    if (amount <= 0) return;
    for (final player in players) {
      if (player.isEliminated) continue;
      player.takeDamage(amount);
      if (player.isEliminated) {
        _cleanupEliminatedPlayer(player);
      }
    }
    _checkGameOver();
  }

  /// Route [amount] of [resource] into the matching player pool. Negative or
  /// zero amounts are no-ops for gem/power (additive) and clamped by the
  /// underlying PlayerState helpers for mastery/health.
  void _gainResource(PlayerState player, ScalingResource resource, int amount) {
    switch (resource) {
      case ScalingResource.power:
        player.powerPool += amount;
      case ScalingResource.gems:
        player.gemPool += amount;
      case ScalingResource.health:
        player.heal(amount);
      case ScalingResource.mastery:
        player.addMastery(amount);
    }
  }

  /// Counts the units a [ScalingResourceEffect] scales by. [filterFaction] is
  /// the effect's explicit faction filter; when null the `perFaction*`
  /// conditions fall back to the source card's faction (mirroring ally logic).
  int _evaluateScalingCount(
    ScalingCondition condition,
    Faction? filterFaction,
    PlayerState player,
    CardModel? sourceCard,
  ) {
    // The four original conditions delegate to _evaluateCondition so behaviour
    // is provably identical to ConditionalPowerEffect (regression guarantee).
    switch (condition) {
      case ScalingCondition.perChampionControlled:
        return _evaluateCondition(
            PowerCondition.perChampionControlled, player, sourceCard);
      case ScalingCondition.perAllyPlayedThisTurn:
        return _evaluateCondition(
            PowerCondition.perAllyPlayedThisTurn, player, sourceCard);
      case ScalingCondition.perFactionPlayedThisTurn:
        return _evaluateCondition(
            PowerCondition.perFactionPlayedThisTurn, player, sourceCard);
      case ScalingCondition.perCardInDiscard:
        return _evaluateCondition(
            PowerCondition.perCardInDiscard, player, sourceCard);
      case ScalingCondition.perFactionCardInDiscard:
        final f = filterFaction ?? sourceCard?.faction;
        if (f == null) return 0;
        return player.discardPile
            .where((c) => _factionsMatch(
                f, false, c.faction, c.countsAsAllFactions,
                aliasPlayer: player))
            .length;
      case ScalingCondition.perFactionChampionControlled:
        final f = filterFaction ?? sourceCard?.faction;
        if (f == null) return 0;
        return player.championsInPlay
            .where((c) => _factionsMatch(
                f, false, c.faction, c.countsAsAllFactions,
                aliasPlayer: player))
            .length;
      case ScalingCondition.perFactionCardPlayedThisTurn:
        final f = filterFaction ?? sourceCard?.faction;
        if (f == null) return 0;
        return _countPlayedThisTurn(
          player,
          sourceCard,
          (c) => _factionsMatch(f, false, c.faction, c.countsAsAllFactions,
              aliasPlayer: player),
        );
      case ScalingCondition.perAllyWithShieldPlayedThisTurn:
        final f = filterFaction ?? sourceCard?.faction;
        if (f == null) return 0;
        return _countPlayedThisTurn(
          player,
          sourceCard,
          (c) =>
              c.shield > 0 &&
              _factionsMatch(f, false, c.faction, c.countsAsAllFactions,
                  aliasPlayer: player),
        );
    }
  }

  /// Counts cards played this turn matching [test], skipping the in-flight
  /// source card exactly once (mirrors the perAllyPlayedThisTurn skip).
  int _countPlayedThisTurn(
    PlayerState player,
    CardModel? sourceCard,
    bool Function(CardModel) test,
  ) {
    var count = 0;
    var skippedSelf = false;
    for (final played in player.cardsPlayedThisTurn) {
      if (!skippedSelf &&
          sourceCard != null &&
          identical(played, sourceCard)) {
        skippedSelf = true;
        continue;
      }
      if (test(played)) count++;
    }
    return count;
  }

  /// Evaluates a [GameCondition] predicate against current game state.
  /// [source] is the in-flight card (skipped via `identical` where the
  /// existing per-ally counting does, so a card doesn't count itself).
  bool _evaluateGameCondition(
    GameCondition c,
    PlayerState player,
    CardModel? source,
  ) {
    switch (c.kind) {
      case GameConditionKind.alliesOfFactionPlayed:
        final f = c.faction ?? source?.faction;
        if (f == null || f == Faction.none) return false;
        final count = _countPlayedThisTurn(
          player,
          source,
          (card) => _factionsMatch(f, false, card.faction,
              card.countsAsAllFactions, aliasPlayer: player),
        );
        return count >= c.threshold;
      case GameConditionKind.factionsPlayedAll:
        if (c.factions.isEmpty) return false;
        final played = <Faction>{
          for (final card in player.cardsPlayedThisTurn)
            if (card.faction != Faction.none) card.faction,
        };
        return c.factions.every(played.contains);
      case GameConditionKind.distinctFactionsPlayed:
        return _evaluateCondition(
                PowerCondition.perFactionPlayedThisTurn, player, source) >=
            c.threshold;
      case GameConditionKind.cardTypePlayed:
        final type = c.cardType;
        if (type == null) return false;
        final count = _countPlayedThisTurn(
            player, source, (card) => card.cardType == type);
        return count >= c.threshold;
      case GameConditionKind.gemParityCardsPlayed:
        final parity = c.parity ?? GemParity.even;
        final count = _countPlayedThisTurn(
          player,
          source,
          (card) => c.faction == null
              ? true
              : _factionsMatch(c.faction!, false, card.faction,
                  card.countsAsAllFactions, aliasPlayer: player),
        );
        final isEven = count.isEven;
        return parity == GemParity.even ? isEven : !isEven;
      case GameConditionKind.filteredCardsPlayed:
        final count = _countPlayedThisTurn(
          player,
          source,
          (card) {
            if (c.faction != null &&
                !_factionsMatch(c.faction!, false, card.faction,
                    card.countsAsAllFactions, aliasPlayer: player)) {
              return false;
            }
            if (c.maxCost != null && card.cost > c.maxCost!) return false;
            return true;
          },
        );
        return count >= c.threshold;
      case GameConditionKind.championsControlled:
        return player.championsInPlay.length >= c.threshold;
      case GameConditionKind.championsOfFactionControlled:
        final f = c.faction ?? source?.faction;
        if (f == null || f == Faction.none) return false;
        final count = player.championsInPlay
            .where((card) => _factionsMatch(
                f, false, card.faction, card.countsAsAllFactions,
                aliasPlayer: player))
            .length;
        return count >= c.threshold;
      case GameConditionKind.masteryAtLeast:
        return player.mastery >= c.threshold;
      case GameConditionKind.sameFactionCountPlayed:
        final f = c.faction ?? source?.faction;
        if (f == null || f == Faction.none) return false;
        // Count ALL same-faction cards played this turn INCLUDING the source.
        final count = player.cardsPlayedThisTurn
            .where((card) => _factionsMatch(
                f, false, card.faction, card.countsAsAllFactions,
                aliasPlayer: player))
            .length;
        return count >= c.threshold;
      case GameConditionKind.isCharacter:
        if (c.character == null) return false;
        return player.character == c.character;
      case GameConditionKind.unblockedDamageAtLeast:
        return player.unblockedDamageThisTurn >= c.threshold;
    }
  }

  int _evaluateCondition(
    PowerCondition condition,
    PlayerState player,
    CardModel? sourceCard,
  ) {
    switch (condition) {
      case PowerCondition.perChampionControlled:
        return player.championsInPlay.length;
      case PowerCondition.perAllyPlayedThisTurn:
        // Count cards played this turn whose faction matches the source card's
        // faction (allies), excluding the source card itself. Mirrors the
        // ally-matching rule (countsAsAllFactions matches any faction).
        if (sourceCard == null) return 0;
        var count = 0;
        var skippedSelf = false;
        for (final played in player.cardsPlayedThisTurn) {
          if (!skippedSelf && identical(played, sourceCard)) {
            skippedSelf = true;
            continue;
          }
          if (_factionsMatch(
            sourceCard.faction,
            sourceCard.countsAsAllFactions,
            played.faction,
            played.countsAsAllFactions,
            aliasPlayer: player,
          )) {
            count++;
          }
        }
        return count;
      case PowerCondition.perFactionPlayedThisTurn:
        // Number of distinct (non-none) factions played this turn.
        final factions = <Faction>{};
        for (final played in player.cardsPlayedThisTurn) {
          if (played.faction != Faction.none) {
            factions.add(played.faction);
          }
        }
        return factions.length;
      case PowerCondition.perCardInDiscard:
        return player.discardPile.length;
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
