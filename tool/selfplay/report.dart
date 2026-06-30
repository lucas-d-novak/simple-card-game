// Bug-report aggregation + writer — dev-only.
// See ai-docs/self_play_bots_design.md §5.
//
// Every oracle finding is replayable: it carries the game seed + the action
// sequence up to the failure, so a flagged bug is a one-command repro. Findings
// are DEDUPED by (kind, card, effect) so a scale run that hits the same bug 500
// times produces ONE grouped report with a count + an example repro, not 500
// rows. That dedup is what makes a scale run actionable.

import 'dart:convert';
import 'dart:io';

import 'oracle.dart';

/// A finding enriched with everything needed to reproduce it.
class BugReport {
  BugReport({
    required this.finding,
    required this.seed,
    required this.actionIndex,
    required this.actionSequence,
    required this.actionLogTail,
  });

  final OracleFinding finding;
  final int seed;
  final int actionIndex;
  final List<String> actionSequence;
  final List<String> actionLogTail;

  /// The dedup key: same bug class collapses to one entry.
  String get dedupKey =>
      '${finding.kind}|${finding.card ?? '-'}|${finding.effect ?? '-'}';

  Map<String, dynamic> toJson() => {
        'kind': finding.kind,
        'message': finding.message,
        if (finding.card != null) 'card': finding.card,
        if (finding.effect != null) 'effect': finding.effect,
        if (finding.expectedDelta != null)
          'expectedDelta': finding.expectedDelta,
        if (finding.actualDelta != null) 'actualDelta': finding.actualDelta,
        'seed': seed,
        'actionIndex': actionIndex,
        'actionSequence': actionSequence,
        'actionLog': actionLogTail,
      };
}

/// Collects + dedups findings across a whole run.
class BugCollector {
  final Map<String, _Group> _groups = {};

  void add(BugReport report) {
    final g = _groups.putIfAbsent(
      report.dedupKey,
      () => _Group(example: report),
    );
    g.count++;
    // Keep the SHORTEST repro as the canonical example (easiest to debug).
    if (report.actionSequence.length < g.example.actionSequence.length) {
      g.example = report;
    }
  }

  int get distinctBugs => _groups.length;
  int get totalHits =>
      _groups.values.fold(0, (sum, g) => sum + g.count);

  /// A human-readable console summary.
  String summary() {
    if (_groups.isEmpty) return 'No bugs found.';
    final b = StringBuffer();
    b.writeln('Found $distinctBugs distinct bug(s) across $totalHits hit(s):');
    final sorted = _groups.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    for (final g in sorted) {
      b.writeln('  [${g.count.toString().padLeft(5)}x] '
          '${g.example.finding.kind}: ${g.example.finding.message}');
      b.writeln('          repro: seed=${g.example.seed} '
          'actionIndex=${g.example.actionIndex} '
          '(${g.example.actionSequence.length} actions)');
    }
    return b.toString();
  }

  /// Write one JSON file per distinct bug into [dir] (created if needed).
  /// Returns the number of files written.
  int writeTo(String dir) {
    if (_groups.isEmpty) return 0;
    final d = Directory(dir);
    d.createSync(recursive: true);
    var n = 0;
    final sorted = _groups.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    for (final g in sorted) {
      final json = g.example.toJson();
      json['hitCount'] = g.count;
      final safe = g.example.dedupKey
          .replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')
          .substring(0, g.example.dedupKey.length.clamp(0, 80));
      final f = File('$dir/${n.toString().padLeft(3, '0')}_$safe.json');
      f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
      n++;
    }
    return n;
  }
}

class _Group {
  _Group({required this.example});
  BugReport example;
  int count = 0;
}
