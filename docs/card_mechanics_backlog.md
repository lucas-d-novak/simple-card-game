# Card-mechanics backlog (product-owner spec, 2026-07-01)

> **AUTHORITY RULE (owner-mandated):** The product owner's notes below are the
> AUTHORITY. Agents have repeatedly MISREAD the printed card art / rawText — DO NOT
> re-judge or "correct" a spec against the art. Implement the owner's stated intent
> as written here. If the rawText disagrees, the rawText is wrong — fix the rawText to
> match, don't override the owner. Only ask the owner if a note is genuinely ambiguous
> about the mechanic itself (not about "the art shows X").

Working spec for queued engine work. All items require `game_service.dart` (effect
resolution) + `cards.json` (effect encoding), so they are serialized behind whatever
agent currently owns `game_service.dart`. Read each card's `rawText` in
`assets/card_db/cards.json` for the authoritative ability text; the notes below are
the product owner's callouts of what is MISSING or WRONG today.

## A. Aion / Prism subsystem build (owner said "start the build now")
The live market currently PARKS all `group: Aion` and `group: Prism` cards out of the
market (unmodeled). Goal: model their mechanics and bring them into the market.

- **Carmine Eclipse** (Aion champion) — missing (1) the FAST-PLAY mechanic, and (2)
  the "when this champion is destroyed, you may BUY/acquire the cards tucked UNDER it"
  mechanic. (Champion with cards tucked underneath; destruction releases them for
  purchase.)
- **Dash** (Aion) — missing "return an Aion card from your discard pile to the TOP of
  your deck" — this happens BEFORE the draw-a-card step already on the card.
- **Scarlet Slayer** (Aion) — missing the "draw a card" mechanic.
- **Swyft** (Aion champion) — missing the "if you are Rez …" conditional mechanic
  (character-conditional on playing as Rez).
- **Breaker** (Aion) — missing the "when you recruit this …" on-recruit trigger.
- **Stricture** (Prism champion) — NONE of its mechanics implemented. Model from rawText.
- **Shard Cultist** (Prism ally) — NONE of its mechanics implemented. Model from rawText.
- **Skry-77** (Prism ally) — Mastery-20 ability has TWO effects: **you GAIN 2 mastery AND
  a target/another player LOSES 2 mastery** (OWNER-CONFIRMED: "they lose two, you gain
  two" — mastery, NOT health; current encoding is WRONG). Needs the NEW opponent-loses-
  mastery effect (shared with Venator).

## B. General engine fixes
- **Global 50-health cap** — a player's health can never exceed 50. Clamp all
  health-gain paths (GainHealthEffect, lifegain, etc.).
- **Duplication Fabricator** (Order) — after its mastery threshold, present a SELECTION
  from the top cards of EVERY player's deck, and copy the chosen card's effect. It must
  NOT be allowed to select another Duplication Fabricator.
- **Order Initiate** — its Homodeus/Undergrowth/Wraethe faction trigger grants
  **mastery**, not gems (currently grants gems — wrong resource).

## B2. Gem→Mastery resource errors (SWEEP the whole DB for this class)
Several cards grant GEMS where they should grant MASTERY. Fix each AND grep all cards for
the same mistake (esp. Order faction):
- **Order Initiate** — Homodeus/Undergrowth/Wraethe trigger grants mastery, not gems.
- **Shard Abstractor** — grants mastery, not gems.
- **Grand Architect** — grants **5 mastery**, not 5 gems.
- **Arach Devotees** — the Undergrowth trigger grants **health**, not gems.
- **Fungal Hermit** — the base play effect grants **mastery** (not gems); its ADDITIONAL
  (mastery-threshold) effect grants **health**.
- **Hounds of Volos** — the "if you are Volos" effect grants **power**, not gems
  (OWNER-CONFIRMED: power — fix both the effect AND the rawText, which currently say gems).
  Also a character-conditional; see B3 "if your character is X".
- **Evokatus** — its Exhaust ability grants **power**, not gems.
- **Umbral Scourge** — grants **mastery**, not gems.
- **Carnivorous Vine(s)** — the "gain an additional…" effect grants BOTH **+2 health AND
  +2 power** for EACH Undergrowth ally played this turn (a per-ally scaling effect on two
  resources at once — make sure the effect model can grant two resource types that both
  scale).
- **Shardwood Guardian** — its secondary "gain 6 … if you have played…" effect grants
  **health**, not power.
- **Orm Madu** — Exhaust ability: gain **7 health**, then IF you have **50 health** (a
  HEALTH-threshold condition, not mastery), gain **1 mastery**. Needs a "if your health >=
  N" condition (ties to the 50-HP cap in §B — at cap this triggers).
- **Root of The Forest** — grants **+10 health** and a conditional **+10 power**, NOT gems.
- **Entropic Talons** — its "gain power for EACH health you have GAINED this turn" effect
  is NOT encoded. Needs tracking of health gained this turn (a per-turn counter) to scale
  power. (New scaling source: health-gained-this-turn.)
- **Kiln Drones** — has a conditional "gain an additional **+4 gems** if you have a
  champion in play" that's missing/wrong. Encode the champion-in-play conditional +4 gems.
- **Venator of the Wastes** — "if you have a champion in play" conditional makes a TARGET
  player **lose 2 MASTERY** (OWNER-CONFIRMED: mastery, NOT health — current encoding as
  opponent-loses-HEALTH is WRONG). Needs a NEW opponent-loses-mastery effect type. (Same
  champion-in-play condition as Kiln Drones.)
This is a broader RESOURCE-TYPE transcription class (gems/mastery/health/power confused),
not just gem→mastery. The fix agent should verify EVERY card's granted resource types
against its `rawText` icons and fix all mismatches, not only the ones listed here.
For every fix in this section, look for OTHER cards with the same error and fix them too.

## B3. More card mechanics (engine + cards.json; read each rawText for authority)
For EACH, also identify other cards where the same fix/mechanic applies.
- **Querry Monk** — has a Mastery-10 ability that is NOT encoded. Encode it.
- **General Decurion** — has a Mastery-20 ability that is NOT encoded. Encode it (read
  rawText). (Also referenced by Drakonarius' "if you control General Decurion" passive.)
- **Missing mastery-threshold abilities (encode from rawText):** **Fa Cu Tul** (Mastery
  20), **Rue Bo Vai, the Transcendent** (Mastery 10), **The World Piercer** (Mastery 20),
  **Zara Ra, Soulflayer** (Mastery 10 = banish UP TO TWO cards).
- **The Dispossessed** — has a return-from-discard effect that's missing (reuse the
  existing `ReturnFromDiscardEffect`/`returnFromDiscard` path).
- **Cinder Scars** — "if you have played ANOTHER Cinder Scars this turn" conditional
  (needs a "count of same-named card played this turn" condition; check
  `cardsPlayedThisTurn`).
- **Pall Shades** — its two mechanics are in the WRONG ORDER; reorder them to match the
  card.
- **Li Hin, the Shattered** — has a "can't be attacked" ability, BUT it can still be
  DESTROYED by other card effects (cannotBeAttacked variant that does NOT block
  DestroyChampionEffect — group with the Drakonarius/Raidian/Zetta cannotBeAttacked work).
- **The Heart of Nothing** — conditional: you DRAW MORE next turn if you dealt enough
  UNPREVENTED (unblocked) damage this turn (uses `unblockedDamageThisTurn`; grants a
  next-turn draw bonus — needs a deferred/next-turn draw modifier).
- **Nexus, Datic Hunter** — missing an "if you are Tetra" (character-conditional) effect.
- **Raidian, Cloud Master** — missing "cannot be attacked by players with LESS mastery
  than you" effect (a conditional cannotBeAttacked keyed to relative mastery).
- **Drakonarius** — "if you control the champion **General Decurion**, this cannot be
  attacked" (a conditional cannotBeAttacked keyed to controlling a specific NAMED champion
  in play). Another cannotBeAttacked variant — with Raidian (mastery-relative) and Zetta
  (aura), build a flexible conditional-cannotBeAttacked, don't hardcode three separate paths.
- **Zetta, the Encryptor** — verify/settle scope: does its cannotBeAttacked aura apply to
  your OTHER champions as well as to you (the player)? (Ties to the earlier Zetta
  aura-cleanup work — confirm the aura's targets match the card text.)
- **Paradigm, the Archivist** — verify cards tucked UNDER it end up in the CORRECT place
  after the champion is killed (check the tuck-under → release-on-death path;
  `_releaseUnderCards` / `cardsUnderChampion`). Fix if they go to the wrong zone.
- **Aedifex, Deus Engineer** — verify its secondary PASSIVE (recruit-cost reduction)
  actually applies: while this passive is in play, recruiting from the center should cost
  less. Check that a recruit-cost-reduction static modifier exists and is applied in the
  buy/recruit price path (`buyCard`/`recruitFromCenter` cost calc). Fix if the discount
  isn't wired.
- **Legion Carrier** — its "mill the top 3 cards of your deck" effect is NOT implemented.
  Needs a mill effect (move top N of own deck to discard). Likely a new effect type; check
  for any existing mill/self-discard-from-deck effect to reuse.
- **Axia** — has a SELF cost-reduction: it costs less to recruit from the market/center
  when [see card condition]. This is a market-price modifier on the card ITSELF (distinct
  from Aedifex, which discounts OTHER recruits). Read Axia's rawText for the exact
  condition and wire it into the center-row price calculation for that card.
- **Swyft "if you are Rez"**, **Nexus "if you are Tetra"**, **Hounds of Volos "if you are
  Volos"**, **Ferrata Guard "if you are Decima"** — all character-identity conditionals;
  build ONE "if your character is X" condition and reuse across all of them (Rez / Tetra /
  Volos / Decima …). Ferrata Guard's Decima branch is currently left out entirely.

## B4. Known gaps from Group 2 verification (deferred, LATENT — not triggerable today)
- `_modifierApplies` (faction-filtered static buffs like phasic/healthBuff/cardCostReduction)
  and `_recruitRedirectMatches` do NOT honor a card's mastery-gated `countsAsFactions`
  (they lack the extra-factions/mastery context). No current card triggers this (querry_monk
  is a regular; the faction-filtered redirect/recruit-top cards are champion-gated). Fixing
  needs a signature change to thread the owner's mastery into `_modifierApplies` — do it if a
  future multi-faction card must interact with those systems.
- Distinct-faction COUNTING conditions (`factionsPlayedAll` / `distinctFactionsPlayed` /
  `perFactionPlayedThisTurn`) count only a card's PRINTED faction — a `countsAsFactions` or
  `countsAsAllFactions` card counts as ONE faction for "played all 4 factions"-style checks.
  Consistent with existing all-factions handling; change only if the owner wants querry_monk
  to single-handedly satisfy multi-faction counts.

## B5. Wave-B Group 4 (deferred-selection trio) — OWNER RULINGS (2026-07-01)
Design plan captured (needs game_service.dart + server protocol + client picker; see
the Group-4 design agent output). Owner rulings:
- **Duplication Fabricator** — play effect grants **+1 mastery, THEN** (base, every play —
  NOT mastery-gated) reveal the top card of every player's deck and copy one revealed
  ALLY's effect (cannot copy another Duplication Fabricator; "this effect can't be
  copied"). The deck-top reveal is APPROVED (shown only to the chooser; intentional public
  reveal — the one sanctioned exception to the secret-deck rule; ship a server redaction
  test that opponents never see it). **After copying, leave the revealed cards ON TOP**
  (accepts that the chooser now knows each player's next draw).
- **Carmine Eclipse** — tuck fast-played cards under it (mandatory; reuses shieldPerCardUnder
  health). On death, the owner may **PAY each under-card's gem cost to acquire it** (NOT
  free), and the rest are banished. Resolve as a deferred choice (off-turn if Carmine dies
  on an opponent's turn — first off-turn action; needs the protocol turn-gate exception).
- **Swyft** — "if you are Rez, you may recruit any card you fast-play (to discard)"; default
  gate = controlling Swyft AND character==Rez; Carmine's mandatory tuck takes precedence
  over Swyft's optional recruit.

## C. Ingeminex wire-up (owner: "in-scope, wire them up") — DONE 2026-07-02
**Status: SHIPPED end-to-end.** Engine + data + server + UI, 20 tests. Notes:
- 6 cards flagged in-scope (`outOfScope:false`), kept OUT of the market via
  `_nonMarketGroups` ∋ `Ingeminex`; each has `appearanceEffects` (Attack) +
  `rewardEffects` (Reward) encoded in cards.json. Built into a template catalog by
  `buildIngeminexCatalogFromDatabase`, injected into `GameService`
  (`ingeminexCatalog:`) and spawnable via `spawnIngeminexById`.
- Owner reward rulings applied: **Brutality** = +20 HEALTH, **Torment** = +4
  MASTERY (not gems). **Corruption** attack = banish a random card from each hand
  (owner note over the "lose 3 and 1" rawText, which was corrected); reward =
  recruit a Relic to hand. **Desolation** attack = banish random from each hand;
  reward = deferred banish up to 3 (hand/deck/discard) then shuffle
  (`banishUpToFromAnyZone`). **Agony** = each player discards 2 / draw 2 + extra
  Destiny claim. **Malice** = each destroys their highest gem-cost champion /
  return a Champion from discard + extra Destiny claim.
- New effect types: `banishRandomFromEachHand`, `allPlayersDiscard`,
  `allPlayersDestroyHighestChampion`, `grantExtraDestinyClaim`,
  `recruitRelicToHand`, `banishUpToFromAnyZone` (+ schema + codec).
- Server: `attackIngeminex` / `spawnIngeminex` / `banishUpToFromAnyZone` protocol
  actions (current-player gated), `ingeminex` shipped PUBLIC in `redactFor`
  (ownerless HP pool — no hidden info), undo/stats via the generic apply path.
- UI: `_IngeminexTile` (name + red HP bar) renders a boss strip above the
  opponent champions on the networked board; tap-to-attack commits your power.
- OPEN (deliberate): no card in the current data TRIGGERS a spawn in a
  competitive game — `spawnIngeminex` is a versus-adaptation summon entry point
  (any player, on their turn) pending a final owner rule on how bosses appear.

### Original spec (for reference)
- Flag the 6 Ingeminex cards in-scope (they still spawn as NEUTRAL entities via
  `spawnIngeminex`, NOT into the normal market — keep them out of the center supply,
  but make them visible in the Card List and reachable by the mechanic).
- Model the 4 unmodeled effects: **Corruption** (banish a random card from EACH
  player's hand / reward: recruit an extra Relic to hand), **Desolation** (attack value
  10; reward: banish up to 3 from hand/deck/discard then shuffle), **Agony** (each
  player discards 2; reward: draw 2 + acquire an extra Destiny), **Malice** (each player
  destroys their highest-cost Champion; reward: return a Champion from discard + extra
  Destiny). Brutality + Torment already work.
- UI pass: render the neutral entity in the champions row with a damage bar; make it an
  attack target for ALL players; drive the appearance/all-players-hit via the existing
  damage-flash/log. (See the Ingeminex engine agent's handoff for the 6 integration
  points: redaction in server/lib/views.dart, an `attackIngeminex` protocol action
  authorized for the current player, undo/stats capture, board rendering, attack
  affordance for all players.)

## D. Destiny
- **power_struggle** — include as the INERT 30th Destiny (owner: "add inert 30th"). Its
  Exhaust cost "destroy a Champion you control" is unmodellable, so it appears in the
  Destiny row but its ability is a safe no-op (must NOT crash if invoked). Needs the
  Destiny supply builder + ability path to tolerate an inert destiny.

## E. FOUNDATIONAL — shield vs champion-health combat model (investigate FIRST)
Product owner's stated model:
- **Allies have shields.** Shields DEDUCT damage — "if in hand when someone tries to
  damage you" (a shield on a card in your hand reduces damage directed at YOU/the
  player). Suspected many ally records are MISSING their shield value in cards.json.
- **Champions may also have shields, but champions ADDITIONALLY have HEALTH POINTS.** A
  champion is killed only when it takes damage EQUAL TO its health (an accumulating
  damage pool, like the Ingeminex entity) — NOT the current "spend power >= shield to
  one-shot destroy" threshold. Champions stay in play until destroyed.
- Owner suspects this is implemented incorrectly today (champions use a shield-threshold
  kill in `attackChampion`, no champion HEALTH pool; allies' shields largely absent).

This is FOUNDATIONAL — Aion/Prism/Ingeminex card mechanics depend on it.

### OWNER RULINGS (2026-07-01) — implement to these:
- **Player shield (damage reduction) = PASSIVE, SUM of all shielded cards currently in
  your HAND.** Every card in hand with a `shield` value contributes; they sum to reduce
  each incoming attack on you; NOT consumed (passive while held). This applies to ANY
  card in hand with a shield — allies AND champion cards while still in hand.
- **A card's own `shield` only reduces damage while it is IN HAND, not while in play.**
  E.g. Zetta's shield contributes to your defense while Zetta is in your hand; once
  played out it no longer contributes its in-hand shield (it's now a champion with
  HEALTH in play).
- **Champions in play have HEALTH** (the current `shield` field value = printed health
  pips → reinterpret/relabel as HEALTH). Destroyed when attacked. **You may only ATTACK a
  champion if you have enough power to KILL it outright** (power >= remaining health) —
  NO partial/chip damage, NO accumulating pool for regular champions (this differs from
  Ingeminex, which DOES accumulate). So the current "need power >= value to destroy" gate
  STAYS; the value is HEALTH. Champions stay in play until destroyed.
- **Champions that GRANT you shields (e.g. Praetorian-02 / -01) = a CONSTANT shield
  increase to your damage-reduction that lasts while that champion is in play, until it
  is destroyed** (a standing shield buff, NOT an in-hand contribution). So
  `StaticModifierKind.shieldBuff` from a champion in play adds to PLAYER damage reduction,
  removed when the champion leaves play.
- Net: PLAYER damage reduction each hit = Σ(shield of cards in hand) + Σ(shieldBuff from
  champions in play). Champion kill = one-shot, power >= HEALTH. Backfill the missing
  ally shield values in cards.json from printed [shield] icons; relabel champion value as
  health in schema/UI. Defaults confirmed: ignoreShield/Spirit-Leech = ignore the per-hit
  shield (not instakill); DestroyChampion effects = instant-kill bypassing the gate.

## F. FOUNDATIONAL — deterministic RNG seed per game (investigate FIRST)
Product owner: every game should start from a UNIQUE random seed that is SAVED with the
game and reconstructable post-hoc from the game actions. That seed must drive ALL
randomization (deck shuffles, draws, market shuffles, any Random use) so a game is fully
reproducible/replayable from (seed + action log). Investigate: how `GameService` Random
is currently created (constructor takes `Random?`), whether the server generates and
PERSISTS a seed (GameStateCodec / lobby), and whether all randomness routes through the
single injected Random (no stray `Random()`/`DateTime`-seeded calls). Produce a plan to:
generate a unique seed at game creation, persist it in the game record + expose it in the
game view/actions, and guarantee determinism (single seeded Random, no ambient entropy).

## Already applied (2026-07-01, cosmetic, in cards.json)
- Taur "Archpriest" → "Arachpriest"; "Keeper of datic Vessels" → "Datic"; "Isa Tel Tor,
  the Axe" → "The Axe".
- synthetica_artifex stray `shield: 2` — LEFT AS-IS (owner: "allies can have shields,
  that's correct").
- 7 Chapter-2 KS center cards flagged `ksOnly: true` (catalog audit).
