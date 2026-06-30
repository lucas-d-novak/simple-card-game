# Roadmap — optional / future enhancements

Things intentionally deferred. Nothing here blocks the limited alpha; they're
captured so they aren't lost. Grouped by area.

## Onboarding / auth

- **Invite-link login (`?invite=CODE`)** — let invitees arrive via
  `https://play.example.com/?invite=CODE`; the app auto-fills + saves the access
  token and they just enter a name (zero copy-paste; natural friend-of-friend
  forwarding). Built on top of the existing paste-once flow (keep the manual
  field). *Current state: paste-only — the user types the access code once and
  the browser remembers it (localStorage).*
- **Per-player credentials** — if the alpha grows beyond a single shared token,
  move from one shared access token to per-player accounts/keys.

## Server / hosting

- **SQLite persistence** — the shipped store is one-JSON-file-per-game
  (`server/lib/persistence.dart`), which survives restarts. SQLite is the design
  target for the always-on hosted phase (concurrent writes, queries for the
  stats DB below). *Note: the stats/telemetry DB already uses SQLite
  (`server/lib/stats_store.dart`); this item is only about migrating the
  per-game **persistence** store from JSON files to SQLite.*
- ~~**Cloudflare Tunnel deploy runbook**~~ — **DONE**:
  [`ai-docs/deploy_cloudflare.md`](ai-docs/deploy_cloudflare.md) documents the
  tunnel + custom domain + `wss://play.example.com/ws` routing (bare-link Option A),
  the Cloudflare-Pages-for-app vs box split, and the Pi `dart run` + `libsqlite3`
  setup.
- **Connection / lobby caps + rate limiting** — basic per-IP connection caps and
  action rate limits for a public endpoint (message-size cap + Origin allowlist
  already shipped).
- **Evict completed games** — `_games` keeps finished games in memory; add
  cleanup once volume matters.

## Player analytics / stats database

- **Persistent per-player action history** — a compressed log of every action
  each username takes (cards bought from the market, Destinies claimed, Relics
  recruited, plays/attacks/focus, outcomes), in a queryable store, for later
  mining. (See the dedicated design when started; the engine already produces a
  full action log per game — `GameService.actionLog` — which is a natural source.)

## Card data / faithfulness

- **Faithful base-game deck (88 cards)** — the market currently ships ~96
  in-scope cards / 163 copies (base + some expansion content) because the DB's
  `set` tagging is lossy. Per-card `copies` (pip) counts are correct; the *total*
  is larger than a single retail base game. Correct the `set` column against the
  BGG chapter list to offer an exact 88-card base mode.
- **Verify the remaining unverified cards** — ~41 in-scope cards are encoded but
  not yet human-confirmed against the printed card; raise verified coverage above
  the current ~71%.

## Community / bug intake

- **Discord bug-report channel + automated triage pipeline** — a Discord server
  where alpha players report bugs, wired to an automated agent pipeline that reads
  the channel and spins up investigator → implementation → verification agents to
  propose fixes. Design: [`ai-docs/discord_bug_pipeline.md`](ai-docs/discord_bug_pipeline.md).
  *Status: design drafted; not yet built.*

## AI

- **AI awareness of new mechanics** — the heuristic AI doesn't use Focus,
  Destiny, or Relics yet; it plays the classic way.
- **Self-play bots (dev-only) — training data + semantic bug detection** — two
  bots play each other at scale to (a) find runtime/semantic bugs ("the card
  didn't do what its text says") via a differential oracle and (b) emit
  bot-tagged training telemetry kept separate from human data. Ad-hoc, run only
  during development. Design: [`ai-docs/self_play_bots_design.md`](ai-docs/self_play_bots_design.md).
  *Status: design drafted; not yet built.*

## UI

- **Local-board draw-pile viewer** — the networked board shows your draw pile's
  contents A→Z; add the same tap-to-view on the local/hotseat board for parity.
- **Networked deferred effects via Play All / choice-gated** — target pickers
  prompt on single-card plays; Play All and choice-gated deferred effects use
  defaults (matches the local board's behaviour).
