// Action protocol — client→server actions mapped to GameService methods, with
// authorization. The action vocabulary IS the engine's public method set.
//
// Authorization gates (ai-docs/multiplayer_architecture.md §3):
//  1. IDENTITY — the acting player is the authenticated connection's id; the
//     client cannot claim to act as someone else (we ignore any actor in the
//     payload and pass the connection's id).
//  2. TURN — the action is only allowed if it is that player's turn (the engine
//     also guards this, but we reject early for a clear error).
//  3. LEGALITY — the engine's own methods return false / no-op on an illegal
//     action; we surface that as a rejected result without mutating nothing.

import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/services/game_service.dart';

class ActionResult {
  ActionResult.ok() : accepted = true, error = null;
  ActionResult.reject(this.error) : accepted = false;

  final bool accepted;
  final String? error;
}

/// Apply [action] (a decoded message payload) to [game] on behalf of
/// [actingPlayerId] (the AUTHENTICATED connection id — never trust the payload
/// for identity). Returns whether the engine accepted it.
ActionResult applyAction(
  GameService game,
  String actingPlayerId,
  Map<String, dynamic> action,
) {
  final type = action['type'] as String?;
  if (type == null) return ActionResult.reject('missing action type');

  // TURN gate: only the current player may act (except read-only / none here).
  if (game.isGameOver) return ActionResult.reject('game is over');
  if (game.currentPlayer.id != actingPlayerId) {
    return ActionResult.reject('not your turn');
  }

  String s(String k) => action[k] as String? ?? '';
  int i(String k, [int dflt = 0]) => (action[k] as int?) ?? dflt;
  bool b(String k, [bool dflt = false]) => (action[k] as bool?) ?? dflt;

  bool ok;
  switch (type) {
    case 'playCard':
      ok = game.playCard(s('cardId'), choiceIndex: i('choiceIndex'));
    case 'playAllCards':
      game.playAllCards();
      ok = true;
    case 'buyCard':
      ok = game.buyCard(s('cardId'));
    case 'fastPlayMercenary':
      // Player-initiated: pay a center-row Mercenary's cost and play it
      // immediately (removed after). Distinct from 'fastPlayFromCenter' (the
      // FREE warp effect triggered by a card).
      ok = game.payAndFastPlayFromCenter(s('cardId'));
    case 'endTurn':
      game.endTurn();
      ok = true;
    case 'attackPlayer':
      ok = game.attackPlayer(s('targetId'), i('amount'));
    case 'attackChampion':
      ok = game.attackChampion(s('championId'), s('targetPlayerId'));
    case 'activateChampion':
      ok = game.activateChampion(s('championId'));
    case 'useActivatedAbility':
      ok = game.useActivatedAbility(s('championId'));
    case 'focus':
      ok = game.focus();
    case 'banishCard':
      ok = game.banishCard(s('cardId'), _banishSource(s('source')));
    case 'scrapFromCenterRow':
      ok = game.scrapFromCenterRow(s('cardId'));
    case 'destroyChampion':
      ok = game.destroyChampion(s('championId'), s('targetPlayerId'));
    case 'returnFromDiscard':
      ok = game.returnFromDiscard(s('cardId'));
    case 'resetChampion':
      ok = game.resetChampion(s('championId'));
    case 'recruitFromCenter':
      ok = game.recruitFromCenter(
        s('cardId'),
        free: b('free'),
        toHand: b('toHand'),
        toTopOfDeck: b('toTopOfDeck'),
      );
    case 'fastPlayFromCenter':
      ok = game.fastPlayFromCenter(s('cardId'));
    case 'copyPlayedCard':
      ok = game.copyPlayedCard(s('cardId'));
    case 'scryResolve':
      // The client sends the disposition it read off the card's ScryEffect (it
      // knows which scry is pending). Defaults to drawOrDiscard when absent.
      // `banishAfterPlay` is stricture/Chroma's "play and then banish" option.
      ok = game.scryResolve(
        s('cardId'),
        keep: b('keep'),
        disposition: _scryDisposition(s('disposition')),
        banishAfterPlay: b('banishAfterPlay'),
      );
    case 'centerDeckScryResolve':
      ok = game.centerDeckScryResolve(s('cardId'));
    case 'tuckUnderChampion':
      // Engine signature is (championId, cardId).
      ok = game.tuckUnderChampion(s('championId'), s('cardId'));
    // ---- Destiny / Relic (Into the Horizon / Relics of the Future) ----------
    // The turn gate above already applies; the engine re-checks all eligibility
    // (mastery thresholds, per-game claim allowance, relic-once, target present)
    // and no-ops on any illegal call, which we surface as a rejection.
    case 'claimDestiny':
      ok = game.claimDestiny(s('cardId'));
    case 'useDestinyAbility':
      ok = game.useDestinyAbility(s('cardId'));
    case 'recruitRelic':
      ok = game.recruitRelic(s('cardId'));
    // ---- Ingeminex (neutral co-op boss entity) -------------------------------
    case 'attackIngeminex':
      // Any player may hit the shared neutral entity on their turn (spends
      // power; the killing blow awards the reward). Turn gate above applies.
      ok = game.attackIngeminex(s('ingeminexId'), i('amount'));
    case 'spawnIngeminex':
      // Versus-adaptation summon entry point: bring a catalog boss into play on
      // your turn (its appearance hits ALL players, including you). Returns null
      // when the id isn't in the injected catalog → surfaced as illegal.
      ok = game.spawnIngeminexById(s('ingeminexId')) != null;
    case 'banishUpToFromAnyZone':
      // Desolation's deferred reward: banish up to 3 chosen cards from
      // hand/deck/discard, then shuffle. Always "succeeds" (0 is a valid choice).
      game.banishUpToFromAnyZone(
        (action['cardIds'] as List?)?.cast<String>() ?? const <String>[],
      );
      ok = true;
    case 'banishPairRecruit':
      // shard_cultist: banish this + a chosen hand card, recruit a center card
      // within their summed cost (Chroma may discardSelf instead of banishing).
      ok = game.banishPairAndRecruit(
        s('selfCardId'),
        s('otherCardId'),
        s('recruitCardId'),
        discardSelf: b('discardSelf'),
      );
    default:
      return ActionResult.reject('unknown action "$type"');
  }

  return ok ? ActionResult.ok() : ActionResult.reject('illegal action "$type"');
}

BanishSource _banishSource(String raw) {
  for (final v in BanishSource.values) {
    if (v.name == raw) return v;
  }
  return BanishSource.handOrDiscard;
}

ScryDisposition _scryDisposition(String raw) {
  for (final v in ScryDisposition.values) {
    if (v.name == raw) return v;
  }
  return ScryDisposition.drawOrDiscard;
}
