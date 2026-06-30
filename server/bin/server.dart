// Authoritative WebSocket game server entrypoint (Phase 1: LAN shared games).
//
// Run:   dart run bin/server.dart [port]   (default 8080)
// Note:  run with `dart run` + the Dart SDK; `dart compile exe` is NOT supported
//        here (the sqlite3 dependency uses build hooks that compile-exe rejects).
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

import 'package:shards_server/game_session.dart';
import 'package:shards_server/lobby.dart';
import 'package:shards_server/persistence.dart';
import 'package:shards_server/stats_capture.dart';
import 'package:shards_server/stats_store.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/data/market_deck.dart';
import 'package:simple_card_game/models/card_model.dart';

/// The lobby is built in [main] once the authoritative card database has loaded
/// from disk, so all games use the real market deck (per-card copy counts).
late final Lobby _lobby;

/// Shared access token gate. When set (via SHARDS_ACCESS_TOKEN), every client
/// must present a matching `token` in its first `identify` message or the server
/// closes the connection. When EMPTY/unset the server is OPEN (no token) — fine
/// for local dev; set the env var for any exposed deployment. Invitees share the
/// token; only token-holders can connect.
String _accessToken = '';
bool get _tokenRequired => _accessToken.isNotEmpty;

/// Allowed browser origins (from SHARDS_ALLOWED_ORIGINS, comma-separated). Empty
/// = allow any. Checked on the WebSocket upgrade to block cross-site hijacking.
Set<String> _allowedOrigins = {};

/// Hard cap on a single inbound WebSocket message (bytes). A frame larger than
/// this is rejected without parsing, so a giant payload can't exhaust memory.
const int _maxMessageBytes = 64 * 1024;

/// Constant-time string comparison so a wrong token can't be discovered by
/// timing how long the reject takes.
bool _tokenMatches(String provided) {
  final a = _accessToken;
  // Always compare over the full expected length; never early-exit on mismatch.
  var diff = a.length ^ provided.length;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ (i < provided.length ? provided.codeUnitAt(i) : 0);
  }
  return diff == 0;
}

/// Disk snapshot store so in-progress games survive a restart. Built in [main];
/// disabled (in-memory only) if the data directory is unwritable.
late final GamePersistence _store;

/// Telemetry store (player-stats + ML training data). Built in [main]; disabled
/// (no-op) if the stats database can't be opened.
late final StatsStore _stats;

/// Persist a game by id (after any change that mutated it). Best-effort — the
/// store no-ops when disabled and never throws.
void _persist(String gameId) {
  final g = _lobby.game(gameId);
  if (g != null) _store.save(g);
}

/// Connected clients by lobby player id → their socket.
final Map<String, WebSocket> _sockets = {};

void main(List<String> args) async {
  final port =
      args.isNotEmpty ? int.tryParse(args.first) ?? 8080 : 8080;

  // Access-token gate (shared secret). Set SHARDS_ACCESS_TOKEN to require it.
  _accessToken = (Platform.environment['SHARDS_ACCESS_TOKEN'] ?? '').trim();
  stdout.writeln(_tokenRequired
      ? 'Access token REQUIRED (clients must present SHARDS_ACCESS_TOKEN).'
      : 'WARNING: no access token set — server is OPEN. Set '
          'SHARDS_ACCESS_TOKEN for any exposed deployment.');

  _allowedOrigins = (Platform.environment['SHARDS_ALLOWED_ORIGINS'] ?? '')
      .split(',')
      .map((o) => o.trim())
      .where((o) => o.isNotEmpty)
      .toSet();
  if (_allowedOrigins.isNotEmpty) {
    stdout.writeln('Origin allowlist: ${_allowedOrigins.join(', ')}');
  }

  // Load the authoritative card DB from disk (pure-Dart, no Flutter) and build
  // the market deck. The path is relative to the repo root; the server runs
  // from server/, so the DB sits one level up.
  final dbFile = File('../assets/card_db/cards.json');
  List<MarketCard>? marketDeck;
  List<CardModel>? destinySupply;
  if (dbFile.existsSync()) {
    final db = CardDatabase.fromJsonString(dbFile.readAsStringSync());
    marketDeck = buildMarketDeckFromDatabase(db);
    destinySupply = buildDestinySupplyFromDatabase(db);
    stdout.writeln('Loaded card DB: ${db.records.length} records, '
        '${marketDeck.length} unique market cards, '
        '${destinySupply.length} Destinies (separate supply).');
  } else {
    stdout.writeln('WARNING: ${dbFile.path} not found — '
        'falling back to the legacy hardcoded market.');
  }
  // Player-stats + ML-training telemetry. Opens SQLite at SHARDS_STATS_DB (or
  // server/data/stats.db, gitignored). GRACEFUL: if it can't open, it becomes a
  // no-op store and the server runs with telemetry off — never crashes.
  _stats = StatsStore.open();
  stdout.writeln(_stats.enabled
      ? 'Player-stats telemetry enabled.'
      : 'Player-stats telemetry DISABLED (db unavailable) — running without it.');

  _lobby = Lobby(
    marketDeck: marketDeck,
    destinySupply: destinySupply,
    stats: _stats,
  );

  // Persistence: snapshot games to disk so they survive a restart. The storage
  // directory is configurable via SHARDS_DATA_DIR (default: server/data, which
  // is gitignored). If it's unwritable the store disables itself and the server
  // runs purely in-memory — never crashes.
  final dataDir =
      Platform.environment['SHARDS_DATA_DIR'] ?? GamePersistence.defaultDir;
  _store = GamePersistence.open(dataDir);
  final restored = _store.loadInto(_lobby);
  if (_store.enabled) {
    stdout.writeln('Persistence enabled at $dataDir '
        '(${restored == 0 ? 'no games to restore' : '$restored restored'}).');
  }

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
      // ORIGIN allowlist: when SHARDS_ALLOWED_ORIGINS is set (comma-separated),
      // only browser pages from those origins may open a socket — blocks
      // cross-site WebSocket hijacking from arbitrary websites. Unset = allow
      // any origin (non-browser clients send no Origin header anyway).
      if (_allowedOrigins.isNotEmpty) {
        final origin = req.headers.value('origin');
        if (origin != null && !_allowedOrigins.contains(origin)) {
          req.response.statusCode = HttpStatus.forbidden;
          await req.response.close();
          continue;
        }
      }
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
      // Reject oversized frames BEFORE parsing so a huge payload can't OOM us.
      if (data is String && data.length > _maxMessageBytes) {
        err('message too large');
        return;
      }
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
        // ACCESS-TOKEN GATE: reject (and close) anyone without the shared token.
        if (_tokenRequired) {
          final provided = msg['token'];
          if (provided is! String || !_tokenMatches(provided)) {
            send({'type': 'error', 'error': 'invalid access token', 'code': 'auth'});
            socket.close(4001, 'invalid access token');
            return;
          }
        }
        final rawId = msg['playerId'] as String;
        final id = rawId.trim();
        if (id.isEmpty || id.length > 40) {
          err('player name must be 1-40 characters');
          return;
        }
        playerId = id;
        // Same-name (re)connect = takeover: close any prior socket for this name
        // and bind to the new one. This is the reconnect path (reopened tab /
        // returning device). Impersonation is already gated by the access token
        // above — only token-holders reach here — so takeover is the right UX.
        final existing = _sockets[playerId!];
        if (existing != null && existing != socket) {
          try {
            existing.close(4003, 'reconnected elsewhere');
          } catch (_) {/* old socket already gone */}
        }
        _sockets[playerId!] = socket;
        send({'type': 'welcome', 'playerId': playerId});
        send({'type': 'lobby', 'games': _lobby.summaries()});
        // RECONNECT: if this player is already in a live game, immediately
        // resend their current redacted state so a reopened tab / returning
        // device drops straight back into the game instead of going stale.
        _resyncPlayer(playerId!, send);
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
      // Already identified; re-confirm and resync any live game (idempotent —
      // lets a client explicitly request a resync).
      send({'type': 'welcome', 'playerId': playerId});
      _resyncPlayer(playerId, send);

    case 'resyncGame':
      // Resync a SPECIFIC game (used when a player is in multiple games and
      // picks one from the lobby). Only a MEMBER of a live game gets its state.
      final gameId = msg['gameId'] as String?;
      if (gameId == null) {
        err('resyncGame needs gameId');
        return;
      }
      final g = _lobby.resyncableGameForPlayer(gameId, playerId);
      final session = g?.session;
      if (g == null || session == null) {
        err('cannot resync $gameId (missing, not started, or not a member)');
        return;
      }
      send({
        'type': 'state',
        'gameId': g.id,
        'state': session.viewFor(playerId),
      });

    case 'listGames':
      send({'type': 'lobby', 'games': _lobby.summaries()});

    case 'createGame':
      final seats = (msg['seats'] as int?) ?? 2;
      if (seats < 2 || seats > 4) {
        err('seats must be 2-4');
        return;
      }
      var name = msg['name'] as String?;
      if (name != null && name.length > 60) name = name.substring(0, 60);
      final g = _lobby.createGame(hostId: playerId, seats: seats, name: name);
      _persist(g.id);
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
      _persist(g.id);
      _broadcastLobby();
      // Auto-start when full.
      if (g.isFull) {
        final session = _lobby.startGame(g.id);
        if (session != null) {
          _persist(g.id);
          _broadcastState(g.id);
        }
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
      // Win check → mark complete. On the FIRST transition to complete, record
      // game-end telemetry: stamp the games row + JOIN the supervised `playerWon`
      // label onto every decision in this game. Guarded so it fires once.
      if (session.game.isGameOver && g!.status != GameStatus.complete) {
        g.status = GameStatus.complete;
        _stats.recordGameEnd(
          gameId: g.id,
          winnerId: _winnerLobbyId(session),
          winType: winTypeOf(session.game),
          turns: session.game.turnNumber,
        );
      }
      // Persist AFTER the accepted mutation (and any complete transition) so the
      // on-disk snapshot reflects the new authoritative state + stateVersion.
      _persist(gameId);
      _broadcastState(gameId);
  }
}

/// The LOBBY player id of the winner (the engine's `winnerId` is a seat id like
/// `p0`; decisions are keyed by lobby id, so the supervised-label join needs the
/// lobby id). Null if there is no winner (drawn/abandoned).
String? _winnerLobbyId(GameSession session) {
  final seatId = session.game.winnerId;
  if (seatId == null) return null;
  final seat = session.game.players.indexWhere((p) => p.id == seatId);
  final ids = session.playerIds;
  return (seat >= 0 && seat < ids.length) ? ids[seat] : seatId;
}

/// If [playerId] is in a live game, send them their current redacted state so a
/// reconnecting client resyncs immediately (without waiting for the next action).
void _resyncPlayer(String playerId, void Function(Map<String, dynamic>) send) {
  final g = _lobby.activeGameForPlayer(playerId);
  final session = g?.session;
  if (g == null || session == null) return;
  send({
    'type': 'state',
    'gameId': g.id,
    'state': session.viewFor(playerId),
  });
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
