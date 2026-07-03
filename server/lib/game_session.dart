// A single in-progress game: wraps one authoritative GameService and the set of
// connected players. Applies actions and produces per-player redacted views.
//
// Transport-agnostic on purpose: the WebSocket layer (bin/server.dart) owns the
// sockets and calls into this. That keeps the session unit-testable without a
// network.

import 'package:shards_server/protocol.dart';
import 'package:shards_server/stats_capture.dart';
import 'package:shards_server/stats_store.dart';
import 'package:shards_server/views.dart';
import 'package:simple_card_game/data/database/game_state_codec.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/services/game_service.dart';

class GameSession {
  GameSession({
    required this.id,
    required this.game,
    required this.playerIds,
    StatsStore? stats,
  }) : stats = stats ?? StatsStore.disabled();

  /// Rebuild a session from a persisted snapshot: same as the default
  /// constructor plus a restored [stateVersion] so reconnecting clients keep
  /// monotonic versioning across a server restart. The per-turn undo stack is
  /// intentionally NOT persisted (it's same-turn, transient state), so a
  /// restored session starts with an empty undo history — a player can't undo
  /// across a restart, which is the safe behaviour.
  GameSession.restored({
    required this.id,
    required this.game,
    required this.playerIds,
    required int stateVersion,
    StatsStore? stats,
  })  : _stateVersion = stateVersion,
        stats = stats ?? StatsStore.disabled();

  final String id;

  /// Telemetry sink (player-stats + ML training data). Defaults to a DISABLED
  /// (no-op) store so a session constructed without one — every existing
  /// constructor call, all current tests — behaves EXACTLY as before. Telemetry
  /// failures inside the store never throw, so the game loop is never affected.
  final StatsStore stats;

  /// The authoritative engine. NOT final: a server-authoritative UNDO swaps it
  /// out wholesale by decoding a snapshot (`GameStateCodec.decode`), so this is
  /// reassigned in place. All read sites (`session.game.*`) keep working since
  /// it stays a public, readable field.
  GameService game;

  /// Stable LOBBY player ids in seat order (index aligns with game.players).
  /// The engine names its own seats `p0..pN` (PlayerState.id, which is final and
  /// cannot be renamed), so the session translates between a lobby player id and
  /// its engine seat id for both authorization and redaction.
  final List<String> playerIds;

  int _stateVersion = 0;
  int get stateVersion => _stateVersion;

  /// Per-turn UNDO history: full-fidelity snapshots captured BEFORE each accepted
  /// mutating action taken DURING the current player's turn. The stack is CLEARED
  /// when a turn ends (an accepted `endTurn`) so a player can never undo into a
  /// finished turn — neither their own previous turn nor an opponent's. The top
  /// of the stack is the state immediately before the most recent action.
  final List<Map<String, dynamic>> _undoStack = [];

  /// Whether the player seated as [lobbyPlayerId] could undo right now: it is
  /// their turn, the game is live, and there is at least one snapshot captured
  /// this turn. Surfaced to that player via redaction (`canUndo`).
  bool canUndoFor(String lobbyPlayerId) {
    if (_undoStack.isEmpty || game.isGameOver) return false;
    final seatId = _seatIdFor(lobbyPlayerId);
    return seatId != null && game.currentPlayer.id == seatId;
  }

  /// Engine seat id (`p0`..) for a lobby player id, or null if not seated.
  String? _seatIdFor(String lobbyPlayerId) {
    final seat = playerIds.indexOf(lobbyPlayerId);
    return seat == -1 ? null : game.players[seat].id;
  }

  /// Lobby player id for an engine seat id (`p0`..), or the seat id unchanged if
  /// it can't be mapped (and null for null). Used to denormalize an attack/
  /// destroy target on the outcome event into a stable lobby id.
  String? _lobbyIdForSeatId(String? seatId) {
    if (seatId == null) return null;
    final seat = game.players.indexWhere((p) => p.id == seatId);
    return (seat >= 0 && seat < playerIds.length) ? playerIds[seat] : seatId;
  }

  /// The LOBBY player id (username) of the winner, or null if there is no winner
  /// (game in progress, or a draw). Maps the engine's seat-id `winnerId` through
  /// the seat↔lobby-id table. Public so the lobby past-games summary and
  /// telemetry share one correct mapping (rather than each re-deriving it).
  String? get winnerLobbyId => _lobbyIdForSeatId(game.winnerId);

  /// Apply an action on behalf of [lobbyPlayerId]. On success the broadcast
  /// version bumps so clients can detect they need the new state.
  ActionResult apply(String lobbyPlayerId, Map<String, dynamic> action) {
    final seatId = _seatIdFor(lobbyPlayerId);
    if (seatId == null) return ActionResult.reject('not a player in this game');

    // UNDO is handled HERE (before delegating to applyAction) because it must
    // REPLACE the GameService, whereas applyAction only mutates a fixed engine.
    if (action['type'] == 'undo') {
      final result = _undo(seatId);
      if (result.accepted) _stateVersion++;
      return result;
    }

    // FORFEIT is also handled HERE, deliberately BEFORE the turn gate inside
    // applyAction: it is an operator "close out this game" control, so ANY
    // seated player may forfeit at any time (not only the current player). It
    // ends the game with no winner and a distinct 'forfeit' condition so it
    // round-trips as a finished game (not a bogus draw). See [_forfeit].
    if (action['type'] == 'forfeit') {
      final result = _forfeit(seatId);
      if (result.accepted) {
        _stateVersion++;
        // A finished game can't be undone into; clear the same-turn history.
        _undoStack.clear();
      }
      return result;
    }

    // Capture a pre-action snapshot for a mutating action so it can be undone.
    // `endTurn` is special: an accepted end-turn CLEARS the history instead of
    // pushing onto it (you cannot undo across a turn boundary).
    final isEndTurn = action['type'] == 'endTurn';
    final snapshot = isEndTurn ? null : GameStateCodec.encode(game);

    // TELEMETRY: snapshot the DECISION context BEFORE applying, from the actor's
    // OWN legal information set (their hand known; opponents' hands count-only;
    // no draw-pile order). Built before the mutation so options/state reflect the
    // moment of choosing. Only modelled CHOICE actions yield a snapshot.
    final actionType = action['type'] as String? ?? '';
    final seat = playerIds.indexOf(lobbyPlayerId);
    final turn = game.turnNumber;
    final decision = buildDecisionSnapshot(
      game: game,
      actorSeatId: seatId,
      actionType: actionType,
      action: action,
    );
    // Resolve the acted-on card up front (zones can change once applied).
    final actor = game.players[seat];
    final actedCard =
        resolveActionCard(game: game, actor: actor, action: action);

    final result = applyAction(game, seatId, action);
    if (result.accepted) {
      _stateVersion++;
      if (isEndTurn) {
        _undoStack.clear();
      } else if (snapshot != null) {
        _undoStack.add(snapshot);
      }
      _recordTelemetry(
        lobbyPlayerId: lobbyPlayerId,
        seat: seat,
        turn: turn,
        actionType: actionType,
        action: action,
        decision: decision,
        actedCard: actedCard,
      );
    }
    return result;
  }

  /// Persist the decision record (if this was a modelled choice) + the compact
  /// outcome event for an ACCEPTED action. All writes are best-effort (the store
  /// no-ops on failure), so telemetry never affects the game loop.
  void _recordTelemetry({
    required String lobbyPlayerId,
    required int seat,
    required int turn,
    required String actionType,
    required Map<String, dynamic> action,
    required DecisionSnapshot? decision,
    required CardModel? actedCard,
  }) {
    if (decision != null) {
      stats.recordDecision(
        gameId: id,
        turn: turn,
        seat: seat,
        playerId: lobbyPlayerId,
        decisionType: decision.decisionType,
        chosenIndex: decision.chosenIndex,
        options: decision.options,
        selfState: decision.selfState,
        oppState: decision.oppState,
        board: decision.board,
      );
    }

    // Compact outcome event (design §2). amount/targetId come from the payload.
    final amount = action['amount'] as int?;
    final targetSeatId =
        (action['targetId'] ?? action['targetPlayerId']) as String?;
    final targetLobbyId = _lobbyIdForSeatId(targetSeatId);
    stats.recordEvent(
      gameId: id,
      turn: turn,
      seat: seat,
      playerId: lobbyPlayerId,
      type: actionType,
      cardId: actedCard?.id,
      cardName: actedCard?.name,
      faction: actedCard?.faction.name,
      cost: actedCard?.cost,
      amount: amount,
      targetId: targetLobbyId,
      meta: {
        if (action['choiceIndex'] != null) 'choiceIndex': action['choiceIndex'],
        if (action['source'] != null) 'source': action['source'],
        if (action['free'] != null) 'free': action['free'],
      },
    );
  }

  /// Pop the most recent same-turn snapshot and restore it, replacing [game].
  /// Legal only for the CURRENT player ([seatId]) with a non-empty stack.
  ActionResult _undo(String seatId) {
    if (game.isGameOver) return ActionResult.reject('game is over');
    if (game.currentPlayer.id != seatId) {
      return ActionResult.reject('not your turn');
    }
    if (_undoStack.isEmpty) {
      return ActionResult.reject('nothing to undo this turn');
    }
    game = GameStateCodec.decode(_undoStack.removeLast());
    return ActionResult.ok();
  }

  /// End the game by FORFEIT on behalf of a seated player ([seatId] is any
  /// player's engine seat id — the turn gate is intentionally NOT applied). The
  /// game is marked completed with NO winner and a distinct `winType` of
  /// `'forfeit'` (round-tripped by GameStateCodec, so a persisted forfeit
  /// reloads as a finished game — see winTypeOf / Lobby.restoreGame). Rejected
  /// if the game is already over. Uses only the engine's public surface
  /// (winnerId / winType fields + restoreGameOver) — the engine itself is
  /// unchanged.
  ActionResult _forfeit(String seatId) {
    if (game.isGameOver) return ActionResult.reject('game is over');
    game.winnerId = null;
    game.winType = 'forfeit';
    game.restoreGameOver(true);
    return ActionResult.ok();
  }

  /// The redacted view for a NON-PARTICIPANT spectator: the exact same filter an
  /// opponent gets (no player's hidden hand, no draw-pile order/contents), by
  /// redacting for a recipient id that matches no seat. Spectators therefore see
  /// only board-public information — never hidden info beyond what a seated
  /// opponent already sees. `canUndo` is always false (spectators can't act).
  Map<String, dynamic> spectatorView() => redactFor(
        game,
        '', // matches no seat → all hands stay hidden (opponent-level view)
        stateVersion: _stateVersion,
        canUndo: false,
        names: _seatNames(),
      );

  /// The redacted view a specific lobby player is allowed to see. [names] lets
  /// [broadcastViews] pass a single precomputed seat→username map shared across
  /// all recipients (it's the same for everyone), avoiding an N× rebuild.
  Map<String, dynamic> viewFor(String lobbyPlayerId, {Map<String, String>? names}) {
    final seatId = _seatIdFor(lobbyPlayerId);
    // Unknown viewers get a spectator-style view (no private hand).
    return redactFor(
      game,
      seatId ?? '',
      stateVersion: _stateVersion,
      canUndo: canUndoFor(lobbyPlayerId),
      // Reuse a caller-supplied seat→name map when broadcasting to many players
      // (it's identical for all recipients); compute it here only for a
      // standalone single-player view (resync).
      names: names ?? _seatNames(),
    );
  }

  /// Engine seat id (`p0`..) → lobby username, so redacted views can show real
  /// player names instead of seat ids. Seats and [playerIds] share order (seat i
  /// == game.players[i], joined at start), so we zip them.
  Map<String, String> _seatNames() {
    final out = <String, String>{};
    for (var i = 0; i < game.players.length && i < playerIds.length; i++) {
      out[game.players[i].id] = playerIds[i];
    }
    return out;
  }

  /// Redacted views for every connected player, keyed by LOBBY id — what the
  /// server broadcasts after each accepted action.
  Map<String, Map<String, dynamic>> broadcastViews() {
    // The seat→username map is identical for every recipient — compute it ONCE
    // per broadcast instead of once per player inside each viewFor.
    final names = _seatNames();
    return {for (final id in playerIds) id: viewFor(id, names: names)};
  }
}
