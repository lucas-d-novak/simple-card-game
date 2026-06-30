// Authoritative WebSocket game server entrypoint (Phase 1: LAN shared games).
//
// Run:   dart run bin/server.dart [port]   (default 8080)
// Build: dart compile exe bin/server.dart -o shards-server
//
// Protocol (JSON message envelope over WebSocket):
//   client → server: {"type": <action>, ...payload}
//     - identify:   {"type":"identify","playerId":"alice"}   (first message)
//     - lobby:      {"type":"createGame","seats":2}
//                   {"type":"joinGame","gameId":"game_0"}
//                   {"type":"listGames"}
//     - game:       {"type":"playCard","cardId":"...","gameId":"game_0"}  etc.
//   server → client:
//     - {"type":"welcome","playerId":...}
//     - {"type":"lobby","games":[...]}                (broadcast on lobby change)
//     - {"type":"state","gameId":...,"state":{...redacted...}}
//     - {"type":"error","error":"..."}
//
// Hidden-info safety: a client only ever receives its own redacted view
// (server/lib/views.dart). Deck order + opponents' hands never leave the server.

import 'dart:convert';
import 'dart:io';

import 'package:shards_server/lobby.dart';

final Lobby _lobby = Lobby();

/// Connected clients by lobby player id → their socket.
final Map<String, WebSocket> _sockets = {};

void main(List<String> args) async {
  final port =
      args.isNotEmpty ? int.tryParse(args.first) ?? 8080 : 8080;

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('Shards server listening on ws://0.0.0.0:$port');

  await for (final req in server) {
    if (req.uri.path == '/health') {
      req.response
        ..statusCode = 200
        ..write('ok');
      await req.response.close();
      continue;
    }
    if (WebSocketTransformer.isUpgradeRequest(req)) {
      final socket = await WebSocketTransformer.upgrade(req);
      _handleSocket(socket);
    } else {
      req.response.statusCode = HttpStatus.upgradeRequired;
      await req.response.close();
    }
  }
}

void _handleSocket(WebSocket socket) {
  String? playerId;

  void send(Map<String, dynamic> msg) {
    if (socket.readyState == WebSocket.open) socket.add(jsonEncode(msg));
  }

  void err(String message) => send({'type': 'error', 'error': message});

  socket.listen(
    (data) {
      late final Map<String, dynamic> msg;
      try {
        msg = (jsonDecode(data as String) as Map).cast<String, dynamic>();
      } catch (_) {
        err('malformed message');
        return;
      }
      final type = msg['type'] as String?;

      // First message must identify the player.
      if (playerId == null) {
        if (type != 'identify' || msg['playerId'] is! String) {
          err('first message must be {"type":"identify","playerId":...}');
          return;
        }
        playerId = msg['playerId'] as String;
        _sockets[playerId!] = socket;
        send({'type': 'welcome', 'playerId': playerId});
        send({'type': 'lobby', 'games': _lobby.summaries()});
        return;
      }

      _dispatch(playerId!, msg, send, err);
    },
    onDone: () {
      if (playerId != null) _sockets.remove(playerId);
    },
    onError: (_) {
      if (playerId != null) _sockets.remove(playerId);
    },
    cancelOnError: true,
  );
}

void _dispatch(
  String playerId,
  Map<String, dynamic> msg,
  void Function(Map<String, dynamic>) send,
  void Function(String) err,
) {
  final type = msg['type'] as String?;
  switch (type) {
    case 'identify':
      // Already identified; ignore re-identify.
      send({'type': 'welcome', 'playerId': playerId});

    case 'listGames':
      send({'type': 'lobby', 'games': _lobby.summaries()});

    case 'createGame':
      final seats = (msg['seats'] as int?) ?? 2;
      if (seats < 2 || seats > 4) {
        err('seats must be 2-4');
        return;
      }
      final g = _lobby.createGame(hostId: playerId, seats: seats);
      send({'type': 'created', 'gameId': g.id});
      _broadcastLobby();

    case 'joinGame':
      final gameId = msg['gameId'] as String?;
      if (gameId == null) {
        err('joinGame needs gameId');
        return;
      }
      final g = _lobby.joinGame(gameId, playerId);
      if (g == null) {
        err('cannot join $gameId (missing, full, or already started)');
        return;
      }
      _broadcastLobby();
      // Auto-start when full.
      if (g.isFull) {
        final session = _lobby.startGame(g.id);
        if (session != null) _broadcastState(g.id);
      }

    default:
      // Anything else is a game action; it must carry a gameId.
      final gameId = msg['gameId'] as String?;
      if (gameId == null) {
        err('action "$type" needs a gameId');
        return;
      }
      final g = _lobby.game(gameId);
      final session = g?.session;
      if (session == null) {
        err('game $gameId is not in progress');
        return;
      }
      final result = session.apply(playerId, msg);
      if (!result.accepted) {
        err(result.error ?? 'action rejected');
        return;
      }
      // Win check → mark complete.
      if (session.game.isGameOver) g!.status = GameStatus.complete;
      _broadcastState(gameId);
  }
}

void _broadcastLobby() {
  final payload = {'type': 'lobby', 'games': _lobby.summaries()};
  for (final socket in _sockets.values) {
    if (socket.readyState == WebSocket.open) socket.add(jsonEncode(payload));
  }
}

/// Send each player in [gameId] their OWN redacted view.
void _broadcastState(String gameId) {
  final session = _lobby.game(gameId)?.session;
  if (session == null) return;
  final views = session.broadcastViews();
  for (final entry in views.entries) {
    final socket = _sockets[entry.key];
    if (socket != null && socket.readyState == WebSocket.open) {
      socket.add(jsonEncode(
          {'type': 'state', 'gameId': gameId, 'state': entry.value}));
    }
  }
}
