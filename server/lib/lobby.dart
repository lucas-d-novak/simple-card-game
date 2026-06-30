// In-memory lobby: tracks open/active games and routes players into sessions.
// (SQLite persistence is a later phase — see ai-docs/multiplayer_architecture.md
// §6/§10. For the LAN/beta phase, in-memory is enough.)

import 'package:shards_server/game_session.dart';
import 'package:simple_card_game/data/market_deck.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/services/game_service.dart';

enum GameStatus { waiting, started, complete }

class LobbyGame {
  LobbyGame({
    required this.id,
    required this.hostId,
    required this.seats,
  });

  final String id;
  final String hostId;

  /// Desired player count (2-4). The game starts once this many have joined.
  final int seats;

  /// Joined player ids, in seat order.
  final List<String> players = [];

  GameStatus status = GameStatus.waiting;
  GameSession? session;

  bool get isFull => players.length >= seats;

  Map<String, dynamic> toSummary() => {
        'id': id,
        'hostId': hostId,
        'seats': seats,
        'players': players,
        'status': status.name,
        if (session != null) 'currentPlayerIndex': session!.game.currentPlayerIndex,
      };
}

class Lobby {
  /// Optional authoritative market deck (real cards + per-card copies) and the
  /// SEPARATE Destiny supply, both built once at server startup from the card
  /// database. When null, games fall back to the engine's legacy hardcoded
  /// catalog (and no Destinies).
  Lobby({List<MarketCard>? marketDeck, List<CardModel>? destinySupply})
      : _marketDeck = marketDeck,
        _destinySupply = destinySupply;

  final List<MarketCard>? _marketDeck;
  final List<CardModel>? _destinySupply;
  final Map<String, LobbyGame> _games = {};
  int _counter = 0;

  /// Deterministic id generator (no Date.now/Random — keeps the server
  /// reproducible and testable). Ids are unique within a process run.
  String _nextId(String prefix) => '${prefix}_${_counter++}';

  LobbyGame createGame({required String hostId, required int seats}) {
    final game = LobbyGame(id: _nextId('game'), hostId: hostId, seats: seats);
    game.players.add(hostId);
    _games[game.id] = game;
    return game;
  }

  /// Join an existing waiting game. Returns null if it doesn't exist, is full,
  /// or the player is already in it (idempotent-ish: re-join is a no-op join).
  LobbyGame? joinGame(String gameId, String playerId) {
    final g = _games[gameId];
    if (g == null || g.status != GameStatus.waiting) return null;
    if (g.players.contains(playerId)) return g;
    if (g.isFull) return null;
    g.players.add(playerId);
    return g;
  }

  /// Start a full waiting game: spin up the authoritative GameService + session.
  /// The engine seats players p0..pN; we map them to the lobby's player ids by
  /// seat order.
  GameSession? startGame(String gameId) {
    final g = _games[gameId];
    if (g == null || g.status != GameStatus.waiting || !g.isFull) return null;
    final svc = GameService(
      playerCount: g.players.length,
      marketDeck: _marketDeck,
      destinySupply: _destinySupply,
    );
    // The engine names seats p0..pN (both PlayerState.id and .name are final);
    // GameSession owns the lobby-player-id <-> seat-id mapping for both
    // authorization and redaction, so no engine renaming is needed.
    final session = GameSession(
      id: g.id,
      game: svc,
      playerIds: List.of(g.players),
    );
    g.session = session;
    g.status = GameStatus.started;
    return session;
  }

  LobbyGame? game(String id) => _games[id];

  List<Map<String, dynamic>> summaries() =>
      [for (final g in _games.values) g.toSummary()];
}
