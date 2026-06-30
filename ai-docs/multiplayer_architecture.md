# Multiplayer Architecture

**Status:** Phase 0/1 implemented (`server/`); Phases 2/3 design-ready.
**Scope:** Online, turn-based, 2–4 player Shards of Infinity over the network.
**Model:** Authoritative server. The server runs the real game engine; clients
are untrusted thin terminals that send *actions* and render *state*.

> **Implemented since this doc was first written.** The serialization dependency
> below is **done** (`lib/data/database/game_state_codec.dart` +
> `card_serialization.dart`), and the Phase 0/1 server is live in `server/`. On
> top of the original design it also has: same-turn server-authoritative **undo**
> (per-game undo stack, `canUndo` flag in the redacted view, `undo` action),
> **reconnect/resync** (`Lobby.activeGameForPlayer` + per-player resync on
> `identify`/`hello`), per-game **rejoin** (`resyncGame`), custom game **names**
> (`LobbyGame.name`, `createGame(name:)`), multi-game membership
> (`activeGamesForPlayer`), and a redacted **card dictionary** (`view.cards`,
> id→full `CardModel` by value) so the client renders exact engine cards without
> re-deriving them from a catalog. These are called out inline below.

This doc designs to decisions already made — they are not relitigated here:

- **Authoritative server.** The server holds the single source of truth
  (`GameService`). Clients never run game rules that matter; they send actions,
  the server validates + applies + broadcasts.
- **Self-hosted origin.** A Raspberry Pi behind a Cloudflare Tunnel with a
  custom domain. Low budget. Intermittent uptime acceptable at first, always-on
  eventually.
- **Target UX.** The official client's "Online" lobby (Your Games / More Games /
  Create Game), turn-based 2–4 player games, shared cross-device state. See
  [`design_reference/05_online_lobby.png`](design_reference/05_online_lobby.png).

> **Hard dependency.** This entire design assumes `toJson`/`fromJson` exists for
> the engine's models (`GameService`, `PlayerState`, `CardModel`-as-id,
> `CardEffect` is *not* serialized — cards travel as ids). That serialization
> work is happening in parallel. Sections [5](#5-serialization) and
> [10](#10-phased-rollout) call out exactly what blocks on it.

---

## 1. Topology & stack

### Recommendation: one Dart engine package, two runtimes

The single most important architectural lever is that **`lib/` is already pure
Dart with no game-rule dependency on Flutter.** `GameService`, `PlayerState`,
`CardModel`, `CardEffect`, and `AiService` import only `dart:math` and each
other. That means the *exact same rules code* can run on a `dart:io` server and
in the Flutter client. There is one implementation of the rules, ever. No
TypeScript port, no rule drift, no "the server thinks the attack is legal but
the client greyed out the button."

```
                        ┌─────────────────────────────┐
                        │   Shared Dart engine (lib/)  │
                        │  GameService, PlayerState,   │
                        │  CardModel, CardEffect, AI   │
                        └───────┬──────────────┬───────┘
                                │ imports      │ imports
                  ┌─────────────▼───┐     ┌────▼──────────────┐
                  │  server/  (new) │     │  Flutter client   │
                  │  dart:io,       │     │  ui/ + net layer  │
                  │  WebSocket,     │     │  (this repo)      │
                  │  SQLite, AI     │     │                   │
                  └─────────────────┘     └───────────────────┘
```

**Why a Dart server (not Node/Go/Firebase):**

- **Rule reuse is the whole game.** The engine is the hard part and it's already
  written in Dart. Any non-Dart server re-implements `_resolveEffects`'s 31-case
  switch, `_factionsMatch` aliasing, mastery tiers, guard, under-cards, static
  modifiers… and keeps them in sync forever. That is the bug factory we avoid.
- **Deterministic engine.** `GameService(random: Random(seed))` already gives a
  seeded, reproducible engine — ideal for an authoritative server (replay,
  audit, identical results).
- **Low-budget self-host.** `dart compile exe` produces a single
  self-contained native binary that runs great on a Raspberry Pi (ARM64). No
  runtime to install, no container required, ~tens of MB RAM for dozens of
  idle turn-based games.
- **Firebase/Supabase rejected.** They'd push rule logic to client-side security
  rules or cloud functions (rule drift again), add recurring cost, and don't fit
  "Pi behind a tunnel." We want the engine on the box we control.

### Code organization

Add a `server/` directory at the repo root that depends on the existing package:

```
simple-card-game/
├── lib/                      # engine (shared) + Flutter UI
├── server/
│   ├── pubspec.yaml          # depends on simple_card_game via path: ../
│   ├── bin/server.dart       # dart:io entrypoint (HttpServer + WebSocket)
│   ├── lib/
│   │   ├── game_session.dart # wraps one GameService + connected sockets
│   │   ├── lobby.dart        # game registry, matchmaking
│   │   ├── protocol.dart     # envelope + action/event codecs
│   │   ├── views.dart        # per-player redaction (hidden-info filter)
│   │   ├── store.dart        # SQLite persistence
│   │   └── auth.dart         # device-token auth
│   └── test/
```

> **One refactor blocks server reuse: `CardDatabase`.**
> `lib/data/database/card_database.dart` imports
> `package:flutter/services.dart` for `rootBundle` (the asset loader). A
> `dart:io` server has no `rootBundle`. **Split the loader from the parser:**
> keep `CardDatabase.fromJsonString(String)` (already pure Dart) as the core,
> and move the Flutter `rootBundle.load` call into a thin
> `card_database_flutter.dart` the app uses. The server reads `cards.json` from
> disk with `File(...).readAsString()` and calls `fromJsonString`. This is a
> small, mechanical change and it's the only Flutter coupling in the rules path.

### Where the Pi sits

```
 Player devices (phone / web / desktop)
        │  wss://game.example.com/ws        (TLS terminated by Cloudflare edge)
        ▼
 ┌──────────────────────┐   encrypted tunnel, outbound-only
 │  Cloudflare edge      │◄───────────────────────────────────┐
 │  (TLS, DDoS, DNS)     │                                     │
 └──────────────────────┘                                     │
                                                   ┌───────────┴──────────┐
                                                   │  Raspberry Pi (LAN)   │
                                                   │  cloudflared (tunnel) │
                                                   │      │ http://127.0.0.1:8080
                                                   │  game-server (exe)    │
                                                   │  + sqlite file        │
                                                   └──────────────────────┘
```

- **Cloudflare Tunnel (`cloudflared`).** The Pi makes an **outbound** persistent
  connection to Cloudflare; no inbound ports, no port-forwarding, no exposed
  home IP. Cloudflare provides TLS + the custom domain + basic DDoS protection
  for free.
- **TLS.** Terminated at the Cloudflare edge. Client speaks `wss://`. Inside the
  tunnel, the server can listen plain HTTP on `127.0.0.1:8080`.
- **WebSocket support.** Cloudflare Tunnel proxies WebSockets natively (it's a
  supported, default behaviour). The server upgrades `HTTP GET /ws` →
  WebSocket; the tunnel passes the upgrade through transparently.
- **Custom domain.** A CNAME/`tunnel` route maps `game.example.com` → the tunnel
  → `http://localhost:8080`. Configured in `cloudflared`'s `config.yml` (see
  [§9](#9-deployops-on-the-pi)).

---

## 2. Transport

### WebSocket, full stop

Use a **single persistent WebSocket per connected client**. Justification vs. the
alternatives for *this* workload:

| Option | Verdict |
|--------|---------|
| **WebSocket** | **Chosen.** Bidirectional, low-latency push. The server must *push* "it's your turn now" and "opponent attacked you" without the client asking. One connection, framed messages, trivial JSON. |
| HTTP polling | Rejected. The defining server→client event ("opponent moved") would arrive only on the next poll — laggy and wasteful. Turn-based tolerates latency, but polling burns the Pi's modest CPU and battery on phones for nothing. |
| SSE | Rejected. Server→client only; we'd still need POSTs for actions, so two channels to manage. WS gives both directions over one socket. |
| gRPC / custom TCP | Rejected. Overkill; harder through Cloudflare; harder to debug. JSON-over-WS is readable in browser devtools. |

Turn-based means message frequency is *low* (a handful of messages per turn), so
WebSocket's overhead is negligible and its simplicity wins.

### Message envelope

Every frame in either direction is a JSON object with a fixed envelope. `type`
discriminates; `seq` orders; `ts` is for logging/debug.

```json
{
  "v": 1,
  "type": "action",
  "seq": 42,
  "ts": 1719600000000,
  "gameId": "g_7Q2K",
  "payload": { }
}
```

- `v` — protocol version (bump on breaking changes; server can reject mismatches).
- `type` — one of: `action`, `state`, `event`, `error`, `ack`, `ping`, `pong`,
  `hello`, `lobby` (see [§6](#6-lobby--matchmaking)).
- `seq` — monotonically increasing per connection. The server echoes the
  client's `seq` in its `ack`/`error` so the client can correlate a response to
  the action it sent.
- `gameId` — present for in-game messages; absent for lobby/auth.
- `payload` — type-specific (action body, redacted state, etc.).

### Heartbeat / keepalive

- Server sends `ping` every **30 s**; client replies `pong`. Client may also
  ping if idle.
- No `pong` within **2 missed intervals (~75 s)** → server marks the connection
  dead, closes the socket, and flags the player **disconnected** (not abandoned —
  see [§7](#7-reconnect--disconnect)).
- Cloudflare Tunnel and most NATs idle-timeout long-lived sockets; a 30 s ping
  keeps the path warm.

---

## 3. Action protocol

### The action vocabulary *is* `GameService`'s public methods

The client→server `action` payloads map **1:1** onto the engine's public action
methods. The client never invents semantics; it names a method and supplies
params plus the acting player's id.

```json
{
  "v": 1, "type": "action", "seq": 42, "gameId": "g_7Q2K",
  "payload": {
    "actor": "p1",
    "action": "playCard",
    "args": { "cardId": "crystal_3", "choiceIndex": 0 }
  }
}
```

The full action set (each maps to the identically-named `GameService` method):

| `action` | args | Engine method |
|----------|------|---------------|
| `playCard` | `cardId`, `choiceIndex?` | `playCard` |
| `playAllCards` | — | `playAllCards` |
| `buyCard` | `cardId` | `buyCard` |
| `focus` | — | `focus` (spend 1 gem → 1 mastery, Character Focus) |
| `undo` | — | session-level same-turn rollback (see [§7](#7-reconnect--disconnect)) |
| `endTurn` | — | `endTurn` |
| `attackPlayer` | `targetPlayerId`, `amount` | `attackPlayer` |
| `attackChampion` | `championId`, `targetPlayerId` | `attackChampion` |
| `activateChampion` | `championId` | `activateChampion` |
| `useActivatedAbility` | `championId` | `useActivatedAbility` |
| `banishCard` | `cardId`, `source` | `banishCard` |
| `scrapFromCenterRow` | `cardId` | `scrapFromCenterRow` |
| `destroyChampion` | `championId`, `targetPlayerId` | `destroyChampion` |
| `returnFromDiscard` | `cardId`, `filter`, `faction?` | `returnFromDiscard` |
| `scryResolve` | `cardId`, `keep`, `disposition` | `scryResolve` |
| `centerDeckScryResolve` | `cardId`, `disposition` | `centerDeckScryResolve` |
| `copyPlayedCard` | `cardId`, `filter`, `faction?` | `copyPlayedCard` |
| `tuckUnderChampion` | `championId`, `cardId`, `alliesOnly?` | `tuckUnderChampion` |
| `copyUnderCards` | `championId` | `copyUnderCards` |
| `resetChampion` | `championId` | `resetChampion` |
| `recruitFromCenter` | `cardId`, `free`, `maxCost?`, `toHand?`, `toTopOfDeck?` | `recruitFromCenter` |
| `fastPlayFromCenter` | `cardId`, `maxCost?`, `alliesOnly?` | `fastPlayFromCenter` |

(`scryReveal`/`centerDeckScryReveal` are *read* helpers, not state
mutations — see deferred selection below.)

> **Not yet wired to the protocol.** The engine has gained `claimDestiny`,
> `useDestinyAbility`, `banishDestinyToCascade`, and `recruitRelic` (the Destiny
> and Relics subsystems — see
> [`shards_of_infinity_mechanics.md`](shards_of_infinity_mechanics.md) §25), but
> `server/lib/protocol.dart` does not yet expose them as wire actions. They work
> in the local Flutter client today; adding them is a localized addition to the
> action `switch` plus the same auth gates.

### Authorization: the server's two gates

When an `action` arrives, the server runs it through two checks **before** ever
touching the engine:

1. **Identity gate — "is this really player N?"** The connection is bound to an
   authenticated `playerId` (from the `hello`/auth handshake, [§8](#8-security--anti-cheat)).
   The server **ignores `payload.actor` and substitutes the connection's
   authenticated id.** A client cannot act as someone else by lying in the body.

2. **Turn gate — "is it your turn?"** The server checks
   `game.players[game.currentPlayerIndex].id == connectionPlayerId`. If not, it
   replies with an `error` (`code: "NOT_YOUR_TURN"`) and does **not** call the
   engine. (Exception: none today — all listed actions are current-player-only.
   If future cards add reactive/interrupt actions for the non-active player, this
   gate gets a per-action allowlist; the architecture already routes every action
   through here, so that's a localized change.)

3. **Legality gate — the engine itself.** Every `GameService` action method is
   already a *guarded, all-or-nothing* operation: it returns `false`/no-op and
   mutates nothing when the move is illegal (wrong zone, unaffordable, guard
   blocks the attack, game over, etc.). The server **trusts the engine's return
   value as the authority on legality.** It does not re-derive rules. Pattern:

   ```dart
   // server: applying one action
   final before = session.engine.snapshotHash();      // cheap integrity marker
   final ok = session.dispatch(action);               // calls the named method
   if (!ok) {
     conn.send(Envelope.error(seq, code: 'ILLEGAL', msg: 'rejected by engine'));
     return; // no broadcast: state did not change
   }
   session.store.save(session);                       // persist new state
   session.broadcastState();                          // push redacted views (§4)
   ```

   Because the engine never half-applies an illegal action, a rejected action is
   a clean no-op and the server simply tells the offender "no."

### Deferred-selection actions (the multi-step interactions)

Several effects can't resolve in one shot: the engine resolves the triggering
card to a **no-op placeholder** and exposes a follow-up method the player calls
after choosing a target. These are: `BanishCardEffect`, `ScrapFromCenterRowEffect`,
`DestroyChampionEffect` (single), `ReturnFromDiscardEffect`, `ScryEffect`,
`CenterDeckScryEffect`, `CopyPlayedCardEffect`, `RecruitFromCenterEffect`,
`FastPlayFromCenterEffect`, `TuckUnderChampionEffect` (hand), `ResetChampionEffect`,
`CopyUnderCardsEffect`.

**The protocol does not need a special "pending selection" state machine on the
wire** — and this is deliberate. Each follow-up is just another `action` against
the same turn, guarded by the same gates, and validated by the engine method's
own preconditions. The sequence over the wire for, e.g., a Scry card:

```
client → action playCard {cardId: keeper_of_datic_vessels}
server →  state (snapshot; the ScryEffect resolved to a no-op, nothing visible changed)
          event {kind: "selectionRequired", action: "scryResolve",
                 reveal: [{cardId:"vine_guardian_1"}], hint:"drawOrDiscard"}
client → action scryReveal? (optional read — server may instead inline the reveal
          in the event above so the client needs no extra round-trip)
client → action scryResolve {cardId:"vine_guardian_1", keep:true,
          disposition:"drawOrDiscard"}
server →  state (snapshot reflecting the resolution)
```

Key design points:

- **Reveal data rides on the prompting `event`.** Rather than a separate
  `scryReveal` round-trip, the server runs `scryReveal()` / `centerDeckScryReveal()`
  *for the acting player only* and embeds the revealed card ids in the
  `selectionRequired` event. (These reveals are *private*: scry shows the acting
  player their own deck top — never broadcast to opponents.)
- **The server emits `selectionRequired` by inspecting the engine after the
  triggering action.** The cleanest mechanism: the engine's deferred effects are
  enumerable (they're explicit `CardEffect` subtypes on the just-played card).
  The server's `session.dispatch` post-step scans the resolved card's effect
  list for deferred types and, for each, emits the matching prompt. (A small
  helper on the server — *not* a rules change — walks `card.playEffects` for the
  deferred subtypes.)
- **No partial turn lock.** If a client never sends the follow-up (e.g. they
  decline an optional banish), nothing is stuck: the engine never entered a
  half-state, and the player can simply continue or `endTurn`. Optional
  selections are genuinely optional; mandatory ones the UI enforces, but the
  *server* tolerates the player moving on (the unredeemed effect just didn't
  happen, exactly as in solo play today).

This is the big payoff of reusing the engine: the awkward multi-step card
interactions are already modeled correctly in solo play, and the network layer
is a thin courier on top.

---

## 4. State sync (server → client)

### Recommendation: full-state snapshots, per-player redacted

For a turn-based game with low message frequency, **send a full (redacted)
state snapshot after every state change.** Do **not** build a delta protocol.

Why snapshots:

- **Simplicity & correctness.** A snapshot is self-describing; there's no risk of
  a client drifting out of sync because it missed or misapplied a delta. After
  any action the client *replaces* its view wholesale.
- **Cheap here.** A full game state is small (4 players × a few dozen card *ids* +
  scalar pools). A snapshot is a few KB of JSON, a few times per turn. Deltas
  would optimize bandwidth that isn't a problem while adding a whole class of
  bugs.
- **Reconnect is free.** "Resync" and "normal update" are the same message — a
  reconnecting client just gets the current snapshot ([§7](#7-reconnect--disconnect)).

A `state` message:

```json
{
  "v": 1, "type": "state", "seq": 0, "gameId": "g_7Q2K",
  "payload": {
    "stateVersion": 87,        // increments on every applied action
    "view": { ...redacted GameState for THIS recipient... }
  }
}
```

`stateVersion` lets the client discard an out-of-order/stale snapshot (keep the
highest it has seen).

### CRITICAL: hidden information — per-player filtered views

This is the **single most important correctness-and-security requirement in the
whole system.** The engine's `GameService` holds *everyone's* full state:
every hand, every draw pile **in order**, every discard, the infinity deck order.
If the server serialized the raw `GameService` and broadcast it, every client
would see every opponent's hand and could compute the entire future of every
deck. That is total information leakage and the death of the game.

**Therefore: the server NEVER serializes the raw engine to a client. It always
produces a per-recipient redacted view.** For recipient `p`, the filter is:

| State | What `p` sees |
|-------|---------------|
| `p`'s own `hand` | **Full** — card ids, ordered. |
| Opponents' `hand` | **Count only** (`handCount: 3`). No ids. |
| `p`'s own `drawPile` | **Count only** — `p` must NOT know their own deck order either (otherwise scry/shuffle are meaningless and a cheating client predicts draws). Exception: an active *scry/reveal* reveals exactly the peeked top cards to `p`, delivered via the `selectionRequired` event ([§3](#3-action-protocol)), never in the broadcast snapshot. |
| Opponents' `drawPile` | **Count only.** |
| `infinityDeck` | **Count only.** Order is server-secret. `centerDeckScryReveal` reveals the single top card to the acting player only. |
| `discardPile` (all players) | **Full** — discards are public in Shards. Ordered list of card ids. |
| `centerRow` | **Full** — the market is public; card ids. |
| `championsInPlay` (all) | **Full** — champions are public; ids + per-champion `exhausted`/`activated`/`underCount`. |
| `cardsUnderChampion` | **Count only** to everyone (face-down tucked cards). The *owner* may see ids of cards they tucked from hand if the official rules allow it; default to count-only — safest. |
| `removedFromGame` | **Full** (or omit; it's reference-only and public). |
| Scalars: `health`, `mastery`, `gemPool`, `powerPool`, `unblockedDamageThisTurn`, `staticModifiers`, `character`, `activatedChampions`, `exhaustedChampions` | **Full for all players** — these are public game state. |
| `currentPlayerIndex`, `turnNumber`, `isGameOver`, `winnerId` | **Full** — public. |

The filter is the implemented pure function
`redactFor(GameService game, String recipientId, {required int stateVersion, bool canUndo})`
in [`server/lib/views.dart`](../server/lib/views.dart). It runs once per recipient
per broadcast. Because it's the *only* path from engine to wire, hidden-info
leakage is structurally impossible: there is no code path that ships an
unredacted hand or deck order.

> **Implemented additions to the wire view.** The shipped `redactFor` also
> carries, beyond the table above:
> - **`cards`** — a dictionary `id → full CardModel (by value)` for *every card
>   the recipient may legitimately see* (own hand, all discards, center row,
>   champions, played-this-turn, removed-from-game). The client renders straight
>   from this rather than re-deriving cards from a catalog, so it shows the
>   *exact* engine cards (the engine mints per-instance ids like `chaos_imp_1`
>   that aren't in the authoritative `CardDatabase`). Hidden info is preserved:
>   opponents' hands and **all** draw piles are deliberately excluded from the
>   dictionary — those models are never serialized.
> - **`canUndo`** — true only in the recipient's own view when they may issue an
>   `undo` right now (their turn + the session holds a same-turn rollback
>   snapshot); drives the client's Undo button. See [§7](#7-reconnect--disconnect).
> - **`focusedThisTurn`** / **`ignoresShieldThisTurn`** per-player flags, and
>   **`playedThisTurn`** (public card ids), surfacing the Focus action and the
>   played-this-turn zone added to the engine.

> **Anti-cheat note (expanded in [§8](#8-security--anti-cheat)):** redaction is
> not a UI nicety, it is the primary anti-cheat. A modified client cannot reveal
> what the server never sent. Hand contents and deck order simply do not exist on
> the wire.

### Example redacted view (recipient = `p1`)

`p1` sees their own hand; `p0`'s hand is a count; nobody's deck order leaks.

```json
{
  "stateVersion": 87,
  "you": "p1",
  "currentPlayerIndex": 1,
  "turnNumber": 6,
  "isGameOver": false,
  "winnerId": null,
  "centerRow": ["reactor_monk_2","chaos_imp_0","vine_guardian_1",
                "shield_bearer_3","neural_relay_0","blood_ritualist_1"],
  "infinityDeckCount": 122,
  "removedFromGameCount": 4,
  "players": [
    {
      "id": "p0", "name": "korvus", "character": "fervor",
      "health": 41, "mastery": 12, "gemPool": 0, "powerPool": 0,
      "handCount": 4,
      "drawPileCount": 9,
      "discardPile": ["crystal_0","crystal_1","blaster_0"],
      "championsInPlay": [
        {"id":"kor_arbiter_1","exhausted":false,"activated":false,"underCount":0}
      ],
      "staticModifiers": [],
      "eliminated": false
    },
    {
      "id": "p1", "name": "you", "character": "convergence",
      "health": 47, "mastery": 9, "gemPool": 3, "powerPool": 5,
      "hand": ["crystal_2","reactor_monk_2","leaf_dancer_0","crystal_5",
               "infinity_shard_0"],          // ← full, ordered: p1's own hand
      "handCount": 5,
      "drawPileCount": 7,                     // ← own deck: COUNT ONLY
      "discardPile": ["crystal_3","crystal_4","shard_reactor_0"],
      "championsInPlay": [],
      "staticModifiers": [
        {"kind":"cardCostReduction","amount":1,"faction":"undergrowth"}
      ],
      "eliminated": false
    }
  ]
}
```

Note what is **absent**: `p0.hand` ids, anyone's `drawPile` ids, `infinityDeck`
ids/order. Those never leave the server.

---

## 5. Serialization

> **This section depends on the parallel `toJson`/`fromJson` work.** It specifies
> the *wire shape* that work must produce; it does not assume any specific
> internal implementation beyond "models can serialize."

### Cards on the wire are just ids

The single biggest payload lever: **a card is its `id` string and nothing else.**
`CardDatabase.byId(id)` rehydrates the full `CardModel` (cost, faction, type,
shield, the entire `playEffects` / `allyAbility` / `masteryBonus` / `activatedAbility`
effect trees) on both sides. The client already loads `cards.json`; so does the
server. Therefore:

- **Never serialize `CardEffect`.** Effect trees are large, recursive
  (`ChooseOneEffect`, `ConditionalEffect`), and identical for every copy of a
  card. Sending them per-message would bloat payloads 10–50×. The wire carries
  `"reactor_monk_2"`; the receiver looks up the rest.
- **Card *instance* ids vs. template ids.** The engine mints per-copy ids like
  `"${templateId}_$copy"` (e.g. `reactor_monk_2`). The wire uses these instance
  ids so a specific physical card is addressable across zones. To rehydrate the
  model, strip the `_$copy` suffix back to the template id for the
  `CardDatabase.byId` lookup (or have the server send a one-time
  `instanceId → templateId` note; the suffix-strip is simpler and already
  deterministic).
- **Starter-deck cards** (`crystal_*`, `blaster_*`, `infinity_shard_*`,
  `shard_reactor_*`) are the one wrinkle: they have *player-scoped instance ids*
  (`p0_crystal_3`) and are built fresh by the starter-deck builder — they are NOT
  in `CardDatabase`, so `byId` + suffix-strip does NOT recover them. Two clean
  options: (a) the wire view sends only the **public** cards a recipient may see
  (center row, discards, champions) which ARE all catalog cards rehydratable by
  id, and represents the recipient's own hand by id where those too are catalog
  cards — for starter cards in hand, fall back to (b); or (b) include a small
  **card dictionary** (id → value) for any referenced non-catalog card, exactly
  as the implemented `GameStateCodec` already does for the full snapshot.

> **Reconciliation with the implemented serialization
> (`lib/data/database/game_state_codec.dart`):** there are TWO serializers and
> they are different on purpose. (1) The **authoritative full snapshot**
> (`GameStateCodec.encode/decode`) — used for SQLite persistence + reconnect
> rebuild — serializes every distinct card *by value* into a card dictionary and
> references by id. It is full-fidelity, server-side only, and never sent to a
> client. (2) The **redacted per-player wire view** (`redactFor`, to build) is
> derived from the engine and ships ids (+ a tiny dictionary only for any
> referenced non-catalog/starter card a recipient is allowed to see). Cards never
> ship their effect trees on the wire; the full snapshot's dictionary stays on
> the box.

### What gets serialized

Only **structure + scalars + ids**:

- Per-player scalars (`health`, `mastery`, pools, flags, `character`).
- Zone membership as **lists/counts of card ids** (redacted per [§4](#4-state-sync-server--client)).
- `staticModifiers` (small value objects: kind/amount/faction/cardType).
- `championsInPlay` enriched with `exhausted`/`activated`/`underCount` booleans.
- Game scalars (`currentPlayerIndex`, `turnNumber`, `isGameOver`, `winnerId`,
  `stateVersion`).

### RNG / deck order: server-authoritative, never shipped

This is the serialization rule that protects hidden info at the source:

- **The server constructs the engine with a secret seed:**
  `GameService(playerCount: n, random: Random(secretSeed))`. The seed and the
  resulting shuffle order are **server-only state.**
- **The seed is NEVER sent to any client.** A client with the seed could replay
  every shuffle and know all future draws. The seed lives only in the server
  process (and, for crash recovery, encrypted/at-rest in the server's SQLite —
  not in any client-visible column).
- **Deck *order* is never serialized to a client.** Clients get `drawPileCount`
  and `infinityDeckCount` only (see [§4](#4-state-sync-server--client)). The
  ordered `drawPile`/`infinityDeck` lists are serialized **only** for the
  server's own persistence snapshot (to disk/SQLite), so a server restart can
  reconstruct the exact game.
- **Persistence snapshot ≠ client view.** The server keeps two serializations:
  1. **Authoritative full snapshot** (everything, ordered decks, seed) → SQLite,
     for crash recovery / restart. Never sent over a socket.
  2. **Redacted per-player view** (`redactFor`) → the wire. Built fresh per
     broadcast.

The `redactFor` function is the only producer of (2); the engine's own `toJson`
produces (1). Keeping these as two distinct code paths makes it impossible to
accidentally leak the authoritative snapshot to a client — they aren't the same
serializer.

---

## 6. Lobby & matchmaking

Mirrors the official "Online" screen: **Your Games**, **More Games**,
**Create Game**, with per-player ready dots and game status badges
("Invitation Expired", "Complete", "Game Started").

### Game data model

```json
{
  "id": "g_7Q2K",
  "status": "waiting",            // waiting | started | complete | abandoned
  "createdBy": "u_korvus",
  "createdAt": 1719600000000,
  "playerCap": 4,
  "seats": [
    {"playerId":"u_korvus","name":"korvus","ready":true,"connected":true,"isAi":false},
    {"playerId":"u_shanks","name":"shanks","ready":false,"connected":false,"isAi":false},
    {"playerId":"ai_1","name":"AI (Order)","ready":true,"connected":true,"isAi":true}
  ],
  "currentPlayerId": "u_korvus", // whose turn (null until started)
  "turnNumber": 4,
  "winnerId": null,
  "invitePolicy": "open"         // open | invite-only
}
```

The lobby keeps this **summary** separately from the heavyweight engine snapshot,
so listing games is cheap (no engine deserialization to render the list).

### Lobby messages (`type: "lobby"`)

Client→server: `createGame {playerCap, name?, fillWithAi?, invitePolicy}`
(**implemented:** `name` is a host-chosen display name — `LobbyGame.name`,
defaulted when blank), `joinGame {gameId}`, `leaveGame {gameId}`, `listGames`,
`deleteGame {gameId}` (the trash-can on an expired/finished game),
`startGame {gameId}`, `addAi {gameId, count}`, `resyncGame {gameId}` (rejoin a
specific in-progress game, see [§7](#7-reconnect--disconnect)).

Server→client: `gameList {yours:[...], more:[...]}`, `gameUpdated {summary}`,
`gameStarted {gameId}`.

### Screen flows (→ official UI)

- **Your Games** = games where `you ∈ seats`. Surfaces it-is-your-turn badges and
  invite states. The "Invitation Expired" card from the reference maps to a
  `waiting` game past its invite TTL → server marks `status:"abandoned"` and shows
  the trash-can to delete.
- **More Games** = public/`open` games you're not in, that are joinable
  (`waiting`, seats free) or browsable (`started`/`complete`). The reference's
  "Game Started"/"Complete" tiles are exactly these summaries with a status badge.
- **Create Game** → `createGame`. Choose `playerCap` (2–4), optionally
  `fillWithAi` so a solo player can start immediately; the server seats
  `AiService`-backed players for empty slots.

### AI-fill

The server already has `AiService`. An AI seat is a `PlayerState` like any other;
when the turn advances to an AI seat, **the server runs `AiService.takeTurn()`
locally** and broadcasts the resulting snapshot(s). No socket, no client — the AI
"plays" entirely server-side. This makes 1-human-vs-AI games work on day one and
lets a multiplayer game continue if a human seat is converted to AI on
abandonment ([§7](#7-reconnect--disconnect)).

### Persistence

**SQLite on the Pi.** Low-budget, zero-ops, single-file, perfect for intermittent
uptime. Tables:

- `games(id, status, summary_json, created_at, updated_at)` — lobby summaries.
- `game_state(game_id, state_version, snapshot_json, seed)` — the
  **authoritative** full engine snapshot ([§5](#5-serialization), form 1). One
  row per game (latest), or append-only for audit/replay if desired. `seed` and
  ordered decks live here and **only** here.
- `users(id, name, device_token_hash, created_at)` — accounts/device tokens
  ([§8](#8-security--anti-cheat)).
- `seats(game_id, player_id, seat_index, is_ai)` — membership (also derivable
  from summary; a real table makes "Your Games" a fast indexed query).

A game is persisted after **every applied action**, so a crash loses at most the
in-flight action (which the client can resend).

---

## 7. Reconnect & disconnect

Turn-based is forgiving: nobody loses a reflex-timed moment when a phone sleeps.

### Reconnect = re-auth + resnapshot

1. Client reopens the socket, sends `hello`/`identify {playerId}`.
2. Server authenticates and finds the player's active games. **Implemented:**
   `Lobby.activeGameForPlayer(playerId)` returns the player's most-recent live
   game; `activeGamesForPlayer(playerId)` lists all of them (a player can be in
   several at once). A completed game is **not** returned as active.
3. For the game the client re-enters, the server sends the **current redacted
   snapshot** — the *same* `state` message a live client gets ([§4](#4-state-sync-server--client)).
   Because sync is snapshot-based, "resync" needs no special path: the latest
   snapshot *is* the full truth. **Implemented:** identify auto-resyncs the
   most-recent game, and a member can re-request any specific game via
   `resyncGame {gameId}` (a non-member is refused; a still-`waiting` game isn't
   resyncable).

The client throws away whatever it had and renders the snapshot. `stateVersion`
guards against a late stale snapshot racing the fresh one.

### Same-turn undo (implemented)

The server supports an in-turn **undo**. Each `GameSession` keeps an `_undoStack`
of pre-action `GameStateCodec` snapshots. Before applying a *mutating* action the
session pushes the current full state; an `endTurn` **clears** the stack (you can
never undo across a turn boundary, which would leak an opponent's hidden draw).
The `undo` action pops the last snapshot and `GameStateCodec.decode`s it back into
the live engine, then re-broadcasts. The redacted view's `canUndo` flag
(`GameSession.canUndoFor`) tells the acting player's client whether the Undo
button is live. Because undo restores a full authoritative snapshot, it cannot
desync clients — the next broadcast is just another snapshot.

### Disconnect handling

- **Transient disconnect** (heartbeat miss, [§2](#2-transport)): mark the seat
  `connected:false` in the lobby summary, broadcast `gameUpdated` so opponents
  see the dot go grey. **The game does not pause or skip** — it's that player's
  problem to come back; if it's their turn, the turn simply waits.
- **Turn timeout (optional, configurable).** To stop a disconnected player from
  halting a game forever, an optional per-turn timer (e.g. 48 h for casual async
  play; shorter for "live" games). On expiry the server can **auto-`endTurn`**
  for the stalled player (safe: `endTurn` is a legal no-cost action that just
  discards + draws + advances) or, more aggressively, convert the seat to AI.
- **Abandonment.** A `waiting` game whose invites never fill past a TTL →
  `status:"abandoned"` (the "Invitation Expired" tile). A `started` game where a
  player is gone past the abandonment window → offer remaining players a
  resolution: convert the absent seat to `AiService`, or end the game.

### Mid-deferred-selection disconnect

Recall ([§3](#3-action-protocol)) that deferred selections leave the engine in
**no pending half-state** — the triggering effect already resolved to a no-op and
the follow-up is just another optional action. So a disconnect mid-scry is
trivially safe:

- The engine is in a clean, persisted state (the unredeemed selection simply
  hasn't happened).
- On reconnect, the server **re-emits the `selectionRequired` prompt** if the
  opportunity is still live (e.g. the scry top card is still on the deck and it's
  still the player's turn). Mandatory-but-skippable selections degrade to "didn't
  take it," matching solo-play semantics. Nothing is corrupt, nothing is locked.

This robustness is, again, a direct dividend of the authoritative-engine design:
there is no fragile cross-message transaction to recover.

---

## 8. Security & anti-cheat

### The authoritative server kills most cheats by construction

- **No client-side rules to subvert.** Clients can't fabricate gem totals, free
  cards, or illegal attacks, because the client doesn't *apply* anything — it
  asks, and the server's engine decides. A hacked client can send any action it
  likes; illegal ones are rejected as no-ops ([§3](#3-action-protocol)).
- **Identity is server-bound.** `payload.actor` is ignored; the connection's
  authenticated id is used. You cannot act as another player.
- **Turn gate.** Out-of-turn actions are rejected before reaching the engine.

### Hidden-info redaction is the primary anti-cheat

The classic deck-game cheat — read your opponent's hand, predict your own draws —
is impossible because **that information is never on the wire** ([§4](#4-state-sync-server--client),
[§5](#5-serialization)). A modified client, a proxy, a packet capture: none can
reveal what the server didn't send. This is why the `redactFor` filter and the
"never ship deck order / seed" rules are load-bearing security, not polish.

**What must NEVER be sent to a client:**

1. Any other player's `hand` card ids.
2. **Any** player's `drawPile` order/ids (including the recipient's own).
3. The `infinityDeck` order/ids.
4. The RNG **seed**.
5. The authoritative full snapshot (form-1 serialization) — only the redacted
   per-player view ever crosses a socket.

### Input validation

- **Envelope validation.** Reject malformed JSON, unknown `type`, wrong `v`,
  oversized frames (cap message size, e.g. 16 KB — legit actions are tiny).
- **Argument validation.** Ids are strings of bounded length; `amount`/`maxCost`
  are non-negative ints in range; enums (`source`, `filter`, `disposition`) must
  be known values. Then hand off to the engine, which does the *semantic*
  validation (is that card actually in your hand, can you afford it).
- **Engine return value is the verdict.** No bypassing it.

### Rate limiting

- Per-connection token bucket on `action`/`lobby` messages (e.g. ~10/s burst,
  sustained lower). Turn-based humans never approach this; it caps a spammer.
- Cap concurrent games per user and concurrent connections per device token.
- Cloudflare provides edge-level DDoS/rate protection in front of all this.

### Auth — recommend lightweight device tokens (not accounts, at first)

Low budget, frictionless onboarding:

- **Phase-1/2: anonymous device tokens.** On first launch the client generates a
  random token, stores it locally, and registers it (`hello` → server mints/links
  a `users` row keyed by a hash of the token). The token *is* the identity. No
  email, no password, no auth provider, no recurring cost. The Pi stores only the
  **hash** of the token.
- **Later: optional account upgrade.** A device can later bind a username/claim
  code so a player can play from multiple devices. This is additive — the
  device-token path keeps working.
- **Why not OAuth/Firebase Auth now:** cost, complexity, and an external
  dependency for a hobby-scale, self-hosted game. Device tokens are sufficient to
  *bind a connection to an identity*, which is all the anti-cheat model needs.

Tokens are bearer credentials: transmit only over `wss://` (TLS via Cloudflare),
store hashed at rest, allow rotation.

---

## 9. Deploy / ops on the Pi

### Build

```bash
# On the Pi (or cross-compile for ARM64), from server/:
dart pub get
dart compile exe bin/server.dart -o build/game-server
# → a single self-contained native binary; no Dart runtime needed to run it.
```

Ship `cards.json` (and any starter data the engine reads from disk) alongside the
binary; the server reads it with `File(...).readAsString()`
([§1](#1-topology--stack), the `CardDatabase` split).

### Run as a service (systemd)

```ini
# /etc/systemd/system/game-server.service
[Unit]
Description=Shards game server
After=network-online.target

[Service]
ExecStart=/opt/game/game-server --port 8080 --db /opt/game/data/game.sqlite
Restart=on-failure
RestartSec=3
User=game
WorkingDirectory=/opt/game

[Install]
WantedBy=multi-user.target
```

`Restart=on-failure` covers the "intermittent uptime now" reality; when it's up,
it self-heals crashes. Persistence ([§6](#6-lobby--matchmaking)) means a restart
resumes every game from its last snapshot.

### cloudflared

```yaml
# /etc/cloudflared/config.yml
tunnel: <TUNNEL_UUID>
credentials-file: /etc/cloudflared/<TUNNEL_UUID>.json
ingress:
  - hostname: game.example.com
    service: http://localhost:8080      # WebSocket upgrades pass through
  - service: http_status:404
```

Run `cloudflared` as its own systemd service. The Pi makes an outbound tunnel; no
inbound ports. WebSocket upgrade on `/ws` is proxied transparently.

### SQLite backups

- The DB is one file. Back it up with the **online backup API** or
  `VACUUM INTO '/backup/game-YYYYMMDD.sqlite'` on a cron (e.g. nightly), then
  copy off-box (rsync to another machine, or push to cheap object storage).
- Because the file is small and writes are infrequent (turn-based), backups are
  trivial and cheap.

### Logging

- Structured JSON lines to stdout → captured by `journald` (systemd). Log:
  connection open/close, auth result, each action (`gameId`, `actor`, `action`,
  accepted/rejected + reason), state-version transitions, errors. **Never log
  redacted-away data** (no hand contents, no seed) — logs are not a leak vector.
- A `--log-level` flag; default `info`, `debug` for protocol tracing.

### Updating

1. Build new `game-server` binary.
2. `systemctl stop game-server` (in-flight games are persisted; players see a
   transient disconnect — forgiving for turn-based).
3. Swap the binary, run any SQLite migration (keep migrations forward-only and
   versioned).
4. `systemctl start game-server`; clients reconnect and resnapshot
   ([§7](#7-reconnect--disconnect)).

For "always-on later," add a second Pi / process and put Cloudflare's
load-balancing or a blue-green swap in front; the snapshot-in-SQLite design makes
a process restart cheap, so even a single box has near-zero-friction updates.

---

## 10. Phased rollout

Each phase is shippable and demoable. The **serialization dependency** is called
out per phase.

### Phase 0 — Engine seam (no networking yet)

- Split `CardDatabase` so `fromJsonString` is Flutter-free; server reads
  `cards.json` from disk ([§1](#1-topology--stack)).
- Land `toJson`/`fromJson` for `GameService` + `PlayerState` (authoritative
  snapshot, form-1) **and** the `redactFor` per-player view (form-2). *This is the
  blocking item for everything below.*
- Unit-test: round-trip a mid-game `GameService` through form-1; assert
  `redactFor` never emits opponent hand ids / any deck order / the seed.

**Blocks on:** the parallel serialization work. Nothing networked ships until
form-1 and `redactFor` exist.

### Phase 1 — Two browsers on the LAN share a game

- `server/bin/server.dart`: `dart:io` `HttpServer`, WebSocket upgrade on `/ws`,
  the envelope ([§2](#2-transport)), one hard-coded game.
- Wire the action protocol ([§3](#3-action-protocol)) to `GameService` methods;
  broadcast redacted snapshots ([§4](#4-state-sync-server--client)).
- Client: a thin net layer that sends actions and renders snapshots, replacing
  the in-process `GameService` call with a socket round-trip. No lobby, no auth
  (pick a seat by query param).
- **Demo:** two browser tabs / two devices on the same Wi-Fi (`ws://pi.local:8080/ws`)
  play a full game; hidden info verified (each tab sees only its own hand).

### Phase 2 — Cloudflare Tunnel public beta

- Stand up `cloudflared` + custom domain; client switches to `wss://game.example.com/ws`.
- Add device-token auth ([§8](#8-security--anti-cheat)) and the lobby
  ([§6](#6-lobby--matchmaking)): Create / Join / Your Games / More Games,
  AI-fill, the official "Online" screen.
- SQLite persistence ([§6](#6-lobby--matchmaking)); systemd service; heartbeat,
  reconnect/resnapshot, turn timeout ([§7](#7-reconnect--disconnect)).
- Rate limiting + input validation hardening ([§8](#8-security--anti-cheat)).
- **Demo:** strangers on the internet play 2–4 player async games from phone +
  desktop, leave and come back, AI fills empty seats.

### Phase 3 — Accounts, durability, always-on

- Optional account upgrade (bind device token → username, multi-device)
  ([§8](#8-security--anti-cheat)).
- Backups + monitoring + log retention ([§9](#9-deployops-on-the-pi)); replay/audit
  from the append-only `game_state` history if enabled.
- Always-on posture: redundant process / second Pi, blue-green updates,
  Cloudflare load balancing.
- Polish: invites, friend lists, per-game turn-timer presets, push/notify
  "it's your turn."

---

## Appendix A — End-to-end example: a buy

```
# p1 (whose turn it is) buys a card from the market.
client → {"v":1,"type":"action","seq":17,"gameId":"g_7Q2K",
          "payload":{"action":"buyCard","args":{"cardId":"reactor_monk_2"}}}

# server: identity gate (conn is p1 ✓), turn gate (currentPlayerIndex → p1 ✓),
#         engine: buyCard("reactor_monk_2") → applies discount, deducts gems,
#         moves card to discard, refills center row, returns true.
server → {"v":1,"type":"ack","seq":17,"gameId":"g_7Q2K"}
server → {"v":1,"type":"state","gameId":"g_7Q2K",
          "payload":{"stateVersion":88,"view":{ ...redacted for p0... }}}   # to p0
server → {"v":1,"type":"state","gameId":"g_7Q2K",
          "payload":{"stateVersion":88,"view":{ ...redacted for p1... }}}   # to p1
```

If `buyCard` had returned `false` (couldn't afford it), the server would have
sent `{"type":"error","seq":17,"payload":{"code":"ILLEGAL"}}` to p1 only, and
broadcast **no** state (nothing changed).

## Appendix B — Why this is low-risk

The risky part of a card game is the rules engine, and **it already exists, is
tested (550 engine tests + 21 server tests), is deterministic, and is pure Dart.** This architecture adds
exactly three new responsibilities around that proven core: (1) a courier
(WebSocket + envelope), (2) a redaction filter (the security boundary), and (3) a
lobby + store. None of them re-implement a single game rule. That separation is
the entire point.
