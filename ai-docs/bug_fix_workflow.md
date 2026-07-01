# Bug-fix workflow — the parallel find-and-stamp-out loop

Our **principal method for fixing card and mechanic bugs.** When a bug (or a
stream of bugs) comes in, we don't hand-patch the one symptom and move on. We
spin up **parallel agents** that trace each bug to its true source, fix it,
prove the fix, and then hunt down every *other* card or mechanic sharing that
code path — because our bugs travel in classes (see
[`bug_patterns.md`](bug_patterns.md)).

This is the in-repo sibling of the deferred
[`discord_bug_pipeline.md`](discord_bug_pipeline.md): same investigate →
implement → verify spine, but driven interactively by us instead of from a
Discord queue, and **not** gated behind draft-PR-only. Here we fix on
`rld-mvp-sprint` directly.

> **Pair this with [`bug_patterns.md`](bug_patterns.md).** That doc is the field
> guide to recurring bug *shapes*; this doc is the *method* for stamping them
> out. Read the pattern first — if the incoming bug matches a known shape, you
> already know where the rest of the class hides.

---

## 0. The loop at a glance

```
 A card/mechanic bug arrives (from a live tester, a play session, or us)
   │
   ▼
 ┌──────── one workflow per bug — or one per conflict-GROUP ────────┐
 │ 1. FIND      trace to the ROOT CAUSE, not the symptom             │
 │ 2. FIX       minimal, targeted change at the source              │
 │ 3. CONFIRM   repro-then-green: a test that failed now passes      │
 │ 4. IDENTIFY  which OTHER cards/mechanics share this code path?    │
 │ 5. INVESTIGATE  check each of those for the same defect           │
 │ 6. REVIEW    adversarial pass over the whole change              │
 │ 7. ITERATE   if review finds a gap, loop back to the right step   │
 └────────────────────────────────────────────────────────────────────┘
   │
   ▼
 Tests green (608 + 8 goldens + 52 server) → summarize what changed
```

The non-negotiable steps are **4 and 5.** Anyone can fix the one card a tester
named. The value is finding the other five cards with the same
resource-icon transcription error, the same deferred-picker wiring gap, the same
seat-id-vs-username leak — *before* a tester hits them.

---

## 1. Routing: parallel vs. grouped

When a stream of bugs comes in, sort them before spawning anything:

- **Independent bugs → parallel workflows, one per bug.** Different files,
  different mechanics, no shared fix surface. Launch them concurrently.
- **Bugs that could conflict → one grouped workflow.** If two bugs touch the
  same file, the same card record, or the same mechanic, a single workflow
  handles them in sequence so parallel agents don't stomp each other's edits or
  produce merge-conflicting patches.

**Conflict test — group if any is true:**
- same source file (e.g. both touch `game_service.dart` combat, or the same
  `cards.json` record),
- same effect type in [`card_effect.dart`](../lib/models/card_effect.dart),
- same UI widget / picker flow,
- one bug's fix would plausibly change the other's repro.

When agents *do* edit files in parallel, isolate them in **git worktrees** so
their working trees can't collide.

---

## 2. The steps in detail

### 1. FIND — root cause, not symptom
- Reproduce first. A bug you can't reproduce, you can't confirm you fixed.
- **Card-data bugs: art is ground truth.** Open `assets/cards/<id>.jpg` and read
  the icon before trusting `rawText`/`notes` — the notes carried the original
  mis-transcription. (See `bug_patterns.md` §1.)
- **"Nothing happened when I clicked" bugs:** look at the effect wiring /
  deferred-picker path, not the card value. (See `bug_patterns.md` §2.)
- Name the root cause in one sentence before writing any fix. If you can't, you
  haven't found it yet.

### 2. FIX — minimal and at the source
- Smallest change that removes the root cause. Fix the data in `cards.json` or
  the codec/engine logic — not the symptom in the UI.
- Follow [`AGENTS.md`](../AGENTS.md): write/adjust the test *first*, keep edits
  small and incremental, don't change existing tests unless requirements changed.

### 3. CONFIRM — repro-then-green
- The proof is a **test that failed before the fix and passes after.** Run the
  targeted suite (`flutter test test/services/`, `test/data/`, etc.) after each
  change; finish on the full suite.
- Server-side mechanics: `cd server && dart test`.
- For visual/board bugs, a golden or a screenshot-report diff.

### 4. IDENTIFY — who else shares this code path? *(do not skip)*
- Match the bug to a **class** in `bug_patterns.md`. If it's a known shape, the
  doc already lists where the rest hide and the discriminator to use.
- Grep the shared surface: the same effect type, the same helper, the same
  faction batch, the same JSON field. Produce an explicit candidate list.

### 5. INVESTIGATE — check each candidate
- **Fan out.** This is the step that most rewards parallel subagents: give each
  a batch of candidates + the discriminator, ask them to flag only clear
  matches and say UNCLEAR otherwise. Verify every claimed match against art /
  rules before changing it.
- Fold any confirmed siblings into the same fix + tests.

### 6. REVIEW — adversarial pass
- A separate agent (fresh eyes) reviews the whole change: does the fix match the
  card art / the mechanics doc
  ([`fragments_of_boundlessness_mechanics.md`](fragments_of_boundlessness_mechanics.md),
  source of truth for rules)? Did step 4/5 actually cover the class? Any
  regressions in adjacent tests?

### 7. ITERATE
- If review finds a gap, loop back to the *earliest* step it implicates (often
  step 4 — an under-scoped class), not just a patch on the patch.

---

## 3. Definition of done

- [ ] Root cause named, not just the symptom.
- [ ] Fix is minimal and at the source.
- [ ] A test that **failed before / passes after** locks it in.
- [ ] The rest of the bug's **class** was searched and any siblings fixed.
- [ ] Adversarial review passed.
- [ ] Full suite green: **608 engine + 8 golden + 52 server** tests.
- [ ] One-paragraph summary of what changed and which cards/mechanics were touched.

---

## 4. Guardrails

- **Branch:** fix on `rld-mvp-sprint`. Never push to `main` (owned by someone
  else — see [`CLAUDE.md`](../CLAUDE.md) "Branch strategy").
- **Tests are the contract.** Don't edit an existing test to make a fix pass
  unless the requirement genuinely changed.
- **No silent scope caps.** If step 4 finds a class too big to clear in one pass,
  say so and list what's deferred — don't fix three of eight and imply "done."
