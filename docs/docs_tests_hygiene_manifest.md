# Docs + Tests Hygiene Manifest

> **READ-ONLY audit deliverable.** This is a plan for a *later* hygiene pass — no
> docs or tests were changed to produce it. Every DELETE/MERGE below carries the
> evidence that it is safe; anything uncertain is marked
> **⚠ NEEDS HUMAN CONFIRM — DO NOT AUTO-DELETE**.
>
> Audited branch `rld-mvp-sprint`, 2026-07-01.

## Headline

- **Stale docs: 16** — 11 with concrete wrong counts/facts to fix + 5 shipped
  design/plan docs that should get a "historical/implemented" banner or be archived.
- **Broken cross-links: 0** — every relative markdown link across the CLAUDE.md
  tree + ai-docs + README/ROADMAP/AGENTS resolves, and every backtick-referenced
  file path spot-checked (schema.json, cards.json, web/manifest.json, version.json,
  build scripts, CI workflow, dart_test.yaml, tool scripts, design_reference/) exists.
- **Test-merge opportunities: 1 clear cluster** (4 codec files → fold effect-codec
  groups into `effect_codec_test.dart`, relocating — not deleting — their unique
  groups) **+ 3 needs-confirm consolidation clusters** (combat/shield, legacy
  ConditionalPower, passive-champion UI). **No whole test file is safe to delete**
  — every candidate holds at least one unique assertion.

## Ground-truth counts (verified from code, for reference)

| Fact | Docs claim | Actual (code) |
|---|---|---|
| `CardEffect` subclasses | "37" (CLAUDE tree) / "31" (README + ai-docs) | **43** (`grep 'class \w+ extends CardEffect' lib/models/card_effect.dart`; 42 excl. legacy `GainMoneyEffect`) |
| `GameConditionKind` values | "19" | **19** ✓ accurate |
| `cards.json` entries | "183" | **183** ✓ accurate |
| `card_definitions.dart` cards | "55" | **55** ✓ accurate |
| Verified cards in DB | "102" / "101" | **114** (`verified: true` in cards.json) |
| Live market size | "96" (some) / "88" (others) | doc-internal conflict; `lib/data/CLAUDE.md` authoritatively says **88 unique / 155 copies** (relics excluded) — verify by running `buildMarketDeckFromDatabase` |
| Engine tests | "791" | **≈872** non-golden (`^\s*(test\|testWidgets)\(` = 880 incl. 8 goldens) — recount after any merge |
| Golden tests | "8" | **8** ✓ accurate |
| Server tests | "64" | **65** (`^\s*test\(` in server/test) |

The 5 effect subclasses added since the "37" era: `AcquireCostReductionPerChampionEffect`,
`BonusDrawNextTurnOnUnblockedDamageEffect`, `IgnoreGuardThisTurnEffect`,
`DoublePowerEffect`, `CopyAllPlayedCardsEffect`, `RevealAndCopyTopOfDecksEffect`
(37 → 43; note the "37" itself already lagged reality).

---

## (a) STALE DOCS to fix / archive

### A1. Concrete wrong counts/facts — fix in place

| Doc | Stale claim (evidence) | Correct value | Safety |
|---|---|---|---|
| `CLAUDE.md` (root) | "37 card effect types" / "all 37 effect types" / "(37 effect types)" repeated (lines 7, 58, 254-…, 308, 369); "791 engine tests" + "64 server tests" (lines 13, 339-353); "102/142 in-scope verified" (306, 370); mechanics-table "DB-driven market + separate Destiny supply (**96** + 29)" (274) | 43 effects; recount tests (~872/65); verified now 114; market 88 | SAFE (code-verified). "102/142 **in-scope**" subset — mark verified total is 114; ⚠ confirm in-scope subset |
| `README.md` | "GameService engine (**31** effect types…)" (370); market "built from the card DB (**96** cards)" (129) — but line 17 already says "88 in-scope cards" (self-contradiction); "102 of the 142 in-scope cards verified" (16-17, 242) | 43 effects; 88 market; verified 114 | SAFE for 31→43 & 96→88 (contradicts own line 17); ⚠ verified in-scope subset |
| `test/CLAUDE.md` | "791 engine tests" + "64 server tests" (7, 9, 106); line 41 mislabels `corrected_effects_test.dart` as "codec coverage for the new effect types" (it is a `cards.json` resource-correctness test, no codec involved) | recount; relabel corrected_effects | SAFE |
| `lib/models/CLAUDE.md` | "**37 subtypes**" (24); "the `_resolveEffects` switch … is exhaustive over them" (24) | 43 subtypes | SAFE |
| `lib/services/CLAUDE.md` | "handles all **37** CardEffect subtypes" (78) | 43 | SAFE |
| `ai-docs/bug_fix_workflow.md` | "(608 + 8 goldens + 52 server)" (40); "608 engine + 8 golden + 52 server" (131) | recount (~872/8/65) | SAFE |
| `ai-docs/discord_bug_pipeline.md` | "the 608 engine/UI tests CI runs" (246); "52 server tests" (247) | recount | SAFE |
| `ai-docs/multiplayer_architecture.md` | "608 engine tests + 52 server tests" (~1096) — otherwise current, header correctly says Phase 0/1 implemented | recount | SAFE |
| `ai-docs/self_play_bots_design.md` | "switch over all **31** `CardEffect` types" (26); "`_resolveEffects`, **31** types" (160) | 43 | SAFE. Also §0 heading "chosen: Tier B" vs Tier-A-only impl → ⚠ NEEDS HUMAN CONFIRM (intent vs reality; §7 status markers are accurate) |
| `ai-docs/engine_gaps.md` | Already self-marked "(Historical)"; but status note "has since grown to **31** `CardEffect` types" (37-47) | 43 | SAFE (count only) |
| `ai-docs/card_coverage_gaps.md` | Self-marked SUPERSEDED (redirects to `assets/card_db/COVERAGE.md`); summary row "Verified \| 101" (24) | 114 | SAFE to note; doc is honestly historical |

### A2. Shipped design/plan docs — add "historical/implemented" banner or archive

These have no *wrong* current facts beyond stale counts, but read as pre-build
plans for work that has shipped. Not marked historical.

| Doc | Status | Action |
|---|---|---|
| `ai-docs/engine_phase2_plan.md` | "14→31 effect types" plan; shipped (43 now). Figures: "cover ~42 of 66 cards" (20), "263 existing tests" (74) | Add historical banner / archive |
| `ai-docs/engine_phase3_plan.md` | "14 → 31 subtypes … 22 cards remain blocked" (3); all F1–F13 families landed | Add historical banner / archive |
| `ai-docs/implementation_plan.md` | v6 17-step plan; Steps 1-13b,15 shipped; dated "23 tests" baselines | Add historical banner / archive |
| `ai-docs/implementation_plan_review.md` | Peer review of **v5**; "all issues addressed in v6" — point-in-time artifact | Archive (historical by nature) |
| `ai-docs/player_stats_design.md` | "v0.2 for iteration" — store shipped verbatim (`stats_store.dart`/`stats_capture.dart`); framing only is stale | Add "implemented" banner (low priority) |

### A3. Currently accurate (no action) — recorded for completeness

`ai-docs/bug_patterns.md`, `card_list_source_bgg.md`, `deploy_cloudflare.md`,
`responsive_ui_design.md`, `visual_iteration_system.md`, `frontend_assets_research.md`,
`fragments_of_boundlessness_mechanics.md` (declared rules source-of-truth),
`design_reference/DESIGN_SPEC.md` + PNGs, `ROADMAP.md`, `AGENTS.md`,
`lib/data/CLAUDE.md` (authoritative on the 88/155 market), `lib/ui/CLAUDE.md`.
`ai-docs/animation_system_design.md` — status line roughly accurate; ⚠ "only
Iterations 1-2 implemented" may understate shipped fly-animations (needs confirm).

---

## (b) MERGE candidates

### DOCS
No doc-to-doc merges recommended. The five A2 plan docs could be **consolidated
into a single `ai-docs/_archive/` folder** (organizational, not a content merge) —
that is a judgment call, ⚠ NEEDS HUMAN CONFIRM.

### TESTS

**B1. CLEAR — codec round-trip fragments → `test/data/effect_codec_test.dart`**
(the canonical 917-line `encodeEffect`/`decodeEffect` suite).

| Source | Fold in | MUST relocate, not delete (unique coverage) |
|---|---|---|
| `test/data/new_effects_codec_test.dart` | `new-effect codec round-trips` + `batch-2 codec round-trips` groups | its `cards.json wiring` group (Venator, Skry-77, Hounds of Volos, Nexus, Breaker, Cinder Scars, Legion Carrier, Dispossessed, World Piercer, Dash) — real-DB, keep |
| `test/data/mastery_abilities_codec_test.dart` | `new-effect codec round-trips` (ignoreGuardThisTurn, doublePower, copyAllPlayedCards) + `countsAsFactions serialization` | `GameStateCodec ignoresGuardThisTurn` + `cards.json wired shapes` — keep |
| `test/data/conditional_cannot_be_attacked_codec_test.dart` | `effect_codec — conditional cannotBeAttacked` group | `game_state_codec — StaticModifier round-trip` + `card DB — three cards decode` — keep |

Overlap evidence: each file re-declares its own local `roundTrip()`/`encodeEffect`
helper and its round-trip group is the same *form* as `effect_codec_test.dart`'s
groups. **Safety: consolidate carefully — NO file is a safe whole-delete**; the
`cards.json`-wiring and `GameStateCodec` groups are unique and must move, not vanish.
Opportunity to hoist the duplicated `roundTrip()` into a shared helper.

**B1b. OPTIONAL** — `test/data/ingeminex_codec_test.dart` is misnamed: it tests
`GameStateCodec`, not `effect_codec`. It could fold into
`test/data/game_state_codec_test.dart` as one more round-trip group (unique:
entity HP-pool accumulation + reward-on-kill after decode). Keep the assertions.

**B2. ⚠ NEEDS HUMAN CONFIRM — combat/shield cluster**
`test/services/shield_combat_model_test.dart`, `owner_shield_data_test.dart`,
`conditional_cannot_be_attacked_test.dart`, and the shield/`cannotBeAttacked`
groups in `static_modifiers_test.dart`.
Overlap: "`cannotBeAttacked` blocks direct attack" asserted in 3 files;
"shieldBuff reduces player damage but not champion-destroy threshold" in 2. But
each file owns unique coverage — `shield_combat_model_test` uniquely holds the
**50-HP cap** group and the **hand-shield-sum reduction** group;
`owner_shield_data_test` is the real-`cards.json` cards (datic_robes, praetorian,
one_mind_one_army); `conditional_cannot_be_attacked_test` is the condition matrix.
**DO NOT auto-delete.** Safest partial: fold only the *basic* duplicated
regressions in `shield_combat_model_test` into `static_modifiers_test`.

**B3. ⚠ NEEDS HUMAN CONFIRM — legacy ConditionalPower vs new conditions**
`test/services/game_service_test.dart` still has legacy `ConditionalPowerEffect
(Step 10)` (line ~1839) + `(Phase 1)` (line ~2240) groups on the OLD effect class;
`test/services/game_condition_test.dart` is the comprehensive new
`ConditionalEffect`/`ScalingResourceEffect` suite (and already carries a
`regression: 4 original conditions match ConditionalPowerEffect` test). Confirm
whether the legacy groups are subsumed before removing them.

**B4. ⚠ NEEDS HUMAN CONFIRM — passive-champion UI (keep per-board)**
`test/ui/passive_champion_button_test.dart` (local board) and
`network_passive_champion_test.dart` (network board) share passive-button
assertions but exercise different screens (`game_screen.dart` vs
`network_game_screen.dart`); `champion_unused_border_test.dart` tests a *different*
predicate (`championHasUnusedAction`); `game_screen_champion_use_test.dart` is the
Giga single-button regression. **Keep all four** — merging loses per-board coverage.

**B5. REFACTOR (not a merge)** — the `network_*` UI tests each re-define
`pumpBoard`/`fixtureWithMyChampion` over the shared `assets/fixtures/net_board.json`;
`roundTrip()` is re-defined across codec tests. Hoist to shared helpers when B1 runs.
No behavior overlap to delete.

---

## (c) BROKEN cross-links

**None found.** All relative markdown links in `CLAUDE.md`, `README.md`,
`ROADMAP.md`, `AGENTS.md`, the four `lib/*/CLAUDE.md`, `test/CLAUDE.md`, and every
`ai-docs/*.md` resolve on disk (checked programmatically). All backtick-referenced
file paths spot-checked also exist (`assets/card_db/{schema,cards}.json`,
`assets/card_db/README.md`, `web/manifest.json`, `web/version.json`,
`scripts/build_web.sh`, `scripts/generate_report.sh`,
`.github/workflows/flutter-ci.yml`, `dart_test.yaml`, `tool/validate_card_db.dart`,
`tool/fetch_card_art.py`, `ai-docs/design_reference/DESIGN_SPEC.md`).

---

## (d) ORPHANS

- **Docs describing non-existent features: none.** The two "removed feature"
  risks are actually fine:
  - `ai-docs/flutter_deck_draw_plan.md` is self-labeled **"OBSOLETE (historical)"**
    and describes the early deck-draw demo; the `DeckService`/`home_screen`/
    `widget_test.dart` it references still exist. Keep archived.
  - `ai-docs/self_play_bots_design.md` / `ai-docs/discord_bug_pipeline.md` describe
    systems that DO exist now (`tool/selfplay/` Tier A, `tool/bug_pipeline/`) — the
    reverse of orphans (the CLAUDE.md line 396 "Deferred" label for self-play is
    the stale part; ROADMAP already notes the first cut shipped).
- **Orphaned test helpers/fixtures: none.** `assets/fixtures/net_board.json` is
  consumed by the `network_*` UI tests; the documented `deck_service_test`/
  `widget_test` helpers (`ZeroRandom`, `MaxRandom`, `gainMoneyAmount`,
  `pumpDeckDrawApp`, `tapKey`, …) are used within their own files. Duplicated (not
  unused) helpers noted in B5.
- **⚠ NEEDS HUMAN CONFIRM — `CLAUDE.md` "Open pull requests (temporary)" section**
  (lines 399-409): PRs #3 and #4 are STILL OPEN (verified via `gh`, from 2026-04)
  but are described as stale relative to `rld-mvp-sprint`. The section is factually
  accurate but is a "temporary" block that has lived for months — candidate for
  removal, but the PRs exist, so confirm before deleting.
- Possible code (not doc/test) orphans noticed in passing, out of scope for this
  manifest: `lib/ui/screens/net_board_fixture_screen.dart` and
  `server/tool/gen_board_fixture.dart` are unreferenced by any CLAUDE.md — flag for
  a separate code-hygiene pass.
