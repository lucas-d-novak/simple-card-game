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

import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/player_state.dart';
import 'package:simple_card_game/services/game_service.dart';

List<String> _ids(List<CardModel> cards) => [for (final c in cards) c.id];

/// Build the redacted view of [game] for the player [recipientId].
/// [stateVersion] is the monotonic broadcast counter for this game.
Map<String, dynamic> redactFor(
  GameService game,
  String recipientId, {
  required int stateVersion,
}) {
  return {
    'stateVersion': stateVersion,
    'you': recipientId,
    'currentPlayerIndex': game.currentPlayerIndex,
    'turnNumber': game.turnNumber,
    'isGameOver': game.isGameOver,
    if (game.winnerId != null) 'winnerId': game.winnerId,
    // Market is public.
    'centerRow': _ids(game.centerRow),
    // Order is secret; only the size leaks.
    'infinityDeckCount': game.infinityDeck.length,
    'removedFromGame': _ids(game.removedFromGame),
    'players': [
      for (final p in game.players) _redactPlayer(p, p.id == recipientId),
    ],
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
    'eliminated': p.isEliminated,
    // Hand: full ids for the recipient, COUNT ONLY for opponents.
    if (isRecipient) 'hand': _ids(p.hand),
    'handCount': p.hand.length,
    // Draw pile: COUNT ONLY for everyone — even the owner must not see order.
    'drawPileCount': p.drawPile.length,
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
