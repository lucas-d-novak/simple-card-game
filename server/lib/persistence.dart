// Game persistence — snapshots in-progress games to disk so they survive a
// server restart. Today the Lobby is in-memory; without this, a restart drops
// every active game and reconnecting clients have nothing to resync into.
//
// STORAGE FORMAT (chosen: one JSON file per game in a flat directory):
//   <dir>/<gameId>.json  =  {
//     "schema": 1,
//     "id", "name", "hostId", "seats",          // LobbyGame metadata
//     "players": [lobbyId, ...],                 // seat order (the seat<->id map)
//     "status": "waiting" | "started" | "complete",
//     "stateVersion": <int>,                     // GameSession broadcast version
//     "game": { ...GameStateCodec.encode... }    // present iff a session exists
//   }
//
// Why JSON files (not sqlite): the project has NO third-party dependencies and
// prefers pure Dart. The engine ALREADY serializes a full game to JSON
// (GameStateCodec.encode/decode round-trips a complete game), so a per-game JSON
// file is the smallest robust thing that satisfies "survive restart" with zero
// native deps. Writes are atomic (temp file + rename) so a crash mid-write never
// corrupts the live snapshot. One file per game keeps writes independent and
// makes a corrupt single game skippable on load rather than poisoning everything.
//
// GRACEFUL DEGRADATION: if the directory is unwritable, the store logs once and
// becomes a no-op — the server runs in-memory exactly as before, never crashing.

import 'dart:convert';
import 'dart:io';

import 'package:shards_server/lobby.dart';
import 'package:simple_card_game/data/database/game_state_codec.dart';

/// Current on-disk schema version for a per-game snapshot file.
const int _snapshotSchema = 1;

/// A JSON-file-backed store: one `<gameId>.json` per game under [directory].
///
/// All methods are best-effort and non-throwing by contract: a disabled store
/// (unwritable directory) silently no-ops so the caller never has to branch.
class GamePersistence {
  GamePersistence._(this.directory, this._enabled, this._log);

  final Directory directory;
  bool _enabled;
  final void Function(String) _log;

  /// Whether snapshots are actually being written (false → in-memory only).
  bool get enabled => _enabled;

  /// Open (creating if needed) a store rooted at [path]. If the directory can't
  /// be created/written, returns a DISABLED store that no-ops every call and
  /// logs a single warning via [log] — the server then runs purely in-memory.
  factory GamePersistence.open(
    String path, {
    void Function(String)? log,
  }) {
    final logger = log ?? (String m) => stdout.writeln(m);
    final dir = Directory(path);
    try {
      dir.createSync(recursive: true);
      // Probe writability so we fail fast (and gracefully) at startup, not on
      // the first mid-game snapshot.
      final probe = File('${dir.path}/.write_probe');
      probe.writeAsStringSync('ok');
      probe.deleteSync();
      return GamePersistence._(dir, true, logger);
    } catch (e) {
      logger('WARNING: persistence disabled — cannot write to '
          '${dir.path} ($e). Running in-memory; games will NOT survive a '
          'restart.');
      return GamePersistence._(dir, false, logger);
    }
  }

  /// A store that never touches disk (explicit in-memory mode, used in tests
  /// and when persistence is turned off).
  factory GamePersistence.disabled() =>
      GamePersistence._(Directory('.'), false, (_) {});

  /// Path of the snapshot file for [gameId]. The id is SANITIZED to a safe
  /// filename (alphanumerics, `_`, `-` only) so it can never escape [directory]
  /// via `../` or path separators — defense-in-depth even though ids are
  /// server-generated (`game_N`) today.
  File _fileFor(String gameId) {
    final safe = gameId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${directory.path}/$safe.json');
  }

  /// Build the JSON snapshot map for [g] (metadata + the full encoded game when
  /// a session exists). Pure — no I/O — so it is unit-testable.
  static Map<String, dynamic> snapshotOf(LobbyGame g) => {
        'schema': _snapshotSchema,
        'id': g.id,
        'name': g.name,
        'hostId': g.hostId,
        'seats': g.seats,
        'players': List<String>.from(g.players),
        'status': g.status.name,
        if (g.session != null) 'stateVersion': g.session!.stateVersion,
        if (g.session != null) 'game': GameStateCodec.encode(g.session!.game),
      };

  /// Write [g]'s snapshot atomically (temp file + rename). No-ops if disabled.
  /// Never throws — an I/O failure logs once and disables further writes so a
  /// flaky disk degrades to in-memory instead of crashing the game loop.
  void save(LobbyGame g) {
    if (!_enabled) return;
    try {
      final json = jsonEncode(snapshotOf(g));
      final tmp = File('${_fileFor(g.id).path}.tmp');
      tmp.writeAsStringSync(json, flush: true);
      tmp.renameSync(_fileFor(g.id).path);
    } catch (e) {
      _enabled = false;
      _log('WARNING: failed to persist game ${g.id} ($e). '
          'Disabling further snapshots; continuing in-memory.');
    }
  }

  /// Remove a game's snapshot (e.g. on cleanup). No-ops if disabled or absent.
  void delete(String gameId) {
    if (!_enabled) return;
    try {
      final f = _fileFor(gameId);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // Best-effort: a failed delete just leaves a stale file, reloaded next
      // boot. Not worth disabling the store over.
    }
  }

  /// Load every persisted game back into [lobby], reconstructing each LobbyGame
  /// and (for started games) its GameSession via GameStateCodec.decode plus the
  /// saved seat<->id mapping and stateVersion.
  ///
  /// Restored games carry their own already-shuffled piles inside the decoded
  /// snapshot, so they don't need the lobby's market/Destiny supply to resume.
  ///
  /// Returns the number of games restored. A corrupt/unreadable single file is
  /// logged and SKIPPED (it never blocks the rest). No-ops (returns 0) if the
  /// store is disabled or the directory is missing.
  int loadInto(Lobby lobby) {
    if (!_enabled || !directory.existsSync()) return 0;
    var restored = 0;
    final files = directory
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    for (final f in files) {
      try {
        final map =
            (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>();
        if (lobby.restoreGame(map)) restored++;
      } catch (e) {
        _log('WARNING: skipping unreadable snapshot ${f.path} ($e).');
      }
    }
    if (restored > 0) {
      _log('Restored $restored persisted game(s) from ${directory.path}.');
    }
    return restored;
  }

  /// Default storage directory for the server process. The server runs from
  /// `server/`, so this resolves to `server/data/` (gitignored).
  static const String defaultDir = 'data';
}
