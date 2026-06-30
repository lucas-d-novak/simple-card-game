// Player-stats + ML-training telemetry store (ai-docs/player_stats_design.md).
//
// TWO data shapes, kept distinct (design §2 vs §4b):
//   * `events`    — compact OUTCOME rows (one per accepted action). Powers
//                   leaderboards, "what does Ray buy", balance. (§2)
//   * `decisions` — rich (state -> choice) ML records snapshotted from the
//                   ACTOR'S OWN information set at each real decision point, with
//                   `playerWon` joined in at game end (the supervised label). (§4b)
//   * `games`     — one row per game (start/end metadata + winner + winType).
//
// HIDDEN-INFO RULE (hard, mirrors server/lib/views.dart): a decision is captured
// from the deciding player's legal information set ONLY — their own hand is known
// (ids recorded), every OPPONENT hand is a COUNT, and NO draw-pile ORDER is ever
// recorded (only sizes). A model trained on this can never learn from knowledge a
// real player could not have. The snapshot helpers in game_session.dart enforce
// this at the source; this store just persists what it is handed.
//
// GRACEFUL DEGRADATION (mirrors GamePersistence): if the database cannot be
// opened — or any write throws — the store becomes a no-op so telemetry can never
// crash the authoritative game loop. A server with NO StatsStore, or a disabled
// one, behaves EXACTLY as before.
//
// CLOCK: the engine is clock-free (deterministic, reproducible). The SERVER
// stamps `ts` (DateTime.now().millisecondsSinceEpoch) at every record call.

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// SQLite-backed telemetry store. All methods are best-effort and non-throwing
/// by contract: a disabled store silently no-ops so callers never have to branch.
class StatsStore {
  StatsStore._(this._db, this._enabled, this._log);

  Database? _db;
  bool _enabled;
  final void Function(String) _log;

  /// Whether writes are actually being persisted (false -> no-op).
  bool get enabled => _enabled;

  /// Environment variable naming an alternate database path.
  static const String envVar = 'SHARDS_STATS_DB';

  /// Default on-disk location (relative to the server's working dir, `server/`).
  /// `server/data/` is gitignored, so the stats db is never committed.
  static const String defaultPath = 'data/stats.db';

  /// Open (creating if needed) a store at [path] (or the `SHARDS_STATS_DB` env
  /// var, or [defaultPath]). On ANY failure — unwritable dir, native lib missing,
  /// DDL error — returns a DISABLED store that no-ops every call and logs a single
  /// warning. The server then runs with telemetry off, never crashing.
  factory StatsStore.open({String? path, void Function(String)? log}) {
    final logger = log ?? (String m) => stdout.writeln(m);
    final dbPath = path ??
        (Platform.environment[envVar]?.trim().isNotEmpty == true
            ? Platform.environment[envVar]!.trim()
            : defaultPath);
    try {
      // Ensure the parent directory exists (best-effort; ':memory:' has none).
      if (dbPath != ':memory:') {
        final parent = File(dbPath).parent;
        if (!parent.existsSync()) parent.createSync(recursive: true);
      }
      final db = sqlite3.open(dbPath);
      _createSchema(db);
      return StatsStore._(db, true, logger);
    } catch (e) {
      logger('WARNING: player-stats disabled — cannot open stats db at '
          '$dbPath ($e). Running without telemetry.');
      return StatsStore._(null, false, logger);
    }
  }

  /// An in-memory store (tests / explicit ephemeral mode). Never touches disk.
  factory StatsStore.inMemory({void Function(String)? log}) =>
      StatsStore.open(path: ':memory:', log: log);

  /// A store that records nothing (explicit off mode; the additive default so a
  /// server constructed without a StatsStore behaves exactly as today).
  factory StatsStore.disabled() => StatsStore._(null, false, (_) {});

  // -------------------------------------------------------------------------
  // Schema
  // -------------------------------------------------------------------------

  static void _createSchema(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS events (
        eventId  INTEGER PRIMARY KEY AUTOINCREMENT,
        ts       INTEGER,
        gameId   TEXT,
        turn     INTEGER,
        seat     INTEGER,
        playerId TEXT,
        type     TEXT,
        cardId   TEXT,
        cardName TEXT,
        faction  TEXT,
        cost     INTEGER,
        amount   INTEGER,
        targetId TEXT,
        meta     TEXT
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS decisions (
        decisionId   INTEGER PRIMARY KEY AUTOINCREMENT,
        ts           INTEGER,
        gameId       TEXT,
        turn         INTEGER,
        seat         INTEGER,
        playerId     TEXT,
        decisionType TEXT,
        chosenIndex  INTEGER,
        options      TEXT,   -- JSON array of option feature maps
        selfState    TEXT,   -- JSON: actor's own (legal) state
        oppState     TEXT,   -- JSON: per-opponent public state (hand COUNT only)
        board        TEXT,   -- JSON: shared supplies + turn
        playerWon    INTEGER -- nullable; backfilled at game end (0/1)
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS games (
        gameId    TEXT PRIMARY KEY,
        startedTs INTEGER,
        endedTs   INTEGER,
        winnerId  TEXT,
        winType   TEXT,
        turns     INTEGER,
        players   TEXT    -- JSON array of {seat, playerId}
      );
    ''');
    // Helpful indices for the common read patterns (per-game, per-player).
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_events_game ON events(gameId);');
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_events_player ON events(playerId);');
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_decisions_game ON decisions(gameId);');

    // Flat TRAINING-EXPORT view: one row per decision with the JSON state pulled
    // into columns via json_extract, so an ML pipeline can `SELECT * FROM
    // decision_export` with no JSON parsing. `options` stays JSON (variable-length
    // action space). `playerWon` is the supervised label (NULL until game end).
    db.execute(r'''
      CREATE VIEW IF NOT EXISTS decision_export AS
      SELECT
        decisionId,
        gameId,
        turn,
        seat,
        playerId,
        decisionType,
        chosenIndex,
        json_extract(selfState, '$.health')    AS self_health,
        json_extract(selfState, '$.mastery')   AS self_mastery,
        json_extract(selfState, '$.gems')      AS self_gems,
        json_extract(selfState, '$.power')     AS self_power,
        json_extract(selfState, '$.handSize')  AS self_handSize,
        json_extract(selfState, '$.deckSize')  AS self_deckSize,
        json_extract(selfState, '$.discardSize') AS self_discardSize,
        json_extract(oppState, '$[0].health')  AS opp_health,
        json_extract(oppState, '$[0].mastery') AS opp_mastery,
        json_extract(board, '$.infinityDeckCount') AS infinityDeckCount,
        -- SYNERGY: the actor's owned non-starter deck (JSON array of base card
        -- ids) at decision time — feeds card-pair covariance / faction synergy.
        json_extract(selfState, '$.ownedNonStarter') AS ownedNonStarter,
        options                                AS options,
        playerWon
      FROM decisions;
    ''');
  }

  // -------------------------------------------------------------------------
  // Writes
  // -------------------------------------------------------------------------

  int _now() => DateTime.now().millisecondsSinceEpoch;

  /// Record a compact OUTCOME event (design §2). Best-effort; disables the store
  /// on failure rather than throwing into the game loop.
  void recordEvent({
    required String gameId,
    required int turn,
    required int seat,
    required String playerId,
    required String type,
    String? cardId,
    String? cardName,
    String? faction,
    int? cost,
    int? amount,
    String? targetId,
    Map<String, dynamic>? meta,
  }) {
    if (!_enabled) return;
    _guarded(() {
      final stmt = _db!.prepare(
        'INSERT INTO events (ts, gameId, turn, seat, playerId, type, cardId, '
        'cardName, faction, cost, amount, targetId, meta) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
      );
      try {
        stmt.execute([
          _now(), gameId, turn, seat, playerId, type, cardId, cardName,
          faction, cost, amount, targetId,
          meta == null ? null : jsonEncode(meta),
        ]);
      } finally {
        stmt.close();
      }
    });
  }

  /// Record a rich (state -> choice) DECISION record (design §4b). [options],
  /// [selfState], [oppState], [board] are arbitrary JSON-encodable structures
  /// captured from the actor's OWN information set (see hidden-info rule above).
  void recordDecision({
    required String gameId,
    required int turn,
    required int seat,
    required String playerId,
    required String decisionType,
    required int chosenIndex,
    required List<dynamic> options,
    required Map<String, dynamic> selfState,
    required List<dynamic> oppState,
    required Map<String, dynamic> board,
  }) {
    if (!_enabled) return;
    _guarded(() {
      final stmt = _db!.prepare(
        'INSERT INTO decisions (ts, gameId, turn, seat, playerId, decisionType, '
        'chosenIndex, options, selfState, oppState, board, playerWon) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,NULL)',
      );
      try {
        stmt.execute([
          _now(), gameId, turn, seat, playerId, decisionType, chosenIndex,
          jsonEncode(options), jsonEncode(selfState), jsonEncode(oppState),
          jsonEncode(board),
        ]);
      } finally {
        stmt.close();
      }
    });
  }

  /// Record the start of a game (design §2 gameStart). [players] is a seat-ordered
  /// list of lobby player ids; we store [{seat, playerId}, ...].
  void recordGameStart({
    required String gameId,
    required List<String> players,
  }) {
    if (!_enabled) return;
    _guarded(() {
      final playersJson = jsonEncode([
        for (var i = 0; i < players.length; i++)
          {'seat': i, 'playerId': players[i]},
      ]);
      final stmt = _db!.prepare(
        'INSERT OR REPLACE INTO games '
        '(gameId, startedTs, endedTs, winnerId, winType, turns, players) '
        'VALUES (?,?,NULL,NULL,NULL,NULL,?)',
      );
      try {
        stmt.execute([gameId, _now(), playersJson]);
      } finally {
        stmt.close();
      }
    });
  }

  /// Record game end AND perform the supervised-label JOIN: stamp the games row
  /// with winner/winType/turns, then backfill `playerWon` on every decision in
  /// this game (1 where playerId == winnerId, else 0). [winnerId] may be null for
  /// a drawn/abandoned game (then every decision's playerWon is set to 0).
  void recordGameEnd({
    required String gameId,
    required String? winnerId,
    required String winType,
    required int turns,
  }) {
    if (!_enabled) return;
    _guarded(() {
      final up = _db!.prepare(
        'UPDATE games SET endedTs = ?, winnerId = ?, winType = ?, turns = ? '
        'WHERE gameId = ?',
      );
      try {
        up.execute([_now(), winnerId, winType, turns, gameId]);
      } finally {
        up.close();
      }
      // The supervised label join: mark each decision won/lost by its actor.
      // `playerId = winnerId` is NULL-safe in SQLite (NULL = x -> NULL -> 0).
      final join = _db!.prepare(
        'UPDATE decisions SET playerWon = '
        '(CASE WHEN playerId = ? THEN 1 ELSE 0 END) WHERE gameId = ?',
      );
      try {
        join.execute([winnerId, gameId]);
      } finally {
        join.close();
      }
    });
  }

  // -------------------------------------------------------------------------
  // Read helpers (small surface — mining is mostly raw SQL over the tables/view)
  // -------------------------------------------------------------------------

  /// Run a read-only SELECT and return the rows as maps (test/inspection helper).
  /// Returns an empty list if disabled or on error (never throws).
  List<Map<String, dynamic>> query(String sql, [List<Object?> params = const []]) {
    if (!_enabled) return const [];
    try {
      final rs = _db!.select(sql, params);
      return [for (final row in rs) Map<String, dynamic>.from(row)];
    } catch (e) {
      _log('WARNING: stats query failed ($e).');
      return const [];
    }
  }

  /// Close the underlying database. Safe to call on a disabled store.
  void close() {
    final db = _db;
    _db = null;
    _enabled = false;
    db?.close();
  }

  /// Run [write]; on any failure disable the store (so a flaky/locked db degrades
  /// to no-op telemetry instead of crashing the game loop) and log once.
  void _guarded(void Function() write) {
    try {
      write();
    } catch (e) {
      _enabled = false;
      _log('WARNING: a stats write failed ($e). Disabling further telemetry; '
          'the game continues unaffected.');
    }
  }
}
