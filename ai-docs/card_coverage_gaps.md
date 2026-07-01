# Card Coverage Gap List

> **SUPERSEDED (historical snapshot).** This file's per-card tables no longer
> match `cards.json`, and its "pending the activated-ability engine" framing is
> false — the activated-ability engine, `cannotBeAttacked`, `copyPlayedCard`,
> scaling resources, and the health-loss scry dispositions all SHIPPED. For live
> coverage use the generated [`assets/card_db/COVERAGE.md`](../assets/card_db/COVERAGE.md)
> and `dart run tool/validate_card_db.dart`. Kept only as a dated record.

_Originally auto-generated from `assets/card_db/cards.json`. Tracks cards still missing effect information or encoded effects._

> **Stale snapshot — see the live `COVERAGE.md`.** The per-card tables (sections A
> and B) below are a historical snapshot and no longer match `cards.json`. The
> live, regenerated coverage report is [`assets/card_db/COVERAGE.md`](../assets/card_db/COVERAGE.md)
> (run `dart run tool/gen_coverage_readme.dart` to refresh it). Only the Summary
> below has been re-synced to the current DB.

## Summary

| Metric | Count |
|--------|------:|
| Total cards | 183 |
| Art on disk | 183/183 |
| Verified | 101 |
| Encoded (playEffects present) | 88 |
| **Missing effect INFO (no rawText)** | **0** |
| **Encodable now (rawText, no playEffects)** | **95** |

> **Art note:** all 183 art files exist on disk and are real (none are <3KB placeholders). Every card now carries `rawText`, so the active gap is *encoding* (turning rawText into `playEffects`/`activatedAbility`), not effect-info hunting.

## A. Encodable now — has rawText, missing playEffects

These need encoding, not searching. Several use Exhaust (pending the activated-ability engine).

| id | faction | set | rawText (truncated) |
|----|---------|-----|---------------------|
| `agony` | none | unknown | Ingeminex. Attack: Each player discards 2 cards from their hand. Reward: Draw 2 cards and  |
| `breaker` | none | unknown | Aion Ally. When you Recruit this, put it into your hand. Warp infinity - Fast-play any All |
| `brutality` | none | unknown | Ingeminex. Attack: All players lose 5 (cannot be prevented by shield). Reward: Gain 20. |
| `corruption` | none | unknown | Ingeminex. Attack: All players lose 3 and 1. This cannot be prevented by (Guard). Reward:  |
| `datic_inquisitors` | order | sos | Order Ally. Choose one: Draw 2 cards / Recruit a card with cost 6 or less for free. Master |
| `ferrata_guard` | homodeus | rotf | Homodeus Champion. If you are Decima, your Champions (including this one) have an addition |
| `g_48` | homodeus | ioh | Homodeus Champion. Exhaust: Reset another Champion you control. (It may be Exhausted a sec |
| `gian_shard_wyrm` | undergrowth | rotf | Undergrowth Champion. Exhaust: Gain 2 (power) and 2 (gems). Mastery 15: Gain 5 (power) and |
| `j_chord` | none | unknown | Aion Champion. Exhaust: Warp 3 - Fast-play an Ally in the Center Row with cost 3 or less f |
| `lasav_tower_commander` | homodeus | sos | Homodeus Champion. (Card art name: 'Lesav, Tower Commander'.) Exhaust: Gain 5 (power). Mas |
| `malice` | none | unknown | Ingeminex. Attack: Each player destroys their highest (gem) cost Champion. Reward: You may |
| `oblivion_gatekeeper` | wraethe | ioh | Wraethe Champion. Exhaust: Reveal the top card of your deck. You lose (power) equal to its |
| `ojas_genesis_druid` | undergrowth | base | Undergrowth Ally. Cost 4. Copy the effect of a non-Champion card you have played this turn |
| `orm_madu` | undergrowth | ioh | Undergrowth Champion. Exhaust: Gain 7 (power). Then, if you have 50 (mastery), gain 1 (gem |
| `portal_monk` | order | base | Order Ally. Cost 3. Recruit a card with cost 6 or less for free. Mastery 15: Put that card |
| `praetorian_02` | homodeus | rotf | Homodeus Relic - Champion. You have 3 (power). Mastery 20: You have 6 instead. |
| `primus_pilus` | homodeus | base | Homodeus Champion. Cost 2, shield 6. Exhaust: If you have three or more Homodeus Champions |
| `subversion_elders` | order | rotf | Order Champion (Ally). Gain 1 (gem) for each Faction you have played this turn. (The Facti |
| `swyft` | none | unknown | Aion Champion. Exhaust: Gain 2 (gems) and 2 (power). If you are Rez, you may recruit any c |
| `taur_archpriest` | undergrowth | base | Undergrowth Champion. Cost 5, shield 4. Exhaust: Copy the effect of an Undergrowth Ally pl |
| `torment` | none | unknown | Ingeminex. Attack: All players lose 2. Reward: Gain 4. |
| `zetta_the_encryptor` | order | base | Order Champion. Cost 5, shield 5. You and your other Champions in play can't be attacked. |

## B. Needs effect-info hunt — no rawText

### set: `base` (1)

| id | name | faction | group | art |
|----|------|---------|-------|-----|
| `fungal_hermit` | Fungal Hermit | undergrowth |  | OK |

### set: `rotf` (1)

| id | name | faction | group | art |
|----|------|---------|-------|-----|
| `spirit_leech` | Spirit Leech | wraethe |  | OK |

### set: `saga` (13)

| id | name | faction | group | art |
|----|------|---------|-------|-----|
| `aedifex_deus_engineer` | Aedifex, Deus Engineer | homodeus |  | OK |
| `chlorophyte_guardian` | Chlorophyte Guardian | undergrowth |  | OK |
| `concussio_and_mirus` | Concussio and Mirus | homodeus |  | OK |
| `huntmaster_arach` | Huntmaster Arach | undergrowth |  | OK |
| `isa_tel_tor_the_axe` | Isa Tel Tor, the Axe | wraethe |  | OK |
| `keeper_of_datic_vessels` | Keeper of datic Vessels | order |  | OK |
| `nexus_datic_hunter` | Nexus, Datic Hunter | order |  | OK |
| `paradigm_the_archivist` | Paradigm, The Archivist | order |  | OK |
| `se_soc_tar_the_inquisitor` | Se Soc Tar, The Inquisitor | wraethe |  | OK |
| `synthetica_artifex` | Synthetica Artifex | homodeus |  | OK |
| `the_voiceless` | The Voiceless | wraethe |  | OK |
| `vinereaper` | Vinereaper | undergrowth |  | OK |
| `wandering_ghost` | Wandering Ghost | wraethe |  | OK |

### set: `unknown` (74)

| id | name | faction | group | art |
|----|------|---------|-------|-----|
| `absorption_grid` | Absorption Grid | none | Destiny | OK |
| `advanced_medicine` | Advanced Medicine | none | Destiny | OK |
| `advanced_weapons` | Advanced Weapons | none | Destiny | OK |
| `aion_egressor` | Aion Egressor | none | Aion | OK |
| `aion_guide` | Aion Guide | none | Aion | OK |
| `armageddon` | Armageddon | none | Dominatus | OK |
| `assassinate` | Assassinate | none | Glitchmother | OK |
| `biotech_enhancements` | Biotech Enhancements | none | Destiny | OK |
| `blitz_shard_runner` | Blitz, Shard Runner | none | Aion | OK |
| `blood_for_blood` | Blood for Blood | none | Destiny | OK |
| `blood_shard` | Blood Shard | none | Necrotic | OK |
| `bound_for_life` | Bound for Life | none | Destiny | OK |
| `brainhack` | Brainhack | none | Mind Hacker | OK |
| `carmine_eclipse` | Carmine Eclipse | none | Aion | OK |
| `cobalt_chaplain` | Cobalt Chaplain | none | Glitch | OK |
| `crimson_operative` | Crimson Operative | none | Aion | OK |
| `custcutta_scourge` | Custcutta Scourge | none | Aberrant | OK |
| `data_wipe` | Data Wipe | none | Glitchmother | OK |
| `datic_secrets` | Datic Secrets | none | Destiny | OK |
| `deadly_recruits` | Deadly Recruits | none | Destiny | OK |
| `death_grasp` | Death Grasp | none | Dominatus | OK |
| `desolation` | Desolation | none | Ingeminex | OK |
| `forged_in_flame` | Forged in Flame | none | Destiny | OK |
| `fragmenta` | Fragmenta | none | Talos | OK |
| `gene_scavs` | Gene Scavs | none | Talos | OK |
| `greater_unstable_rift` | Greater Unstable Rift | none | Moc Sai | OK |
| `havoc_blast` | Havoc Blast | none | Dominatus | OK |
| `healing_hands` | Healing Hands | none | Destiny | OK |
| `homodeus_trap` | Homodeus Trap | none | Vox | OK |
| `lesser_unstable_rift` | Lesser Unstable Rift | none | Moc Sai | OK |
| `maglev_tunnels` | Maglev Tunnels | none | Destiny | OK |
| `masterstroke` | Masterstroke | none | Glitchmother | OK |
| `nature_dominance` | Nature Dominance | none | Destiny | OK |
| `noxious_vapors` | Noxious Vapors | none | Crimson Thorn | OK |
| `one_mind_one_army` | One Mind, One Army | none | Destiny | OK |
| `order_trap` | Order Trap | none | Vox | OK |
| `paradigm_shift` | Paradigm Shift | none | Destiny | OK |
| `phasic_technology` | Phasic Technology | none | Destiny | OK |
| `poison_seed` | Poison Seed | none | Crimson Thorn | OK |
| `power_struggle` | Power Struggle | none | Destiny | OK |
| `project_yggdrasil` | Project Yggdrasil | none | Destiny | OK |
| `red_fortune` | Red Fortune | none | Aion | OK |
| `sagittari` | Sagittari | none | Talos | OK |
| `scarlet_slayer` | Scarlet Slayer | none | Aion | OK |
| `shard_cultist` | Shard Cultist | none | Prism | OK |
| `shard_extractor` | Shard Extractor | none | Prism | OK |
| `shard_horrors` | Shard Horrors | none | Necrotic | OK |
| `shard_spiders` | Shard Spiders | none | Aberrant | OK |
| `shutdown` | Shutdown | none | Mind Hacker | OK |
| `simulacrons` | Simulacrons | none | Glitch | OK |
| `skry_77` | Skry-77 | none | Prism | OK |
| `soul_syphon` | Soul Syphon | none | Destiny | OK |
| `stitchborg` | Stitchborg | none | Necrotic | OK |
| `stolen_future` | Stolen Future | none | Destiny | OK |
| `stranglevines` | Stranglevines | none | Crimson Thorn | OK |
| `strategic_mastermind` | Strategic Mastermind | none | Destiny | OK |
| `stricture` | Stricture | none | Prism | OK |
| `synthesis` | Synthesis | none | DestinyDeck | OK |
| `system_shock` | System Shock | none | Mind Hacker | OK |
| `the_agony_of_choice` | The Agony of Choice | none | Destiny | OK |
| `the_crystal_gate` | The Crystal Gate | none | Destiny | OK |
| `the_last_city` | The Last City | none | Destiny | OK |
| `the_price_of_power` | The Price of Power | none | Destiny | OK |
| `the_shard_defiant` | The Shard Defiant | none | Destiny | OK |
| `toxify` | Toxify | none | Crimson Thorn | OK |
| `true_leader` | True Leader | none | Destiny | OK |
| `twin_trap` | Twin Trap | none | Vox | OK |
| `unconditional_conscription` | Unconditional Conscription | none | Destiny | OK |
| `undergrowth_trap` | Undergrowth Trap | none | Vox | OK |
| `vector_fiend` | Vector Fiend | none | Glitch | OK |
| `war_bound` | War Bound | none | Destiny | OK |
| `whatever_it_takes` | Whatever it Takes | none | Destiny | OK |
| `wraethe_trap` | Wraethe Trap | none | Vox | OK |
| `wrathbloom` | Wrathbloom | none | Aberrant | OK |
