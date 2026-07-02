// Multiplayer serialization / redaction PERF BASELINE — dev-only, read-only.
//
// Measures the per-action server hot path WITHOUT touching engine/server/UI
// source. For each configuration it drives a real in-process GameService to a
// target game length with a compact greedy driver (mirrors AiService/
// gen_board_fixture, minus the 300ms UI phase delays), then times and sizes:
//
//   * GameStateCodec.encode(game)        — the UNDO snapshot taken once per
//                                          non-endTurn action in GameSession.apply
//   * redactFor(game, recipient)         — per-recipient hidden-info filter
//                                          (called N times per accepted action)
//   * jsonEncode(view)                    — wire serialization per recipient
//   * jsonDecode(payload)                 — client-side parse of one view
//
// It reports the PER-ACTION broadcast cost (N recipients) and the payload SIZE
// (bytes) both per recipient and summed across recipients (= bytes on the wire
// per action), and how these scale with player count (2 vs 4) and game length.
//
//   cd server && dart run tool/perf/redaction_bench.dart
//   cd server && dart run tool/perf/redaction_bench.dart --iters 400 --json
//
// A per-recipient view is a FULL redacted snapshot — the server ships full state
// every action (no deltas), so "per action" and "full resync" are the same bytes
// per recipient. This script exists to catch regressions in that hot path.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shards_server/views.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/data/database/game_state_codec.dart';
import 'package:simple_card_game/data/market_deck.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/services/game_service.dart';

int _iters = 200;
bool _jsonOut = false;

void main(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--iters':
        _iters = int.parse(args[++i]);
      case '--json':
        _jsonOut = true;
    }
  }

  // Resolve the card DB relative to this script (run from server/ or repo root).
  final dbFile = _findDb();
  final db = CardDatabase.fromJsonString(dbFile.readAsStringSync());
  final market = buildMarketDeckFromDatabase(db);
  final destinies = buildDestinySupplyFromDatabase(db);

  final configs = <_Cfg>[
    _Cfg(players: 2, turns: 4, label: '2p early'),
    _Cfg(players: 2, turns: 12, label: '2p mid'),
    _Cfg(players: 2, turns: 24, label: '2p late'),
    _Cfg(players: 4, turns: 4, label: '4p early'),
    _Cfg(players: 4, turns: 16, label: '4p mid'),
    _Cfg(players: 4, turns: 32, label: '4p late'),
  ];

  final results = <Map<String, dynamic>>[];
  for (final cfg in configs) {
    results.add(_measure(cfg, market, destinies));
  }

  if (_jsonOut) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'iters': _iters,
      'results': results,
    }));
    return;
  }

  _printTable(results);
}

File _findDb() {
  for (final p in ['assets/card_db/cards.json', '../assets/card_db/cards.json']) {
    final f = File(p);
    if (f.existsSync()) return f;
  }
  stderr.writeln('ERROR: cards.json not found (run from server/ or repo root).');
  exit(1);
}

class _Cfg {
  _Cfg({required this.players, required this.turns, required this.label});
  final int players;
  final int turns;
  final String label;
}

Map<String, dynamic> _measure(
  _Cfg cfg,
  List<MarketCard> market,
  List<CardModel> destinies,
) {
  // Build a representative state. Use a fixed seed so runs are comparable.
  final game = _drive(
    players: cfg.players,
    targetTurns: cfg.turns,
    market: market,
    destinies: destinies,
    seed: 7,
  );

  final recipients = [for (final p in game.players) p.id];

  // ---- GameStateCodec.encode (undo snapshot; once per non-endTurn action) ----
  // Warm up.
  for (var i = 0; i < 20; i++) {
    GameStateCodec.encode(game);
  }
  final swEncode = Stopwatch()..start();
  Map<String, dynamic> encoded = const {};
  for (var i = 0; i < _iters; i++) {
    encoded = GameStateCodec.encode(game);
  }
  swEncode.stop();
  final encodeUs = swEncode.elapsedMicroseconds / _iters;
  final encodeBytes = utf8.encode(jsonEncode(encoded)).length;

  // ---- redactFor per recipient (called N times per accepted action) ----
  for (var i = 0; i < 20; i++) {
    redactFor(game, recipients.first, stateVersion: 1);
  }
  final swRedactAll = Stopwatch()..start();
  for (var i = 0; i < _iters; i++) {
    for (final r in recipients) {
      redactFor(game, r, stateVersion: i);
    }
  }
  swRedactAll.stop();
  final redactPerRecipientUs =
      swRedactAll.elapsedMicroseconds / (_iters * recipients.length);
  final redactAllRecipientsUs = swRedactAll.elapsedMicroseconds / _iters;

  // ---- jsonEncode per recipient view + payload sizes ----
  var wireBytesAll = 0;
  final perRecipientBytes = <int>[];
  final swJson = Stopwatch()..start();
  for (var i = 0; i < _iters; i++) {
    for (final r in recipients) {
      final view = redactFor(game, r, stateVersion: i);
      final s = jsonEncode(view);
      if (i == 0) perRecipientBytes.add(utf8.encode(s).length);
    }
  }
  swJson.stop();
  // Time for redactFor+jsonEncode across all recipients, per action.
  final redactPlusJsonAllUs = swJson.elapsedMicroseconds / _iters;
  // Isolate jsonEncode cost: subtract the redact-only time.
  final jsonOnlyAllUs =
      (redactPlusJsonAllUs - redactAllRecipientsUs).clamp(0, double.infinity);
  for (final b in perRecipientBytes) {
    wireBytesAll += b;
  }
  final oneViewBytes =
      perRecipientBytes.isEmpty ? 0 : perRecipientBytes.first;

  // ---- client parse (jsonDecode) of one recipient view ----
  final oneViewStr = jsonEncode(redactFor(game, recipients.first, stateVersion: 1));
  for (var i = 0; i < 20; i++) {
    jsonDecode(oneViewStr);
  }
  final swParse = Stopwatch()..start();
  for (var i = 0; i < _iters; i++) {
    jsonDecode(oneViewStr);
  }
  swParse.stop();
  final parseUs = swParse.elapsedMicroseconds / _iters;

  // ---- state characterization ----
  final oneView =
      redactFor(game, recipients.first, stateVersion: 1);
  final cardDictSize = (oneView['cards'] as Map).length;
  final encodeCardDictSize = (encoded['cards'] as Map).length;
  var totalDraw = 0, totalDiscard = 0, totalHand = 0, totalChamps = 0;
  for (final p in game.players) {
    totalDraw += p.drawPile.length;
    totalDiscard += p.discardPile.length;
    totalHand += p.hand.length;
    totalChamps += p.championsInPlay.length;
  }

  return {
    'label': cfg.label,
    'players': cfg.players,
    'turnNumber': game.turnNumber,
    'infinityDeck': game.infinityDeck.length,
    'totalDraw': totalDraw,
    'totalDiscard': totalDiscard,
    'totalHand': totalHand,
    'totalChampions': totalChamps,
    'actionLogLen': game.actionLog.length,
    'encodeCardDict': encodeCardDictSize,
    'viewCardDict': cardDictSize,
    'encode_us': _round(encodeUs),
    'encode_fullSnapshot_bytes': encodeBytes,
    'redact_perRecipient_us': _round(redactPerRecipientUs),
    'redact_allRecipients_us': _round(redactAllRecipientsUs),
    'jsonEncode_allRecipients_us': _round(jsonOnlyAllUs.toDouble()),
    'perAction_serialize_us':
        _round(encodeUs + redactPlusJsonAllUs), // encode + redact+json all
    'oneView_bytes': oneViewBytes,
    'wire_perAction_bytes': wireBytesAll, // sum across recipients
    'clientParse_oneView_us': _round(parseUs),
  };
}

/// Greedy synchronous driver: play all, activate champions, buy most-expensive
/// affordable, focus, attack, end turn — until [targetTurns] or game over.
GameService _drive({
  required int players,
  required int targetTurns,
  required List<MarketCard> market,
  required List<CardModel> destinies,
  required int seed,
}) {
  final game = GameService(
    playerCount: players,
    random: Random(seed),
    marketDeck: market,
    destinySupply: destinies,
  );
  var guard = 0;
  while (!game.isGameOver &&
      game.turnNumber < targetTurns &&
      guard++ < 5000) {
    final me = game.currentPlayer;
    game.playAllCards();
    // Activate champions (free once-per-turn) for a developed board.
    for (final c in List.of(me.championsInPlay)) {
      game.activateChampion(c.id);
    }
    // Buy most-expensive affordable, repeat.
    var bought = true;
    while (bought) {
      bought = false;
      final affordable = game.centerRow
          .where((c) => c.cost <= game.currentPlayer.gemPool)
          .toList()
        ..sort((a, b) => b.cost.compareTo(a.cost));
      if (affordable.isNotEmpty) {
        bought = game.buyCard(affordable.first.id);
      }
    }
    if (me.gemPool >= 1) game.focus();
    // Attack the weakest living opponent with any power (keeps HP dynamic but
    // avoids ending the game too early for late-game measurements).
    if (me.powerPool > 0) {
      final targets = game.players
          .where((p) => p.id != me.id && !p.isEliminated)
          .toList()
        ..sort((a, b) => a.health.compareTo(b.health));
      if (targets.isNotEmpty && targetTurns > 8) {
        game.attackPlayer(targets.first.id, min(me.powerPool, 3));
      }
    }
    game.endTurn();
  }
  return game;
}

double _round(num v) => (v * 100).round() / 100;

void _printTable(List<Map<String, dynamic>> rows) {
  String kb(int b) => '${(b / 1024).toStringAsFixed(1)}KB';
  stdout.writeln('=== Serialization / redaction baseline '
      '(Pi 4B, iters=$_iters) ===\n');
  for (final r in rows) {
    stdout.writeln('${r['label']}  (turn ${r['turnNumber']}, '
        'players ${r['players']})');
    stdout.writeln('  state: infinityDeck=${r['infinityDeck']} '
        'draw=${r['totalDraw']} discard=${r['totalDiscard']} '
        'hand=${r['totalHand']} champs=${r['totalChampions']} '
        'log=${r['actionLogLen']} cardDict(view)=${r['viewCardDict']}');
    stdout.writeln('  encode(undo snapshot):    '
        '${r['encode_us']}us  full=${kb(r['encode_fullSnapshot_bytes'] as int)}');
    stdout.writeln('  redactFor/recipient:      '
        '${r['redact_perRecipient_us']}us   '
        'x${r['players']} recipients=${r['redact_allRecipients_us']}us');
    stdout.writeln('  jsonEncode all views:     '
        '${r['jsonEncode_allRecipients_us']}us');
    stdout.writeln('  >> per-action serialize:  '
        '${r['perAction_serialize_us']}us  (encode + redact*N + json*N)');
    stdout.writeln('  payload: oneView=${kb(r['oneView_bytes'] as int)}  '
        'wire/action(all recipients)=${kb(r['wire_perAction_bytes'] as int)}');
    stdout.writeln('  client parse oneView:     '
        '${r['clientParse_oneView_us']}us\n');
  }
}
