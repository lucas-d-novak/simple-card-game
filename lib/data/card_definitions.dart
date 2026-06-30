import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';

/// Full Fragments of Boundlessness card catalog (~55 unique cards across all factions).
///
/// Original 17 test fixture variable names are preserved for backward
/// compatibility. New cards are added below each faction section.

// ---------------------------------------------------------------------------
// Homodeus (Gold) — technology, mastery, card draw (14 cards)
// ---------------------------------------------------------------------------

const reactorMonk = CardModel(
  id: 'reactor_monk',
  name: 'Reactor Monk',
  cost: 1,
  playEffects: [GainGemsEffect(1)],
  faction: Faction.homodeus,
  allyAbility: [GainMasteryEffect(1)],
);

const neuralRelay = CardModel(
  id: 'neural_relay',
  name: 'Neural Relay',
  cost: 2,
  playEffects: [GainMasteryEffect(1)],
  faction: Faction.homodeus,
  allyAbility: [DrawCardsEffect(1)],
);

const korArbiter = CardModel(
  id: 'kor_arbiter',
  name: 'Kor Arbiter',
  cost: 2,
  playEffects: [GainMasteryEffect(1)],
  faction: Faction.homodeus,
  cardType: CardType.champion,
  shield: 3,
  masteryThreshold: 5,
  masteryBonus: [GainPowerEffect(2)],
);

const infinityEngine = CardModel(
  id: 'infinity_engine',
  name: 'Infinity Engine',
  cost: 3,
  playEffects: [GainMasteryEffect(1), GainGemsEffect(1)],
  faction: Faction.homodeus,
  allyAbility: [GainMasteryEffect(1)],
);

const thoughtBroker = CardModel(
  id: 'thought_broker',
  name: 'Thought Broker',
  cost: 3,
  playEffects: [DrawCardsEffect(1), GainMasteryEffect(1)],
  faction: Faction.homodeus,
  allyAbility: [DrawCardsEffect(1)],
);

const crystalConduit = CardModel(
  id: 'crystal_conduit',
  name: 'Crystal Conduit',
  cost: 3,
  playEffects: [GainGemsEffect(1), GainMasteryEffect(1)],
  faction: Faction.homodeus,
  cardType: CardType.champion,
  shield: 3,
);

const korOracle = CardModel(
  id: 'kor_oracle',
  name: 'Kor Oracle',
  cost: 4,
  playEffects: [GainMasteryEffect(2)],
  faction: Faction.homodeus,
  cardType: CardType.champion,
  shield: 4,
  allyAbility: [GainPowerEffect(2)],
);

const empoweredResearcher = CardModel(
  id: 'empowered_researcher',
  name: 'Empowered Researcher',
  cost: 4,
  playEffects: [GainMasteryEffect(2)],
  faction: Faction.homodeus,
  masteryThreshold: 10,
  masteryBonus: [DrawCardsEffect(2)],
);

const knowledgeSeeker = CardModel(
  id: 'knowledge_seeker',
  name: 'Knowledge Seeker',
  cost: 4,
  playEffects: [DrawCardsEffect(2)],
  faction: Faction.homodeus,
  allyAbility: [GainMasteryEffect(1)],
);

const neuralOverload = CardModel(
  id: 'neural_overload',
  name: 'Neural Overload',
  cost: 5,
  playEffects: [GainMasteryEffect(3), DrawCardsEffect(2)],
  faction: Faction.homodeus,
  cardType: CardType.mercenary,
);

const asceticOfTheLidlessEye = CardModel(
  id: 'ascetic_of_the_lidless_eye',
  name: 'Ascetic of the Lidless Eye',
  cost: 5,
  playEffects: [GainMasteryEffect(2), GainGemsEffect(1)],
  faction: Faction.homodeus,
  cardType: CardType.champion,
  shield: 5,
  masteryThreshold: 10,
  masteryBonus: [DrawCardsEffect(1)],
);

const korCelebrant = CardModel(
  id: 'kor_celebrant',
  name: 'Kor Celebrant',
  cost: 6,
  playEffects: [GainMasteryEffect(3)],
  faction: Faction.homodeus,
  cardType: CardType.champion,
  shield: 6,
  allyAbility: [GainPowerEffect(3)],
);

const enlightenedArchitect = CardModel(
  id: 'enlightened_architect',
  name: 'Enlightened Architect',
  cost: 7,
  playEffects: [GainMasteryEffect(3), DrawCardsEffect(1)],
  faction: Faction.homodeus,
  allyAbility: [DrawCardsEffect(2)],
);

const grandKorMaster = CardModel(
  id: 'grand_kor_master',
  name: 'Grand Kor Master',
  cost: 8,
  playEffects: [GainMasteryEffect(3), GainPowerEffect(3)],
  faction: Faction.homodeus,
  cardType: CardType.champion,
  shield: 7,
  masteryThreshold: 15,
  masteryBonus: [GainPowerEffect(5)],
);

// ---------------------------------------------------------------------------
// Wraethe (Purple) — destruction, aggression, power (13 cards)
// ---------------------------------------------------------------------------

const reaper = CardModel(
  id: 'reaper',
  name: 'Reaper',
  cost: 1,
  playEffects: [GainPowerEffect(2)],
  faction: Faction.wraethe,
  masteryThreshold: 5,
  masteryBonus: [GainPowerEffect(2)],
);

const darkSummoner = CardModel(
  id: 'dark_summoner',
  name: 'Dark Summoner',
  cost: 2,
  playEffects: [GainPowerEffect(2)],
  faction: Faction.wraethe,
  allyAbility: [GainPowerEffect(2)],
);

const shadowFiend = CardModel(
  id: 'shadow_fiend',
  name: 'Shadow Fiend',
  cost: 2,
  playEffects: [GainPowerEffect(1)],
  faction: Faction.wraethe,
  cardType: CardType.champion,
  shield: 2,
  masteryThreshold: 5,
  masteryBonus: [GainPowerEffect(2)],
);

const venomStriker = CardModel(
  id: 'venom_striker',
  name: 'Venom Striker',
  cost: 3,
  playEffects: [GainPowerEffect(3)],
  faction: Faction.wraethe,
  allyAbility: [GainPowerEffect(2)],
);

const chaosImp = CardModel(
  id: 'chaos_imp',
  name: 'Chaos Imp',
  cost: 3,
  playEffects: [GainPowerEffect(5)],
  faction: Faction.wraethe,
  cardType: CardType.mercenary,
);

const darkReaver = CardModel(
  id: 'dark_reaver',
  name: 'Dark Reaver',
  cost: 3,
  playEffects: [GainPowerEffect(2)],
  faction: Faction.wraethe,
  cardType: CardType.champion,
  shield: 3,
);

const wraithLord = CardModel(
  id: 'wraith_lord',
  name: 'Wraith Lord',
  cost: 4,
  playEffects: [GainPowerEffect(3)],
  faction: Faction.wraethe,
  cardType: CardType.champion,
  shield: 4,
  allyAbility: [GainPowerEffect(2)],
);

const bloodRitualist = CardModel(
  id: 'blood_ritualist',
  name: 'Blood Ritualist',
  cost: 4,
  playEffects: [GainPowerEffect(3)],
  faction: Faction.wraethe,
  masteryThreshold: 10,
  masteryBonus: [OpponentLosesHealthEffect(3)],
);

const voidReaver = CardModel(
  id: 'void_reaver',
  name: 'Void Reaver',
  cost: 5,
  playEffects: [GainPowerEffect(4)],
  faction: Faction.wraethe,
  allyAbility: [GainPowerEffect(3)],
);

const shadowAssassin = CardModel(
  id: 'shadow_assassin',
  name: 'Shadow Assassin',
  cost: 5,
  playEffects: [GainPowerEffect(7)],
  faction: Faction.wraethe,
  cardType: CardType.mercenary,
  masteryThreshold: 10,
  masteryBonus: [GainPowerEffect(3)],
);

const chaosLord = CardModel(
  id: 'chaos_lord',
  name: 'Chaos Lord',
  cost: 6,
  playEffects: [GainPowerEffect(4)],
  faction: Faction.wraethe,
  cardType: CardType.champion,
  shield: 5,
  allyAbility: [GainPowerEffect(3)],
);

const deathBringer = CardModel(
  id: 'death_bringer',
  name: 'Death Bringer',
  cost: 7,
  playEffects: [GainPowerEffect(6)],
  faction: Faction.wraethe,
  masteryThreshold: 15,
  masteryBonus: [GainPowerEffect(4)],
);

const apocalypse = CardModel(
  id: 'apocalypse',
  name: 'Apocalypse',
  cost: 8,
  playEffects: [GainPowerEffect(12)],
  faction: Faction.wraethe,
  cardType: CardType.mercenary,
  masteryThreshold: 15,
  masteryBonus: [GainPowerEffect(6)],
);

// ---------------------------------------------------------------------------
// Order of the New Dawn (Blue) — healing, defense, guard (12 cards)
// ---------------------------------------------------------------------------

const healer = CardModel(
  id: 'healer',
  name: 'Healer',
  cost: 1,
  playEffects: [GainHealthEffect(3)],
  faction: Faction.order,
  allyAbility: [GainMasteryEffect(1)],
);

const shieldBearer = CardModel(
  id: 'shield_bearer',
  name: 'Shield Bearer',
  cost: 2,
  playEffects: [],
  faction: Faction.order,
  cardType: CardType.champion,
  shield: 3,
  hasGuard: true,
  masteryThreshold: 5,
  masteryBonus: [GainHealthEffect(2)],
);

const dawnCleric = CardModel(
  id: 'dawn_cleric',
  name: 'Dawn Cleric',
  cost: 2,
  playEffects: [GainHealthEffect(2), GainGemsEffect(1)],
  faction: Faction.order,
  allyAbility: [GainHealthEffect(2)],
);

const radiantProtector = CardModel(
  id: 'radiant_protector',
  name: 'Radiant Protector',
  cost: 3,
  playEffects: [GainHealthEffect(2)],
  faction: Faction.order,
  cardType: CardType.champion,
  shield: 4,
  hasGuard: true,
);

const divineAegis = CardModel(
  id: 'divine_aegis',
  name: 'Divine Aegis',
  cost: 3,
  playEffects: [GainHealthEffect(7)],
  faction: Faction.order,
  cardType: CardType.mercenary,
);

const holyWarrior = CardModel(
  id: 'holy_warrior',
  name: 'Holy Warrior',
  cost: 3,
  playEffects: [GainPowerEffect(2), GainHealthEffect(2)],
  faction: Faction.order,
  allyAbility: [GainHealthEffect(2)],
);

const templarKnight = CardModel(
  id: 'templar_knight',
  name: 'Templar Knight',
  cost: 4,
  playEffects: [GainPowerEffect(1)],
  faction: Faction.order,
  cardType: CardType.champion,
  shield: 5,
  hasGuard: true,
  allyAbility: [GainHealthEffect(3)],
);

const blessedHealer = CardModel(
  id: 'blessed_healer',
  name: 'Blessed Healer',
  cost: 4,
  playEffects: [GainHealthEffect(5)],
  faction: Faction.order,
  allyAbility: [GainGemsEffect(1)],
  masteryThreshold: 10,
  masteryBonus: [GainHealthEffect(5)],
);

const radiantChampion = CardModel(
  id: 'radiant_champion',
  name: 'Radiant Champion',
  cost: 5,
  playEffects: [GainHealthEffect(3), GainPowerEffect(2)],
  faction: Faction.order,
  cardType: CardType.champion,
  shield: 6,
  hasGuard: true,
);

const sanctuaryGuard = CardModel(
  id: 'sanctuary_guard',
  name: 'Sanctuary Guard',
  cost: 5,
  playEffects: [GainHealthEffect(4)],
  faction: Faction.order,
  allyAbility: [GainHealthEffect(3)],
  masteryThreshold: 10,
  masteryBonus: [GainPowerEffect(2)],
);

const highTemplar = CardModel(
  id: 'high_templar',
  name: 'High Templar',
  cost: 6,
  playEffects: [GainPowerEffect(3), GainHealthEffect(3)],
  faction: Faction.order,
  cardType: CardType.champion,
  shield: 7,
  hasGuard: true,
  masteryThreshold: 15,
  masteryBonus: [GainHealthEffect(5)],
);

const divineResurrection = CardModel(
  id: 'divine_resurrection',
  name: 'Divine Resurrection',
  cost: 7,
  playEffects: [GainHealthEffect(15)],
  faction: Faction.order,
  cardType: CardType.mercenary,
  allyAbility: [GainPowerEffect(5)],
);

// ---------------------------------------------------------------------------
// Undergrowth (Green) — nature, gems, ramp (13 cards)
// ---------------------------------------------------------------------------

const leafDancer = CardModel(
  id: 'leaf_dancer',
  name: 'Leaf Dancer',
  cost: 1,
  playEffects: [GainGemsEffect(1)],
  faction: Faction.undergrowth,
  allyAbility: [GainGemsEffect(1)],
);

const vineGuardian = CardModel(
  id: 'vine_guardian',
  name: 'Vine Guardian',
  cost: 2,
  playEffects: [GainGemsEffect(1)],
  faction: Faction.undergrowth,
  cardType: CardType.champion,
  shield: 2,
  masteryThreshold: 5,
  masteryBonus: [GainPowerEffect(1)],
);

const forestMystic = CardModel(
  id: 'forest_mystic',
  name: 'Forest Mystic',
  cost: 2,
  playEffects: [GainGemsEffect(2)],
  faction: Faction.undergrowth,
  masteryThreshold: 5,
  masteryBonus: [GainMasteryEffect(1)],
);

const rootWarrior = CardModel(
  id: 'root_warrior',
  name: 'Root Warrior',
  cost: 3,
  playEffects: [GainGemsEffect(2)],
  faction: Faction.undergrowth,
  allyAbility: [GainPowerEffect(1)],
);

const naturesBounty = CardModel(
  id: 'natures_bounty',
  name: "Nature's Bounty",
  cost: 3,
  playEffects: [GainGemsEffect(4)],
  faction: Faction.undergrowth,
  cardType: CardType.mercenary,
);

const thornback = CardModel(
  id: 'thornback',
  name: 'Thornback',
  cost: 3,
  playEffects: [GainGemsEffect(1), GainPowerEffect(1)],
  faction: Faction.undergrowth,
  cardType: CardType.champion,
  shield: 3,
);

const groveTender = CardModel(
  id: 'grove_tender',
  name: 'Grove Tender',
  cost: 4,
  playEffects: [GainGemsEffect(2), GainMasteryEffect(1)],
  faction: Faction.undergrowth,
  allyAbility: [GainGemsEffect(1)],
);

const elderTree = CardModel(
  id: 'elder_tree',
  name: 'Elder Tree',
  cost: 4,
  playEffects: [GainGemsEffect(2)],
  faction: Faction.undergrowth,
  cardType: CardType.champion,
  shield: 5,
  allyAbility: [GainMasteryEffect(1)],
);

const overgrowth = CardModel(
  id: 'overgrowth',
  name: 'Overgrowth',
  cost: 5,
  playEffects: [GainGemsEffect(3)],
  faction: Faction.undergrowth,
  allyAbility: [GainGemsEffect(2)],
  masteryThreshold: 10,
  masteryBonus: [GainPowerEffect(2)],
);

const ancientProtector = CardModel(
  id: 'ancient_protector',
  name: 'Ancient Protector',
  cost: 5,
  playEffects: [GainGemsEffect(2), GainPowerEffect(1)],
  faction: Faction.undergrowth,
  cardType: CardType.champion,
  shield: 6,
  hasGuard: true,
);

const primordialForce = CardModel(
  id: 'primordial_force',
  name: 'Primordial Force',
  cost: 6,
  playEffects: [GainGemsEffect(3), GainPowerEffect(2)],
  faction: Faction.undergrowth,
  allyAbility: [GainPowerEffect(2)],
);

const worldTree = CardModel(
  id: 'world_tree',
  name: 'World Tree',
  cost: 7,
  playEffects: [GainGemsEffect(3), GainMasteryEffect(2)],
  faction: Faction.undergrowth,
  cardType: CardType.champion,
  shield: 8,
  masteryThreshold: 15,
  masteryBonus: [GainPowerEffect(4)],
);

const gaiasWrath = CardModel(
  id: 'gaias_wrath',
  name: "Gaia's Wrath",
  cost: 8,
  playEffects: [GainGemsEffect(6), GainPowerEffect(6)],
  faction: Faction.undergrowth,
  cardType: CardType.mercenary,
);

// ---------------------------------------------------------------------------
// Factionless / Neutral (3 cards)
// ---------------------------------------------------------------------------

const shardReactor = CardModel(
  id: 'shard_reactor',
  name: 'Shard Reactor',
  cost: 3,
  // Gain 2 gems, scaling with Mastery: 3 at Mastery 5, 4 at Mastery 15.
  playEffects: [
    GainGemsEffect(2),
    ConditionalEffect(
      condition:
          GameCondition(kind: GameConditionKind.masteryAtLeast, threshold: 5),
      then: [GainGemsEffect(1)],
    ),
    ConditionalEffect(
      condition:
          GameCondition(kind: GameConditionKind.masteryAtLeast, threshold: 15),
      then: [GainGemsEffect(1)],
    ),
  ],
);

const infinityEngineFragment = CardModel(
  id: 'infinity_engine_fragment',
  name: 'Infinity Engine Fragment',
  cost: 4,
  playEffects: [GainMasteryEffect(2), GainGemsEffect(1)],
);

const universalSoldier = CardModel(
  id: 'universal_soldier',
  name: 'Universal Soldier',
  cost: 5,
  playEffects: [GainPowerEffect(2)],
  cardType: CardType.champion,
  shield: 4,
  countsAsAllFactions: true,
);

// ---------------------------------------------------------------------------
// Card lists
// ---------------------------------------------------------------------------

/// Original 17 test fixture cards — kept for backward compatibility.
const allTestFixtureCards = <CardModel>[
  reactorMonk,
  neuralRelay,
  korArbiter,
  infinityEngine,
  empoweredResearcher,
  shadowFiend,
  bloodRitualist,
  darkSummoner,
  chaosImp,
  shieldBearer,
  radiantProtector,
  dawnCleric,
  vineGuardian,
  leafDancer,
  naturesBounty,
  shardReactor,
  universalSoldier,
];

/// Full Fragments of Boundlessness card catalog (~55 unique cards).
const allInfinityDeckCards = <CardModel>[
  // Homodeus (14)
  reactorMonk,
  neuralRelay,
  korArbiter,
  infinityEngine,
  thoughtBroker,
  crystalConduit,
  korOracle,
  empoweredResearcher,
  knowledgeSeeker,
  neuralOverload,
  asceticOfTheLidlessEye,
  korCelebrant,
  enlightenedArchitect,
  grandKorMaster,
  // Wraethe (13)
  reaper,
  darkSummoner,
  shadowFiend,
  venomStriker,
  chaosImp,
  darkReaver,
  wraithLord,
  bloodRitualist,
  voidReaver,
  shadowAssassin,
  chaosLord,
  deathBringer,
  apocalypse,
  // Order (12)
  healer,
  shieldBearer,
  dawnCleric,
  radiantProtector,
  divineAegis,
  holyWarrior,
  templarKnight,
  blessedHealer,
  radiantChampion,
  sanctuaryGuard,
  highTemplar,
  divineResurrection,
  // Undergrowth (13)
  leafDancer,
  vineGuardian,
  forestMystic,
  rootWarrior,
  naturesBounty,
  thornback,
  groveTender,
  elderTree,
  overgrowth,
  ancientProtector,
  primordialForce,
  worldTree,
  gaiasWrath,
  // Neutral (3)
  shardReactor,
  infinityEngineFragment,
  universalSoldier,
];
