// A single in-progress game: wraps one authoritative GameService and the set of
// connected players. Applies actions and produces per-player redacted views.
//
// Transport-agnostic on purpose: the WebSocket layer (bin/server.dart) owns the
// sockets and calls into this. That keeps the session unit-testable without a
// network.

import 'package:shards_server/protocol.dart';
import 'package:shards_server/views.dart';
import 'package:simple_card_game/services/game_service.dart';

class GameSession {
  GameSession({required this.id, required this.game, required this.playerIds});

  final String id;
  final GameService game;

  /// Stable LOBBY player ids in seat order (index aligns with game.players).
  /// The engine names its own seats `p0..pN` (PlayerState.id, which is final and
  /// cannot be renamed), so the session translates between a lobby player id and
  /// its engine seat id for both authorization and redaction.
  final List<String> playerIds;

  int _stateVersion = 0;
  int get stateVersion => _stateVersion;

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
    final result = applyAction(game, seatId, action);
    if (result.accepted) _stateVersion++;
    return result;
  }

  /// The redacted view a specific lobby player is allowed to see.
  Map<String, dynamic> viewFor(String lobbyPlayerId) {
    final seatId = _seatIdFor(lobbyPlayerId);
    // Unknown viewers get a spectator-style view (no private hand).
    return redactFor(game, seatId ?? '', stateVersion: _stateVersion);
  }

  /// Redacted views for every connected player, keyed by LOBBY id — what the
  /// server broadcasts after each accepted action.
  Map<String, Map<String, dynamic>> broadcastViews() => {
        for (final id in playerIds) id: viewFor(id),
      };
}
