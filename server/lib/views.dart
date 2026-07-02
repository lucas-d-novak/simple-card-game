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
import 'package:simple_card_game/models/card_effect.dart';
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
  Map<String, String> names = const {},
}) {
  // Display name for an engine seat id: the lobby username when known, else the
  // seat id itself (`p0`). So the board shows real usernames, not seats.
  String displayName(String seatId) => names[seatId] ?? seatId;
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
    // Fast-played / warped cards, kept visible (greyed) in the play area for the
    // rest of the turn. Public — they were played face-up.
    registerAll(p.fastPlayedThisTurn);
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
    // winnerId stays the SEAT id (`p0`) — the client matches it against player
    // ids and its own `you` for the game-over screen. The username is carried on
    // each player's `name` (below), so the UI shows the real name.
    if (game.winnerId != null) 'winnerId': game.winnerId,
    // HOW the game was won — 'mastery' (Infinity Shard at 30) / 'elimination' /
    // 'draw' (mutual knockout). Public (not hidden info); drives the win
    // flourish + game-over copy on the networked board.
    if (game.winType != null) 'winType': game.winType,
    // Most recent direct player-vs-player damage event, so every client
    // (attacker AND victim) can play the SAME attack animation deterministically
    // once. Public info (attacker, victim and amount of a direct attack are all
    // board-visible), so shipping this leaks nothing hidden. `seq` is a
    // monotonic high-water mark the client uses to fire the animation exactly
    // once per event; `fromName`/`toName` are resolved to usernames here (the
    // seat ids are also kept so the client can match against its own `you`).
    if (game.lastDamage != null)
      'lastDamage': {
        'seq': game.lastDamage!.seq,
        'fromId': game.lastDamage!.fromId,
        'toId': game.lastDamage!.toId,
        'fromName': displayName(game.lastDamage!.fromId),
        'toName': displayName(game.lastDamage!.toId),
        'amount': game.lastDamage!.amount,
      },
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
    // what happened (e.g. "what did I do last turn") and the playback overlay can
    // show a mini card. Bounded for payload size.
    //
    // HIDDEN-INFO SAFETY: a log entry's optional `cardId` is only kept when that
    // card is CURRENTLY in a public, dictionaried zone (played/champion/discard/
    // removed/center). A card that has since moved to a hidden zone (e.g. a played
    // card shuffled back into a draw pile) has its cardId STRIPPED here, so the
    // wire never carries an id the recipient couldn't otherwise resolve. The
    // message text is unchanged (the card name was already public when logged).
    // Rewrite seat ids (`p0`) to usernames in BOTH the actor field and the
    // message text (some engine messages embed a target/winner seat name, e.g.
    // "destroyed p0's champion", "p0 wins!"), so the log reads with real names.
    'actionLog': [
      for (final e in game.actionLog.length > 80
          ? game.actionLog.sublist(game.actionLog.length - 80)
          : game.actionLog)
        () {
          final j = (e.cardId != null && !cards.containsKey(e.cardId))
              ? (e.toJson()..remove('cardId'))
              : e.toJson();
          if (j['message'] is String) {
            j['message'] = _namifyMessage(j['message'] as String, names);
          }
          return j;
        }(),
    ],
    'players': [
      for (final p in game.players)
        _redactPlayer(p, p.id == recipientId, displayName(p.id)),
    ],
    // Full card definitions for every visible card, by id.
    'cards': cards,
  };
}

/// Replace engine seat ids (`p0`, `p1`, …) with lobby usernames in a log
/// message, so lines that embed a target/winner seat name ("destroyed p0's
/// champion", "p0 wins!") read with real names. Word-boundary matched so a seat
/// id is only swapped as a standalone token (e.g. never inside another word).
/// Longer ids are replaced first so `p10` isn't partially matched by `p1`.
String _namifyMessage(String message, Map<String, String> names) {
  if (names.isEmpty) return message;
  final seatIds = names.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  var out = message;
  for (final seatId in seatIds) {
    final name = names[seatId]!;
    if (name == seatId) continue;
    out = out.replaceAllMapped(
      RegExp('(?<![A-Za-z0-9])${RegExp.escape(seatId)}(?![A-Za-z0-9])'),
      (_) => name,
    );
  }
  return out;
}

Map<String, dynamic> _redactPlayer(
    PlayerState p, bool isRecipient, String displayName) {
  return {
    'id': p.id,
    // The lobby username (falls back to the seat id when unknown). The engine
    // seat `id` stays `p0` above for turn/winner matching.
    'name': displayName,
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
    // Cards fast-played / warped this turn (free warp or paid mercenary
    // fast-play). They were removed-from-game rules-wise but are kept VISIBLE in
    // the play area this turn so the player can see they were played and why they
    // aren't in discard. The UI should render these tiles GREYED OUT. Public
    // (they were played face-up); the ids are dictionaried in `cards` above.
    'fastPlayedThisTurn': _ids(p.fastPlayedThisTurn),
    'staticModifiers': [
      for (final m in p.staticModifiers)
        {
          'kind': m.kind.name,
          if (m.amount != 0) 'amount': m.amount,
          if (m.faction != null) 'faction': m.faction!.name,
          if (m.cardType != null) 'cardType': m.cardType!.name,
          // The champion INSTANCE that sources this modifier (self-scoped
          // buffs like shieldPerCardUnder, and zetta_the_encryptor's
          // cannotBeAttacked aura, which exempts its OWN source champion).
          // Public, NOT a hidden-info leak: every player's champions are
          // already registered into the shared `cards` dict for ALL
          // recipients above (`registerAll(p.championsInPlay)`), so this id
          // is already board-visible. Without it a client-side attack-gating
          // mirror can't tell the source champion (still attackable) from the
          // ones the aura protects. Mirrors GameStateCodec._encodeStaticModifier.
          if (m.sourceChampionId != null) 'sourceChampionId': m.sourceChampionId,
          // Conditional cannotBeAttacked descriptor (scope / condition / named
          // champion) — all PUBLIC board info (the champion's printed ability
          // text is face-up), so a client can grey/label an unattackable
          // champion. Mirrors GameStateCodec._encodeStaticModifier; omitted when
          // at the defaults (unconditional player aura).
          if (m.cannotBeAttackedScope !=
              CannotBeAttackedScope.playerAndOtherChampions)
            'cannotBeAttackedScope': m.cannotBeAttackedScope.name,
          if (m.cannotBeAttackedCondition != CannotBeAttackedCondition.always)
            'cannotBeAttackedCondition': m.cannotBeAttackedCondition.name,
          if (m.conditionCardName != null)
            'conditionCardName': m.conditionCardName,
        },
    ],
  };
}
