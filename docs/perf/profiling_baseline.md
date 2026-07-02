# Multiplayer performance: profiling methodology + baseline

Status: baseline captured 2026-07-01 on the deploy Pi (Raspberry Pi 4 Model B,
4 cores, 8 GB, Dart 3.11.3 arm64). Read-only research — no engine/server/UI
source was changed to produce this.

Goal: a repeatable way to profile the multiplayer per-turn loop and a recorded
baseline, so we can optimize the networked experience **without regressing
single-player gameplay feel**.

---

## 1. The per-turn hot path (architecture map)

One accepted action walks this loop (client → server → all clients):

```
client GameClient.sendAction         lib/services/game_client.dart  (jsonEncode a tiny action msg)
   │  WebSocket text frame
   ▼
server GameSession.apply             server/lib/game_session.dart
   ├─ GameStateCodec.encode(game)    lib/data/database/game_state_codec.dart   ← UNDO snapshot, EVERY non-endTurn action
   ├─ buildDecisionSnapshot(...)     server/lib/stats_capture.dart             ← telemetry (own-info only)
   ├─ applyAction(game, seat, act)   server/lib/protocol.dart → engine mutate  lib/services/game_service.dart
   └─ (accepted) _recordTelemetry + _stateVersion++
   ▼
server _broadcastState(gameId)       server/bin/server.dart
   └─ session.broadcastViews()       server/lib/game_session.dart
        for EACH recipient:
          ├─ redactFor(game, id)     server/lib/views.dart      ← rebuilds card dict + full view PER recipient
          └─ jsonEncode(view)        dart:convert               ← serialize full snapshot PER recipient
        (+ one spectatorView() shared across spectators)
   │  N WebSocket text frames (one full redacted state each)
   ▼
client GameClient._onMessage         lib/services/game_client.dart
   ├─ jsonDecode(payload)            dart:convert
   └─ notifyListeners()  →  NetworkGameScreen rebuild   lib/ui/screens/network_game_screen.dart
```

Cost multipliers to keep in mind:

- **`redactFor` and `jsonEncode` run once per recipient per accepted action.** A
  4-player game pays ~4× the serialization cost of a 2-player game for the same
  action.
- **The redacted view is a FULL state snapshot, not a delta.** "Per action" and
  "full resync" ship the same bytes per recipient — every tap re-ships the whole
  board (card dictionary included).
- **`GameStateCodec.encode` runs once per action** for the undo snapshot (server)
  — and the *same* function runs on the **single-player** local-undo path
  (`lib/ui/screens/game_screen.dart:97`). It is the ONE hot-path function shared
  by both modes.

### Single-player isolation (why most wins are "free")

| Hot-path piece | Single-player uses it? | Safe to optimize freely? |
|---|---|---|
| `redactFor` (server/lib/views.dart) | **No** — never called on the client | **Yes** (server-only) |
| `jsonEncode` broadcast / WS send | **No** | **Yes** (server-only) |
| `broadcastViews` / recipient fan-out | **No** | **Yes** (server-only) |
| client `jsonDecode` + rebuild | **No** (single-player mutates engine in-proc) | **Yes** (networked screen only) |
| **`GameStateCodec.encode`** | **YES** — local undo stack (`game_screen.dart`) | **Careful** — shared code; a change here touches single-player undo |
| engine `applyAction` / `GameService.*` | **YES** — identical code both modes | **Careful** — the actual gameplay |

Takeaway: the biggest multiplayer costs (`redactFor`, per-recipient
`jsonEncode`, fan-out, payload size, client parse/rebuild) live **entirely on the
server or in the networked screen** and never run in single-player. They can be
optimized aggressively with zero risk to single-player feel. Only
`GameStateCodec.encode` and the engine itself are shared and need care.

---

## 2. Baseline numbers (Pi 4B, 2026-07-01)

Captured with `server/tool/perf/redaction_bench.dart` (see §4), 200 timed
iterations per cell after warmup. Games are driven to the target turn with a
greedy in-process driver (play-all → activate champions → buy → focus → attack →
end turn), the same shape as `AiService` / `gen_board_fixture` minus UI delays.
Measured against the **last committed engine** (HEAD `d1c6b06`) in a throwaway
git worktree, because the current working tree has in-progress engine edits that
don't yet compile.

Times are microseconds (µs); payload sizes are the UTF-8 byte length of the
JSON actually sent.

| Config | turn | encode (undo) | full snapshot | redactFor /recipient | redact ×N | jsonEncode ×N | **per-action serialize** | oneView bytes | **wire/action (all recipients)** | client parse /view |
|---|---|---|---|---|---|---|---|---|---|---|
| 2p early | 4  | 2077 µs | 64.0 KB | 447 µs | 893 µs  | 2266 µs | **5.2 ms**  | 13.4 KB | **27.2 KB**  | 961 µs  |
| 2p mid   | 12 | 1675 µs | 81.3 KB | 532 µs | 1064 µs | 2441 µs | **5.2 ms**  | 23.4 KB | **45.7 KB**  | 1564 µs |
| 2p late  | 24 | 2097 µs | 98.1 KB | 662 µs | 1324 µs | 3799 µs | **7.2 ms**  | 32.9 KB | **67.2 KB**  | 2261 µs |
| 4p early | 4  | 1836 µs | 72.6 KB | 402 µs | 1610 µs | 4603 µs | **8.0 ms**  | 20.0 KB | **78.8 KB**  | 1431 µs |
| 4p mid   | 16 | 2054 µs | 101.2 KB| 762 µs | 3049 µs | 8284 µs | **13.4 ms** | 39.9 KB | **157.4 KB** | 2696 µs |
| 4p late  | 32 | 2421 µs | 101.0 KB| 1032 µs| 4129 µs | 10598 µs| **17.1 ms** | 54.7 KB | **215.4 KB** | 3587 µs |

"per-action serialize" = `encode` + (`redactFor` + `jsonEncode`) × recipients —
i.e. the CPU the server spends per accepted action, excluding engine mutate,
telemetry, and socket I/O.

### Headline reads

- **Server CPU per action: ~5 ms (2p early) → ~17 ms (4p late).** A single Pi
  core is fine for one game at a few actions/second, but this is the ceiling that
  concurrent games / bursty turns compete for.
- **`jsonEncode` is the single largest cost** — 2.3–10.6 ms, 43–62% of the
  per-action serialize budget, and it scales with **recipients × payload size**.
- **`redactFor` is #2** and rebuilds the entire card dictionary (full effect
  trees, `cardModelToJson`) from scratch **for every recipient**, even though the
  visible-card set is almost identical across recipients.
- **`GameStateCodec.encode` is a flat ~2 ms** regardless of config (it serializes
  the full authoritative state including hidden zones) and produces a **64–101 KB**
  snapshot every action for the undo stack.
- **Wire bytes explode with player count:** 27 KB/action (2p early) →
  **215 KB/action** (4p late). At ~215 KB per tap, a 4-player late game over a
  weak uplink is the first thing a live tester will feel as lag.
- **The card dictionary dominates the payload.** In 4p late the redacted view
  carries 150 full card definitions; those effect trees, repeated in every view
  and every action, are the bulk of both the bytes and the encode time.
- **Client parse is 1–3.6 ms/view** and grows with payload; Flutter rebuild is on
  top of that (not measured here — see §4).

---

## 3. Optimization candidates (prioritized)

Win = expected impact on the multiplayer hot path. Risk is specifically **risk to
single-player gameplay feel** (see §1 isolation table). Effort is rough.

| # | Candidate | Expected win | Risk to single-player | Effort |
|---|---|---|---|---|
| **1** | **Compute the shared card dict + shared public sections ONCE per broadcast**, then per-recipient only splice the private bits (own hand ids, own drawPileContents, own relicOptions, `you`/`canUndo`). Today `redactFor` re-runs `cardModelToJson` for every visible card for every recipient. | Cuts redact cost from ~N× toward ~1× + small per-recipient delta. On 4p late, `redact ×N` 4.1 ms → ≈1.3 ms. | **None** — `redactFor` is server-only. | Med |
| **2** | **Memoize per-card serialized JSON.** Cards are effectively immutable after creation (id → fixed name/effects/stats). Cache `cardModelToJson(card)` by id (and ideally a pre-encoded JSON *string* fragment) so both `redactFor` dict-building and `jsonEncode` reuse it instead of re-walking effect trees every action. | Large: attacks both the #2 (`redactFor`) and #1 (`jsonEncode`) costs — the card dict is most of both. Compounds with candidate 1. | **None** if kept in the server dict/view layer. **Low** if the cache is added to `GameStateCodec`/`card_serialization` (shared) — must invalidate correctly (accumulated damage lives outside CardModel, so cards really are immutable). | Med |
| **3** | **Ship a static client card catalog; stop sending full CardModel JSON for DB cards.** The client already bundles `assets/card_db/cards.json`. Send by-value only for synthetic instance/starter cards (e.g. `chaos_imp_1`, `p0_crystal_3`) that aren't in the catalog; send just ids for everything else. | Largest byte + parse win: the card dict is the payload bulk, so wire/action and client parse both drop sharply (helps the 27→215 KB scaling directly). | **None** for the wire format itself (networked screen only). Must keep client catalog art/effects in lockstep with the server DB (a versioning concern, not a gameplay one). | Med-High |
| 4 | **Delta broadcasts** — ship only what changed since a recipient's last `stateVersion`, keep `redactFor` as the full-resync/reconnect path. | Very large on both CPU and bytes (most actions touch a small slice of state). | **None** to single-player, but **high correctness risk** in the diff/patch + resync logic (a dropped/mis-applied delta silently desyncs a client). Gate behind version + periodic full snapshot. | High |
| 5 | **Payload minification** — short JSON keys, and drop the ~80-entry `actionLog` tail (with its per-entry `_namifyMessage` regex run per recipient) from every broadcast; send the log incrementally or on demand. | Moderate bytes + a slice of redact CPU (the log tail is re-namified per recipient every action). | **None** — server/wire only. | Low-Med |
| 6 | **Skip / cheapen the undo `GameStateCodec.encode`** — it runs every action (~2 ms, ~100 KB alloc). Options: only snapshot the current player's own actions (already the case), or store a lighter/structural undo record. | ~2 ms + GC pressure per action. | **Careful** — `encode` is the shared single-player local-undo path; a structural change must preserve local undo. Server-side-only gating is safe. | Med |
| 7 | **Narrow the client rebuild scope** — `GameClient` is a single `ChangeNotifier`; each `state` message calls `notifyListeners()` and rebuilds the whole `NetworkGameScreen` (4.2k lines). Split into selectors / `ValueListenable`s so only changed regions rebuild. | Smooths the client frame after each action (the part a player actually feels). | **None** — networked screen only; single-player uses `game_screen.dart`. | Med-High |

### Top 3 to do first

1. **Candidate 1 — build the shared card dict/public view once per broadcast**
   (not per recipient). Biggest safe redact win, self-contained in
   `server/lib/views.dart` + `game_session.dart`.
2. **Candidate 2 — memoize per-card serialized JSON** (immutable cards). Cuts
   both `redactFor` and `jsonEncode`; compounds with #1; low risk.
3. **Candidate 3 — static client catalog + id-only for DB cards.** Attacks the
   215 KB/action payload and the client parse cost directly — the thing testers
   will feel first.

All three are server-side / wire-format changes that **cannot regress
single-player** (which never runs `redactFor`, the broadcast, or the networked
screen). Keep hands off `GameStateCodec.encode` and the engine unless a change is
explicitly measured to help and re-verified against single-player undo.

---

## 4. Repeatable profiling harness

### 4a. Serialization / redaction microbench (this baseline)

`server/tool/perf/redaction_bench.dart` — pure Dart, no server/socket needed.
Lives under the server package because `redactFor` is only importable there.

```bash
export PATH="$HOME/flutter/bin:$HOME/dart-sdk/bin:$PATH"
cd server
dart run tool/perf/redaction_bench.dart              # human-readable table
dart run tool/perf/redaction_bench.dart --iters 400  # more stable timings
dart run tool/perf/redaction_bench.dart --json       # machine-readable (CI / diffing)
```

Measures, per config (2p/4p × early/mid/late): `GameStateCodec.encode` time +
full-snapshot bytes; `redactFor` time per recipient and ×N; `jsonEncode` time;
per-action serialize total; oneView bytes and wire/action bytes; client
`jsonDecode` time. It drives a fresh deterministic game (seed 7) each run, so
numbers are comparable over time.

Run it on the **deploy Pi** (numbers are ~5–10× rosier on a dev laptop and will
hide regressions). Re-run before/after any change to `views.dart`,
`game_state_codec.dart`, `card_serialization.dart`, or the broadcast path.

> Note: if the working tree has in-progress engine edits that don't compile, run
> the bench from a clean checkout, e.g. `git worktree add /tmp/scg-head HEAD`,
> copy the script in, `cd server && dart pub get`, then run.

### 4b. Suggested regression thresholds (Pi 4B)

Fail/alert if, at the **4p mid** config, any of:

- per-action serialize > **16 ms** (baseline ~13.4 ms; ~20% headroom)
- wire/action (all recipients) > **190 KB** (baseline ~157 KB)
- oneView > **48 KB** (baseline ~40 KB)
- `GameStateCodec.encode` > **2.6 ms** (baseline ~2.0 ms; guards single-player undo too)

These are guardrails, not targets — candidates 1–3 should move the baselines
*down*; re-baseline after landing each and tighten the thresholds.

### 4c. What this bench does NOT cover (measure separately)

- **Engine mutate per action** — folded into the greedy driver here; to profile a
  specific action, wrap the individual `GameService` call in a `Stopwatch` or use
  the self-play runner (`tool/selfplay/runner_inproc.dart`, which already times
  total actions).
- **WebSocket / socket I/O + event-loop latency** — measure end-to-end with a
  scripted `web_socket_channel` client against a running `server/bin/server.dart`,
  timing action-sent → state-received round-trips (add multiple concurrent games
  to see fan-out contention on one core).
- **Flutter client rebuild** — use Flutter DevTools timeline / `--profile` on the
  networked board: watch the rebuild after each `state` message (widget rebuild
  count and raster/build times), which candidate 7 targets. `jsonDecode` time
  from this bench is the floor; the rebuild sits on top.
- **Concurrency** — one busy game is ~5–17 ms/action of single-core CPU; multiple
  simultaneous games serialize on the Dart isolate. Load-test with the round-trip
  client above before a public alpha.

---

## Appendix: how the baseline was produced

- Host: deploy Pi (Raspberry Pi 4 Model B Rev 1.4), 4 cores, ~8 GB, Dart 3.11.3
  stable arm64.
- Engine revision: HEAD `d1c6b06` (working-tree engine edits excluded — they did
  not compile at capture time).
- Driver: greedy, deterministic (`Random(7)`), full market + Destiny supply from
  `assets/card_db/cards.json`.
- Method: 20 warmup + 200 timed iterations per measurement; `Stopwatch`
  microseconds; payload sizes are `utf8.encode(jsonEncode(view)).length`.
- Script: `server/tool/perf/redaction_bench.dart` (added with this doc).
