# Self-play bots — training data + semantic bug detection

A design for an **ad-hoc, dev-period-only** system where two bots play
Fragments of Boundlessness against each other, over and over, to accomplish two
goals:

1. **Bug detection at scale (the primary goal)** — surface runtime crashes,
   illegal states, and especially **semantic bugs**: a card that *didn't do what
   its printed text says*. Thousands of games exercise rare effect interactions a
   human would never reach.
2. **Training data for an AI model** — emit the same rich decision/outcome
   telemetry the human games produce, but **tagged as bot-sourced** so the two
   corpora never mix.

> **Scope note.** This is **not** about maxing out bot skill. The bots only need
> to play *legal, varied* games to exercise the engine. A smarter bot is a later
> nice-to-have; a bot that reaches weird board states is what we want now. The
> whole system is ad-hoc — run on demand during development, never part of the
> hosted alpha.

This builds on the existing pure-Dart engine and telemetry. Key infra it plugs
into (all already present):

- **`GameService`** (`lib/services/game_service.dart`) — pure-Dart engine, runs
  headlessly. Single effect-dispatch point `_resolveEffects()` (the switch over
  all 50 `CardEffect` types) — the anchor for the semantic oracle (§3).
- **`AiService`** (`lib/services/ai_service.dart`) — pure-Dart heuristic player;
  `takeTurn()` drives a full turn against a `GameService`. Reusable as a bot brain.
- **`GameSession.apply()`** (`server/lib/game_session.dart`) — transport-agnostic
  action funnel; the server records telemetry here.
- **`GameClient`** (`lib/services/game_client.dart`) — pure-Dart WebSocket client
  (no Flutter deps) — reusable to drive the **real server** over the wire.
- **Telemetry** (`server/lib/stats_capture.dart` + `stats_store.dart`) — the
  `events` / `decisions` / `games` SQLite store; `games.players` is a JSON array
  with room for an `is_bot` flag per seat (§4).

---

## 0. Two harness tiers (chosen: Tier B for bulk)

There are two ways to run self-play; they share the bot brain and the checker.

### Tier A — in-process (fastest, best for the oracle)

Two `AiService` instances against **one in-process `GameService`**, no server, no
WebSocket. The oracle wraps each engine call directly. This is the **highest
throughput** (thousands of games/minute) and gives the semantic checker the
*fullest* access — it can read complete pre/post state with no redaction. Best for
the bug-hunt goal. Downside: it bypasses the server/protocol/redaction layer.

### Tier B — over the real server (chosen for bulk + data) ✅

Two headless **`GameClient`** bots connect to the real running server as real
WebSocket clients, identify with **bot usernames**, create/join a game, and play
real actions. This is what you asked for: "real games on the real server,
executing real actions, monitoring real game logs." It exercises the **full**
path — protocol parsing, `GameSession.apply`, redaction, telemetry capture,
persistence — everything except the Flutter render layer. Throughput is lower than
Tier A (network + per-action round-trips) but still hundreds/thousands of games an
hour, plenty for an ad-hoc dev run.

**Recommendation: build Tier B as the bulk runner** (it generates the bot-tagged
telemetry through the real funnel and finds protocol/server bugs too), and keep a
**Tier A mode** available for the deepest oracle runs (full-state semantic checks
without redaction). They share ~90% of the code: the bot brain (§2) and the
checker (§3) are identical; only the *transport* differs.

> The semantic oracle (§3) is strongest in Tier A (full state). In Tier B a bot
> only sees its **own** redacted view, so per-action oracle checks are limited to
> the acting bot's own visible deltas (gems/power/mastery/health/hand/its own
> champions) — still the majority of effects. For the few effects whose result is
> only visible server-side (opponent draw/discard counts, hidden zones), run those
> assertions in Tier A or add a **server-side oracle hook** (§3d).

---

## 1. The self-play loop

```
 for each game (until N games, a crash, or Ctrl-C):
   ┌──────────────────────────────────────────────────────────────┐
   │ set up: two bots (bot_a, bot_b), a fresh game, a fixed seed   │
   │ loop until isGameOver:                                        │
   │   current bot:                                               │
   │     snapshot state  ──┐                                      │
   │     pick + apply ONE legal action                           │
   │     snapshot state  ──┴──> CHECKER (invariants + oracle §3)  │
   │     if checker flags a mismatch → write a bug report (§5)    │
   │ on game end: record winner/winType (telemetry, bot-tagged)   │
   └──────────────────────────────────────────────────────────────┘
```

**Determinism is the whole game.** Every run is seeded (`GameService(random:
Random(seed))` in Tier A; the server already seeds per game). The runner logs the
**seed + the action sequence** for every game, so any flagged bug is **replayable
exactly**. A bug report is worthless if you can't reproduce it; a seed + action
list makes every finding a one-command repro.

---

## 2. The bot brain (shared by both tiers)

Start from `AiService`'s heuristics, but for **bug-hunting we want variety, not
strength** — a purely greedy bot always plays the same lines and never reaches odd
states. So the bot brain is **`AiService` + a randomized "explorer" mode**:

- **Greedy mode** — reuse `AiService` as-is. Produces sane games (good baseline
  data, reaches normal end states).
- **Explorer mode** — among the *legal* actions each step, pick a **random** one
  (weighted to still finish games: bias toward play/recruit early, attack/endTurn
  late). This is the bug-hunter — it deliberately reaches rare orderings:
  activate-before-play, banish-your-own-key-card, buy-then-scrap, claim-Destiny-
  mid-combat, etc.
- **Mix** — run a fraction of games greedy (clean data) and a fraction explorer
  (bug coverage). Vary per game by seed.

**Legal-move enumeration.** Both modes need "what can I legally do right now?"
Tier A reads it straight off `GameService` (hand, center row affordable by gems,
champions not yet activated, focus-available, claimable Destinies at mastery ≥5,
etc.). Tier B derives it from the bot's **redacted view** (own hand ids + the
`cards` dict for effects + public scalars) — the view ships enough to enumerate
legal moves (the infra map confirmed this). Illegal guesses are simply rejected by
the server (`ActionResult.accepted == false`), which is itself a useful signal
(a rejected move the bot *thought* was legal = a client/redaction mismatch bug).

> The bot does NOT need to be good. It needs to (a) only attempt legal moves,
> (b) eventually end games, and (c) cover variety. Skill is explicitly a non-goal.

---

## 3. Semantic bug detection — the oracle (the heart of this)

The hard part you flagged: **"the card didn't quite do what its text says."** The
action log only records `"played Chaos Imp"` — not the *effect outcome* — so we
can't detect semantic drift from logs alone. The fix is a **differential oracle**:
for each action, independently compute the **expected** state change from the
card's declared `CardEffect`s, then compare it to the **actual** change the engine
produced. A mismatch is a semantic bug.

### 3a. Invariant checks (cheap, every action — catches hard bugs)

Assert these after **every** action; a violation is always a bug:

- **No impossible scalars** — health ≥ 0 (or eliminated), gems ≥ 0, power ≥ 0,
  mastery ≥ 0 and **monotonic non-decreasing within a turn** (mastery never drops).
- **Card conservation** — total card count across all zones (hands + draw +
  discard + champions + center row + center deck + removed) is constant except at
  draw/banish/scrap boundaries where the delta is exactly accounted for. A card
  that vanishes or duplicates is a bug.
- **Turn legality** — only the current player's state mutates on their action;
  it's never someone else's turn when a bot acts.
- **Win-condition consistency** — `isGameOver` ⇔ (some player eliminated OR an
  Infinity Shard played at mastery ≥30); `winType` matches the trigger;
  `winnerId` is set iff game over.
- **No exceptions** — any thrown exception / assertion failure during an action is
  a crash bug (caught, reported with seed+log, game aborted).

### 3b. The per-effect oracle (the semantic core)

The engine resolves effects through one switch (`_resolveEffects`, 31 types). The
oracle is a **parallel, independent re-implementation** of the *expected delta* for
each effect type — deliberately written separately from the engine so a bug in the
engine doesn't hide behind the same bug in the oracle. For a played card:

```
expected = Σ over card.playEffects of expectedDelta(effect, preState)
actual   = diff(preState, postState)         # for THIS player's visible resources
assert actual ⊇ expected      (actual matches expected on the dimensions the
                               effect touches; unrelated dimensions unchanged)
```

Examples of `expectedDelta`:

| Effect | Expected (independently computed) |
|--------|-----------------------------------|
| `GainGemsEffect(n)` | gems += n, nothing else |
| `GainPowerEffect(n)` | power += n |
| `GainMasteryEffect(n)` | mastery += n |
| `GainHealthEffect(n)` | health += n (capped at start? assert cap rule) |
| `DrawCardsEffect(n)` | hand size += n (or draw+discard reshuffle accounted) |
| `OpponentLosesHealthEffect(n)` | each opponent health -= n |
| `ScalingResourceEffect` | resource += perN × (count of matching faction in cardsPlayedThisTurn) — re-derive the count independently |
| `ConditionalEffect(cond, then)` | if cond holds (re-evaluate cond from state), apply `then`'s expected delta; else **no change** |
| `ChooseOneEffect` | the chosen branch's expected delta (oracle knows which index the bot chose) |

**Deferred-selection effects** (banish / destroy / return / recruit / fastPlay /
scry / copy / tuck / reset) resolve to a no-op at play time and complete on a
follow-up action. The oracle checks them on the **follow-up** action (e.g. after
`banishCard`, assert exactly that card left the zone; after `recruitFromCenter`,
assert the recruited card entered discard and the center refilled). Mark them
"deferred-pending" between the two actions so a never-completed deferral is itself
flagged.

**What "didn't do what the text says" looks like when caught:** the oracle says
`Chaos Imp` should give power = (cards played this turn from Wraethe) × 1, the
engine gave a flat 1, `actual ≠ expected` → bug report with the card, the
pre-state, both deltas, the seed, and the action log. That's the exact class of bug
you're after.

### 3c. Cross-checks against the printed text (catch encoding bugs)

The oracle above checks **engine vs. CardEffect encoding**. But a card can be
mis-*encoded* — the `CardEffect` list itself is wrong relative to the printed
`rawText`. That's a different bug (data, not engine). Two complementary checks:

- **Structured lint** — for cards with a `rawText`, a heuristic parser flags
  obvious mismatches: rawText says "gain 3 power" but `playEffects` has
  `GainPowerEffect(2)`; rawText mentions "banish" but no `BanishCardEffect`; etc.
  Cheap, catches transcription typos. (The card DB already has a
  `verified` flag and `notes` provenance — this feeds that workflow.)
- **LLM spot-judge (optional, batched)** — periodically feed `{rawText,
  playEffects-as-English, an example resolution from a real game}` to an LLM and
  ask "does the modeled behavior match the printed text?" Good at subtle wording
  ("you *may*" vs mandatory, "each" vs "a", ordering). Run it as an *offline batch*
  over flagged/low-confidence cards, not in the hot loop. This is the safety net
  for semantics the structured oracle can't express.

### 3d. (Tier B) server-side oracle hook

Because a Tier B bot only sees its own redacted view, add an **optional in-process
oracle on the server** (dev builds only): `GameSession.apply` already has pre/post
state — wrap it with the same invariant + effect-oracle checks against the FULL
game state and log mismatches to a `bug_reports` table. This gives full-state
semantic checking even when bots drive over the wire. Gate it behind a
`SHARDS_BOT_ORACLE=1` env flag so it never runs in the real alpha.

---

## 4. Keeping bot data separate from player data

You want bot training data segregated from human data (so a model isn't trained on
bot-vs-bot noise unless you ask). Three additive, non-breaking changes to the
existing telemetry:

1. **Bot username convention** — bots identify with a reserved prefix, e.g.
   `bot_explorer_01`, `bot_greedy_02`. Zero schema change; instantly filterable.
2. **`is_bot` flag in `games.players`** — the `games` table already stores
   `players` as a JSON array `[{seat, playerId}, …]`. Add `is_bot: true` per bot
   seat. `decision_export` / queries can then `WHERE` on it. (One-line change in
   `stats_store.recordGameEnd` / the players-JSON builder.)
3. **`game_type` column on `games`** — `'human' | 'bot' | 'mixed'`, stamped at game
   end from the seats' bot flags. The single cleanest filter for "give me only
   human games" vs "only bot games" when exporting training data.

All three are **additive** (new optional column/flag, old rows read as human) and
**hidden-info-safe** (a bot flag is not hidden info). The existing
hidden-info-safety guarantees are untouched — bot games redact exactly like human
games.

> **Why separate matters for the model:** bot-vs-bot games reflect the *bot's*
> policy, not human play. Mixing them into a behavior-cloning corpus would teach
> the model to imitate the heuristic/explorer bot. Keep them in separate partitions
> so you can choose: train on humans only, pretrain on bots + fine-tune on humans,
> or use bot games purely for *coverage/bug-finding* and never for the policy.

---

## 5. Bug reports — the output that matters

Every checker flag (invariant violation, oracle mismatch, crash, lint mismatch)
writes a **self-contained, replayable** report:

```jsonc
{
  "kind": "semantic-mismatch | invariant | crash | encoding-lint",
  "seed": 48213,                         // re-create the exact game
  "actionIndex": 37,                     // which action tripped it
  "actionSequence": [ … ],               // full replay up to the failure
  "card": "chaos_imp",                   // the implicated card (if any)
  "effect": "ScalingResourceEffect(...)",
  "expectedDelta": { "power": 3 },
  "actualDelta":   { "power": 1 },
  "preState":  { … redacted to what's relevant … },
  "actionLog": [ … the public log tail … ],
  "message": "Chaos Imp gave 1 power; printed text + effect imply 3 (1 per Wraethe played: 3)."
}
```

Reports land in a **`bug_reports/` dir (or a SQLite table)**, deduped by
`(card, kind, effect)` so 500 games hitting the same bug produce one grouped report
with a count, not 500 rows. This dedup is what makes a scale run actionable: you
want "here are the 6 distinct semantic bugs we found across 10k games," not a
firehose. (This is also the natural hand-off into the Discord bug-pipeline's
investigate→fix→verify stages — see
[`discord_bug_pipeline.md`](discord_bug_pipeline.md).)

---

## 6. Where the code lives

All under a new dev-only tree, kept out of the shipped client/server:

```
tool/selfplay/                      # dev-only, not bundled into the app
├── bot.dart           # the bot brain: greedy (wraps AiService) + explorer modes
├── oracle.dart        # invariants + per-effect expectedDelta + diff/assert
├── checker.dart       # runs oracle on each (pre,post,action) → bug reports
├── runner_inproc.dart # Tier A: two bots vs one in-process GameService, N games
├── runner_ws.dart     # Tier B: two GameClient bots vs the real server, N games
└── report.dart        # bug-report writer + dedup
```

- **Pure-Dart `tool/`** (like the existing `tool/validate_card_db.dart`) — runs
  with `dart run tool/selfplay/runner_inproc.dart --games 5000 --seed-base 1`.
- **No new app dependencies.** Reuses `GameService`, `AiService`, `GameClient`,
  and the codecs already in `lib/`.
- **Server oracle hook** (§3d) is the only `server/` change — a guarded
  `SHARDS_BOT_ORACLE=1` wrapper in `game_session.dart` + a `bug_reports` table in
  `stats_store.dart`. Both additive and dev-gated.

---

## 7. Phased build plan

1. **Phase 1 — Tier A loop + invariants.** ✅ **BUILT.** Two bots vs one
   `GameService`, run N games, assert §3a invariants + no-crash. Lives in
   `tool/selfplay/runner_inproc.dart` + `oracle.dart`.
2. **Phase 2 — the effect oracle.** ✅ **BUILT.** `oracle.dart` (§3b, the flat
   resource oracle) + replayable, deduped bug reports (`report.dart`, §5). This is
   the semantic-bug engine — the core deliverable.
3. **Phase 3 — explorer bot.** ✅ **BUILT.** `bot.dart` has greedy + randomized
   explorer modes (`--mode mix` runs half-and-half); the runner snapshots the full
   game around every action.
4. **Phase 4 — Tier B (real server).** ⏳ **NOT BUILT (deferred).** `runner_ws.dart`:
   two `GameClient` bots over the real WebSocket server with **bot usernames**,
   generating bot-tagged telemetry through the real funnel (§4), plus the optional
   `SHARDS_BOT_ORACLE=1` server hook (§3d). Build when the bot-tagged training
   corpus is actually needed.
5. **Phase 5 (optional) — encoding lint + LLM spot-judge.** §3c, run as an offline
   batch over the card DB / flagged cards. Feeds the `verified` workflow.

Phases 1–3 are built and deliver the primary goal (semantic bug-finding at scale).
On the **first serious run they found a real engine bug**: a self-banishing claimed
Destiny (`stolen_future`'s "Banish this" activated ability) was left in
`claimedDestinies` AND copied into `removedFromGame` — a duplicated card — because
`_selfBanish` only scrubbed the play zones. Fixed in `GameService._selfBanish` with
a regression test (`test/services/game_service_test.dart`, "a self-banishing claimed
Destiny leaves claimedDestinies"). Phase 4 adds real-server fidelity + the bot data
corpus; Phase 5 is the cross-check against printed text.

### Running it (dev-only)

```bash
# From the project root. Reuses the engine in lib/; ships in nothing.
dart run tool/selfplay/runner_inproc.dart --games 500 --mode mix
#   --games N        how many games (default 200)
#   --mode greedy|explorer|mix   bot policy (default mix: half clean, half coverage)
#   --players P      2–4 (default 2)
#   --seed-base S    first game's seed; game g uses seed S+g (default 1)
#   --out DIR        where deduped bug reports land (default tool/selfplay/bug_reports/)
```

Exit code is `2` when any bug was found (so a dev cron/CI step can detect it), `0`
when clean. Each bug report is a self-contained JSON file carrying the seed + the
full action sequence — a one-command repro. The output dir is gitignored.

---

## 8. Open questions for the operator

1. **Throughput target.** How many games per run (1k? 100k?) and how long are you
   willing to let it churn? Drives whether Tier A bulk + Tier B sampling is enough.
2. **Bot-tag default.** Reserved username prefix (`bot_`) is zero-effort; do you
   also want the `is_bot` flag + `game_type` column now, or defer until the model
   training actually needs the partition?
3. **Oracle strictness.** Should an oracle mismatch **halt** the run (fail fast,
   one bug at a time) or **log and continue** (collect all distinct bugs in one
   pass)? Log-and-continue + dedup is the recommended default for a scale run.
4. **LLM judge.** Worth wiring the optional §3c LLM spot-judge, or is the
   structured oracle + lint enough for now? (It's the slowest/most-costly piece and
   purely additive — easy to defer.)
</content>
