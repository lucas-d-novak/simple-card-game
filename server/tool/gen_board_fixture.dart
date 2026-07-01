// Dev-only: generate a realistic redacted-board fixture for visual iteration.
//
// Builds a mid-game GameService from the REAL market deck (so card ids resolve
// to real art), advances it into an interesting state (a hand, a champion in
// play, some played cards, opponent with a champion), then writes the exact
// `redactFor` JSON the server would ship to player p0. The Flutter `?netboard=1`
// route loads this asset into a fake GameClient to render NetworkGameScreen with
// real art — no server/socket needed.
//
//   dart run server/tool/gen_board_fixture.dart
//   -> writes assets/fixtures/net_board.json
//
// Re-run whenever the redacted-view shape or the desired scenario changes.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shards_server/views.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/data/market_deck.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/services/game_service.dart';

void main() {
  final db = CardDatabase.fromJsonString(
      File('assets/card_db/cards.json').readAsStringSync());
  final market = buildMarketDeckFromDatabase(db);
  final destinies = buildDestinySupplyFromDatabase(db);

  // Deterministic so the fixture is stable across runs.
  final game = GameService(
    playerCount: 2,
    random: Random(7),
    marketDeck: market,
    destinySupply: destinies,
  );

  // Drive a couple of turns of simple play so the deck cycles + mastery builds.
  for (var turn = 0; turn < 2; turn++) {
    final me = game.currentPlayer;
    game.playAllCards();
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
    game.endTurn();
  }

  // To render a REALISTIC, populated board (not an empty opening), directly seed
  // an interesting mid-game scene from the real market pool:
  //  - each player has a Champion in play (so the play field isn't empty)
  //  - the active player has some cards played this turn (a developed board)
  //  - the active player's hand holds a RECRUITED real card (not only starters)
  // This is a VISUAL fixture; it doesn't need to be a reachable game — just a
  // faithful redacted-state shape for the UI to render.
  CardModel? pull(bool Function(CardModel card) test) {
    final idx = game.infinityDeck.indexWhere(test);
    if (idx == -1) return null;
    return game.infinityDeck.removeAt(idx);
  }

  // The player we'll ship the view for = whoever is active now.
  final me = game.currentPlayer;
  final opp = game.players.firstWhere((p) => p.id != me.id);

  // A champion for each player (so the play field isn't empty).
  final champMe = pull((CardModel c) => c.shield > 0 && c.name.isNotEmpty);
  final champOpp = pull((CardModel c) => c.shield > 0 && c.name.isNotEmpty);
  if (champMe != null) me.championsInPlay.add(champMe);
  if (champOpp != null) opp.championsInPlay.add(champOpp);

  // A couple of non-champion cards the active player has played this turn.
  for (var i = 0; i < 2; i++) {
    final played = pull((CardModel c) => c.shield == 0 && c.name.isNotEmpty);
    if (played != null) {
      me.playedThisTurn.add(played);
      me.cardsPlayedThisTurn.add(played);
    }
  }

  // A recruited real card sitting in the active player's hand, so the hand isn't
  // only starter cards — the clearest test of "can players see their cards".
  final recruited = pull((CardModel c) => c.name.isNotEmpty && c.cost >= 2);
  if (recruited != null) me.hand.add(recruited);

  final view = redactFor(game, me.id, stateVersion: 1);

  final outDir = Directory('assets/fixtures');
  outDir.createSync(recursive: true);
  final out = File('assets/fixtures/net_board.json');
  out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(view));

  final players = view['players'] as List;
  final meView = players.firstWhere((p) => p['id'] == view['you']) as Map;
  stdout.writeln('Wrote ${out.path}');
  stdout.writeln('  you=${view['you']} turn=${view['turnNumber']} '
      'hand=${(meView['hand'] as List).length} '
      'champions=${(meView['champions'] as List?)?.length ?? 0} '
      'centerRow=${(view['centerRow'] as List).length}');
}
