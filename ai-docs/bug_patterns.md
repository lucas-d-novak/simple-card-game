# Bug patterns — a field guide from the alpha bug-bash

A retrospective on the bugs fixed during the live alpha play-testing sessions.
The point is not the individual fixes (those are in git history) but the
**recurring shapes** — so the next bug of the same shape is recognized and
fixed in one pass, and so we can build guards that catch a whole class at once.

Each pattern lists: the tell (how to recognize it), the root cause, the cards/
sites hit, the fix, and — most usefully — **how to catch the rest of the class
proactively** rather than waiting for a player to hit each one.

---

## 1. Resource-icon transcription errors (the biggest class)

**The tell:** a card "does the wrong thing" — grants gems when it should heal,
grants power when it should give mastery, etc. Reported as "X is coded wrong /
gave me gems not health."

**Root cause:** the card DB was scaffolded from the printed art, and the four
resource icons are easy to confuse at low art resolution:

| Resource | Icon | Confused with |
|----------|------|---------------|
| **Gem** (currency) | smooth cyan/blue **diamond / teardrop** | everything |
| **Health** | **green CROSS / plus** in a rounded square | gems (green-tinted cards), the champion shield/toughness badge (also a green cross!) |
| **Power** (damage) | **orange/red hexagon / burst** | gems on green Undergrowth cards |
| **Mastery** | **gold/purple multi-pointed STAR / octagon** | gems, the cost badge (also a gem/octagon) |

**Cards hit (16+):** spore_cleric, chlorophyte_guardian, undergrowth_aspirant,
vinereaper, carnivorous_vine, gian_shard_wyrm, panconscious_crown,
entropic_talons (gems→health); additri_gaiamancer, general_decurion,
reactor_drone, the_lost, brute (gems→power); the_rotten, paradigm_shift,
slipstream_shard, giga_source_adept, nexus_datic_hunter (gems→mastery);
orm_madu (mixed). Plus value typos (wraethe_skirmisher 4→6, leshai_knight 3→6).

**How to catch the class (not one-at-a-time):**
- **Art is ground truth.** Always open `assets/cards/<id>.jpg` and read the icon
  shape/colour before trusting `rawText` or `notes` (the notes were frequently
  wrong — they carried the original mis-transcription).
- **The discriminators that actually work:**
  - The **cost badge** (top-right) is ALWAYS a gem — use it as your on-card
    colour reference for "what a gem looks like on THIS card's printing."
  - A number in a **green cross** in the effect text = health. A green cross as
    a big stat badge mid-right/bottom-left of a **champion** = its shield/
    toughness (stored as `shield`, NOT an effect — never encode it as a gain).
  - **Gold/purple pointed star = mastery**, never gems.
- **Fan out.** This class is audited efficiently by subagents: give each a batch
  of `<id> | <art> | <what we encoded>` and the discriminator table above, ask
  them to flag only clear mismatches and say UNCLEAR otherwise. Verify every
  flagged card yourself against the art before editing (agents disagreed on the
  green-square gem-vs-health call — the cost-badge reference resolves it).
- **Build guard idea (not yet built):** a `tool/` check that flags any card
  whose `rawText` icon tokens (`[gem]`, `[health]`, `[mastery]`, `[power]`)
  don't match the effect `type`s in its encoded effects. That turns "re-read the
  art" into "re-read only the cards where text and code disagree."

---

## 2. Deferred-effect pickers never fire (the second-biggest class)

**The tell:** "I clicked Use/Play and nothing happened" — a banish/recruit/
scrap that should prompt for a target silently does nothing. Or "it loops."

**Root cause:** several effects (banish, scrap, destroy-champion, return-from-
discard, recruit-from-center, fast-play) resolve to a **no-op in the engine**
and expose a follow-up method the UI must call after the player picks a target.
Every code path that plays a card has to remember to **queue that picker**. Each
new play path forgot:

- **Play All** sent one action, queued nothing → Shadow Apostle's banish skipped.
- **ChooseOne** branches (Datic Inquisitors "recruit for free") queued nothing.
- **Champion Exhaust / Destiny abilities** (Aedifex, Forged in Flame) queued
  nothing.
- **RecruitFromCenter / FastPlayFromCenter** pickers didn't even exist on the
  networked board.
- A picker nested inside a **ConditionalEffect** or **ChooseOneEffect** needed
  recursion to be found.

**The fix shape (repeated):** every play path calls `_queueDeferredSelection`,
and `_deferredPickerFor` / `_hasDeferredEffect` recurse into conditional /
choose-one groups. Pickers drain from a **queue** (not a single slot) so a
multi-deferred action (Play All over several banish cards) prompts each in order.

**How to catch the class:**
- **One choke point.** There should be exactly one "I just played/activated
  something" helper that ALL paths (single play, Play All, champion Exhaust,
  Destiny Use, chooseOne branch) funnel through to queue pickers — so a new play
  path can't forget. Audit for any `client.playX(...)` / `useX(...)` call site
  that isn't followed by a deferred-selection queue.
- **Invariant to assert:** the set of effect types that `_resolveEffects`
  treats as deferred no-ops must EQUAL the set `_deferredPickerFor` handles.
  When a new deferred effect is added to the engine, a test should fail until the
  UI picker is added. (Today they're two hand-maintained switches that drifted.)

---

## 3. Server ships seat ids where the UI wants usernames

**The tell:** "player 1 / player 2 / p0 / p1" shown instead of usernames — on
namebars, in the action log, in the past-games winner, on the deck label.

**Root cause:** the engine names seats `p0..pN` (immutable). The lobby maps seat
↔ username. Anywhere the redacted view shipped a raw seat id, the UI showed it.
Also, some **engine log messages embed the seat name in the string**
("destroyed p0's champion", "p0 wins!"), which the client can't remap after the
fact.

**The fix shape:** pass a seat→username `names` map into `redactFor`; ship each
player's `name` as the username (keep `id` = seat id for turn/winner matching);
rewrite seat-id tokens inside log message strings too.

**How to catch the class:**
- **Rule:** the wire may carry seat ids as **identifiers** (for matching), but
  every **display** string the client renders should already be a username. Any
  new user-facing field or log message is suspect until checked.
- The winner mapping (`winnerLobbyId`) is now centralized + unit-tested — do the
  same (one mapping, one test) for any future seat↔name translation instead of
  re-deriving it per call site.

---

## 4. Stale deployed build masquerading as a live bug

**The tell:** "it's STILL broken" after a fix was pushed; "the animation doesn't
show"; "Giga still shows gems." Often the fix is already correct in git.

**Root cause:** the browser served a cached build (the service worker didn't
reliably activate on refresh). A large share of "still broken" reports were this.

**The fix:** version-poll auto-refresh — `build_web.sh` stamps `version.json`
with the git SHA; the client polls it and hard-reloads once when it changes.

**How to catch the class:**
- **Before debugging a "still broken" report, confirm the build.** Ask "did you
  redeploy / hard-refresh?" or check the running build's SHA. Screenshotting the
  CURRENT branch build (which shows correct behaviour) proves it's a deploy-lag,
  not a code bug — this saved hours of chasing ghosts.
- Server-side changes (relics, usernames, winner recording, log rewriting) need
  a **Pi server restart**, not just a web rebuild — and only take effect for
  games that START/FINISH after the restart. "It didn't work" on an in-flight or
  already-finished game is expected.

---

## 5. Action-state that outlives the game / turn

**The tell:** "illegal action 'focus'" shown in the lobby after winning.

**Root cause:** a mastery win leaves it "your turn" with gems, so turn-gated
action buttons (Focus) stayed live; a tap sent an action to a finished game,
the server rejected it, and the stale error lingered into the lobby.

**The fix shape:** gate all turn actions on `!isGameOver` (fold it into
`myTurn`), and clear transient error state on context transitions (back-to-lobby).

**How to catch the class:** any affordance gated on "my turn" should also be
gated on "game not over." Any error surface (lobby) should not show errors from
a different context (an in-game action).

---

## 6. Rules-model mismatches (the engine can't express the card)

**The tell:** a card's condition is subtly wrong — "it should be 40 HEALTH not
40 mastery" (Furrowing Elemental, Strategic Mastermind).

**Root cause:** the condition vocabulary was missing a kind (`healthAtLeast`), so
the transcriber approximated with the nearest existing one (`masteryAtLeast`) —
double error: wrong resource AND wrong threshold semantics.

**How to catch the class:** when a card fix requires a NEW condition/effect kind,
suspect that other cards were ALSO approximated onto the wrong existing kind.
After adding `healthAtLeast`, grep for other "if you have N (health)" rawText
still encoded as `masteryAtLeast`.

---

## Meta-patterns for smarter bug-fixing

1. **Most "card X is wrong" bugs are data, not code** — and the data's own
   `notes`/`rawText` are unreliable; the **art is the source of truth**. Read it.
2. **Most "nothing happened when I clicked" bugs are a missing UI follow-up for a
   deferred engine effect** — check the play-path → picker-queue choke point.
3. **Most "wrong name / p0 / player 1" bugs are seat-id-vs-username leaks** — one
   translation layer, applied everywhere the UI displays (not matches) a player.
4. **A meaningful fraction of "still broken" is stale deploy** — verify the build
   before debugging.
5. **Audits parallelize well**: batches of cards → subagents with a crisp
   discriminator rubric → human-verify the flags. Reserve solo reads for the
   ambiguous ones.
6. **When a fix needs a new primitive** (condition kind, effect type, picker),
   the same primitive was probably approximated elsewhere — sweep for siblings.
