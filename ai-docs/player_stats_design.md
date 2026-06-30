# Player Stats & Telemetry — Concept Design (v0.2, for iteration)

**Goal:** a persistent, queryable record of what every player does, so we can
power (a) **leaderboards**, (b) **fun data analysis** ("what does Ray buy
most?"), (c) **game-balance** decisions (which cards over/under-perform), and
(d) **training data for a learned AI** — `(game state, decision)` pairs to imitate
or improve on human play. Mine it later.

**Storage decided:** SQLite from the start (`sqlite3` package). **Identity:**
name-as-key for the alpha (migrate to stable UUIDs later; schema unchanged).
**Surfacing:** offline-only first (record now; build leaderboard/profile UI once
the metrics prove useful).

## Two data shapes — keep them distinct

This is the key architectural call. There are TWO records, and they answer
different questions:

1. **Outcome events** (§2) — *what happened*. Compact, one row per action. Powers
   leaderboards, fun stats, and balance. ("Ray recruited Kiln Drone on turn 3.")
2. **Decision records** (§4b — the ML layer) — *the full context a choice was made
   in*: the available options + the actor's resources + board state at the moment
   of choosing, plus which option they picked. A `(state → choice)` pair. Powers
   training a model to play. ("Given THIS board, with THESE 6 cards available and
   THIS health/mastery/gems, Ray chose Kiln Drone over the other 5.")

Both derive from the same emission points; the decision record just snapshots
more context. Store both; they share the event stream and the SQLite db.

This is a *design to iterate on* — the measurements section especially. Nothing
is built yet.

---

## 1. Design principles

1. **Capture structured EVENTS, not parsed prose.** The existing
   `GameService.actionLog` is human-readable strings ("recruited Kiln Drone for
   2 gems") — great for the in-game Log sheet, painful to mine. Analytics needs
   typed events with card ids, amounts, turn, game id, player. Emit those
   alongside the prose log (same call sites).
2. **Append-only event log is the source of truth.** Every metric is *derived*
   from the raw event stream. Don't pre-aggregate into shapes you'll regret —
   store raw events, compute rollups on top. You can always recompute a new
   metric from history; you can't recover an event you never recorded.
3. **Server-side only.** Events are recorded by the authoritative server (it
   sees every accepted action). Clients never write stats → no tampering.
4. **Stable identity.** A "player" is keyed by a stable `playerId`. (Today that's
   the chosen name + shared token. When real accounts land, swap the key; keep
   the event schema.)
5. **Privacy/honesty.** It's our own players in an invite alpha, but: store only
   game actions, not chat/PII. Make it clear in the About/roadmap that play is
   logged for balance + leaderboards.

---

## 2. The event model

One row per meaningful action. Proposed `GameEvent`:

```
GameEvent {
  eventId      // monotonic per-server id (ordering)
  ts           // wall-clock (server) — for time-series; engine has no clock,
               // so the SERVER stamps it, not GameService
  gameId       // which game
  turn         // engine turn number
  seat         // engine seat (p0..) — for per-game position effects
  playerId     // stable player key (the lobby id)
  type         // enum (below)
  cardId?      // the card acted on (recruit/play/banish/destroy/claim/recruitRelic)
  cardName?    // denormalized for convenience (ids are stable; names readable)
  faction?     // card faction (denormalized — saves a join for faction stats)
  cost?        // gem cost paid (recruit) / card cost
  amount?      // damage dealt, gems/power/mastery gained, etc.
  targetId?    // opponent playerId for attacks/destroy
  meta?        // small JSON for type-specifics (choiceIndex, source zone, …)
}
```

### Event types (v0.1)
Mapped to the existing `_log` call sites + a few additions:

| type | when | key fields |
|---|---|---|
| `gameStart` | game begins | players, seats, characters, marketSeed |
| `turnStart` | each turn | turn, playerId |
| `play` | playCard | cardId, faction, cost |
| `recruit` | buyCard (market) | cardId, faction, cost (gems paid) |
| `focus` | focus() | (mastery +1) |
| `attackPlayer` | attackPlayer | amount, targetId |
| `attackChampion` / `destroyChampion` | combat | cardId, targetId |
| `claimDestiny` | claimDestiny | cardId |
| `useDestinyAbility` | useDestinyAbility | cardId |
| `recruitRelic` | recruitRelic | cardId |
| `banish` / `scrap` / `returnFromDiscard` | deck thinning | cardId |
| `gameEnd` | game over | winnerId, loserIds, turns, winType (elimination/mastery) |

That covers "what cards do they buy (market, destinies, relics)" directly:
`recruit` + `claimDestiny` + `recruitRelic` events, grouped by `playerId` +
`cardId`.

---

## 3. Storage

**Phase 1 (alpha): append-only JSONL file(s).** `server/data/events/<date>.jsonl`,
one JSON event per line. Zero deps (matches the project), crash-safe (append +
flush), trivially greppable, and easy to load into anything (pandas, DuckDB,
SQLite) for offline mining. The server already has a `GamePersistence` pattern to
mirror.

**Phase 2 (hosted/always-on): SQLite** (already the roadmap target). Same event
schema → one `events` table + derived `player_stats` / `card_stats` rollup tables
(or just views). Queries like "top cards by player" become one SELECT. The JSONL
is forward-compatible: a loader imports it into SQLite.

**Rollups (either phase):** keep raw events; compute these on read (or as cached
materialized tables refreshed per game-end):
- `player_card_counts(playerId, cardId, acquireType, n)` — the core "what they
  buy" table.
- `player_summary(playerId, games, wins, winRate, avgTurns, favFaction, …)`.
- `card_summary(cardId, timesAcquired, winRateWhenAcquired, avgTurnAcquired, …)`.

---

## 4. Measurements — the interesting part (iterate here)

Tiered by the three goals. **★ = high-signal, build first.**

### A. Player profile / "fun data" (the "what does X buy" stuff)
- ★ **Most-recruited cards** per player (market), top N — your headline ask.
- ★ **Favourite faction** — share of recruits/plays by faction; a "main".
- **Destiny & Relic picks** — which Destinies they claim, which Relic they take
  (offensive vs defensive) — reveals playstyle.
- **Buy curve** — avg gem-cost of cards recruited by turn (do they ramp cheap
  early, splurge late?).
- **Aggression index** — total damage dealt / game, attacks vs champions vs
  players, focus-uses (mastery-rush) — a rush-vs-control fingerprint.
- **Signature card** — the card they recruit far more than the player average
  (their "tell").
- **Pace** — avg turns-per-game they're involved in; avg actions/turn.

### B. Leaderboards (competitive)
- ★ **Win rate** (with a min-games threshold to avoid 1-0 = 100%).
- ★ **Games played / wins** — raw volume board.
- **Mastery-win vs elimination-win** split — *how* they win.
- **Fastest win** (fewest turns) — a speedrun board.
- **Win streak** (current / best).
- **Nemesis / rival** — who they beat / lose to most (needs targetId + gameEnd).
- (Later, if desired) a simple **Elo/Glicko rating** from head-to-head results —
  more robust than raw win-rate for a leaderboard.

### C. Game balance (the analyst view — aggregate across ALL players)
- ★ **Card win-rate** — for each card, win rate of games where a player recruited
  it (vs base rate). Flags over/under-powered cards. (Confounded by skill; still
  a strong first signal.)
- ★ **Card pick rate** — how often each card is recruited when available
  (popularity). A card with low pick + low win-rate = dead weight; high pick +
  high win-rate = possibly overtuned.
- **First-pick / priority** — avg turn a card is recruited (early = high
  priority).
- **Faction balance** — win rate by faction; recruit share by faction.
- **Destiny/Relic balance** — claim rate + win-rate per Destiny / per Relic.
- **Focus/mastery-rush prevalence** — how often games are won via the Infinity
  Shard (mastery 30) vs elimination, and whether that's trending (signals a
  degenerate strategy).
- **Game length distribution** — median turns; flags "too swingy / too grindy".
- **Curse of the leader** — does going first (seat p0) win more? (seat-bias check.)

## 4b. ML training data — DECISION RECORDS (the learned-AI layer)

To train a model to play (imitation learning now; RL/improvement later), we need
`(state, choice, outcome)` tuples — the **full context at each decision point**,
the **choice made**, and (joined later) **whether that player won**. This is the
data your message asks for: "when a card is purchased, save the other cards that
were available, and the current health/mastery."

### A decision record (one row per CHOICE the player faces)
```
DecisionRecord {
  decisionId, gameId, turn, seat, playerId, ts
  decisionType   // recruit | play | claimDestiny | recruitRelic | attackTarget |
                 // chooseOne | banishTarget | useDestiny | focusOrNot | endTurn
  // --- the OPTIONS the player chose among (the action space at that instant) ---
  options[]      // e.g. for recruit: every center-row cardId + cost + faction +
                 // type + whether affordable; PLUS the implicit "buy nothing"
  chosenIndex    // which option they took (label for supervised learning)
  // --- the STATE features (everything observable that informs the choice) ---
  self {  health, mastery, gems, power, handSize, deckSize, discardSize,
          championsInPlay[], claimedDestinies[], relicRecruited,
          handCardIds[] /* their own hand is known to them */ }
  opponents[] { health, mastery, championsInPlay[], handCount, discardSize }
  board { centerRowCardIds[], destinyRowCardIds[], infinityDeckCount, turn }
  // --- outcome, joined at game end ---
  playerWon?     // filled in when the game resolves (the training target/reward)
}
```

Crucially this is a **superset of the redacted view** the player could see — we
record it from the player's OWN information set (their hand is known to them; the
opponent's hand is a count), so a model trained on it learns from *legal*
information and won't cheat. (Important: do NOT record hidden info as a feature,
or the model learns to use knowledge a real player can't have.)

### When to snapshot a decision record
At every point the engine *offers a real choice* — primarily:
- **recruit** (center row) — ★ your headline case: options = the 6 center cards
  (+ "buy nothing"), state = health/mastery/gems/etc.
- **claimDestiny / recruitRelic** — options = the destiny row / the 2 relics.
- **play which card / in what order** — options = hand cards not yet played.
- **chooseOne** (X-or-Y cards) — options = the effect choices.
- **attack target / banish target / destroy target** — options = legal targets.

Each is a labeled example: "in THIS state, from THESE options, the human picked
THIS." Imitation learning fits a policy `π(option | state)`.

### Iterated MEASUREMENTS / features for ML (what to compute from decisions)
The raw record above is the substrate; these are the derived signals worth having:

**Per-decision features (model inputs):**
- ★ **Option encodings** — for each available card: cost, faction (1-hot), type,
  shield, has-activated-ability, its primary value (gems/power/mastery/draw), and
  whether the player's CURRENT conditionals would be satisfied if bought/played
  (we already compute `conditionsSatisfied`).
- ★ **Resource state** — gems available (affordability mask), mastery (gates
  Destiny@5/Relic@10 + Infinity-Shard tiers), power, health, hand size, deck/discard.
- ★ **Tempo/threat** — turn number; opponent health (lethal-this-turn?), opponent
  champion shields (guard blocking?), your unblocked-damage-this-turn.
- **Synergy context** — factions already played this turn (Unify/Inspire/Echo
  triggers), cards in discard (Echo/return targets), champions controlled
  (per-champion scaling) — the stuff conditionals key on.
- **Affordability frontier** — most expensive affordable card; gems "wasted" if
  they pass.

**Labels / targets (model outputs to learn or evaluate against):**
- ★ **chosenIndex** — the imitation target (predict the human's pick).
- **playerWon** — the outcome reward (for value learning / weighting examples by
  winners → "learn from good players").
- **Decision EV proxies** (derived, for analysis + reward shaping): did this
  recruit get played and trigger its conditional? did this attack reduce an
  opponent toward lethal? did this Focus reach a mastery tier?

**Dataset-level signals (for model quality + balance):**
- **State-action coverage** — how many examples per (decisionType, turn-bucket,
  mastery-bucket) — find under-sampled states.
- **Human policy entropy** per state cluster — where humans agree (clear best
  play) vs disagree (interesting / skill-expressing decisions).
- **Win-weighted action frequency** — `P(action | state, player won)` vs overall
  — what *winning* players do differently (a cheap "expert policy" prior before
  full RL).
- **Regret proxy** — for recruit decisions, did passing on a high-pick-rate card
  correlate with losing? (balance + teaches the model card priority.)

### Practical notes for the ML layer
- **Size:** decision records are bigger than events (they embed the option set +
  state). At alpha volume that's fine in SQLite. For training you'll export a
  flat table (one row per decision, columns = features) — a single SQL view does
  this.
- **Replayability:** because we also persist full game snapshots
  (`GameStateCodec`), we can RE-DERIVE additional decision features later from the
  game state at that turn if we under-captured — but capturing the option set +
  resources at decision time is the part that's expensive to reconstruct, so
  capture those now.
- **Two storage tables:** `events` (compact, §2) and `decisions` (rich, this
  section). Leaderboards/balance read `events`; ML exports read `decisions`.
  `decisions` join to `gameEnd` for the `playerWon` label.

### Guardrails for honest numbers
- **Min-sample thresholds** on every rate (a card recruited 3× tells you nothing).
- **Confidence intervals / Wilson score** on win-rates for small N (so
  leaderboards and balance flags don't chase noise).
- **Skill confounding** — card win-rate ≠ card power (good players pick good
  cards AND win). A later refinement: normalize by the recruiting player's
  baseline win-rate, or look at *mirror* picks. Note it; don't over-claim early.

---

## 5. Where it plugs into the code

- **Emit:** a thin `StatsRecorder` the server owns. `GameSession.apply` already
  funnels every accepted action — emit a typed `GameEvent` there (it knows
  gameId, seat→playerId, turn, and the action payload). The engine stays pure;
  the *server* stamps `ts` and writes. `gameStart`/`gameEnd` emit from the lobby
  start + the win check.
- **Store:** `StatsStore` (JSONL now, SQLite later) — mirrors `GamePersistence`.
- **Read/serve:** a `/stats` HTTP endpoint (read-only JSON) + optionally a
  `stats` lobby action so the client can show leaderboards / a profile card.
  (Could also stay offline-only at first — just mine the JSONL.)

---

## 6. Open questions (decide before building)

1. **Identity stability** — names are reused/changeable. Tie events to a more
   stable key now (e.g. a per-player UUID minted at first connect, stored in
   their localStorage alongside the token), or accept name-as-key for the alpha
   and migrate later?
2. **In-app surfacing** — build leaderboard/profile UI in the alpha, or keep
   stats *offline-only* (mine the JSONL yourself) at first and add UI once the
   metrics prove useful?
3. **Card win-rate confounding** — ship the naive version (flag it as
   skill-confounded) or hold balance metrics until we can normalize?
4. **Retention/scope** — keep all events forever (fine at alpha volume), or cap?

---

*Next step after sign-off: pick the v1 measurement set (the ★ items are my
proposed first cut), confirm storage (JSONL→SQLite), and decide identity +
in-app-UI questions above. Then implement StatsRecorder + StatsStore + the
event emission, with the leaderboard/profile read path.*
