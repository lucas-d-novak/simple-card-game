import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connection lifecycle of the [GameClient].
enum ClientStatus { disconnected, connecting, connected, error }

/// One game as advertised in the server lobby (mirrors LobbyGame.toSummary on
/// the server: id, hostId, seats, players, status, currentPlayerIndex).
class LobbyGameSummary {
  LobbyGameSummary({
    required this.id,
    required this.name,
    required this.hostId,
    required this.seats,
    required this.players,
    required this.status,
  });

  final String id;

  /// Host-chosen display name (defaults to "<host>'s game" server-side).
  final String name;
  final String hostId;
  final int seats;
  final List<String> players;
  final String status; // waiting | started | complete

  factory LobbyGameSummary.fromJson(Map<String, dynamic> j) =>
      LobbyGameSummary(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? (j['id'] as String),
        hostId: (j['hostId'] as String?) ?? '',
        seats: (j['seats'] as int?) ?? 2,
        players: [for (final p in (j['players'] as List? ?? const [])) p as String],
        status: (j['status'] as String?) ?? 'waiting',
      );
}

/// Client-side network layer for the authoritative multiplayer server.
///
/// Owns one WebSocket to `ws://host:port`. Sends `identify` on connect, then
/// lobby/game actions; parses server pushes into observable state. The UI
/// listens via [ChangeNotifier]. The engine is NEVER run on the client for
/// networked games — the server is the source of truth and pushes a redacted
/// view per player (see ai-docs/multiplayer_architecture.md).
class GameClient extends ChangeNotifier {
  GameClient({required this.playerId});

  /// The id this client authenticates as (the server trusts the connection's
  /// identity, not action payloads).
  final String playerId;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  ClientStatus status = ClientStatus.disconnected;
  String? lastError;

  /// Latest lobby snapshot from the server.
  List<LobbyGameSummary> lobby = const [];

  /// The id of the game this client is currently in (created or joined), if any.
  String? currentGameId;

  /// Latest redacted game-state view for this player (server `state` message).
  /// Null until a game is in progress. Shape is server/lib/views.dart redactFor.
  Map<String, dynamic>? gameState;

  bool get inGame => gameState != null;

  /// Whose turn it is (index into the state's players), or -1 if no state.
  int get currentPlayerIndex =>
      (gameState?['currentPlayerIndex'] as int?) ?? -1;

  /// True when it is THIS player's turn (their seat == currentPlayerIndex).
  bool get isMyTurn {
    final st = gameState;
    if (st == null) return false;
    final players = st['players'] as List? ?? const [];
    if (currentPlayerIndex < 0 || currentPlayerIndex >= players.length) {
      return false;
    }
    final me = st['you'] as String?;
    return (players[currentPlayerIndex] as Map)['id'] == me;
  }

  /// Whether the server says this player may UNDO right now — it's their turn
  /// AND a same-turn snapshot exists to roll back to. Server-authoritative; the
  /// Undo button gates on it.
  bool get canUndo => (gameState?['canUndo'] as bool?) ?? false;

  // ---- connection ----

  Future<void> connect(String url) async {
    if (status == ClientStatus.connecting || status == ClientStatus.connected) {
      return;
    }
    _setStatus(ClientStatus.connecting);
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      _sub = channel.stream.listen(
        _onMessage,
        onDone: _onDone,
        onError: _onError,
        cancelOnError: true,
      );
      // The server requires identify as the FIRST message.
      _send({'type': 'identify', 'playerId': playerId});
      // Optimistically connected; a `welcome` confirms.
    } catch (e) {
      lastError = '$e';
      _setStatus(ClientStatus.error);
    }
  }

  void disconnect() {
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setStatus(ClientStatus.disconnected);
  }

  // ---- lobby actions ----

  void listGames() => _send({'type': 'listGames'});

  /// Ask the server to resend our current game state. The server's `identify`
  /// handler resyncs a player who is seated in a live game — used to re-enter a
  /// game from the lobby (a tab that lost its in-game view, or a reconnect).
  ///
  /// When a player is in MULTIPLE games this targets the server's most-recent
  /// active game. To re-enter a SPECIFIC game, use [rejoinGame].
  void requestResync() => _send({'type': 'identify', 'playerId': playerId});

  /// Ask the server to push a SPECIFIC game's redacted state (so a player in
  /// several active games can pick which one to re-enter). The server only
  /// honours this for a member of that live game (hidden-info safe).
  void rejoinGame(String gameId) =>
      _send({'type': 'resyncGame', 'gameId': gameId});

  void createGame({int seats = 2, String? name}) => _send({
        'type': 'createGame',
        'seats': seats,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      });

  void joinGame(String gameId) =>
      _send({'type': 'joinGame', 'gameId': gameId});

  // ---- game actions (only valid on your turn; the server re-checks) ----

  void sendAction(String type, [Map<String, dynamic> extra = const {}]) {
    final gameId = currentGameId;
    if (gameId == null) return;
    _send({'type': type, 'gameId': gameId, ...extra});
  }

  void playCard(String cardId, {int choiceIndex = 0}) =>
      sendAction('playCard', {'cardId': cardId, 'choiceIndex': choiceIndex});
  void playAllCards() => sendAction('playAllCards');
  void buyCard(String cardId) => sendAction('buyCard', {'cardId': cardId});
  void endTurn() => sendAction('endTurn');

  /// Undo your most-recent action THIS turn (server-authoritative; legal only on
  /// your turn with same-turn history — the server rejects otherwise).
  void undo() => sendAction('undo');
  void attackPlayer(String targetId, int amount) =>
      sendAction('attackPlayer', {'targetId': targetId, 'amount': amount});
  void attackChampion(String championId, String targetPlayerId) => sendAction(
      'attackChampion',
      {'championId': championId, 'targetPlayerId': targetPlayerId});
  void activateChampion(String championId) =>
      sendAction('activateChampion', {'championId': championId});
  void useActivatedAbility(String championId) =>
      sendAction('useActivatedAbility', {'championId': championId});
  void focus() => sendAction('focus');

  // ---- deferred-selection follow-ups --------------------------------------
  // After playing a card whose effect resolves to a no-op at play time (banish a
  // card / scrap from center / destroy an enemy champion / return from discard),
  // the UI prompts for a target and sends the matching follow-up. The server
  // validates legality (protocol.dart + turn gate), so the client only prompts
  // and sends.

  /// Banish a chosen card from hand/discard (after a BanishCardEffect). [source]
  /// is the engine BanishSource name (e.g. 'handOrDiscard', 'hand', 'discard').
  void banishCard(String cardId, String source) =>
      sendAction('banishCard', {'cardId': cardId, 'source': source});

  /// Scrap a chosen center-row card (after a ScrapFromCenterRowEffect).
  void scrapFromCenterRow(String cardId) =>
      sendAction('scrapFromCenterRow', {'cardId': cardId});

  /// Destroy a chosen enemy champion (after a single-target DestroyChampionEffect).
  void destroyChampion(String championId, String targetPlayerId) => sendAction(
      'destroyChampion',
      {'championId': championId, 'targetPlayerId': targetPlayerId});

  /// Return a chosen card from your discard to hand (after a ReturnFromDiscardEffect).
  void returnFromDiscard(String cardId) =>
      sendAction('returnFromDiscard', {'cardId': cardId});

  // ---- Destiny / Relic -----------------------------------------------------

  /// Claim a face-up Destiny from the shared row (Mastery 5+, free, once).
  void claimDestiny(String cardId) =>
      sendAction('claimDestiny', {'cardId': cardId});

  /// Use a claimed Destiny's per-turn ability.
  void useDestinyAbility(String cardId) =>
      sendAction('useDestinyAbility', {'cardId': cardId});

  /// Recruit one of your two set-aside Relic options (Mastery 10, once).
  void recruitRelic(String cardId) =>
      sendAction('recruitRelic', {'cardId': cardId});

  // ---- internals ----

  void _send(Map<String, dynamic> msg) {
    final ch = _channel;
    if (ch == null) return;
    ch.sink.add(jsonEncode(msg));
  }

  void _onMessage(dynamic data) {
    late final Map<String, dynamic> msg;
    try {
      msg = (jsonDecode(data as String) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    switch (msg['type'] as String?) {
      case 'welcome':
        _setStatus(ClientStatus.connected);
      case 'lobby':
        lobby = [
          for (final g in (msg['games'] as List? ?? const []))
            LobbyGameSummary.fromJson((g as Map).cast<String, dynamic>()),
        ];
        notifyListeners();
      case 'created':
        currentGameId = msg['gameId'] as String?;
        notifyListeners();
      case 'state':
        currentGameId = msg['gameId'] as String? ?? currentGameId;
        gameState = (msg['state'] as Map?)?.cast<String, dynamic>();
        notifyListeners();
      case 'error':
        lastError = msg['error'] as String?;
        notifyListeners();
    }
  }

  void _onDone() => _setStatus(ClientStatus.disconnected);

  void _onError(Object e) {
    lastError = '$e';
    _setStatus(ClientStatus.error);
  }

  void _setStatus(ClientStatus s) {
    status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
