// Validates the authoritative card database (assets/card_db/cards.json).
//
// Run from the project root:
//   dart run tool/validate_card_db.dart
//
// Reports, per card: missing fields, effect-decoding errors, and verification
// status. Prints a per-set completeness summary against the known physical
// composition. Exits 1 if any HARD error (bad JSON, duplicate id, undecodable
// effect) is found; soft gaps (unverified / missing optional fields) exit 0.

import 'dart:convert';
import 'dart:io';

import 'package:simple_card_game/data/database/effect_codec.dart';

/// Known physical center-deck composition (unique-card targets are approximate;
/// these are total CARD counts per set, from the Saga Collection contents).
const Map<String, int> knownCenterDeckCounts = {
  'base': 88,
  'rotf': 24,
  'sos': 9,
  'ioh': 25,
  'ingeminex': 5,
  'promo': 5,
};

void main(List<String> args) {
  final path =
      args.isNotEmpty ? args.first : 'assets/card_db/cards.json';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('ERROR: $path not found');
    exit(1);
  }

  late final Map<String, dynamic> data;
  try {
    data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } on FormatException catch (e) {
    stderr.writeln('ERROR: invalid JSON in $path: $e');
    exit(1);
  }

  final cards = (data['cards'] as List<dynamic>? ?? const []);
  final hardErrors = <String>[];
  final softWarnings = <String>[];
  final seenIds = <String>{};
  final setCounts = <String, int>{};
  final setCopies = <String, int>{};
  var verifiedCount = 0;
  var withArt = 0;

  for (final raw in cards) {
    if (raw is! Map<String, dynamic>) {
      hardErrors.add('card entry is not an object: $raw');
      continue;
    }
    final id = raw['id'] as String?;
    final label = id ?? '(no id)';

    if (id == null || id.isEmpty) {
      hardErrors.add('$label: missing required "id"');
    } else {
      if (!RegExp(r'^[a-z0-9_]+$').hasMatch(id)) {
        hardErrors.add('$id: id must be lowercase letters/digits/underscores');
      }
      if (!seenIds.add(id)) {
        hardErrors.add('$id: duplicate id');
      }
    }

    // Try decoding effects — surfaces bad data loudly.
    for (final key in const ['playEffects', 'allyAbility', 'masteryBonus']) {
      try {
        decodeEffectList(raw[key]);
      } on FormatException catch (e) {
        hardErrors.add('$label: $key — $e');
      }
    }

    // Try decoding the optional Exhaust-gated activated ability.
    try {
      decodeActivatedAbility(raw['activatedAbility']);
    } on FormatException catch (e) {
      hardErrors.add('$label: activatedAbility — $e');
    }

    // Soft completeness checks.
    for (final key in const ['name', 'set', 'faction', 'cardType', 'cost']) {
      if (raw[key] == null) softWarnings.add('$label: missing "$key"');
    }
    final hasAnyEffect = (raw['playEffects'] as List?)?.isNotEmpty ?? false;
    if (!hasAnyEffect) {
      softWarnings.add('$label: no playEffects (placeholder?)');
    }
    if (raw['art'] == null) softWarnings.add('$label: no art');
    if (raw['verified'] == true) {
      verifiedCount++;
    } else {
      softWarnings.add('$label: not verified');
    }
    if (raw['art'] != null) withArt++;

    final set = (raw['set'] as String?) ?? 'unknown';
    setCounts[set] = (setCounts[set] ?? 0) + 1;
    setCopies[set] = (setCopies[set] ?? 0) + ((raw['copies'] as int?) ?? 1);
  }

  // ----- Report -----
  final total = cards.length;
  stdout.writeln('Card database: $path');
  stdout.writeln('  Total entries:   $total');
  stdout.writeln('  Verified:        $verifiedCount / $total');
  stdout.writeln('  With art:        $withArt / $total');
  stdout.writeln('');
  stdout.writeln('Per-set (unique entries / total copies / known copies):');
  final allSets = {...setCounts.keys, ...knownCenterDeckCounts.keys}.toList()
    ..sort();
  for (final set in allSets) {
    final unique = setCounts[set] ?? 0;
    final copies = setCopies[set] ?? 0;
    final known = knownCenterDeckCounts[set];
    final knownStr = known != null ? '$known' : '—';
    stdout.writeln('  ${set.padRight(11)} $unique uniq / $copies copies / '
        '$knownStr known');
  }
  stdout.writeln('');

  if (hardErrors.isNotEmpty) {
    stdout.writeln('HARD ERRORS (${hardErrors.length}):');
    for (final e in hardErrors) {
      stdout.writeln('  ✗ $e');
    }
    stdout.writeln('');
  }

  if (softWarnings.isNotEmpty) {
    stdout.writeln('GAPS (${softWarnings.length}) — incomplete but not fatal:');
    for (final w in softWarnings) {
      stdout.writeln('  • $w');
    }
    stdout.writeln('');
  }

  if (hardErrors.isNotEmpty) {
    stdout.writeln('RESULT: FAIL (${hardErrors.length} hard errors)');
    exit(1);
  }
  stdout.writeln('RESULT: OK (no hard errors; ${softWarnings.length} gaps to fill)');
}
