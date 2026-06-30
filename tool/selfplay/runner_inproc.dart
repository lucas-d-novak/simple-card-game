// Tier A self-play runner (in-process) — DEV-ONLY.
// See ai-docs/self_play_bots_design.md §0/§1/§7.
//
//   dart run tool/selfplay/runner_inproc.dart [--games N] [--seed-base S]
//       [--players P] [--mode greedy|explorer|mix] [--out DIR] [--quiet]
//
// Two bots play a real in-process GameService over and over. After every action
// the differential oracle (oracle.dart) runs invariants + the per-effect
// resource check; any finding is collected (deduped) into a replayable bug
// report (report.dart). Every game is SEEDED so each finding reproduces exactly.
//
// This is the bug-hunt harness (the primary goal). It runs ONLY in the dev
// environment via `dart run` — it is NOT bundled into the Flutter client or the
// multiplayer server, and reuses the engine in lib/ with no production changes.

import 'dart:io';
import 'dart:math';

import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/data/market_deck.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/services/game_service.dart';

import 'bot.dart';
import 'oracle.dart';
import 'report.dart';

Future<void> main(List<String> args) async {
  final opts = _Options.parse(args);

  // Load the authoritative card DB from disk (pure Dart — no Flutter rootBundle).
  final dbFile = File('assets/card_db/cards.json');
  if (!dbFile.existsSync()) {
    stderr.writeln('ERROR: ${dbFile.path} not found (run from project root).');
    exit(1);
  }
  final db = CardDatabase.fromJsonString(dbFile.readAsStringSync());
  final marketDeck = buildMarketDeckFromDatabase(db);
  final destinySupply = buildDestinySupplyFromDatabase(db);

  stdout.writeln('Self-play (Tier A, in-process)');
  stdout.writeln('  games=${opts.games} players=${opts.players} '
      'mode=${opts.mode} seedBase=${opts.seedBase}');
  stdout.writeln('  market=${marketDeck.length} unique cards, '
      'destinies=${destinySupply.length}');
  stdout.writeln('');

  final oracle = Oracle();
  final collector = BugCollector();

  var completed = 0;
  var aborted = 0;
  var totalActions = 0;
  final winTypes = <String, int>{};
  final stopwatch = Stopwatch()..start();

  for (var g = 0; g < opts.games; g++) {
    final seed = opts.seedBase + g;
    final mode = opts.modeForGame(g);
    final game = GameService(
      playerCount: opts.players,
      random: Random(seed),
      marketDeck: marketDeck,
      destinySupply: destinySupply,
    );

    final result = _playGame(
      game: game,
      seed: seed,
      mode: mode,
      oracle: oracle,
      collector: collector,
    );

    totalActions += result.actions;
    if (result.aborted) {
      aborted++;
    } else {
      completed++;
      final wt = game.winType ?? 'unknown';
      winTypes[wt] = (winTypes[wt] ?? 0) + 1;
    }

    if (!opts.quiet && (g + 1) % 100 == 0) {
      stdout.writeln('  ...${g + 1}/${opts.games} games '
          '(${collector.distinctBugs} distinct bugs so far)');
    }
  }

  stopwatch.stop();

  stdout.writeln('');
  stdout.writeln('Done in ${stopwatch.elapsed.inMilliseconds}ms.');
  stdout.writeln('  completed=$completed aborted=$aborted '
      'totalActions=$totalActions');
  stdout.writeln('  winTypes=$winTypes');
  stdout.writeln('');
  stdout.writeln(collector.summary());

  if (collector.distinctBugs > 0) {
    final n = collector.writeTo(opts.outDir);
    stdout.writeln('Wrote $n bug report(s) to ${opts.outDir}/');
    exit(2); // non-zero so a dev cron/CI run detects "bugs found"
  }
}

class _GameResult {
  _GameResult({required this.actions, required this.aborted});
  final int actions;
  final bool aborted;
}

/// Drive one whole game: step the current bot one action at a time, snapshotting
/// the whole game before and after each action so the oracle sees true deltas.
_GameResult _playGame({
  required GameService game,
  required int seed,
  required BotMode mode,
  required Oracle oracle,
  required BugCollector collector,
}) {
  final bots = <String, SelfPlayBot>{
    for (final p in game.players)
      p.id: SelfPlayBot(
        game: game,
        playerId: p.id,
        mode: mode,
        random: Random(seed ^ p.id.hashCode),
      ),
  };

  final actionSequence = <String>[];
  const maxTurns = 400; // hard cap so a non-terminating game can't hang the run
  const maxActionsPerTurn = 250;

  void report(OracleFinding f) {
    collector.add(BugReport(
      finding: f,
      seed: seed,
      actionIndex: actionSequence.length,
      actionSequence: List.of(actionSequence),
      actionLogTail: _logTail(game),
    ));
  }

  while (!game.isGameOver && game.turnNumber <= maxTurns) {
    final actorId = game.currentPlayer.id;
    final bot = bots[actorId]!;
    var actionsThisTurn = 0;
    var turnEnded = false;

    while (!turnEnded &&
        !game.isGameOver &&
        game.currentPlayer.id == actorId &&
        actionsThisTurn < maxActionsPerTurn) {
      final legal = bot.enumerateLegalActions();
      if (legal.isEmpty) {
        game.endTurn();
        actionSequence.add('endTurn(forced)');
        break;
      }

      final chosen =
          mode == BotMode.greedy ? bot.pickGreedy(legal) : bot.pickExplorer(legal);

      // Pre-snapshot + the pre-state facts the play oracle needs.
      final pre = GameSnapshot.capture(game);
      final preMastery = game.currentPlayer.mastery;
      final CardModel? card = chosen.card;
      final thresholdMet =
          card != null && masteryThresholdMetFor(card, preMastery);
      final allyTriggered = card != null && _allyWouldTrigger(game, card);
      final isPlay = chosen.label.startsWith('play:');

      bool accepted;
      try {
        accepted = chosen.apply();
      } catch (e, st) {
        report(OracleFinding(
          kind: 'invariant',
          message: 'Uncaught exception on ${chosen.label}: $e\n$st',
          card: card?.id,
        ));
        return _GameResult(actions: actionSequence.length, aborted: true);
      }

      if (!accepted) {
        // The engine rejected a move the bot believed legal. Often benign (a
        // guard blocked an attack), so we don't flag it — just count it so a
        // persistently-rejected action can't spin forever.
        actionsThisTurn++;
        if (actionsThisTurn >= maxActionsPerTurn) game.endTurn();
        continue;
      }

      actionSequence.add(chosen.label);
      actionsThisTurn++;
      if (chosen.label == 'endTurn') turnEnded = true;

      final post = GameSnapshot.capture(game);

      for (final f in oracle.checkInvariants(pre, post, chosen.label)) {
        report(f);
      }
      if (isPlay && card != null) {
        for (final f in oracle.checkPlay(
          pre: pre,
          post: post,
          card: card,
          masteryThresholdMet: thresholdMet,
          allyTriggered: allyTriggered,
        )) {
          report(f);
        }
      }
    }

    if (!turnEnded &&
        !game.isGameOver &&
        game.currentPlayer.id == actorId) {
      game.endTurn();
      actionSequence.add('endTurn(cap)');
    }
  }

  final aborted = !game.isGameOver && game.turnNumber > maxTurns;
  return _GameResult(actions: actionSequence.length, aborted: aborted);
}

/// Mirror of the engine's ally-trigger precondition (so the play oracle knows
/// whether allyAbility resolved). An ally ability triggers when another
/// same-faction card is already in play at play time.
bool _allyWouldTrigger(GameService game, CardModel card) {
  if (card.allyAbility.isEmpty) return false;
  final p = game.currentPlayer;
  final inPlay = [...p.playedThisTurn, ...p.championsInPlay];
  if (card.countsAsAllFactions) return inPlay.isNotEmpty;
  return inPlay.any((c) =>
      c.id != card.id &&
      (c.faction == card.faction || c.countsAsAllFactions));
}

List<String> _logTail(GameService game) {
  final log = game.actionLog;
  final tail = log.length > 12 ? log.sublist(log.length - 12) : log;
  return tail.map((e) => e.message).toList();
}

// ---------------------------------------------------------------------------
// CLI options
// ---------------------------------------------------------------------------

class _Options {
  _Options({
    required this.games,
    required this.seedBase,
    required this.players,
    required this.mode,
    required this.outDir,
    required this.quiet,
  });

  final int games;
  final int seedBase;
  final int players;
  final String mode; // greedy | explorer | mix
  final String outDir;
  final bool quiet;

  BotMode modeForGame(int g) {
    switch (mode) {
      case 'greedy':
        return BotMode.greedy;
      case 'explorer':
        return BotMode.explorer;
      case 'mix':
      default:
        return g.isEven ? BotMode.greedy : BotMode.explorer;
    }
  }

  static _Options parse(List<String> args) {
    var games = 200;
    var seedBase = 1;
    var players = 2;
    var mode = 'mix';
    var outDir = 'tool/selfplay/bug_reports';
    var quiet = false;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--games':
          games = int.parse(args[++i]);
        case '--seed-base':
          seedBase = int.parse(args[++i]);
        case '--players':
          players = int.parse(args[++i]);
        case '--mode':
          mode = args[++i];
        case '--out':
          outDir = args[++i];
        case '--quiet':
          quiet = true;
      }
    }
    return _Options(
      games: games,
      seedBase: seedBase,
      players: players,
      mode: mode,
      outDir: outDir,
      quiet: quiet,
    );
  }
}
