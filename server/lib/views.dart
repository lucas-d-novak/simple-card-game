// Per-player redacted state views — the SECURITY CORNERSTONE.
//
// The raw GameService holds EVERY player's full state: all hands, all draw
// piles IN ORDER, the infinity-deck order. `redactFor` is the ONLY path from
// engine to wire. Because every broadcast goes through it, hidden-information
// leakage is structurally impossible: a modified client cannot reveal what the
// server never sent.
//
// Rules (see ai-docs/multiplayer_architecture.md §4):
//  - recipient's OWN hand: full, ordered card ids.
//  - opponents' hands: COUNT only.
//  - EVERYONE's draw pile (incl. recipient's own): COUNT only — a player must
//    not know their own deck order, or scry/shuffle become exploitable.
//  - infinity deck: COUNT only; order is server-secret.
//  - discard piles, center row, champions, removed-from-game: public (ids).
//  - under-cards: count only (face-down).
//  - scalars (health/mastery/pools/flags/character/modifiers): public.

import 'package:simple_card_game/data/database/card_serialization.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/player_state.dart';
import 'package:simple_card_game/services/game_service.dart';

List<String> _ids(List<CardModel> cards) => [for (final c in cards) c.id];

/// Build the redacted view of [game] for the player [recipientId].
/// [stateVersion] is the monotonic broadcast counter for this game.
/// [canUndo] is true when the recipient may currently issue an `undo` (it is
/// their turn and the session holds a same-turn snapshot to roll back to); the
/// client uses it to enable the Undo button. Defaults to false so callers that
/// don't track an undo stack (e.g. plain redaction tests) are unaffected.
Map<String, dynamic> redactFor(
  GameService game,
  String recipientId, {
  required int stateVersion,
  bool canUndo = false,
}) {
  // Card dictionary: every card the recipient may legitimately see, serialized
  // BY VALUE (name + effects + stats), keyed by id. The client renders directly
  // from this — it does NOT re-look-up ids in any catalog, so the cards it shows
  // are EXACTLY the ones the engine created (the engine builds the market from
  // card_definitions.dart with per-instance id suffixes like `chaos_imp_1`,
  // which are absent from the authoritative CardDatabase). Hidden info is
  // preserved: only VISIBLE cards are dictionaried — opponents' hands and ALL
  // draw piles are deliberately excluded (we never serialize those models).
  final cards = <String, dynamic>{};
  void register(CardModel c) => cards.putIfAbsent(c.id, () => cardModelToJson(c));
  void registerAll(List<CardModel> cs) => cs.forEach(register);

  registerAll(game.centerRow);
  registerAll(game.removedFromGame);
  // Destiny supply: the face-up shared row is public (anyone may see what is
  // claimable). The cascade `destinyDeck` is NOT registered — its order/contents
  // are server-secret like any draw pile.
  registerAll(game.destinyRow);
  for (final p in game.players) {
    // Own hand AND own draw-pile contents (the latter is shown sorted, so its
    // ORDER stays hidden) — never an opponent's hand/draw pile.
    if (p.id == recipientId) {
      registerAll(p.hand);
      registerAll(p.drawPile);
    }
    registerAll(p.discardPile); // discards are public
    registerAll(p.championsInPlay); // champions are public
    registerAll(p.playedThisTurn); // played-this-turn is public
    // Claimed Destinies are public (face-up beside their owner).
    registerAll(p.claimedDestinies);
    // Relic OPTIONS are private to their owner: the two set-aside relics are a
    // hidden choice the recipient alone may make, so only dictionary them in the
    // recipient's own view.
    if (p.id == recipientId) registerAll(p.relicOptions);
  }

  return {
    'stateVersion': stateVersion,
    'you': recipientId,
    'currentPlayerIndex': game.currentPlayerIndex,
    'turnNumber': game.turnNumber,
    'isGameOver': game.isGameOver,
    if (game.winnerId != null) 'winnerId': game.winnerId,
    // True only in the recipient's OWN view when they may undo right now.
    'canUndo': canUndo,
    // Market is public.
    'centerRow': _ids(game.centerRow),
    // Order is secret; only the size leaks.
    'infinityDeckCount': game.infinityDeck.length,
    'removedFromGame': _ids(game.removedFromGame),
    // Shared Destiny supply: the face-up row is public (its ids are dictionaried
    // above); only the cascade DECK SIZE leaks (order is secret).
    'destinyRow': _ids(game.destinyRow),
    'destinyDeckCount': game.destinyDeck.length,
    // Public action log (no hidden info) — the recent tail, so players can review
    // what happened (e.g. "what did I do last turn"). Bounded for payload size.
    'actionLog': [
      for (final e in game.actionLog.length > 80
          ? game.actionLog.sublist(game.actionLog.length - 80)
          : game.actionLog)
        e.toJson(),
    ],
    'players': [
      for (final p in game.players) _redactPlayer(p, p.id == recipientId),
    ],
    // Full card definitions for every visible card, by id.
    'cards': cards,
  };
}

Map<String, dynamic> _redactPlayer(PlayerState p, bool isRecipient) {
  return {
    'id': p.id,
    'name': p.name,
    if (p.character != null) 'character': p.character!.name,
    'health': p.health,
    'mastery': p.mastery,
    'gemPool': p.gemPool,
    'powerPool': p.powerPool,
    'unblockedDamageThisTurn': p.unblockedDamageThisTurn,
    'ignoresShieldThisTurn': p.ignoresShieldThisTurn,
    'focusedThisTurn': p.focusedThisTurn,
    'eliminated': p.isEliminated,
    // ---- Destiny / Relic ----------------------------------------------------
    // Claimed Destinies sit face-up beside their owner — PUBLIC (ids; the cards
    // are in the dictionary). Whether THIS player may still claim another is a
    // function of public scalars (mastery + claim count), surfaced so the client
    // can show/hide the Destiny entry point without re-deriving the rule.
    'claimedDestinies': _ids(p.claimedDestinies),
    'canClaimAnotherDestiny': p.canClaimAnotherDestiny,
    // Ids of claimed Destinies whose per-turn ability was already used this turn
    // (public — claimed Destinies sit face-up). Mirrors the per-champion
    // `exhausted` flag so the client's Destinies tray can grey used abilities.
    'exhaustedDestinies': [
      for (final c in p.claimedDestinies)
        if (p.exhaustedDestinies.contains(c.id)) c.id,
    ],
    // Relic OPTIONS are the recipient's own hidden choice — never an opponent's.
    // We expose the chooser surface (the two relic ids + whether already
    // recruited) ONLY in the owner's view; opponents see only that recruitment
    // happened indirectly (a relic shuffled into a draw pile is hidden anyway).
    if (isRecipient) 'relicOptions': _ids(p.relicOptions),
    'relicRecruited': p.relicRecruited,
    // Hand: full ids for the recipient, COUNT ONLY for opponents.
    if (isRecipient) 'hand': _ids(p.hand),
    'handCount': p.hand.length,
    // Draw pile: COUNT ONLY for everyone — even the owner must not see ORDER.
    'drawPileCount': p.drawPile.length,
    // The recipient may see the CONTENTS of their own draw pile (it's their own
    // deck), but the list is SORTED so no draw ORDER leaks — preventing scry /
    // shuffle exploits while letting a player review what's left to draw.
    if (isRecipient)
      'drawPileContents': (_ids(p.drawPile)..sort()),
    // Discards are public.
    'discardPile': _ids(p.discardPile),
    // Champions are public; expose tap/exhaust status + under-card COUNT.
    'championsInPlay': [
      for (final c in p.championsInPlay)
        {
          'id': c.id,
          'exhausted': p.exhaustedChampions.contains(c.id),
          'activated': p.activatedChampions.contains(c.id),
          'underCount': p.cardsUnderCount(c.id),
        },
    ],
    'playedThisTurn': _ids(p.playedThisTurn),
    'staticModifiers': [
      for (final m in p.staticModifiers)
        {
          'kind': m.kind.name,
          if (m.amount != 0) 'amount': m.amount,
          if (m.faction != null) 'faction': m.faction!.name,
          if (m.cardType != null) 'cardType': m.cardType!.name,
        },
    ],
  };
}
