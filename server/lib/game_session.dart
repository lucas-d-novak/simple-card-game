// A single in-progress game: wraps one authoritative GameService and the set of
// connected players. Applies actions and produces per-player redacted views.
//
// Transport-agnostic on purpose: the WebSocket layer (bin/server.dart) owns the
// sockets and calls into this. That keeps the session unit-testable without a
// network.

import 'package:shards_server/protocol.dart';
import 'package:shards_server/views.dart';
import 'package:simple_card_game/data/database/game_state_codec.dart';
import 'package:simple_card_game/services/game_service.dart';

class GameSession {
  GameSession({required this.id, required this.game, required this.playerIds});

  final String id;

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

    // Capture a pre-action snapshot for a mutating action so it can be undone.
    // `endTurn` is special: an accepted end-turn CLEARS the history instead of
    // pushing onto it (you cannot undo across a turn boundary).
    final isEndTurn = action['type'] == 'endTurn';
    final snapshot = isEndTurn ? null : GameStateCodec.encode(game);

    final result = applyAction(game, seatId, action);
    if (result.accepted) {
      _stateVersion++;
      if (isEndTurn) {
        _undoStack.clear();
      } else if (snapshot != null) {
        _undoStack.add(snapshot);
      }
    }
    return result;
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

  /// The redacted view a specific lobby player is allowed to see.
  Map<String, dynamic> viewFor(String lobbyPlayerId) {
    final seatId = _seatIdFor(lobbyPlayerId);
    // Unknown viewers get a spectator-style view (no private hand).
    return redactFor(
      game,
      seatId ?? '',
      stateVersion: _stateVersion,
      canUndo: canUndoFor(lobbyPlayerId),
    );
  }

  /// Redacted views for every connected player, keyed by LOBBY id — what the
  /// server broadcasts after each accepted action.
  Map<String, Map<String, dynamic>> broadcastViews() => {
        for (final id in playerIds) id: viewFor(id),
      };
}
