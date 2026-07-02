import 'dart:math';

import 'package:simple_card_game/data/card_definitions.dart';
import 'package:simple_card_game/data/character_relics.dart';
import 'package:simple_card_game/data/market_deck.dart';
import 'package:simple_card_game/data/starter_deck.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/models/ingeminex_entity.dart';
import 'package:simple_card_game/models/player_state.dart';

/// A structured resource gain attached to a [GameLogEntry] so the UI can render
/// small resource icons (e.g. three gem icons for "+3 gems") beside the entry
/// instead of parsing the message string.
///
/// PURE DART (no Flutter) so it lives in the engine. [kind] is one of
/// `'gem'` / `'power'` / `'mastery'` / `'health'` — the same set the UI's
/// `ResourceIcon` enum covers. Public-info-safe: these are the flat,
/// unconditional grants of a card that was just played face-up, so the amounts
/// were already implied by the (public) played card.
class LogResourceGrant {
  const LogResourceGrant(this.kind, this.amount);

  final String kind;
  final int amount;

  Map<String, dynamic> toJson() => {'kind': kind, 'amount': amount};

  factory LogResourceGrant.fromJson(Map<String, dynamic> j) => LogResourceGrant(
        (j['kind'] as String?) ?? '',
        (j['amount'] as int?) ?? 0,
      );
}

/// One human-readable entry in the [GameService.actionLog] — a public game event
/// (which turn it happened on, who did it, and a short description). Carries no
/// hidden information.
class GameLogEntry {
  const GameLogEntry({
    required this.turn,
    required this.playerId,
    required this.message,
    this.cardId,
    this.grants = const [],
  });

  final int turn;
  final String? playerId;
  final String message;

  /// The card this action involved, if any (a play / recruit / fast-play /
  /// activate). Lets the shared-action playback show a mini card face alongside
  /// the message. Null for card-less events (focus, turn change, attack player).
  /// The id resolves against the redacted view's `cards` dictionary, so it never
  /// leaks hidden info — only public actions carry a card id.
  final String? cardId;

  /// Structured resource gains this event granted (gems / power / mastery /
  /// health), so the UI can show small resource icons beside the entry. Empty
  /// for events that granted no flat resources. Public-info-safe (see
  /// [LogResourceGrant]).
  final List<LogResourceGrant> grants;

  Map<String, dynamic> toJson() => {
        'turn': turn,
        if (playerId != null) 'playerId': playerId,
        'message': message,
        if (cardId != null) 'cardId': cardId,
        if (grants.isNotEmpty)
          'grants': [for (final g in grants) g.toJson()],
      };

  factory GameLogEntry.fromJson(Map<String, dynamic> j) => GameLogEntry(
        turn: (j['turn'] as int?) ?? 0,
        playerId: j['playerId'] as String?,
        message: (j['message'] as String?) ?? '',
        cardId: j['cardId'] as String?,
        grants: [
          for (final g in (j['grants'] as List? ?? const []))
            LogResourceGrant.fromJson((g as Map).cast<String, dynamic>()),
        ],
      );
}

/// A structured record of the MOST RECENT direct player-vs-player damage event.
///
/// Set by [GameService.attackPlayer] every time one player deals direct combat
/// damage to another (the guard-blocked / zero-damage paths do NOT set it). It
/// exists so every client — attacker AND victim — can render the SAME damage
/// animation deterministically from a single shipped event, rather than each
/// side re-deriving it from the action-log text.
///
/// Everything here is PUBLIC information: the attacker, the victim, and the
/// amount of a direct attack are all visible on the board (health totals are
/// public scalars), so shipping this leaks nothing hidden.
///
/// [seq] is a monotonic counter bumped on each new event; the UI uses it as a
/// high-water mark so the animation fires exactly ONCE per event (and survives
/// undo/resync without replaying).
class LastDamageEvent {
  const LastDamageEvent({
    required this.seq,
    required this.fromId,
    required this.toId,
    required this.amount,
  });

  /// Monotonic sequence number (1-based). Distinguishes one damage event from
  /// the next even when from/to/amount repeat.
  final int seq;

  /// Engine seat id of the attacker (e.g. `p0`).
  final String fromId;

  /// Engine seat id of the victim (e.g. `p1`).
  final String toId;

  /// Damage dealt.
  final int amount;

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'fromId': fromId,
        'toId': toId,
        'amount': amount,
      };

  factory LastDamageEvent.fromJson(Map<String, dynamic> j) => LastDamageEvent(
        seq: (j['seq'] as int?) ?? 0,
        fromId: (j['fromId'] as String?) ?? '',
        toId: (j['toId'] as String?) ?? '',
        amount: (j['amount'] as int?) ?? 0,
      );
}

/// Orchestrates a Fragments of Boundlessness game: turn lifecycle, effect resolution,
/// market management, and multi-player turn rotation.
class GameService {
  GameService({
    required int playerCount,
    Random? random,
    List<Character?>? characters,
    List<MarketCard>? marketDeck,
    Map<String, CardModel>? relicCards,
    List<CardModel>? destinySupply,
  })  : _random = random ?? Random(),
        _marketDeck = marketDeck,
        _relicCards = relicCards,
        assert(playerCount >= 2 && playerCount <= 4),
        assert(characters == null || characters.length == playerCount,
            'characters, when provided, must have one entry per player') {
    _initializeGame(playerCount);
    if (characters != null) {
      for (var i = 0; i < playerCount; i++) {
        players[i].character = characters[i];
      }
    }
    // Relic options are set aside beside the player at setup. This runs AFTER
    // character assignment so the constructor's `characters` path is covered.
    for (final p in players) {
      _populateRelicOptions(p);
    }
    // Destiny supply is OPT-IN (Into the Horizon). When omitted (the default),
    // destinyRow / destinyDeck stay empty and the game behaves exactly as
    // before — no Destinies are ever claimable. When a supply is provided, it is
    // shuffled and the top six are dealt face-up into the shared destinyRow; the
    // rest form the destinyDeck (cascade source). The row is NOT auto-refilled
    // when a Destiny is claimed (Into the Horizon rule).
    if (destinySupply != null) {
      _initializeDestinySupply(destinySupply);
    }
  }

  /// Bare constructor for state restoration (multiplayer snapshot / reconnect).
  /// Skips [_initializeGame] entirely — the caller (a serialization codec) is
  /// responsible for populating [players], [centerRow], [infinityDeck], etc.
  /// from a snapshot. A FRESH [Random] is used: in the authoritative-server
  /// model the server is the only place shuffles happen, so it is correct to
  /// resume from the already-shuffled concrete pile orders captured in the
  /// snapshot and reseed the RNG for any future shuffle.
  GameService.restore({Random? random})
      : _random = random ?? Random(),
        _marketDeck = null,
        _relicCards = null;

  final Random _random;

  /// The authoritative market deck (unique templates + per-card copy counts).
  /// When null, the legacy [allInfinityDeckCards] + cost-bucket formula is used
  /// (keeps existing tests and the legacy demo unchanged).
  final List<MarketCard>? _marketDeck;

  /// Relic card templates by id (Relics of the Future). When provided, each
  /// player whose [Character] is in [characterRelicIds] gets that character's two
  /// relics set aside in [PlayerState.relicOptions] at setup. When null (the
  /// default — e.g. the legacy demo, most tests), NO relic options are created
  /// and the game behaves exactly as before. The caller (Flutter app / server)
  /// loads these from the card DB and injects them; the pure-Dart engine does
  /// not load assets itself.
  final Map<String, CardModel>? _relicCards;

  final List<PlayerState> players = [];
  final List<CardModel> centerRow = [];
  final List<CardModel> infinityDeck = [];
  final List<CardModel> removedFromGame = [];

  /// Cards tucked under a destroyed [CardModel.recruitUnderCardsOnDeath] champion
  /// (carmine_eclipse) that are pending the OWNER's salvage choice, keyed by the
  /// owner's player id. Populated by [_disposeUnderCardsOnDeath] when such a
  /// champion dies with cards under it (possible OFF-TURN — Carmine may be
  /// destroyed on an opponent's turn). The owner then either PAYS a card's gem
  /// cost to recruit it ([recruitUnderCard], → discard) or banishes the rest
  /// ([finishUnderCardSalvage], → removedFromGame). Empty when no salvage is
  /// pending. Round-tripped by [GameStateCodec]. NOTE: an owner who is
  /// ELIMINATED gets no salvage — [_cleanupEliminatedPlayer] sends their
  /// under-cards straight to removed-from-game.
  final Map<String, List<CardModel>> pendingUnderCardRecruit = {};

  /// Top-of-deck cards revealed by a [RevealAndCopyTopOfDecksEffect]
  /// (duplication_fabricator) that are awaiting the caster's copy choice, each
  /// paired with the id of the player whose deck it came from. Populated by
  /// [revealTopOfAllDecks] (peek-only — the cards are LEFT ON TOP of their decks)
  /// and consumed by [copyRevealedCard]. Empty outside a pending choice.
  ///
  /// REDACTION NOTE (follow-up pass): this list is the ONE sanctioned exception
  /// to the secret-deck rule — it must be shipped ONLY to the current chooser and
  /// REDACTED from every other player's view. Round-tripped whole by
  /// [GameStateCodec] (omitted when empty).
  final List<({String ownerId, CardModel card})> pendingDeckReveal = [];

  /// The shared, NEUTRAL Ingeminex entities occupying the Champions Row. Each
  /// belongs to NO player: any current player may attack it via
  /// [attackIngeminex] (unlike a normal champion, which lives in its owner's
  /// [PlayerState.championsInPlay] and is only attackable by opponents). Populated
  /// by [spawnIngeminex]; an entity is removed when killed (its reward goes to the
  /// killer). Empty in a game that never spawns an Ingeminex. Serialized whole by
  /// [GameStateCodec] (`ingeminex` key) — accumulated damage survives
  /// undo/persistence/reconnect.
  final List<IngeminexEntity> ingeminexRow = [];

  /// Append-only, human-readable log of game actions (oldest first), so players
  /// can review what happened — e.g. "remind themselves what they did last
  /// turn". Public game events only (no hidden info). Bounded to keep memory and
  /// the serialized payload flat in long games.
  final List<GameLogEntry> actionLog = [];
  static const int _maxLogEntries = 400;

  /// Record a public game event. [playerId] is the actor (or null for system
  /// events like turn changes). [cardId] is the involved card, if any, so the
  /// shared-action playback can show a mini card face (public actions only).
  void _log(String message,
      {String? playerId,
      String? cardId,
      List<LogResourceGrant> grants = const []}) {
    actionLog.add(GameLogEntry(
      turn: turnNumber,
      playerId: playerId,
      message: message,
      cardId: cardId,
      grants: grants,
    ));
    if (actionLog.length > _maxLogEntries) {
      actionLog.removeRange(0, actionLog.length - _maxLogEntries);
    }
  }

  /// Best-effort read of the flat, unconditional resource grants ([GainGems /
  /// Power / Mastery / HealthEffect]) in [effects], for the action-log's small
  /// resource icons. Mirrors the UI's `resourceGrantsOf` but returns pure-Dart
  /// [LogResourceGrant]s so the engine stays Flutter-free.
  ///
  /// Only always-on grants are counted; conditional / scaling / choose-one
  /// effects are skipped (they'd need live state) so a shown icon is never wrong
  /// — at most it under-reports (no icon for a conditional bonus). Amounts are
  /// public (the played card is face-up), so this is hidden-info safe.
  static List<LogResourceGrant> _resourceGrantsOf(List<CardEffect> effects) {
    var gems = 0, power = 0, mastery = 0, health = 0;
    for (final e in effects) {
      switch (e) {
        case GainGemsEffect(:final amount):
          gems += amount;
        case GainPowerEffect(:final amount):
          power += amount;
        case GainMasteryEffect(:final amount):
          mastery += amount;
        case GainHealthEffect(:final amount):
          health += amount;
        default:
          break;
      }
    }
    return [
      if (gems > 0) LogResourceGrant('gem', gems),
      if (power > 0) LogResourceGrant('power', power),
      if (mastery > 0) LogResourceGrant('mastery', mastery),
      if (health > 0) LogResourceGrant('health', health),
    ];
  }

  /// The ACTUAL positive resource deltas the actor gained since the snapshot
  /// (gems/power/mastery/health), as log grants. Unlike [_resourceGrantsOf]
  /// (which statically reads only flat GainX effects and misses scaling /
  /// conditional / mastery-bonus / ally grants), this measures what really
  /// happened — so e.g. an Infinity Shard's tier-scaled power+mastery, or a
  /// conditional bonus that actually fired, shows the correct icons. The actor's
  /// resource totals and the played card are public, so this is hidden-info safe.
  static List<LogResourceGrant> _grantsSince(
      PlayerState p, int gem0, int power0, int mastery0, int health0) {
    final gems = p.gemPool - gem0;
    final power = p.powerPool - power0;
    final mastery = p.mastery - mastery0;
    final health = p.health - health0;
    return [
      if (gems > 0) LogResourceGrant('gem', gems),
      if (power > 0) LogResourceGrant('power', power),
      if (mastery > 0) LogResourceGrant('mastery', mastery),
      if (health > 0) LogResourceGrant('health', health),
    ];
  }

  /// Shared face-up supply of Destinies (Into the Horizon), up to
  /// [maxDestinyRow]. Empty unless a `destinySupply` was passed to the
  /// constructor. NOT auto-refilled when a Destiny is claimed.
  final List<CardModel> destinyRow = [];

  /// Face-down remainder of the Destiny supply (the cascade source, drawn from
  /// by Mastery-10 cascade Destinies). Empty unless a supply was provided.
  final List<CardModel> destinyDeck = [];

  /// The maximum number of face-up Destinies in [destinyRow].
  static const int maxDestinyRow = 6;
  int currentPlayerIndex = 0;
  int turnNumber = 1;
  bool _gameOver = false;

  /// The ID of the player who won, or null if the game is still in progress.
  String? winnerId;

  /// HOW the game was won: 'mastery' (Infinity Shard at mastery 30) or
  /// 'elimination' (all opponents reduced to 0 health), or null while in
  /// progress. Set precisely at each win path so telemetry/analytics don't have
  /// to guess from the winner's mastery (which can be >=30 even on an
  /// elimination win in a long game).
  String? winType;

  /// The most recent direct player-vs-player damage event (see
  /// [LastDamageEvent]), or null before any direct attack. Set by
  /// [attackPlayer]; shipped in the redacted view so every client can play the
  /// same attack animation once. Its [LastDamageEvent.seq] is a high-water mark
  /// the UI uses to fire the animation exactly once per event.
  LastDamageEvent? lastDamage;
  int _damageSeq = 0;

  PlayerState get currentPlayer => players[currentPlayerIndex];
  bool get isGameOver => _gameOver;

  /// Restore the game-over flag from a snapshot. Only the serialization codec
  /// should call this; normal play sets it via [_checkGameOver].
  void restoreGameOver(bool value) => _gameOver = value;

  /// Restore the last-damage event from a snapshot, keeping the internal
  /// sequence counter monotonic so a resumed game keeps issuing higher seqs.
  /// Only the serialization codec should call this; normal play sets it in
  /// [attackPlayer].
  void restoreLastDamage(LastDamageEvent event) {
    lastDamage = event;
    if (event.seq > _damageSeq) _damageSeq = event.seq;
  }

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
    // Create players with starter decks.
    for (int i = 0; i < playerCount; i++) {
      final player = PlayerState(id: 'p$i', name: 'Player ${i + 1}');
      // Staggered starting Mastery to offset turn-order advantage: the player
      // who goes first starts at 0, the second at 1, third at 2, fourth at 3
      // (seat index). Later seats act later, so they're compensated up front —
      // the advantage scales down the seat order.
      player.mastery = i;
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
  // Destiny system (Into the Horizon expansion)
  // -------------------------------------------------------------------------

  /// Mastery a player must reach before they may claim a Destiny (for free).
  static const int destinyClaimMastery = 5;

  /// Deal the provided Destiny supply into the shared row + deck. The supply is
  /// shuffled with the game RNG (deterministic under an injected [Random]); the
  /// first [maxDestinyRow] go face-up into [destinyRow], the rest into
  /// [destinyDeck]. Idempotent only at construction (called once).
  void _initializeDestinySupply(List<CardModel> supply) {
    final shuffled = List<CardModel>.of(supply)..shuffle(_random);
    final faceUp = shuffled.length < maxDestinyRow ? shuffled.length : maxDestinyRow;
    destinyRow.addAll(shuffled.take(faceUp));
    destinyDeck.addAll(shuffled.skip(faceUp));
  }

  /// Claim a Destiny from the shared [destinyRow] for the current player, FREE.
  ///
  /// Legal only when: the current player can act, they have reached Mastery
  /// [destinyClaimMastery] (5), they have not exhausted their per-game claim
  /// allowance ([PlayerState.canClaimAnotherDestiny] — base 1, plus any cascade
  /// grants), and [cardId] names a Destiny currently in the row. On success the
  /// Destiny moves from the row into the player's persistent
  /// [PlayerState.claimedDestinies] zone (it never enters the deck), the row is
  /// NOT refilled, the player's claim count increments, and any persistent
  /// PASSIVE effect on the Destiny (its [CardModel.playEffects] — e.g. a
  /// [StaticModifier]) resolves ONCE now so the standing buff applies for the
  /// rest of the game. Activated Destinies (those carrying an
  /// [CardModel.activatedAbility]) have NO playEffects to resolve here; their
  /// ability is used per-turn via [useDestinyAbility]. Returns false (no state
  /// change) on any failure.
  bool claimDestiny(String cardId) {
    if (!_currentPlayerCanAct) return false;
    final player = currentPlayer;
    if (player.mastery < destinyClaimMastery) return false;
    if (!player.canClaimAnotherDestiny) return false;

    final index = destinyRow.indexWhere((c) => c.id == cardId);
    if (index == -1) return false;

    final destiny = destinyRow.removeAt(index);
    player.claimedDestinies.add(destiny);
    player.destinyClaimCount += 1;

    // Resolve any persistent passive effect once on claim (StaticModifier /
    // turn-scoped standing effects). Activated-only Destinies have empty
    // playEffects, so this is a no-op for them. We deliberately do NOT route an
    // InfinityShardEffect or deferred-selection effects through here — Destiny
    // passives in the encoded set are StaticModifier / TreatFactionAs only.
    if (destiny.playEffects.isNotEmpty) {
      _resolveEffects(destiny.playEffects, player, sourceCard: destiny);
    }
    return true;
  }

  /// Use a claimed Destiny's Exhaust-gated activated ability (the "second Focus
  /// button"). Mirrors [useActivatedAbility] but operates on the persistent
  /// [PlayerState.claimedDestinies] zone and the per-turn
  /// [PlayerState.exhaustedDestinies] set. Fails (returns false, no state
  /// change) when: the player can't act, the Destiny is not claimed, it has no
  /// activated ability, it is already exhausted this turn, or the cost is
  /// unpayable. On success it pays the cost, marks the Destiny exhausted, and
  /// resolves the ability (honouring its mastery tier).
  bool useDestinyAbility(String cardId) {
    if (!_currentPlayerCanAct) return false;
    final player = currentPlayer;

    final destiny =
        player.claimedDestinies.where((c) => c.id == cardId).firstOrNull;
    if (destiny == null) return false;

    final ability = destiny.activatedAbility;
    if (ability == null) return false;

    if (player.exhaustedDestinies.contains(cardId)) return false;
    if (!_canPayActivationCost(player, ability.cost)) return false;

    _payActivationCost(player, ability.cost);
    player.exhaustedDestinies.add(cardId);
    _resolveActivatedAbility(ability, player, sourceCard: destiny);
    return true;
  }

  /// Whether the current player could use claimed Destiny [cardId]'s activated
  /// ability RIGHT NOW (UI gate for the Destiny tray's "Use" action). Mirrors
  /// the guards in [useDestinyAbility] without mutating state: the player can
  /// act, the Destiny is claimed and carries an [ActivatedAbility], it is not
  /// already exhausted this turn, and its activation cost is payable. A
  /// passive-only claimed Destiny (no activated ability) returns false.
  bool canUseDestinyAbility(String cardId) {
    if (!_currentPlayerCanAct) return false;
    final player = currentPlayer;
    final destiny =
        player.claimedDestinies.where((c) => c.id == cardId).firstOrNull;
    if (destiny == null) return false;
    final ability = destiny.activatedAbility;
    if (ability == null) return false;
    if (player.exhaustedDestinies.contains(cardId)) return false;
    return _canPayActivationCost(player, ability.cost);
  }

  /// Cascade (Mastery 10): banish a claimed Destiny [cardId] to reveal the top
  /// [revealCount] (default 2) Destinies from the [destinyDeck] for the player
  /// to choose from, granting [grant] (default 2) additional Destiny claims.
  ///
  /// The banished Destiny is removed from the player's [claimedDestinies] and
  /// added to [removedFromGame]; the revealed Destinies are appended to
  /// [destinyRow] (face-up) so the player can then [claimDestiny] them under the
  /// extended allowance. Legal only when the current player can act, holds the
  /// named claimed Destiny, and the Destiny's own mastery gate (if any) is met.
  /// Returns the list of revealed Destinies on success, or an empty list on
  /// failure / when the deck is empty.
  List<CardModel> banishDestinyToCascade(
    String cardId, {
    int revealCount = 2,
    int grant = 2,
  }) {
    if (!_currentPlayerCanAct) return const [];
    final player = currentPlayer;

    final index = player.claimedDestinies.indexWhere((c) => c.id == cardId);
    if (index == -1) return const [];

    final destiny = player.claimedDestinies[index];
    // Respect a card-level mastery gate (stolen_future is Mastery 10).
    final gate = destiny.masteryThreshold;
    if (gate != null && player.mastery < gate) return const [];

    player.claimedDestinies.removeAt(index);
    player.exhaustedDestinies.remove(cardId);
    removedFromGame.add(destiny);

    final reveal = <CardModel>[];
    for (var i = 0; i < revealCount && destinyDeck.isNotEmpty; i++) {
      reveal.add(destinyDeck.removeLast());
    }
    destinyRow.addAll(reveal);
    player.destinyClaimGrants += grant;
    return reveal;
  }

  /// Assign (or clear) the Character a player has chosen, by player id. Lets the
  /// setup flow pick characters after construction (the constructor's
  /// `characters` param is the other supported path). Returns false if no player
  /// has [playerId]. A null [character] clears the assignment (no character).
  bool setCharacter(String playerId, Character? character) {
    final player = players.where((p) => p.id == playerId).firstOrNull;
    if (player == null) return false;
    player.character = character;
    // Re-derive the set-aside relics from the new Character. Only before the
    // player has recruited — once recruited the relic decision is locked in.
    if (!player.relicRecruited) {
      _populateRelicOptions(player);
    }
    return true;
  }

  // -------------------------------------------------------------------------
  // Relics (Relics of the Future expansion)
  // -------------------------------------------------------------------------

  /// Populate [player]'s [PlayerState.relicOptions] from its Character, if any.
  /// No-op unless relic card templates were injected AND the player's Character
  /// is in [characterRelicIds] (rez / chroma and no-character players get none).
  /// Each option is a unique per-player instance (`<relicId>_relic_<playerId>`)
  /// so it never collides with a market copy of the same template.
  void _populateRelicOptions(PlayerState player) {
    player.relicOptions.clear();
    final templates = _relicCards;
    if (templates == null) return;
    final ids = relicIdsFor(player.character);
    if (ids == null) return;
    for (final relicId in ids) {
      final template = templates[relicId];
      if (template == null) continue; // missing template → skip (documented).
      player.relicOptions.add(_relicInstanceFor(template, player.id));
    }
  }

  /// A concrete relic-card instance owned by [playerId], preserving every
  /// gameplay field of [template] with a per-player unique id.
  CardModel _relicInstanceFor(CardModel template, String playerId) {
    // copyWith carries EVERY gameplay field (e.g. Datic Robes' shieldEqualsMastery)
    // — a manual field list here previously dropped them on the relic instance.
    return template.copyWith(id: '${template.id}_relic_$playerId');
  }

  /// Recruit ONE of the current player's two set-aside Relics (Relics of the
  /// Future). Legal only when the current player may act, has mastery >= 10, has
  /// NOT already recruited, and [cardId] matches one of their two
  /// [PlayerState.relicOptions]. On success the chosen relic is SHUFFLED INTO the
  /// player's draw pile (unlike Destiny, which stays beside play), the OTHER
  /// relic is banished to [removedFromGame], the options zone is emptied, and
  /// [PlayerState.relicRecruited] is set. Returns true on success; false (no
  /// state change) on any precondition failure — including a player with no
  /// mapped character / no relic options, for whom this is always a no-op.
  bool recruitRelic(String cardId) {
    if (!_currentPlayerCanAct) return false;
    final player = currentPlayer;
    if (player.relicRecruited) return false;
    if (player.mastery < 10) return false;

    final index = player.relicOptions.indexWhere((c) => c.id == cardId);
    if (index < 0) return false; // not one of this player's relics (or none).

    final chosen = player.relicOptions[index];
    // Banish every OTHER set-aside relic.
    for (var i = 0; i < player.relicOptions.length; i++) {
      if (i != index) removedFromGame.add(player.relicOptions[i]);
    }
    player.relicOptions.clear();
    player.relicRecruited = true;

    // Shuffle the chosen relic into the draw pile.
    player.drawPile.add(chosen);
    player.drawPile.shuffle(_random);
    return true;
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
    final gem0 = player.gemPool,
        power0 = player.powerPool,
        mastery0 = player.mastery,
        health0 = player.health;
    _resolvePlayOrMastery(champion, player);
    _checkAllyAbility(champion, player);
    _log('activated ${champion.name}',
        playerId: player.id,
        cardId: champion.id,
        grants: _grantsSince(player, gem0, power0, mastery0, health0));
    return true;
  }

  /// Character **Focus** — the universal once-per-turn base action: exhaust your
  /// character card and pay 1 gem to gain 1 mastery (Fragments of Boundlessness core
  /// rules). Available to every player every turn, independent of any card.
  ///
  /// Returns false (no state change) if the player can't act, has already
  /// focused this turn, or has fewer than 1 gem. Card effects may grant more
  /// mastery on top; only this Focus action is once-per-turn.
  bool focus() {
    if (!_currentPlayerCanAct) return false;
    final player = currentPlayer;
    if (player.focusedThisTurn) return false;
    if (player.gemPool < 1) return false;

    player.gemPool -= 1;
    player.addMastery(1);
    player.focusedThisTurn = true;
    _log('focused (1 gem → 1 mastery)', playerId: player.id);
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

  // -------------------------------------------------------------------------
  // Static modifier consults (Engine Phase 2, wave 5a — Family 11)
  // -------------------------------------------------------------------------

  /// Whether a [StaticModifier]'s optional faction/type filters match [card].
  /// A null filter matches anything; faction matching honours
  /// countsAsAllFactions (no alias player — static buffs are not turn-scoped).
  bool _modifierApplies(StaticModifier mod, CardModel card) {
    if (mod.faction != null &&
        !_factionsMatch(mod.faction!, false, card.faction,
            card.countsAsAllFactions)) {
      return false;
    }
    if (mod.cardType != null && card.cardType != mod.cardType) return false;
    return true;
  }

  /// The effective HEALTH of [champion] owned by [owner]: the printed `shield`
  /// field value (reinterpreted as the champion's health pips per the owner's
  /// combat model, backlog §E) plus — for a [StaticModifierKind.shieldPerCardUnder]
  /// modifier whose [StaticModifier.sourceChampionId] is THIS champion —
  /// `amount` per card currently tucked under it (carmine_eclipse; FLAGGED for
  /// owner confirmation of how "+shield per card under" maps to health).
  ///
  /// A champion is destroyed only by an attack whose power is >= this value (the
  /// existing one-shot lethal gate, unchanged). NOTE: [StaticModifierKind.shieldBuff]
  /// is NO LONGER folded in here — a shield buff granted by a champion in play
  /// (e.g. praetorian_02) is a standing buff to the PLAYER's per-hit damage
  /// reduction (see [_playerDamageReduction]), not to any champion's kill
  /// threshold. A champion's own value never protects the player.
  int _effectiveHealth(CardModel champion, PlayerState owner) {
    var health = champion.shield;
    for (final mod in owner.staticModifiers) {
      if (mod.kind == StaticModifierKind.shieldPerCardUnder &&
          mod.sourceChampionId == champion.id) {
        // Self-scoped: only buffs the champion that owns the modifier, scaling
        // with that champion's under-card count.
        health += mod.amount * owner.cardsUnderCount(champion.id);
      }
      // one_mind_one_army: a healthBuff raises the destroy threshold of the
      // owner's champions (optionally faction/type-filtered) by `amount`.
      if (mod.kind == StaticModifierKind.healthBuff &&
          _modifierApplies(mod, champion)) {
        health += mod.amountFor(owner.mastery);
      }
    }
    return health;
  }

  /// The passive damage reduction protecting [player] against each direct attack
  /// (owner combat model, backlog §E): the SUM of the `shield` value of every
  /// card currently in the player's HAND, PLUS the SUM of every
  /// [StaticModifierKind.shieldBuff] granted by a champion the player currently
  /// has in play (e.g. praetorian_02 grants a constant shield to YOU while it is
  /// in play; the buff is dropped from [staticModifiers] the instant that
  /// champion leaves play — see [_releaseUnderCards]). Passive, NOT consumed.
  ///
  /// A card's own shield contributes ONLY while it is IN HAND — a champion in
  /// play does NOT contribute its own (health) value. Champion-sourced shield
  /// buffs are recognised by a non-null [StaticModifier.sourceChampionId] that
  /// matches a champion currently in play.
  int _playerDamageReduction(PlayerState player) {
    var reduction = 0;
    for (final card in player.hand) {
      // datic_robes: a card whose in-hand shield is DYNAMIC contributes the
      // player's CURRENT mastery instead of its static shield value.
      reduction += card.shieldEqualsMastery ? player.mastery : card.shield;
    }
    for (final mod in player.staticModifiers) {
      if (mod.kind == StaticModifierKind.shieldBuff &&
          mod.sourceChampionId != null &&
          player.championsInPlay.any((c) => c.id == mod.sourceChampionId)) {
        // praetorian_02: a champion-sourced shieldBuff may be mastery-scaled
        // (4 normally, 8 at mastery >= 20).
        reduction += mod.amountFor(player.mastery);
      }
    }
    return reduction;
  }

  /// Resolve the state a champion leaves behind when [championId]'s champion
  /// leaves [owner]'s play (destroyed or eliminated). Moves any cards tucked
  /// under it to the owner's discard pile (paradigm_the_archivist "put all cards
  /// under it into your discard pile" — the simple, default disposition;
  /// carmine_eclipse's optional "recruit any, banish the rest" is a documented
  /// follow-up) and drops EVERY [StaticModifier] the champion sourced — not just
  /// its self-scoped shieldPerCardUnder buff, but any board-wide aura it granted
  /// (e.g. zetta_the_encryptor's [StaticModifierKind.cannotBeAttacked], which
  /// protects the owner and their other champions only while zetta is in play).
  /// A champion-sourced modifier is aura-scoped: it must vanish the instant its
  /// source leaves, else "you and your other champions can't be attacked" would
  /// outlive the champion granting it. A no-op when the champion had no
  /// under-cards / modifier.
  void _releaseUnderCards(PlayerState owner, String championId) {
    final under = owner.cardsUnderChampion.remove(championId);
    if (under != null && under.isNotEmpty) {
      owner.discardPile.addAll(under);
    }
    owner.staticModifiers.removeWhere((m) => m.sourceChampionId == championId);
  }

  /// Shared champion-DEATH under-card disposition, called by EVERY combat/effect
  /// death path (attackChampion / destroyChampion / _selfBanish / banishCard's
  /// played-this-turn champion branch) in place of [_releaseUnderCards].
  ///
  /// When [champion] carries [CardModel.recruitUnderCardsOnDeath] (carmine_eclipse)
  /// AND has cards tucked under it, those cards are moved to
  /// [pendingUnderCardRecruit] for the OWNER to salvage (pay-to-recruit / banish
  /// the rest) — instead of going straight to discard. The champion's static
  /// modifiers are still dropped (exactly as [_releaseUnderCards] does), so its
  /// shieldPerCardUnder / tuck auras vanish with it. Otherwise this falls back to
  /// [_releaseUnderCards] (the ordinary paradigm_the_archivist disposition — all
  /// under-cards to discard, modifiers dropped).
  ///
  /// Elimination is NOT routed here: [_cleanupEliminatedPlayer] sweeps an
  /// eliminated owner's under-cards to removed-from-game (no salvage — they are
  /// out of the game).
  void _disposeUnderCardsOnDeath(PlayerState owner, CardModel champion) {
    final under = owner.cardsUnderChampion[champion.id];
    if (champion.recruitUnderCardsOnDeath && under != null && under.isNotEmpty) {
      owner.cardsUnderChampion.remove(champion.id);
      pendingUnderCardRecruit.putIfAbsent(owner.id, () => []).addAll(under);
      // Drop the champion's sourced modifiers, mirroring _releaseUnderCards.
      owner.staticModifiers
          .removeWhere((m) => m.sourceChampionId == champion.id);
    } else {
      _releaseUnderCards(owner, champion.id);
    }
  }

  /// The id of a champion in [player]'s play that sources an ACTIVE
  /// [StaticModifierKind.tuckFastPlaysUnder] modifier (carmine_eclipse), or null
  /// if none. Used by [_disposeFastPlayedCard] to route fast-plays under Carmine.
  String? _tuckFastPlaysChampionId(PlayerState player) {
    for (final m in player.staticModifiers) {
      if (m.kind == StaticModifierKind.tuckFastPlaysUnder &&
          m.sourceChampionId != null &&
          player.championsInPlay.any((c) => c.id == m.sourceChampionId)) {
        return m.sourceChampionId;
      }
    }
    return null;
  }

  /// Final disposition of a just-resolved fast-played [card] at BOTH fast-play
  /// sites ([fastPlayFromCenter] free warp, [payAndFastPlayFromCenter] paid
  /// mercenary). If [player] controls a champion with an active
  /// [StaticModifierKind.tuckFastPlaysUnder] aura (carmine_eclipse), the card is
  /// MANDATORILY tucked under that champion (auto-raising its
  /// shieldPerCardUnder health; the card never reaches `fastPlayedThisTurn`, so
  /// Carmine's tuck takes precedence over swyft's optional recruit). Otherwise
  /// the card goes to `fastPlayedThisTurn`, where it stays visible (greyed) for
  /// the rest of the turn and is swept to removed-from-game by
  /// [PlayerState.cleanupTurn] — unless swyft's [recruitFastPlayedCard] rescues
  /// it to discard first.
  void _disposeFastPlayedCard(PlayerState player, CardModel card) {
    final championId = _tuckFastPlaysChampionId(player);
    if (championId != null) {
      player.cardsUnderChampion.putIfAbsent(championId, () => []).add(card);
    } else {
      player.fastPlayedThisTurn.add(card);
    }
  }

  /// Whether a cannotBeAttacked modifier [m] owned by [owner] is currently
  /// ACTIVE against [attacker]. Evaluates the modifier's
  /// [StaticModifier.cannotBeAttackedCondition] with the attacker in context so
  /// per-attacker (relative-mastery) conditions resolve correctly. [attacker] is
  /// only consulted by [CannotBeAttackedCondition.attackerMasteryLessThanOwner].
  bool _cannotBeAttackedActive(
      StaticModifier m, PlayerState owner, PlayerState attacker) {
    switch (m.cannotBeAttackedCondition) {
      case CannotBeAttackedCondition.always:
        return true;
      case CannotBeAttackedCondition.controlsNamedChampion:
        final needed = m.conditionCardName;
        if (needed == null) return true; // degenerate → always
        return owner.championsInPlay.any((c) => c.name == needed);
      case CannotBeAttackedCondition.attackerMasteryLessThanOwner:
        return attacker.mastery < owner.mastery;
    }
  }

  /// Whether [attacker] is barred from directly attacking [target] (the player)
  /// by a [StaticModifierKind.cannotBeAttacked] modifier. Only a
  /// [CannotBeAttackedScope.playerAndOtherChampions] modifier (e.g. Zetta's aura)
  /// protects the PLAYER; a self-scoped per-champion protection (Li Hin, Raidian,
  /// Drakonarius) shields only its champion, never the player.
  bool _playerCannotBeAttacked(PlayerState target, PlayerState attacker) =>
      target.staticModifiers.any((m) =>
          m.kind == StaticModifierKind.cannotBeAttacked &&
          m.cannotBeAttackedScope ==
              CannotBeAttackedScope.playerAndOtherChampions &&
          _cannotBeAttackedActive(m, target, attacker));

  /// [card]'s acquisition cost for [buyer] after applying every matching
  /// [StaticModifierKind.cardCostReduction] modifier, floored at 1 gem.
  int _discountedCost(CardModel card, PlayerState buyer) {
    var cost = card.cost;
    // aedifex-style board-wide cost reductions on the BUYER (floor at 1 gem).
    for (final mod in buyer.staticModifiers) {
      if (mod.kind == StaticModifierKind.cardCostReduction &&
          _modifierApplies(mod, card)) {
        cost -= mod.amount;
      }
    }
    if (cost < 1) cost = 1;
    // axia: a SELF acquire-cost reduction carried by THIS card — subtract
    // `amountPer` per matching champion the buyer controls (floored at 0, so the
    // card can become free). Distinct from the aedifex discount above (which
    // floors at 1 and applies to OTHER cards).
    for (final effect in card.playEffects) {
      if (effect is AcquireCostReductionPerChampionEffect) {
        final matching = buyer.championsInPlay
            .where((c) => _factionsMatch(
                effect.faction, false, c.faction, c.countsAsAllFactions,
                aliasPlayer: buyer, extraB: _extraFactions(c, buyer)))
            .length;
        cost -= effect.amountPer * matching;
      }
    }
    return cost < 0 ? 0 : cost;
  }

  /// Whether a recruited [card] should be routed to the top of [player]'s deck
  /// because of a matching [StaticModifierKind.recruitToTopOfDeck] modifier.
  bool _recruitsToTopOfDeck(CardModel card, PlayerState player) =>
      player.staticModifiers.any((m) =>
          m.kind == StaticModifierKind.recruitToTopOfDeck &&
          _modifierApplies(m, card));

  /// Whether [player]'s pending [RedirectNextRecruitEffect] matches [card].
  /// A null faction/type filter matches anything; faction matching honours
  /// `countsAsAllFactions` (and the player's turn-scoped aliases). For an
  /// `intoPlay` redirect the card must additionally be a champion — only
  /// champions can persist in play.
  bool _recruitRedirectMatches(RedirectNextRecruitEffect r, CardModel card) {
    if (r.faction != null &&
        !_factionsMatch(r.faction!, false, card.faction,
            card.countsAsAllFactions, aliasPlayer: currentPlayer)) {
      return false;
    }
    if (r.cardType != null && card.cardType != r.cardType) return false;
    if (r.destination == RecruitRedirect.intoPlay &&
        card.cardType != CardType.champion) {
      return false;
    }
    return true;
  }

  /// If [player] has a pending [RedirectNextRecruitEffect] that matches the
  /// just-recruited [card] (numeri_drones / anomaly_cleric), this places the
  /// card at the redirected destination, CONSUMES the redirect (single-use), and
  /// returns true. Otherwise it leaves the redirect intact and returns false so
  /// the caller places the card the normal way.
  ///
  /// For [RecruitRedirect.intoPlay] the champion is DEPLOYED exactly as if it had
  /// been played from hand (mechanics doc: a champion "immediately enters play"):
  /// it joins `championsInPlay`, is recorded in `cardsPlayedThisTurn`, its
  /// play/mastery effects resolve, and its ally ability is checked — so it can
  /// use its ability this turn. For [RecruitRedirect.toHand] the card simply goes
  /// to hand (to be played later), with no effects resolved.
  bool _applyPendingRecruitRedirect(PlayerState player, CardModel card) {
    final redirect = player.pendingRecruitRedirect;
    if (redirect == null) return false;
    if (!_recruitRedirectMatches(redirect, card)) return false;

    player.pendingRecruitRedirect = null; // single-use — consumed
    switch (redirect.destination) {
      case RecruitRedirect.intoPlay:
        player.championsInPlay.add(card);
        player.cardsPlayedThisTurn.add(card);
        _resolvePlayOrMastery(card, player);
        _checkAllyAbility(card, player);
      case RecruitRedirect.toHand:
        player.hand.add(card);
    }
    return true;
  }

  /// Whether [card] carries an on-recruit "put into hand" trigger
  /// ([RecruitToHandEffect]) whose optional Character gate is satisfied by
  /// [player]. Scanned by [buyCard] / [recruitFromCenter] to route a freshly
  /// recruited card to hand instead of the discard pile (breaker unconditional;
  /// nexus_datic_hunter gated on [Character.tetra]).
  bool _recruitsToHand(CardModel card, PlayerState player) {
    for (final e in card.playEffects) {
      if (e is RecruitToHandEffect &&
          (e.character == null || player.character == e.character)) {
        return true;
      }
    }
    return false;
  }

  /// praetorian_01 trigger: after [player] plays a Champion, move every card in
  /// their discard pile that carries a [ReturnSelfWhenChampionPlayedEffect] back
  /// to their hand. A passive, while-in-discard trigger; no effects resolve on
  /// the returned card (it goes to hand to be replayed later). A no-op when no
  /// such card is in the discard pile.
  void _triggerChampionPlayReturns(PlayerState player) {
    final returning = <CardModel>[];
    player.discardPile.removeWhere((c) {
      final match =
          c.playEffects.any((e) => e is ReturnSelfWhenChampionPlayedEffect);
      if (match) returning.add(c);
      return match;
    });
    for (final c in returning) {
      player.hand.add(c);
      _log('returned ${c.name} to hand', playerId: player.id, cardId: c.id);
    }
  }

  // -------------------------------------------------------------------------
  // Opponent draw / discard (Engine Phase 2, wave 5a — Family 13)
  // -------------------------------------------------------------------------

  /// Every player except [source] draws [count] card(s) from their own draw
  /// pile, reshuffling their discard when the draw pile empties (mirrors
  /// [_drawCards]). Eliminated players are skipped. Used by [OpponentDrawsEffect]
  /// (blitz_shard_runner).
  void _eachOtherPlayerDraws(PlayerState source, int count) {
    if (count <= 0) return;
    for (final player in players) {
      if (player.id == source.id || player.isEliminated) continue;
      _drawCards(player, count);
    }
  }

  /// Every player except [source] discards [count] card(s) from their hand
  /// (the first [count], or all they have if fewer). Eliminated players are
  /// skipped. Used by [OpponentDiscardsEffect] (blitz_shard_runner mastery
  /// variant).
  void _eachOtherPlayerDiscards(PlayerState source, int count) {
    if (count <= 0) return;
    for (final player in players) {
      if (player.id == source.id || player.isEliminated) continue;
      final n = count > player.hand.length ? player.hand.length : count;
      for (var i = 0; i < n; i++) {
        player.discardPile.add(player.hand.removeAt(0));
      }
    }
  }

  // -------------------------------------------------------------------------
  // Copy-effect (Engine Phase 2, wave 5a — Family 9)
  // -------------------------------------------------------------------------

  /// Re-resolve the play effects of a card the current player already played
  /// this turn, fulfilling a [CopyPlayedCardEffect] after the player selects a
  /// target. [cardId] must name a card in [PlayerState.cardsPlayedThisTurn].
  ///
  /// Honours the effect's [CopyFilter] (nonChampion excludes champions).
  ///
  /// RE-ENTRANCY GUARD: a card that itself contains a [CopyPlayedCardEffect] is
  /// NOT copyable (returns false) — this prevents a copy-of-a-copy from looping.
  /// In addition, when re-resolving, any [InfinityShardEffect] in the copied
  /// card's play effects is SKIPPED so copying can never grant mastery or
  /// trigger a spurious Infinity Shard win.
  ///
  /// Returns false (no state change) if the game is over / the player can't act,
  /// the card is not found, it does not match the filter, or it is itself a copy
  /// card.
  bool copyPlayedCard(
    String cardId, {
    CopyFilter filter = CopyFilter.nonChampion,
    Faction? faction,
  }) {
    if (!_currentPlayerCanAct) return false;
    final player = currentPlayer;

    final card =
        player.cardsPlayedThisTurn.where((c) => c.id == cardId).firstOrNull;
    if (card == null) return false;

    if (filter == CopyFilter.nonChampion &&
        card.cardType == CardType.champion) {
      return false;
    }

    // Optional faction filter (taur_archpriest: Undergrowth allies only).
    if (faction != null &&
        faction != Faction.none &&
        !_factionsMatch(faction, false, card.faction, card.countsAsAllFactions,
            aliasPlayer: player, extraB: _extraFactions(card, player))) {
      return false;
    }

    // Re-entrancy guard: refuse to copy a card that itself copies.
    if (_containsCopyEffect(card.playEffects)) return false;

    // Re-resolve the copied card's play effects, excluding InfinityShardEffect
    // so the copy never causes a mastery gain / spurious win, and
    // RevealAndCopyTopOfDecksEffect ("this effect can't be copied").
    final copyable = [
      for (final e in card.playEffects)
        if (e is! InfinityShardEffect && e is! RevealAndCopyTopOfDecksEffect) e,
    ];
    _resolveEffects(copyable, player, sourceCard: card);
    return true;
  }

  /// Copy the play effects of EVERY card played this turn matching [filter] and
  /// (optionally) [faction], in play order — the copy-ALL variant used by
  /// general_decurion's Mastery-20 ("copy the effect of each Homodeus Ally you
  /// played this turn"). Immediate (no target selection). [excludeSource] (the
  /// in-flight champion resolving the ability) is never copied.
  ///
  /// RE-ENTRANCY GUARD (mirrors [copyPlayedCard]): a matched card that itself
  /// contains any copy effect ([CopyPlayedCardEffect] / [CopyAllPlayedCardsEffect])
  /// is skipped so a copy never recurses, and every [InfinityShardEffect] among a
  /// matched card's effects is excluded from the re-resolved list so copying can
  /// never grant mastery / trigger a spurious Infinity Shard win.
  void _copyAllPlayedCards(
    PlayerState player, {
    CopyFilter filter = CopyFilter.nonChampion,
    Faction? faction,
    CardModel? excludeSource,
  }) {
    // Snapshot the play history first: re-resolving a card's effects can append
    // to cardsPlayedThisTurn (rare), and we must not copy those newly-added
    // cards nor iterate a mutating list.
    final candidates = List<CardModel>.from(player.cardsPlayedThisTurn);
    for (final card in candidates) {
      if (excludeSource != null && identical(card, excludeSource)) continue;
      if (filter == CopyFilter.nonChampion &&
          card.cardType == CardType.champion) {
        continue;
      }
      if (faction != null &&
          faction != Faction.none &&
          !_factionsMatch(faction, false, card.faction, card.countsAsAllFactions,
              aliasPlayer: player, extraB: _extraFactions(card, player))) {
        continue;
      }
      // Never re-resolve a card that itself copies (no copy-of-a-copy loop).
      if (_containsCopyEffect(card.playEffects)) continue;

      final copyable = [
        for (final e in card.playEffects)
          if (e is! InfinityShardEffect && e is! RevealAndCopyTopOfDecksEffect)
            e,
      ];
      _resolveEffects(copyable, player, sourceCard: card);
    }
  }

  bool _containsCopyEffect(List<CardEffect> effects) {
    for (final e in effects) {
      if (e is CopyPlayedCardEffect) return true;
      if (e is CopyAllPlayedCardsEffect) return true;
      // duplication_fabricator "this effect can't be copied".
      if (e is RevealAndCopyTopOfDecksEffect) return true;
      // Guard nested copies inside chooseOne / conditional too.
      if (e is ChooseOneEffect) {
        for (final group in e.choices) {
          if (_containsCopyEffect(group)) return true;
        }
      }
      if (e is ConditionalEffect && _containsCopyEffect(e.then)) return true;
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Under-card stacking (Engine Phase 2, wave 5b — Family 13)
  // -------------------------------------------------------------------------

  /// Tuck [cardId] from the current player's HAND under their champion
  /// [championId], fulfilling a [TuckUnderChampionEffect] (source hand) after
  /// the player selects both. The card is removed from hand and appended to the
  /// champion's under-card list ([PlayerState.cardsUnderChampion]); its effects
  /// do NOT resolve (it is tucked, not played).
  ///
  /// When [alliesOnly] is true, champions cannot be tucked (an ally is a
  /// non-champion card). Returns false (no state change) if the game is over /
  /// the player can't act, the champion is not controlled by the player, the
  /// card is not in hand, or it fails the allies-only filter.
  bool tuckUnderChampion(
    String championId,
    String cardId, {
    bool alliesOnly = false,
  }) {
    if (!_currentPlayerCanAct) return false;
    final player = currentPlayer;

    final controls = player.championsInPlay.any((c) => c.id == championId);
    if (!controls) return false;

    final handIndex = player.hand.indexWhere((c) => c.id == cardId);
    if (handIndex == -1) return false;
    if (alliesOnly && player.hand[handIndex].cardType == CardType.champion) {
      return false;
    }

    final card = player.hand.removeAt(handIndex);
    player.cardsUnderChampion.putIfAbsent(championId, () => []).add(card);
    return true;
  }

  /// Tuck the top card of the CENTER (infinity) deck under [championId]
  /// (gene_scavs ambush). Immediate variant of [TuckUnderChampionEffect] (source
  /// centerDeck), called inline during effect resolution. Returns false (no
  /// state change) if the player doesn't control the champion or the infinity
  /// deck is empty.
  bool _tuckTopOfCenterDeck(PlayerState player, String championId) {
    final controls = player.championsInPlay.any((c) => c.id == championId);
    if (!controls) return false;
    if (infinityDeck.isEmpty) return false;
    final card = infinityDeck.removeLast();
    player.cardsUnderChampion.putIfAbsent(championId, () => []).add(card);
    return true;
  }

  /// Re-resolve the `playEffects` of every card tucked under [championId] for
  /// the current player, fulfilling a [CopyUnderCardsEffect]
  /// (paradigm_the_archivist). Cards are copied in tuck order. The under-cards
  /// themselves are NOT consumed — they stay under the champion.
  ///
  /// RE-ENTRANCY / SAFETY: among each under-card's effects, [InfinityShardEffect]
  /// is skipped (no spurious mastery/win, mirroring [copyPlayedCard]), and
  /// [TuckUnderChampionEffect] / [CopyUnderCardsEffect] are skipped to avoid
  /// re-entrant tucking/copying.
  ///
  /// Returns false (no state change) if the game is over / the player can't act,
  /// the player doesn't control the champion, or there are no cards under it.
  bool copyUnderCards(String championId) {
    if (!_currentPlayerCanAct) return false;
    final player = currentPlayer;

    final controls = player.championsInPlay.any((c) => c.id == championId);
    if (!controls) return false;

    final under = player.cardsUnderChampion[championId];
    if (under == null || under.isEmpty) return false;

    // Snapshot so re-resolution can't mutate the list mid-iteration.
    for (final card in List<CardModel>.from(under)) {
      final copyable = [
        for (final e in card.playEffects)
          if (e is! InfinityShardEffect &&
              e is! TuckUnderChampionEffect &&
              e is! CopyUnderCardsEffect &&
              e is! RevealAndCopyTopOfDecksEffect)
            e,
      ];
      _resolveEffects(copyable, player, sourceCard: card);
    }
    return true;
  }

  // -------------------------------------------------------------------------
  // Reveal-and-copy top of every deck (Wave-B Group 4b — duplication_fabricator)
  // -------------------------------------------------------------------------

  /// PEEK at the top card of EVERY player's deck (owner ruling: base effect,
  /// every play), populating [pendingDeckReveal] for the caster's copy choice.
  /// Resolved INLINE from [RevealAndCopyTopOfDecksEffect].
  ///
  /// - The revealed card is LEFT ON TOP (peek-only — never removed).
  /// - When a player's draw pile is empty, their discard pile is reshuffled into
  ///   it first (mirrors [_drawCards] / [scryReveal]); a player with NO cards at
  ///   all (empty draw AND discard) is skipped.
  /// - "Top of deck" is the END of [PlayerState.drawPile] (the next card
  ///   [_drawCards] would deal via removeLast()).
  ///
  /// Any prior pending reveal is cleared first (a fresh play supersedes it).
  void revealTopOfAllDecks() {
    pendingDeckReveal.clear();
    for (final player in players) {
      if (player.isEliminated) continue;
      if (player.drawPile.isEmpty && player.discardPile.isNotEmpty) {
        player.drawPile.addAll(player.discardPile);
        player.discardPile.clear();
        player.drawPile.shuffle(_random);
      }
      if (player.drawPile.isEmpty) continue; // no cards to reveal — skip
      pendingDeckReveal
          .add((ownerId: player.id, card: player.drawPile.last));
    }
  }

  /// Fulfil a [RevealAndCopyTopOfDecksEffect]: copy the effect of the revealed
  /// card [cardId] (chosen from [pendingDeckReveal]) for the CURRENT player.
  ///
  /// The chosen card must (1) be present in [pendingDeckReveal], (2) be an ALLY —
  /// a regular, non-champion card — and (3) NOT be another Duplication Fabricator
  /// ("cannot copy another Duplication Fabricator"). Its `playEffects` are then
  /// re-resolved for the current player using the shared copy guards: an
  /// [InfinityShardEffect], a [RevealAndCopyTopOfDecksEffect] ("this effect can't
  /// be copied"), and any nested copy effect (`_containsCopyEffect`) are all
  /// excluded so copying can neither win the game nor recurse.
  ///
  /// The revealed cards are LEFT ON TOP of their decks (peek-only); [cardId] is
  /// NOT moved. [pendingDeckReveal] is cleared on success.
  ///
  /// Returns false (no state change) if the game is over / the player can't act,
  /// the card is not a valid pending reveal, or it fails the ally / self filters.
  bool copyRevealedCard(String cardId) {
    if (!_currentPlayerCanAct) return false;

    final entry =
        pendingDeckReveal.where((e) => e.card.id == cardId).firstOrNull;
    if (entry == null) return false;
    final card = entry.card;

    // Ally = a regular, non-champion card (mercenaries are not allies).
    if (card.cardType != CardType.regular) return false;

    // Cannot copy another Duplication Fabricator (by id/name).
    if (card.id == 'duplication_fabricator' ||
        card.name == 'Duplication Fabricator') {
      return false;
    }

    // Re-entrancy guard: never copy a card that itself copies.
    if (_containsCopyEffect(card.playEffects)) return false;

    final player = currentPlayer;
    // Re-resolve the copied ally's play effects, excluding InfinityShardEffect
    // (no spurious mastery/win) and RevealAndCopyTopOfDecksEffect (uncopyable).
    final copyable = [
      for (final e in card.playEffects)
        if (e is! InfinityShardEffect && e is! RevealAndCopyTopOfDecksEffect) e,
    ];
    _resolveEffects(copyable, player, sourceCard: card);

    // Peek-only: revealed cards stay on top. Clear the pending choice.
    pendingDeckReveal.clear();
    return true;
  }

  // -------------------------------------------------------------------------
  // Center-deck scry (Engine Phase 2, wave 5a — extends Family 8)
  // -------------------------------------------------------------------------

  /// Peek at the top card of the CENTER (infinity) deck WITHOUT removing it (for
  /// UI display before a [CenterDeckScryEffect] resolution). Returns null when
  /// the infinity deck is empty. The "top" is the END of [infinityDeck] (the
  /// next card [_refillCenterRow] would deal, via removeLast()).
  CardModel? centerDeckScryReveal() {
    if (infinityDeck.isEmpty) return null;
    return infinityDeck.last;
  }

  /// Resolve a [CenterDeckScryEffect] against the top card of the infinity deck,
  /// after the player has seen it (deferred-selection). [cardId] must name the
  /// current top card (returned by [centerDeckScryReveal]).
  ///
  /// - [CenterScryDisposition.acquire] (the_shard_defiant): the revealed card is
  ///   removed from the infinity deck and acquired to the player's discard pile,
  ///   for free.
  /// - [CenterScryDisposition.toHandLosePowerEqualToCost] (oblivion_gatekeeper):
  ///   the revealed card is put into the player's hand and they lose power equal
  ///   to its gem cost (power pool floored at 0). This "ignores Guard" — it is a
  ///   pure resource interaction with no targeting, so Guard never applies.
  ///
  /// Returns false (no state change) if the game is over / the player can't act,
  /// the deck is empty, or [cardId] is not the current top card.
  bool centerDeckScryResolve(
    String cardId, {
    CenterScryDisposition disposition = CenterScryDisposition.acquire,
  }) {
    if (!_currentPlayerCanAct) return false;
    if (infinityDeck.isEmpty) return false;
    if (infinityDeck.last.id != cardId) return false;

    final player = currentPlayer;
    final card = infinityDeck.removeLast();

    switch (disposition) {
      case CenterScryDisposition.acquire:
        player.discardPile.add(card);
      case CenterScryDisposition.toHandLosePowerEqualToCost:
        player.hand.add(card);
        player.powerPool -= card.cost;
        if (player.powerPool < 0) player.powerPool = 0;
    }
    return true;
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
      // praetorian_01: playing a Champion returns any discard-pile card carrying
      // the on-champion-play return trigger back to the owner's hand.
      _triggerChampionPlayReturns(player);
    } else {
      player.playedThisTurn.add(card);
    }

    // Record for per-turn scaling effects (ConditionalPowerEffect). Includes
    // champions and mercenaries, in play order.
    player.cardsPlayedThisTurn.add(card);

    // Measure the ACTUAL resources this play grants (captures scaling /
    // conditional / mastery-bonus / ally grants a static read would miss).
    final gem0 = player.gemPool,
        power0 = player.powerPool,
        mastery0 = player.mastery,
        health0 = player.health;

    // Resolve play effects (or, for masteryReplaces cards at threshold, the
    // mastery bonus INSTEAD; otherwise the additive mastery bonus on top).
    _resolvePlayOrMastery(card, player, choiceIndex: choiceIndex);

    // Step 9: check ally ability
    _checkAllyAbility(card, player);

    _log('played ${card.name}',
        playerId: player.id,
        cardId: card.id,
        grants: _grantsSince(player, gem0, power0, mastery0, health0));
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
    // aedifex: apply any cardCostReduction static modifiers the buyer owns
    // (min 1 gem). Mirrored in recruitFromCenter for non-free recruits.
    final price = _discountedCost(card, currentPlayer);
    if (currentPlayer.gemPool < price) return false;

    final buyer = currentPlayer;
    buyer.gemPool -= price;
    centerRow.removeAt(rowIndex);
    // numeri_drones / anomaly_cleric: a pending "next recruit" redirect may
    // route this card directly into play or to hand instead of the discard pile.
    // breaker / nexus_datic_hunter: an on-recruit "put into hand" trigger routes
    // it to hand (takes precedence over the default discard destination).
    if (_applyPendingRecruitRedirect(buyer, card)) {
      // routed into play / to hand by the pending redirect
    } else if (_recruitsToHand(card, buyer)) {
      buyer.hand.add(card);
    } else {
      buyer.discardPile.add(card);
    }
    _refillCenterRow();

    _log('recruited ${card.name} for $price gems',
        playerId: buyer.id, cardId: card.id);
    return true;
  }

  /// End the current player's turn: cleanup, draw, advance.
  void endTurn() {
    final player = currentPlayer;
    _log('ended their turn', playerId: player.id);

    // the_heart_of_nothing: arm a next-turn draw bonus if a card PLAYED this turn
    // requests it and this player dealt enough UNBLOCKED damage. Evaluated NOW,
    // before resetTurnResources zeroes unblockedDamageThisTurn / clears
    // cardsPlayedThisTurn. The bonus is consumed by the end-of-turn draw below,
    // which deals this player's NEXT hand.
    for (final card in player.cardsPlayedThisTurn) {
      for (final effect in card.playEffects) {
        if (effect is BonusDrawNextTurnOnUnblockedDamageEffect &&
            player.unblockedDamageThisTurn >= effect.threshold) {
          player.nextTurnDrawBonus += effect.count;
        }
      }
    }

    // Discard remaining hand cards (unplayed cards go to discard)
    player.discardPile.addAll(player.hand);
    player.hand.clear();

    // A Duplication Fabricator reveal-and-copy is a SAME-TURN deferred choice —
    // if the caster ended their turn without picking, drop it. Otherwise the
    // list (which carries no chooser id) would linger and let the NEXT player
    // consume the prior caster's copy choice, and its "leave on top" guarantee
    // would already be stale (the owner may have drawn the revealed card).
    pendingDeckReveal.clear();

    // Cleanup: move played cards to discard; mercenaries and fast-played/warped
    // cards (kept visible in the play area this turn) leave the game.
    final removed = player.cleanupTurn();
    removedFromGame.addAll(removed);

    // Reset per-turn resources (nextTurnDrawBonus is deliberately preserved —
    // it is consumed by the draw just below, not by resetTurnResources).
    player.resetTurnResources();

    // Draw 5 cards for end-of-turn (mechanics doc Section 4d), plus any armed
    // next-turn draw bonus (the_heart_of_nothing), then clear the bonus.
    final drawCount = 5 + player.nextTurnDrawBonus;
    player.nextTurnDrawBonus = 0;
    _drawCards(player, drawCount);

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

    // Flexible conditional cannotBeAttacked (backlog §B3). A champion is shielded
    // from a normal ATTACK when the owner holds a cannotBeAttacked modifier that
    // (a) is currently ACTIVE against THIS attacker (currentPlayer) and (b) whose
    // SCOPE covers this champion:
    //   * playerAndOtherChampions (Zetta aura) protects every champion EXCEPT the
    //     one that sources it — so the source champion (e.g. Zetta) stays
    //     attackable while the owner's other champions are shielded.
    //   * selfChampion (Li Hin / Raidian / Drakonarius) protects ONLY the champion
    //     that sources it, and only while its condition holds (named-champion in
    //     play, or attacker-mastery-less-than-owner).
    // Card-effect destruction (destroyChampion / DestroyChampionEffect) is a
    // SEPARATE path and is NOT gated here — so Li Hin can still be destroyed.
    final protected = target.staticModifiers.any((m) {
      if (m.kind != StaticModifierKind.cannotBeAttacked) return false;
      if (!_cannotBeAttackedActive(m, target, currentPlayer)) return false;
      final coversThisChampion =
          m.cannotBeAttackedScope == CannotBeAttackedScope.selfChampion
              ? m.sourceChampionId == champion.id
              : m.sourceChampionId != champion.id;
      return coversThisChampion;
    });
    if (protected) return false;
    // Owner combat model (backlog §E): a champion has HEALTH (its printed
    // `shield` value, plus any self-scoped shieldPerCardUnder term) and is
    // destroyed only by an attack with power >= that health — the existing
    // one-shot lethal gate, unchanged. spirit_leech / ignoresShieldThisTurn no
    // longer applies here: "ignore shield" means ignore the target PLAYER's
    // per-hit damage reduction (see attackPlayer), NOT instakill a champion.
    final healthNeeded = _effectiveHealth(champion, target);
    if (currentPlayer.powerPool < healthNeeded) return false;

    currentPlayer.powerPool -= healthNeeded;
    target.championsInPlay.removeAt(champIndex);
    target.discardPile.add(champion);
    _disposeUnderCardsOnDeath(target, champion);

    // Note the health the champion absorbed (public: the champion's value is
    // board-visible). Kept as "shield N absorbed" for log/UI continuity — the
    // value is the champion's health under the new model.
    final shieldNote = healthNeeded > 0 ? ' (shield $healthNeeded absorbed)' : '';
    // Reference the victim by SEAT ID (`p0`), not PlayerState.name: the UI's
    // shared log renderer (and the server's name rewrite) resolves seat ids to
    // real player names, so the line reads with usernames on both boards.
    _log('destroyed ${target.id}\'s ${champion.name}$shieldNote',
        playerId: currentPlayer.id, cardId: champion.id);
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

    // zetta_the_encryptor: a player-scoped cannotBeAttacked modifier makes the
    // target untargetable by direct attacks. A self-scoped per-champion
    // protection (Li Hin / Raidian / Drakonarius) does NOT shield the player.
    if (_playerCannotBeAttacked(target, currentPlayer)) return false;

    // Guard check: target must have no guard champions. rue_bo_vai's Mastery-10
    // "you ignore Guard this turn" lets the attacker bypass this gate entirely.
    final hasGuard = !currentPlayer.ignoresGuardThisTurn &&
        target.championsInPlay.any((c) => c.hasGuard);
    if (hasGuard) {
      // Public-info-safe: guard champions and their owner are visible on the
      // board, so noting that a guard blocked the direct attack leaks nothing.
      _log("${target.id}'s guard blocked the attack",
          playerId: currentPlayer.id);
      return false;
    }

    if (currentPlayer.powerPool < amount) return false;

    final attackerId = currentPlayer.id;
    currentPlayer.powerPool -= amount;

    // Owner combat model (backlog §E): the target's PASSIVE damage reduction —
    // the sum of the shield of every card in their HAND plus every shieldBuff a
    // champion they control grants — reduces the incoming damage (floored at 0)
    // BEFORE it lands. spirit_leech / ignoresShieldThisTurn on the ATTACKER lets
    // this attack ignore that per-hit reduction. lastDamage / the flash and
    // unblockedDamageThisTurn all reflect the POST-reduction number.
    final reduction =
        currentPlayer.ignoresShieldThisTurn ? 0 : _playerDamageReduction(target);
    final dealt = amount - reduction < 0 ? 0 : amount - reduction;

    target.takeDamage(dealt);
    _log('dealt $dealt damage to ${target.id}', playerId: attackerId);

    // Publish a structured "last damage" event so every client (attacker AND
    // victim) can play the SAME attack animation once, keyed off the bumped seq.
    // Public info (attacker/victim/amount are all board-visible).
    lastDamage = LastDamageEvent(
      seq: ++_damageSeq,
      fromId: attackerId,
      toId: target.id,
      amount: dealt,
    );

    // Record unblocked damage dealt this turn (guard already ruled out above),
    // for GameConditionKind.unblockedDamageAtLeast (e.g. blood_for_blood) — the
    // POST-reduction number (shield-reduced damage is not "unblocked").
    currentPlayer.unblockedDamageThisTurn += dealt;

    // Check elimination and clean up zones if the target was just eliminated
    if (target.isEliminated) {
      _cleanupEliminatedPlayer(target);
      _checkGameOver();
    }

    return true;
  }

  // -------------------------------------------------------------------------
  // Ingeminex — neutral shared champion-row entities (co-op boss, versus adapt)
  // -------------------------------------------------------------------------

  /// Make an Ingeminex ENTITY APPEAR in the shared Champions Row.
  ///
  /// Per the Ingeminex mechanic, ON APPEARANCE the entity IMMEDIATELY deals its
  /// effect to ALL players — every player in the game, INCLUDING whoever caused
  /// it to appear. This is realized by resolving [IngeminexEntity.appearanceEffects]
  /// exactly ONCE: those effects are authored as ALL-PLAYERS-scoped effects (e.g.
  /// [AllPlayersLoseHealthEffect], which loops over every seat with no exclusion
  /// via [_applyAllPlayersHealthLoss]), so a single resolution broadcasts to
  /// everyone. If the appearance effect is damage, all players take it (an
  /// appearance can even eliminate a player / end the game, exactly like any
  /// [AllPlayersLoseHealthEffect]).
  ///
  /// The entity then persists in [ingeminexRow] as a NEUTRAL, shared attackable
  /// (see [attackIngeminex]) with [IngeminexEntity.maxHealth] (10) until killed.
  ///
  /// APPEARANCE-TRIGGER ASSUMPTION (documented, not guessed): the six Ingeminex
  /// cards carry NO spawn trigger in the card data — their `playEffects` are empty
  /// and the Attack/Reward text lives only in `rawText`. This method is therefore
  /// the clean, explicit appearance entry point a future caller (a dedicated
  /// Ingeminex deck, a triggering card's effect, or scenario seeding) invokes to
  /// bring one into play. Not gated on the acting player, since an appearance is a
  /// board event, not a player turn-action. Returns the spawned entity.
  IngeminexEntity spawnIngeminex(IngeminexEntity entity) {
    ingeminexRow.add(entity);
    _log('Ingeminex ${entity.name} appeared — all players are hit',
        cardId: entity.id);
    // Broadcast the appearance effect to ALL players. The effects are
    // all-players-scoped, so resolving once reaches every seat (including the
    // spawner). currentPlayer is passed only as the nominal source; all-players
    // effects ignore it.
    _resolveEffects(entity.appearanceEffects, currentPlayer);
    return entity;
  }

  /// Attack a NEUTRAL [IngeminexEntity] in the shared Champions Row.
  ///
  /// Unlike [attackChampion] (which rejects attacking your OWN champions and
  /// targets a specific player's board), an Ingeminex belongs to no player, so
  /// ANY current player may attack it — there is no owner / opponent check.
  /// Damage ACCUMULATES ([IngeminexEntity.damageTaken]) across attacks AND turns
  /// (an HP pool, unlike a normal champion's all-or-nothing shield). The attacker
  /// commits up to [amount] power; the engine spends only what is needed to reach
  /// the entity's remaining health (no overkill waste). When accumulated damage
  /// reaches [IngeminexEntity.maxHealth] (10) the entity DIES: its
  /// [IngeminexEntity.rewardEffects] resolve for the KILLER ONLY (the current
  /// player), and it leaves [ingeminexRow]. Returns true if any damage was applied.
  bool attackIngeminex(String ingeminexId, int amount) {
    if (!_currentPlayerCanAct) return false;
    if (amount <= 0) return false;

    final index = ingeminexRow.indexWhere((e) => e.id == ingeminexId);
    if (index == -1) return false;

    final entity = ingeminexRow[index];
    if (entity.isDead) return false; // defensive; dead entities are removed

    // Spend only what's needed to reach remaining health (avoid overkill waste).
    final needed = entity.remainingHealth;
    final spend = amount < needed ? amount : needed;
    if (currentPlayer.powerPool < spend) return false;

    currentPlayer.powerPool -= spend;
    entity.applyDamage(spend);
    _log('dealt $spend damage to Ingeminex ${entity.name}',
        playerId: currentPlayer.id, cardId: entity.id);

    if (entity.isDead) {
      // Remove the neutral entity, then hand the reward to the KILLER only.
      ingeminexRow.removeAt(index);
      final killer = currentPlayer;
      _resolveEffects(entity.rewardEffects, killer);
      _log('defeated Ingeminex ${entity.name} (reward claimed)',
          playerId: killer.id,
          cardId: entity.id,
          grants: _resourceGrantsOf(entity.rewardEffects));
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
      case BanishSource.playedThisTurn:
        // blood_for_blood: banish a card you have played this turn. The card
        // lives in playedThisTurn (regular/mercenary) or championsInPlay
        // (champion); it is ALSO recorded in the cardsPlayedThisTurn history,
        // which must be purged so scaling/conditional counts and end-of-turn
        // cleanup do not still see it.
        final inPlayed = _banishFromZone(player.playedThisTurn, cardId);
        // Capture the champion model BEFORE banishing so its under-cards can be
        // disposed with the correct death disposition (carmine_eclipse salvage
        // vs. discard). _banishFromZone only returns a bool.
        final banishedChampion = inPlayed
            ? null
            : player.championsInPlay
                .where((c) => c.id == cardId)
                .firstOrNull;
        final inChampions =
            !inPlayed && _banishFromZone(player.championsInPlay, cardId);
        if (!inPlayed && !inChampions) return false;
        // A banished champion must dispose its under-cards (mirrors every other
        // champion-removal path; otherwise tucked cards + shieldPerCardUnder
        // orphan).
        if (inChampions && banishedChampion != null) {
          _disposeUnderCardsOnDeath(player, banishedChampion);
        }
        // Remove a SINGLE history entry (ids are card-type ids, so duplicates
        // legitimately recur this turn — removeWhere would over-purge and
        // corrupt per-turn counts; we only banished one physical card).
        final histIndex =
            player.cardsPlayedThisTurn.indexWhere((c) => c.id == cardId);
        if (histIndex != -1) player.cardsPlayedThisTurn.removeAt(histIndex);
        return true;
    }
  }

  /// Banish the in-flight source card itself ("Then, banish this"). Removes it
  /// from whichever zone it currently occupies (playedThisTurn for regular/
  /// mercenary cards, championsInPlay for champions, and always the
  /// cardsPlayedThisTurn history) so end-of-turn cleanup does not also discard
  /// it, then moves it to [removedFromGame]. A no-op if [source] is null.
  void _selfBanish(PlayerState player, CardModel? source) {
    if (source == null) return;
    final wasChampion =
        player.championsInPlay.any((c) => identical(c, source));
    player.playedThisTurn.removeWhere((c) => identical(c, source));
    player.championsInPlay.removeWhere((c) => identical(c, source));
    player.cardsPlayedThisTurn.removeWhere((c) => identical(c, source));
    // A self-banishing Destiny (e.g. stolen_future's "Banish this" activated
    // ability) lives in claimedDestinies, NOT the play zones above — so it must
    // be removed from there too, else it ends up in BOTH claimedDestinies and
    // removedFromGame (card duplication). Also drop its per-turn exhaustion mark.
    player.claimedDestinies.removeWhere((c) => identical(c, source));
    player.exhaustedDestinies.remove(source.id);
    // If a champion self-banishes, dispose any cards tucked under it and drop
    // its self-scoped modifiers — otherwise the under-cards orphan in the map
    // and the modifier dangles. Mirrors every other champion-removal path
    // (attack/destroy/eliminate). A recruitUnderCardsOnDeath champion
    // (carmine_eclipse) routes its under-cards to the owner's salvage instead of
    // discard.
    if (wasChampion) _disposeUnderCardsOnDeath(player, source);
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
    _disposeUnderCardsOnDeath(target, champion);
    return true;
  }

  // -------------------------------------------------------------------------
  // Carmine Eclipse — on-death under-card salvage (deferred, may be OFF-TURN)
  // -------------------------------------------------------------------------

  /// carmine_eclipse: after a [CardModel.recruitUnderCardsOnDeath] champion is
  /// destroyed, its OWNER may PAY each salvageable under-card's gem cost to
  /// recruit it (owner ruling §B5: PAY GEMS, not free). Moves [cardId] from the
  /// owner's [pendingUnderCardRecruit] bucket to their DISCARD pile, charging
  /// `card.cost` gems.
  ///
  /// This is authorized for the OWNER ([playerId]) — NOT necessarily the current
  /// player, because Carmine can be destroyed on an opponent's turn (the
  /// protocol layer will off-turn-authorize this later). It therefore does NOT
  /// gate on [_currentPlayerCanAct]; it only validates the salvage is legal.
  ///
  /// Returns false (no state change) if [playerId] has no pending salvage, the
  /// card is not pending for them, or they cannot afford its cost.
  bool recruitUnderCard(String playerId, String cardId) {
    final player = players.where((p) => p.id == playerId).firstOrNull;
    if (player == null || player.isEliminated) return false;

    final pending = pendingUnderCardRecruit[playerId];
    if (pending == null) return false;

    final index = pending.indexWhere((c) => c.id == cardId);
    if (index == -1) return false;

    final card = pending[index];
    if (player.gemPool < card.cost) return false;

    player.gemPool -= card.cost;
    pending.removeAt(index);
    player.discardPile.add(card);
    if (pending.isEmpty) pendingUnderCardRecruit.remove(playerId);
    _log('salvaged ${card.name} for ${card.cost} gems',
        playerId: playerId, cardId: card.id);
    return true;
  }

  /// carmine_eclipse: finish [playerId]'s under-card salvage — BANISH every
  /// remaining pending card (→ [removedFromGame], "banish the rest") and clear
  /// their [pendingUnderCardRecruit] bucket. Like [recruitUnderCard] this is an
  /// OWNER action that may run OFF-TURN, so it does NOT gate on
  /// [_currentPlayerCanAct]. Returns false (no state change) if [playerId] had no
  /// pending salvage.
  bool finishUnderCardSalvage(String playerId) {
    final pending = pendingUnderCardRecruit.remove(playerId);
    if (pending == null) return false;
    removedFromGame.addAll(pending);
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

    // aedifex: cost reduction applies to non-free recruits (min 1 gem).
    final price = free ? 0 : _discountedCost(card, player);
    if (player.gemPool < price) return false;

    player.gemPool -= price;
    centerRow.removeAt(index);

    // maglev_tunnels: a recruitToTopOfDeck static modifier matching this card
    // overrides the default discard destination, routing it to the top of the
    // deck. An explicit toHand / toTopOfDeck on the effect still takes priority.
    final modifierToTop = !toHand && _recruitsToTopOfDeck(card, player);

    if (toHand) {
      player.hand.add(card);
    } else if (toTopOfDeck) {
      // _drawCards draws via removeLast(), so the TOP of the deck (next draw) is
      // the END of the drawPile list. Append so this card is drawn next.
      player.drawPile.add(card);
    } else if (_applyPendingRecruitRedirect(player, card)) {
      // numeri_drones / anomaly_cleric: a pending "next recruit" redirect placed
      // this card directly into play or into hand (and consumed itself). A
      // pending redirect takes precedence over the maglev top-of-deck modifier.
    } else if (_recruitsToHand(card, player)) {
      // breaker / nexus_datic_hunter: on-recruit "put into hand" trigger.
      player.hand.add(card);
    } else if (modifierToTop) {
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
    final gem0 = player.gemPool,
        power0 = player.powerPool,
        mastery0 = player.mastery,
        health0 = player.health;
    _resolvePlayOrMastery(card, player);
    _checkAllyAbility(card, player);

    // Per warp rules: the card is removed from the game after it resolves. Move
    // it out of playedThisTurn (so end-of-turn cleanup does not send it to
    // discard) and into fastPlayedThisTurn, where it STAYS VISIBLE (greyed) in
    // the play area for the rest of the turn; cleanupTurn() moves it to
    // removedFromGame at end of turn. NOTE: it deliberately STAYS in
    // cardsPlayedThisTurn — the ally was genuinely played this turn, so later
    // cards' play-history scaling/conditions (perAllyPlayedThisTurn, etc.)
    // should still count it even though the physical card will leave the game.
    player.playedThisTurn.removeWhere((c) => identical(c, card));
    // Carmine-tuck (mandatory) vs. plain fast-play disposition (from where
    // swyft's optional recruit or end-of-turn removal can later act).
    _disposeFastPlayedCard(player, card);

    _refillCenterRow();
    _log('warped ${card.name}',
        playerId: player.id,
        cardId: card.id,
        grants: _grantsSince(player, gem0, power0, mastery0, health0));
    return true;
  }

  /// PLAYER-INITIATED mercenary fast-play: PAY a center-row Mercenary's gem cost,
  /// play it immediately from the row (its effects resolve this turn), then
  /// remove it from the game. This is the Mercenary "recruit OR fast-play"
  /// choice — the alternative to [buyCard] (which sends the card to the buyer's
  /// discard to be played on a later turn). Distinct from [fastPlayFromCenter],
  /// which is the FREE warp effect triggered BY another card (no cost paid).
  ///
  /// Only Mercenaries may be fast-played this way; champions and regular cards
  /// must be recruited normally. The cost honours the buyer's cost-reduction
  /// static modifiers (same as [buyCard]). Returns false (no state change) if the
  /// card isn't a payable center-row Mercenary on the current player's turn.
  bool payAndFastPlayFromCenter(String cardId) {
    if (!_currentPlayerCanAct) return false;
    final player = currentPlayer;

    final index = centerRow.indexWhere((c) => c.id == cardId);
    if (index == -1) return false;

    final card = centerRow[index];
    // Only Mercenaries can be paid-fast-played from the market.
    if (card.cardType != CardType.mercenary) return false;

    final price = _discountedCost(card, player);
    if (player.gemPool < price) return false;

    player.gemPool -= price;
    centerRow.removeAt(index);

    // Play immediately (mirrors the warp path's zone bookkeeping). Snapshot
    // AFTER the cost was paid so the gem delta shows only what the card grants.
    player.playedThisTurn.add(card);
    player.cardsPlayedThisTurn.add(card);
    final gem0 = player.gemPool,
        power0 = player.powerPool,
        mastery0 = player.mastery,
        health0 = player.health;
    _resolvePlayOrMastery(card, player);
    _checkAllyAbility(card, player);

    // Mercenaries are removed from the game after use — move out of
    // playedThisTurn (so end-of-turn cleanup doesn't discard it) and into
    // fastPlayedThisTurn, where it STAYS VISIBLE (greyed) in the play area for
    // the rest of the turn; cleanupTurn() removes it from the game at end of
    // turn. Keep it in cardsPlayedThisTurn for this turn's play-history scaling.
    player.playedThisTurn.removeWhere((c) => identical(c, card));
    // Carmine-tuck (mandatory) vs. plain fast-play disposition (from where
    // swyft's optional recruit or end-of-turn removal can later act).
    _disposeFastPlayedCard(player, card);

    _refillCenterRow();
    _log('fast-played ${card.name} for $price gems',
        playerId: player.id,
        cardId: card.id,
        grants: _grantsSince(player, gem0, power0, mastery0, health0));
    return true;
  }

  /// swyft: "if you are Rez, you may recruit any card you fast-play (to
  /// discard)". Moves the fast-played [cardId] out of the current player's
  /// `fastPlayedThisTurn` (where it would otherwise leave the game at end of
  /// turn) into their DISCARD pile, so it can be drawn and played again later.
  ///
  /// GATE (owner ruling §B5): the player must (a) control a champion in play that
  /// sources an active [StaticModifierKind.fastPlayRecruit] modifier (swyft) AND
  /// (b) have `character == Character.rez`. Carmine's mandatory
  /// [StaticModifierKind.tuckFastPlaysUnder] takes precedence — a tucked card
  /// never enters `fastPlayedThisTurn`, so it is not reachable here.
  ///
  /// Returns false (no state change) if the gate fails, the player can't act, or
  /// [cardId] is not currently in `fastPlayedThisTurn`.
  bool recruitFastPlayedCard(String cardId) {
    if (!_currentPlayerCanAct) return false;
    final player = currentPlayer;

    final hasSwyftAura = player.staticModifiers.any((m) =>
        m.kind == StaticModifierKind.fastPlayRecruit &&
        m.sourceChampionId != null &&
        player.championsInPlay.any((c) => c.id == m.sourceChampionId));
    if (!hasSwyftAura) return false;
    if (player.character != Character.rez) return false;

    final index = player.fastPlayedThisTurn.indexWhere((c) => c.id == cardId);
    if (index == -1) return false;

    final card = player.fastPlayedThisTurn.removeAt(index);
    player.discardPile.add(card);
    _log('recruited fast-played ${card.name}',
        playerId: player.id, cardId: card.id);
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
      case ScryDisposition.toHandLosePowerEqualToCost:
        // Mandatory: the revealed card always goes to hand and the player loses
        // power equal to its cost (floored at 0). `keep` is ignored.
        final card = player.drawPile.removeAt(index);
        player.hand.add(card);
        player.powerPool -= card.cost;
        if (player.powerPool < 0) player.powerPool = 0;
        return true;
      case ScryDisposition.toHandLoseHealthEqualToCost:
        // Mandatory: the revealed card always goes to hand and the controller
        // loses HEALTH equal to its cost (ignores Guard). `keep` is ignored.
        final card = player.drawPile.removeAt(index);
        player.hand.add(card);
        if (card.cost > 0) {
          player.takeDamage(card.cost);
          if (player.isEliminated) _cleanupEliminatedPlayer(player);
          _checkGameOver();
        }
        return true;
      case ScryDisposition.toHandOpponentsLoseHealthEqualToCost:
        // Mandatory: the revealed card always goes to hand and ALL OPPONENTS
        // lose HEALTH equal to its cost (the Mastery-20 variant; ignores Guard).
        final card = player.drawPile.removeAt(index);
        player.hand.add(card);
        if (card.cost > 0) _applyOpponentHealthLoss(player, card.cost);
        return true;
    }
  }

  /// Destroy every enemy champion (the [DestroyChampionEffect.all] variant).
  /// Each destroyed champion goes to its owner's discard pile. No power cost.
  void _destroyAllEnemyChampions(PlayerState source) {
    for (final player in players) {
      if (player.id == source.id) continue;
      if (player.championsInPlay.isEmpty) continue;
      for (final champion in player.championsInPlay) {
        // Route through the shared death disposition so a Carmine-style
        // recruitUnderCardsOnDeath champion still offers its salvage even when
        // wiped by a destroy-all effect (not just single-target destroy).
        _disposeUnderCardsOnDeath(player, champion);
      }
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

  /// Return a card from the current player's discard pile to the TOP of their
  /// draw pile (it becomes their next draw), fulfilling a
  /// [ReturnFromDiscardToDeckTopEffect] after target selection. Mirrors
  /// [returnFromDiscard] but the destination is the deck top, not the hand. The
  /// top of the draw pile is the END of the list (drawn via removeLast), so the
  /// card is appended. Used by dash. Returns true if returned.
  bool returnFromDiscardToDeckTop(
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
    player.drawPile.add(card);
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
        case OpponentLosesMasteryEffect():
          _applyOpponentMasteryLoss(player, effect.amount);
        case AllPlayersLoseHealthEffect():
          _applyAllPlayersHealthLoss(player, effect.amount);
        case ChooseOneEffect():
          if (effect.choices.isEmpty) break;
          // Resolve `pick` DISTINCT choice groups. For pick==1 this is the
          // classic single selection at choiceIndex. For pick>1 ("choose N
          // distinct"), start at choiceIndex and take the next `pick` distinct
          // groups, wrapping — deterministic for AI/tests; the UI may later
          // pass an explicit selection.
          final n = effect.pick.clamp(1, effect.choices.length);
          final start = choiceIndex.clamp(0, effect.choices.length - 1);
          for (var k = 0; k < n; k++) {
            final idx = (start + k) % effect.choices.length;
            _resolveEffects(effect.choices[idx], player, sourceCard: sourceCard);
          }
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
          if (effect.self) {
            // Self-return (the_dispossessed): return a discarded copy of the
            // SOURCE card (matched by name) to hand, inline — no selection.
            _returnSelfFromDiscard(player, sourceCard);
          } else if (effect.all) {
            // Return ALL matching cards (the_world_piercer Mastery-20), inline.
            _returnAllFromDiscard(player, effect.filter, effect.faction);
          }
          // Otherwise requires card selection — the player calls
          // returnFromDiscard() separately after this effect.
          break;
        case ReturnFromDiscardToDeckTopEffect():
          // Requires card selection — the player should call
          // returnFromDiscardToDeckTop() separately after this effect (dash).
          break;
        case MillEffect():
          _millTopCards(player, effect.count);
        case RecruitToHandEffect():
          // On-RECRUIT trigger, not a play effect — a no-op here. buyCard /
          // recruitFromCenter consult it to route the recruited card to hand.
          break;
        case ReturnSelfWhenChampionPlayedEffect():
          // Passive while-in-discard trigger (praetorian_01), not a play effect —
          // a no-op here. playCard scans the discard pile for it after a champion
          // is played and returns the carrier to the owner's hand.
          break;
        case AcquireCostReductionPerChampionEffect():
          // SELF acquire-cost reduction (axia), not a play effect — a no-op here.
          // _discountedCost scans the card's playEffects for it to discount THIS
          // card's center-row price per matching champion the buyer controls.
          break;
        case BonusDrawNextTurnOnUnblockedDamageEffect():
          // Next-turn draw bonus marker (the_heart_of_nothing), not resolved at
          // play time — a no-op here. endTurn scans cardsPlayedThisTurn for it and
          // arms PlayerState.nextTurnDrawBonus when the unblocked-damage bar is met.
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
        case RedirectNextRecruitEffect():
          // Turn-scoped, single-use: install the redirect so the NEXT matching
          // card this player recruits this turn (via buyCard / recruitFromCenter)
          // goes to the redirected destination instead of the discard pile.
          // Consumed by the recruit, or cleared at end of turn by
          // resetTurnResources. numeri_drones (Exhaust, into play) can only fire
          // once per turn (it's an Exhaust ability), and re-installing simply
          // overwrites an unused redirect — never stacks.
          player.pendingRecruitRedirect = effect;
        case ScryEffect():
          // The two "toHand*LoseHealthEqualToCost" dispositions are MANDATORY
          // (no keep/discard choice) and resolve INLINE here — this is what
          // makes oblivion_gatekeeper's Exhaust (and its Mastery-20 replacement
          // via masteryBonusEffects) actually do something. The choice-based
          // dispositions (drawOrDiscard/drawOrBanish/toHand/lose-POWER) still
          // defer to the scryReveal()/scryResolve() UI flow (a no-op here).
          switch (effect.disposition) {
            case ScryDisposition.toHandLoseHealthEqualToCost:
            case ScryDisposition.toHandOpponentsLoseHealthEqualToCost:
              _resolveScryToHandLoseHealth(player, effect.disposition);
            case ScryDisposition.drawOrDiscard:
            case ScryDisposition.drawOrBanish:
            case ScryDisposition.toHand:
            case ScryDisposition.toHandLosePowerEqualToCost:
              break;
          }
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
        case IgnoreGuardThisTurnEffect():
          // Turn-scoped: this player's direct attacks are not blocked by enemy
          // Guard champions this turn (see attackPlayer). Cleared by
          // resetTurnResources. rue_bo_vai_the_transcendent Mastery-10.
          player.ignoresGuardThisTurn = true;
        case DoublePowerEffect():
          // Immediate: multiply the current power pool by two (a no-op at 0).
          // Resolves AFTER any flat power gains earlier in the same list.
          player.powerPool *= 2;
        case CopyAllPlayedCardsEffect():
          // Immediate: re-resolve the play effects of EVERY matching card played
          // this turn (general_decurion Mastery-20). Excludes the in-flight
          // source (the champion) and honours the re-entrancy / shard guards.
          _copyAllPlayedCards(
            player,
            filter: effect.filter,
            faction: effect.faction,
            excludeSource: sourceCard,
          );
        case AddStaticModifierEffect():
          // Immediate: append the persistent modifier to the player's list. It
          // stays for the rest of the game (wave-5a lifetime). Consulted by
          // attackChampion / attackPlayer / buyCard / recruitFromCenter.
          //
          // When the source is a CHAMPION, its playEffects re-resolve every turn
          // it is activated (activateChampion) — so we MUST stamp the modifier
          // with the champion's id and add it only ONCE, else it accumulates a
          // duplicate buff each turn (unbounded growth). Regular/mercenary
          // sources resolve once per play, so they need no dedupe but are still
          // stamped when a source card is known. A shieldPerCardUnder modifier
          // is additionally SELF-scoped so _effectiveHealth only buffs that
          // champion (carmine_eclipse).
          final stamped = effect.modifier.sourceChampionId == null &&
                  sourceCard != null
              ? StaticModifier(
                  kind: effect.modifier.kind,
                  amount: effect.modifier.amount,
                  faction: effect.modifier.faction,
                  cardType: effect.modifier.cardType,
                  sourceChampionId: sourceCard.id,
                  masteryThreshold: effect.modifier.masteryThreshold,
                  masteryAmount: effect.modifier.masteryAmount,
                  cannotBeAttackedScope: effect.modifier.cannotBeAttackedScope,
                  cannotBeAttackedCondition:
                      effect.modifier.cannotBeAttackedCondition,
                  conditionCardName: effect.modifier.conditionCardName,
                )
              : effect.modifier;
          final alreadyApplied = stamped.sourceChampionId != null &&
              player.staticModifiers.any((m) =>
                  m.sourceChampionId == stamped.sourceChampionId &&
                  m.kind == stamped.kind &&
                  m.amount == stamped.amount &&
                  m.faction == stamped.faction &&
                  m.cardType == stamped.cardType &&
                  m.masteryThreshold == stamped.masteryThreshold &&
                  m.masteryAmount == stamped.masteryAmount &&
                  m.cannotBeAttackedScope == stamped.cannotBeAttackedScope &&
                  m.cannotBeAttackedCondition ==
                      stamped.cannotBeAttackedCondition &&
                  m.conditionCardName == stamped.conditionCardName);
          if (!alreadyApplied) {
            player.staticModifiers.add(stamped);
          }
        case TuckUnderChampionEffect():
          // hand source: deferred-selection — the player calls
          // tuckUnderChampion() after picking a champion + hand card.
          // centerDeck source: immediate — tuck the top center-deck card under
          // the in-flight champion (gene_scavs ambush).
          if (effect.source == TuckSource.centerDeck && sourceCard != null) {
            _tuckTopOfCenterDeck(player, sourceCard.id);
          }
        case CopyUnderCardsEffect():
          // Re-resolve every under-card's effects for the in-flight champion
          // (paradigm_the_archivist). When resolved via an activated ability the
          // sourceCard IS the champion; otherwise the player calls
          // copyUnderCards() with the champion id.
          if (sourceCard != null &&
              player.championsInPlay.any((c) => c.id == sourceCard.id)) {
            copyUnderCards(sourceCard.id);
          }
        case OpponentDrawsEffect():
          _eachOtherPlayerDraws(player, effect.count);
        case OpponentDiscardsEffect():
          _eachOtherPlayerDiscards(player, effect.count);
        case CopyPlayedCardEffect():
          // Requires selecting which previously-played card to copy — the player
          // should call copyPlayedCard() separately after this effect.
          break;
        case RevealAndCopyTopOfDecksEffect():
          // duplication_fabricator: reveal the top card of EVERY player's deck
          // INLINE (peek-only; populates pendingDeckReveal), then DEFER the copy
          // choice — the player calls copyRevealedCard() with the chosen ally.
          revealTopOfAllDecks();
          break;
        case CenterDeckScryEffect():
          // Requires a center-deck peek + per-card disposition — the player
          // should call centerDeckScryReveal() then centerDeckScryResolve()
          // separately after this effect.
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
    // The Infinity Shard does NOT grant mastery — it only reads your current
    // mastery to scale its power (and to check the instant win at 30+).
    final m = player.mastery;

    // Instant win when played at mastery 30 or higher.
    if (m >= 30) {
      _gameOver = true;
      winnerId = player.id;
      winType = 'mastery';
      return;
    }

    // Power scales with current mastery tier
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

    final extraCard = _extraFactions(card, player);

    // Check playedThisTurn for same-faction cards (excluding the card itself)
    for (final other in player.playedThisTurn) {
      if (other.id == card.id) continue;
      if (_factionsMatch(cardFaction, card.countsAsAllFactions,
          other.faction, other.countsAsAllFactions,
          aliasPlayer: player,
          extraA: extraCard,
          extraB: _extraFactions(other, player))) {
        return true;
      }
    }

    // Check championsInPlay for same-faction cards (excluding the card itself)
    for (final other in player.championsInPlay) {
      if (other.id == card.id) continue;
      if (_factionsMatch(cardFaction, card.countsAsAllFactions,
          other.faction, other.countsAsAllFactions,
          aliasPlayer: player,
          extraA: extraCard,
          extraB: _extraFactions(other, player))) {
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
    Set<Faction> extraA = const {},
    Set<Faction> extraB = const {},
  }) {
    // The (pre-alias) set of real factions each side counts as: its own faction
    // (when non-none) plus any mastery-gated multi-faction extras (querry_monk).
    // countsAsAllFactions is handled separately below on the raw all-flags.
    final setA = <Faction>{if (factionA != Faction.none) factionA, ...extraA};
    final setB = <Faction>{if (factionB != Faction.none) factionB, ...extraB};

    // A side has NO faction identity if it is factionless, not all-factions,
    // and carries no extra factions — such a side never matches (mirrors the
    // original none-guard). Empty extras is the common case (const {}).
    if (setA.isEmpty && !allFactionsA) return false;
    if (setB.isEmpty && !allFactionsB) return false;

    // If either counts as ALL factions, it matches any side with an identity
    // (the other side already passed the none-guard above).
    if (allFactionsA || allFactionsB) return true;

    // Fast path: direct intersection (covers the common identical-faction case
    // with zero further work).
    if (setA.any(setB.contains)) return true;

    // Alias-aware path. A `from -> to` alias means a `from` card ALSO counts as
    // `to` (it keeps its own faction too). The two sides match when their
    // alias-expanded faction sets intersect. With no alias player / no aliases
    // this is skipped and behaviour matches the original.
    if (aliasPlayer == null || aliasPlayer.factionAliasesThisTurn.isEmpty) {
      return false;
    }
    final expA = {for (final f in setA) ..._aliasExpand(f, aliasPlayer)};
    final expB = {for (final f in setB) ..._aliasExpand(f, aliasPlayer)};
    return expA.any(expB.contains);
  }

  /// The EXTRA factions [card] counts as for [player] beyond its own
  /// [CardModel.faction]: its mastery-gated multi-faction set
  /// ([CardModel.countsAsFactions]), active only when the card's
  /// [CardModel.countsAsFactionsMasteryThreshold] (if any) is met by [player]'s
  /// current mastery. Empty (a shared const) for the vast majority of cards, so
  /// the common faction-matching path allocates nothing. querry_monk Mastery-10.
  Set<Faction> _extraFactions(CardModel card, PlayerState player) {
    if (card.countsAsFactions.isEmpty) return const {};
    final threshold = card.countsAsFactionsMasteryThreshold;
    if (threshold != null && player.mastery < threshold) return const {};
    return card.countsAsFactions.toSet();
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
      // and do NOT additively check mastery again. Forward choiceIndex so a
      // ChooseOneEffect (incl. pick>1) in the bonus honours the player's
      // selection (red_fortune Mastery-15 "choose two").
      _resolveEffects(
        card.masteryBonus,
        player,
        choiceIndex: choiceIndex,
        sourceCard: card,
      );
      return;
    }

    // Default / additive path — unchanged from prior behavior.
    _resolveEffects(
      card.playEffects,
      player,
      choiceIndex: choiceIndex,
      sourceCard: card,
    );
    _checkMasteryBonus(card, player, choiceIndex: choiceIndex);
  }

  void _checkMasteryBonus(CardModel card, PlayerState player,
      {int choiceIndex = 0}) {
    if (card.masteryThreshold == null) return;
    if (card.masteryBonus.isEmpty) return;
    if (player.mastery >= card.masteryThreshold!) {
      _resolveEffects(card.masteryBonus, player,
          choiceIndex: choiceIndex, sourceCard: card);
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

  /// Apply [amount] of MASTERY loss to every living opponent of [attacker]
  /// (floored at 0). The mastery analogue of [_applyOpponentHealthLoss]: like
  /// the direct health-loss effects it hits ALL opponents (per the multiplayer
  /// convention) and cannot be prevented by shield/guard. Used by
  /// [OpponentLosesMasteryEffect] (venator_of_the_wastes, skry_77). Losing
  /// mastery never eliminates a player, so no cleanup/game-over check is needed.
  void _applyOpponentMasteryLoss(PlayerState attacker, int amount) {
    if (amount <= 0) return;
    for (final player in players) {
      if (player.id != attacker.id && !player.isEliminated) {
        player.loseMastery(amount);
      }
    }
  }

  /// Mill the top [count] cards of [player]'s own draw pile straight to their
  /// discard pile (legion_carrier). Reshuffles the discard into the draw pile if
  /// the draw pile empties mid-mill (mirrors [_drawCards]); mills as many as are
  /// available. Top of the draw pile is the END of the list (removeLast).
  void _millTopCards(PlayerState player, int count) {
    for (int i = 0; i < count; i++) {
      if (player.drawPile.isEmpty && player.discardPile.isNotEmpty) {
        player.drawPile.addAll(player.discardPile);
        player.discardPile.clear();
        player.drawPile.shuffle(_random);
      }
      if (player.drawPile.isEmpty) break;
      player.discardPile.add(player.drawPile.removeLast());
    }
  }

  /// Return a discarded copy of [sourceCard] (matched by NAME — market copies
  /// share a name but get per-copy ids) from [player]'s discard pile to their
  /// hand. Inline self-return for the_dispossessed. Returns the FIRST matching
  /// copy; a no-op if none is in discard.
  void _returnSelfFromDiscard(PlayerState player, CardModel? sourceCard) {
    if (sourceCard == null) return;
    final index =
        player.discardPile.indexWhere((c) => c.name == sourceCard.name);
    if (index == -1) return;
    player.hand.add(player.discardPile.removeAt(index));
  }

  /// Return ALL cards in [player]'s discard pile matching [filter]/[faction] to
  /// their hand at once (the_world_piercer Mastery-20). Inline — no selection.
  void _returnAllFromDiscard(
    PlayerState player,
    ReturnFilter filter,
    Faction? faction,
  ) {
    final matched = player.discardPile
        .where((c) => _matchesReturnFilter(c, filter, faction))
        .toList();
    for (final card in matched) {
      player.discardPile.remove(card);
      player.hand.add(card);
    }
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

  /// Resolve the mandatory "reveal the top of your own deck, put it into your
  /// hand, lose HEALTH equal to its gem cost" family (oblivion_gatekeeper).
  /// [disposition] selects WHO loses the health:
  ///  - [ScryDisposition.toHandLoseHealthEqualToCost]: the controller ([player]).
  ///  - [ScryDisposition.toHandOpponentsLoseHealthEqualToCost]: all opponents
  ///    (the Mastery-20 replacement — "all opponents lose health instead of
  ///    you").
  /// The revealed card ALWAYS goes to hand. Health loss is a raw subtraction and
  /// "cannot be prevented by Guard" (guard only gates power-based attacks, which
  /// this is not). A no-op with an empty draw pile.
  void _resolveScryToHandLoseHealth(
    PlayerState player,
    ScryDisposition disposition,
  ) {
    if (player.drawPile.isEmpty) return;
    // Top of the draw pile is the END of the list (mirrors scryReveal ordering).
    final card = player.drawPile.removeLast();
    player.hand.add(card);
    final loss = card.cost;
    if (loss <= 0) return;
    switch (disposition) {
      case ScryDisposition.toHandLoseHealthEqualToCost:
        player.takeDamage(loss);
        if (player.isEliminated) _cleanupEliminatedPlayer(player);
        _checkGameOver();
      case ScryDisposition.toHandOpponentsLoseHealthEqualToCost:
        _applyOpponentHealthLoss(player, loss);
      case ScryDisposition.drawOrDiscard:
      case ScryDisposition.drawOrBanish:
      case ScryDisposition.toHand:
      case ScryDisposition.toHandLosePowerEqualToCost:
        break;
    }
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
                aliasPlayer: player, extraB: _extraFactions(c, player)))
            .length;
      case ScalingCondition.perFactionChampionControlled:
        final f = filterFaction ?? sourceCard?.faction;
        if (f == null) return 0;
        return player.championsInPlay
            .where((c) => _factionsMatch(
                f, false, c.faction, c.countsAsAllFactions,
                aliasPlayer: player, extraB: _extraFactions(c, player)))
            .length;
      case ScalingCondition.perFactionCardPlayedThisTurn:
        final f = filterFaction ?? sourceCard?.faction;
        if (f == null) return 0;
        return _countPlayedThisTurn(
          player,
          sourceCard,
          (c) => _factionsMatch(f, false, c.faction, c.countsAsAllFactions,
              aliasPlayer: player, extraB: _extraFactions(c, player)),
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
                  aliasPlayer: player, extraB: _extraFactions(c, player)),
        );
      case ScalingCondition.perHealthGainedThisTurn:
        // entropic_talons: scale by the HEALTH gained this turn (faction filter
        // ignored — health gain is not faction-scoped).
        return player.healthGainedThisTurn;
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
  /// Whether [card] has at least one [ConditionalEffect] whose [GameCondition]
  /// currently holds for the CURRENT player (the active perspective). Used by
  /// the UI to paint a "bonus active now" glow on hand / market cards. Scans the
  /// card's `playEffects` for any [ConditionalEffect] (the only place a per-card
  /// board-state bonus lives) and evaluates its condition against live state via
  /// the same [_evaluateGameCondition] the engine uses at play time, so the glow
  /// and the actual bonus agree. Faction-less conditions resolve against the
  /// card's own faction (the standard source-card rule). Returns false when the
  /// card carries no conditional bonus or none of its conditions hold.
  bool conditionsSatisfied(CardModel card) {
    final player = currentPlayer;
    for (final effect in card.playEffects) {
      if (effect is ConditionalEffect &&
          _evaluateGameCondition(effect.condition, player, card)) {
        return true;
      }
    }
    return false;
  }

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
              card.countsAsAllFactions,
              aliasPlayer: player, extraB: _extraFactions(card, player)),
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
                  card.countsAsAllFactions,
                  aliasPlayer: player, extraB: _extraFactions(card, player)),
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
                    card.countsAsAllFactions,
                    aliasPlayer: player, extraB: _extraFactions(card, player))) {
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
                aliasPlayer: player, extraB: _extraFactions(card, player)))
            .length;
        return count >= c.threshold;
      case GameConditionKind.masteryAtLeast:
        return player.mastery >= c.threshold;
      case GameConditionKind.healthAtLeast:
        return player.health >= c.threshold;
      case GameConditionKind.sameFactionCountPlayed:
        final f = c.faction ?? source?.faction;
        if (f == null || f == Faction.none) return false;
        // Count ALL same-faction cards played this turn INCLUDING the source.
        final count = player.cardsPlayedThisTurn
            .where((card) => _factionsMatch(
                f, false, card.faction, card.countsAsAllFactions,
                aliasPlayer: player, extraB: _extraFactions(card, player)))
            .length;
        return count >= c.threshold;
      case GameConditionKind.isCharacter:
        if (c.character == null) return false;
        return player.character == c.character;
      case GameConditionKind.unblockedDamageAtLeast:
        return player.unblockedDamageThisTurn >= c.threshold;
      case GameConditionKind.factionAllyPlayedOrInHand:
        final f = c.faction ?? source?.faction;
        if (f == null || f == Faction.none) return false;
        bool matches(CardModel card) => _factionsMatch(
            f, false, card.faction, card.countsAsAllFactions,
            aliasPlayer: player, extraB: _extraFactions(card, player));
        // "played another <faction> ally this turn" (excludes the source via
        // _countPlayedThisTurn) ...
        final played = _countPlayedThisTurn(player, source, matches);
        if (played >= c.threshold) return true;
        // ... OR a matching card is in hand to reveal (always optional/free).
        return player.hand.any(matches);
      case GameConditionKind.factionCardInDiscard:
        final f = c.faction ?? source?.faction;
        if (f == null || f == Faction.none) return false;
        return player.discardPile.any((card) => _factionsMatch(
            f, false, card.faction, card.countsAsAllFactions,
            aliasPlayer: player, extraB: _extraFactions(card, player)));
      case GameConditionKind.oddCostCardsPlayed:
        final count = _countPlayedThisTurn(
            player, source, (card) => card.cost.isOdd);
        return count >= c.threshold;
      case GameConditionKind.evenCostCardsPlayed:
        final count = _countPlayedThisTurn(
            player, source, (card) => card.cost.isEven);
        return count >= c.threshold;
      case GameConditionKind.sameNamePlayedThisTurn:
        // Count OTHER cards with the same NAME as the source played this turn
        // (the source itself is excluded by _countPlayedThisTurn). cinder_scars.
        if (source == null) return false;
        final count = _countPlayedThisTurn(
            player, source, (card) => card.name == source.name);
        return count >= c.threshold;
      case GameConditionKind.highestMasteryAmongPlayers:
        // Strictly greater than every other non-eliminated player's mastery.
        for (final other in players) {
          if (identical(other, player)) continue;
          if (other.isEliminated) continue;
          if (other.mastery >= player.mastery) return false;
        }
        return true;
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
            extraA: _extraFactions(sourceCard, player),
            extraB: _extraFactions(played, player),
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
    // Authoritative path: an injected market deck carries each unique card with
    // its REAL printed copy count. Expand one concrete instance per copy.
    final injected = _marketDeck;
    if (injected != null) {
      final deck = <CardModel>[];
      for (final entry in injected) {
        for (int copy = 0; copy < entry.copies; copy++) {
          deck.add(_instanceOf(entry.template, copy));
        }
      }
      return deck;
    }

    // Legacy path (no injected deck): the original cost-bucket approximation
    // over the hardcoded catalog. Kept so existing tests / the legacy demo are
    // unchanged.
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
        deck.add(_instanceOf(template, copy));
      }
    }
    return deck;
  }

  /// A concrete market-card instance for [copy], preserving every gameplay field
  /// of [template] but with a per-copy unique id (`<id>_<copy>`).
  CardModel _instanceOf(CardModel template, int copy) {
    // copyWith carries EVERY gameplay field (shieldEqualsMastery, countsAsFactions,
    // etc.) — a manual field list here previously dropped newly-added fields on
    // recruited market copies.
    return template.copyWith(id: '${template.id}_$copy');
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
    if (_gameOver) {
      if (winnerId != null) {
        final w = players.firstWhere((p) => p.id == winnerId);
        _log('${w.id} wins!');
      }
      return;
    }

    _log('— Turn $turnNumber: ${currentPlayer.id} —');
    startTurn();
  }

  void _checkGameOver() {
    final alive = players.where((p) => !p.isEliminated).toList();
    if (alive.length <= 1) {
      _gameOver = true;
      if (alive.length == 1) {
        winnerId = alive.first.id;
        // This path is reached by reducing opponents to 0 health. The mastery
        // (Infinity Shard) win sets winType earlier and returns before any
        // elimination check, so only set 'elimination' if not already a mastery
        // win.
        winType ??= 'elimination';
      } else {
        // alive.length == 0 — every remaining player was eliminated at once
        // (e.g. an AllPlayersLoseHealthEffect like bound_for_life that drops the
        // last 2+ players simultaneously). The rules don't name a winner for a
        // mutual knockout, so this is an explicit DRAW: no winnerId, a distinct
        // terminal winType. (Found by the self-play oracle, tool/selfplay.)
        winType ??= 'draw';
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

    // Fast-played / warped cards were kept visible this turn; they too leave.
    removedFromGame.addAll(player.fastPlayedThisTurn);
    player.fastPlayedThisTurn.clear();

    removedFromGame.addAll(player.championsInPlay);
    player.championsInPlay.clear();

    // Cards tucked under any of this player's champions also leave the game.
    for (final under in player.cardsUnderChampion.values) {
      removedFromGame.addAll(under);
    }
    player.cardsUnderChampion.clear();

    // A Carmine-style salvage bucket already migrated out of cardsUnderChampion
    // (its champion died) still belongs to this player — an eliminated owner
    // gets no salvage, so banish any pending under-cards too (else the bucket
    // would orphan forever and a zombie eliminated seat could still salvage).
    final pending = pendingUnderCardRecruit.remove(player.id);
    if (pending != null) removedFromGame.addAll(pending);

    // Board-wide static modifiers leave with the player too. Champion-sourced
    // auras (e.g. zetta_the_encryptor's cannotBeAttacked) are keyed to a
    // champion that just left play above; the per-champion combat path
    // (_releaseUnderCards) drops them one champion at a time, but an all-at-once
    // elimination (attackPlayer / an AllPlayersLoseHealthEffect) never destroys
    // those champions individually — so clear the whole set here, else a stale
    // aura would outlive its source. An eliminated player holds no board state.
    player.staticModifiers.clear();
  }
}
