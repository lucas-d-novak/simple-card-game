import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';

sealed class CardEffect {
  const CardEffect();

  String get description;
}

// ---------------------------------------------------------------------------
// Characters (Engine Phase 2, wave 0 — minimal enum; PlayerState.character is
// wired up in a later wave). Listed here so GameCondition.isCharacter can name
// a target. Add more values as character cards are encoded.
// ---------------------------------------------------------------------------

/// A playable Character a player may have chosen for the game. Character-gated
/// card effects (`GameConditionKind.isCharacter`) only resolve when the
/// controlling player IS that character.
enum Character {
  decima,
  tetra,
  volos,
  rez,
  koSynWu,
}

// ---------------------------------------------------------------------------
// Original effects (kept intact for DeckService and existing tests)
// ---------------------------------------------------------------------------

final class GainMoneyEffect extends CardEffect {
  const GainMoneyEffect(this.amount);

  final int amount;

  @override
  String get description => 'Gain $amount money';
}

// ---------------------------------------------------------------------------
// Shards of Infinity resource effects
// ---------------------------------------------------------------------------

/// Gain gems (currency used to buy cards from the center row).
/// This is the Shards of Infinity equivalent of GainMoneyEffect.
final class GainGemsEffect extends CardEffect {
  const GainGemsEffect(this.amount);

  final int amount;

  @override
  String get description => 'Gain $amount ${amount == 1 ? 'gem' : 'gems'}';
}

/// Gain power (damage that can be dealt to opponents or their champions).
final class GainPowerEffect extends CardEffect {
  const GainPowerEffect(this.amount);

  final int amount;

  @override
  String get description => 'Gain $amount power';
}

/// Gain mastery (accumulated to unlock thresholds and the Infinity Shard).
final class GainMasteryEffect extends CardEffect {
  const GainMasteryEffect(this.amount);

  final int amount;

  @override
  String get description => 'Gain $amount mastery';
}

/// Gain health (healing).
final class GainHealthEffect extends CardEffect {
  const GainHealthEffect(this.amount);

  final int amount;

  @override
  String get description => 'Gain $amount health';
}

/// Draw cards from your personal draw pile into your hand.
/// (Already existed; kept as-is.)
final class DrawCardsEffect extends CardEffect {
  const DrawCardsEffect(this.count);

  final int count;

  @override
  String get description => 'Draw $count ${count == 1 ? 'card' : 'cards'}';
}

// ---------------------------------------------------------------------------
// Opponent interaction effects
// ---------------------------------------------------------------------------

/// Target opponent loses health directly. Bypasses Guard champions.
final class OpponentLosesHealthEffect extends CardEffect {
  const OpponentLosesHealthEffect(this.amount);

  final int amount;

  @override
  String get description =>
      'Target opponent loses $amount health';
}

// ---------------------------------------------------------------------------
// Banish / scrap effects (deck thinning and market denial)
// ---------------------------------------------------------------------------

/// Where a card can be banished from.
enum BanishSource {
  hand,
  discard,
  handOrDiscard,
}

/// Banish a card (permanently remove from the game). The [source] specifies
/// which zone the player can pick from. Most cards in Shards of Infinity say
/// "banish a card from your hand or discard pile" (handOrDiscard).
final class BanishCardEffect extends CardEffect {
  const BanishCardEffect(this.source);

  final BanishSource source;

  @override
  String get description {
    switch (source) {
      case BanishSource.hand:
        return 'Banish a card from your hand';
      case BanishSource.discard:
        return 'Banish a card from your discard pile';
      case BanishSource.handOrDiscard:
        return 'Banish a card from your hand or discard pile';
    }
  }
}

/// Scrap a card from the center row (remove without buying; denies opponents
/// and triggers a market refill).
final class ScrapFromCenterRowEffect extends CardEffect {
  const ScrapFromCenterRowEffect();

  @override
  String get description => 'Scrap a card from the center row';
}

// ---------------------------------------------------------------------------
// Champion removal effects (Phase 1)
// ---------------------------------------------------------------------------

/// Destroy an enemy champion without spending power (card-effect removal).
///
/// When [all] is false the player picks a single target enemy champion (target
/// selection mirrors [OpponentLosesHealthEffect] / banish — see GameService).
/// When [all] is true every enemy champion is destroyed with no target choice.
/// Destroyed champions go to their owner's discard pile, exactly like the
/// destruction half of [GameService.attackChampion].
final class DestroyChampionEffect extends CardEffect {
  const DestroyChampionEffect({this.all = false});

  /// If true, destroy ALL enemy champions instead of a single chosen target.
  final bool all;

  @override
  String get description => all
      ? 'Destroy all enemy champions'
      : 'Destroy a target enemy champion';
}

// ---------------------------------------------------------------------------
// Discard recursion effects (Phase 1)
// ---------------------------------------------------------------------------

/// Which cards in the discard pile a [ReturnFromDiscardEffect] may return.
enum ReturnFilter {
  /// Any card may be returned.
  any,

  /// Only champion-type cards.
  champion,

  /// Only mercenary-type cards.
  mercenary,

  /// Only cards matching [ReturnFromDiscardEffect.faction].
  faction,
}

/// Return a card from your own discard pile to your hand.
///
/// The [filter] restricts which cards are eligible. When [filter] is
/// [ReturnFilter.faction], [faction] names the required faction. Target
/// selection mirrors banish (the player calls
/// [GameService.returnFromDiscard] with the chosen card id).
final class ReturnFromDiscardEffect extends CardEffect {
  const ReturnFromDiscardEffect({
    this.filter = ReturnFilter.any,
    this.faction,
  });

  final ReturnFilter filter;

  /// Required faction when [filter] is [ReturnFilter.faction]; otherwise null.
  final Faction? faction;

  @override
  String get description {
    switch (filter) {
      case ReturnFilter.any:
        return 'Return a card from your discard pile to your hand';
      case ReturnFilter.champion:
        return 'Return a champion from your discard pile to your hand';
      case ReturnFilter.mercenary:
        return 'Return a mercenary from your discard pile to your hand';
      case ReturnFilter.faction:
        final f = faction?.name ?? 'faction';
        return 'Return a $f card from your discard pile to your hand';
    }
  }
}

// ---------------------------------------------------------------------------
// Complex / composite effects
// ---------------------------------------------------------------------------

/// Player chooses one of several effect groups to resolve.
/// Each choice is a list of effects that are applied together.
final class ChooseOneEffect extends CardEffect {
  const ChooseOneEffect(this.choices);

  /// Each entry is a group of effects applied together when chosen.
  final List<List<CardEffect>> choices;

  @override
  String get description {
    final options = choices
        .map((group) => group.map((e) => e.description).join(' and '))
        .join(' OR ');
    return options;
  }
}

// ---------------------------------------------------------------------------
// GameCondition predicate + ConditionalEffect wrapper (Engine Phase 2, wave 0)
// ---------------------------------------------------------------------------

/// Parity for [GameConditionKind.gemParityCardsPlayed] — whether the count of
/// matching cards played this turn must be even or odd.
enum GemParity { even, odd }

/// The kind of board-state predicate a [GameCondition] evaluates. Each kind
/// reads game state (cards played this turn, champions in play, mastery, the
/// controlling player's Character) and answers true/false. The optional
/// [GameCondition] fields (`threshold`, `faction`, `factions`, `parity`,
/// `cardType`, `maxCost`, `character`) parameterise the specific kind.
enum GameConditionKind {
  /// At least `threshold` allies (cards matching `faction`, or the source
  /// card's faction when `faction` is null) have been played this turn.
  alliesOfFactionPlayed,

  /// Every faction in `factions` has been played this turn.
  factionsPlayedAll,

  /// At least `threshold` DISTINCT (non-none) factions have been played this
  /// turn. The resolving source card's own faction IS counted toward the set
  /// (unlike the self-skipping "this turn" count kinds).
  distinctFactionsPlayed,

  /// At least `threshold` cards of `cardType` have been played this turn.
  cardTypePlayed,

  /// The number of matching cards played this turn has the given `parity`
  /// (even/odd). When `faction` is set, only cards of that faction are counted.
  /// The resolving source card is EXCLUDED from the count (so a lone card sees
  /// count 0 = even) — encoders should pick thresholds accordingly.
  gemParityCardsPlayed,

  /// At least `threshold` cards played this turn match the filter (`faction`
  /// and/or `maxCost` when provided).
  filteredCardsPlayed,

  /// The player controls at least `threshold` champions.
  championsControlled,

  /// The player controls at least `threshold` champions of `faction`.
  championsOfFactionControlled,

  /// The player's mastery is at least `threshold`.
  masteryAtLeast,

  /// At least `threshold` cards of the SAME faction (the source card's faction,
  /// or `faction` when set) have been played this turn (counting the source).
  sameFactionCountPlayed,

  /// The controlling player IS the named `character`.
  isCharacter,
}

/// A board-state predicate evaluated by `GameService._evaluateGameCondition`.
///
/// This is a value type, NOT a [CardEffect]. It is carried by
/// [ConditionalEffect] (the wrapper effect) and answers a single yes/no
/// question about current game state. Fields beyond [kind] are optional and
/// only meaningful for the kinds that read them.
class GameCondition {
  const GameCondition({
    required this.kind,
    this.threshold = 1,
    this.faction,
    this.factions = const [],
    this.parity,
    this.cardType,
    this.maxCost,
    this.character,
  });

  final GameConditionKind kind;

  /// The numeric bar for "at least N" kinds (default 1).
  final int threshold;

  /// A single faction filter (e.g. for `alliesOfFactionPlayed`,
  /// `championsOfFactionControlled`). Null = use the source card's faction
  /// where applicable.
  final Faction? faction;

  /// A set of factions for `factionsPlayedAll`.
  final List<Faction> factions;

  /// Parity for `gemParityCardsPlayed`.
  final GemParity? parity;

  /// A card-type filter for `cardTypePlayed`.
  final CardType? cardType;

  /// A max-cost filter for `filteredCardsPlayed` (inclusive). Null = no cap.
  final int? maxCost;

  /// The required Character for `isCharacter`.
  final Character? character;

  String get description {
    switch (kind) {
      case GameConditionKind.alliesOfFactionPlayed:
        final f = faction?.name ?? 'same-faction';
        return 'if you have played $threshold+ $f allies this turn';
      case GameConditionKind.factionsPlayedAll:
        final names = factions.map((f) => f.name).join(', ');
        return 'if you have played all of: $names this turn';
      case GameConditionKind.distinctFactionsPlayed:
        return 'if you have played $threshold+ distinct factions this turn';
      case GameConditionKind.cardTypePlayed:
        final t = cardType?.name ?? 'card';
        return 'if you have played $threshold+ ${t}s this turn';
      case GameConditionKind.gemParityCardsPlayed:
        final p = parity?.name ?? 'even';
        final f = faction != null ? '${faction!.name} ' : '';
        return 'if an $p number of ${f}cards were played this turn';
      case GameConditionKind.filteredCardsPlayed:
        return 'if you have played $threshold+ matching cards this turn';
      case GameConditionKind.championsControlled:
        return 'if you control $threshold+ champions';
      case GameConditionKind.championsOfFactionControlled:
        final f = faction?.name ?? 'faction';
        return 'if you control $threshold+ $f champions';
      case GameConditionKind.masteryAtLeast:
        return 'if your mastery is $threshold+';
      case GameConditionKind.sameFactionCountPlayed:
        return 'if you have played $threshold+ same-faction cards this turn';
      case GameConditionKind.isCharacter:
        return 'if you are ${character?.name ?? 'a character'}';
    }
  }
}

/// A wrapper effect that resolves its [then] effects only when [condition]
/// holds. Works uniformly in `playEffects`, `allyAbility`, `masteryBonus`, and
/// inside an `activatedAbility` (since each routes through
/// `GameService._resolveEffects`).
final class ConditionalEffect extends CardEffect {
  const ConditionalEffect({required this.condition, required this.then});

  final GameCondition condition;
  final List<CardEffect> then;

  @override
  String get description {
    final body = then.map((e) => e.description).join(', ');
    return '${condition.description}: $body';
  }
}

/// The condition type for scaling power effects.
enum PowerCondition {
  /// Gain power equal to the number of champions you control.
  perChampionControlled,

  /// Gain power equal to the number of allies (cards matching this card's
  /// faction) you have played so far this turn.
  perAllyPlayedThisTurn,

  /// Gain power equal to the number of distinct factions you have played so
  /// far this turn.
  perFactionPlayedThisTurn,

  /// Gain power equal to the number of cards in your discard pile.
  perCardInDiscard,
}

/// Power that scales based on game state rather than a fixed amount.
final class ConditionalPowerEffect extends CardEffect {
  const ConditionalPowerEffect(this.condition);

  final PowerCondition condition;

  @override
  String get description {
    switch (condition) {
      case PowerCondition.perChampionControlled:
        return 'Gain 1 power for each champion you control';
      case PowerCondition.perAllyPlayedThisTurn:
        return 'Gain 1 power for each ally played this turn';
      case PowerCondition.perFactionPlayedThisTurn:
        return 'Gain 1 power for each faction played this turn';
      case PowerCondition.perCardInDiscard:
        return 'Gain 1 power for each card in your discard pile';
    }
  }
}

// ---------------------------------------------------------------------------
// ScalingResourceEffect (Engine Phase 2, wave 0) — generalises
// ConditionalPowerEffect to any resource pool with faction-filtered conditions.
//
// MIGRATION CHOICE: ConditionalPowerEffect is KEPT as-is (its JSON type
// "conditionalPower" still decodes to it, and all existing model + codec tests
// stay green with zero churn). ScalingResourceEffect is added as a SEPARATE new
// effect with its own JSON type "scalingResource". No card data uses
// "conditionalPower" yet (only rawText/notes mention it), so there is nothing to
// re-key; keeping both side by side is the lowest-risk path that keeps the 263
// existing tests passing. ScalingResourceEffect with resource=power +
// the 4 original conditions is behaviourally identical to ConditionalPowerEffect.
// ---------------------------------------------------------------------------

/// The resource pool a [ScalingResourceEffect] feeds into.
enum ScalingResource { power, gems, health, mastery }

/// The board-state quantity a [ScalingResourceEffect] scales by. The first four
/// mirror [PowerCondition] exactly; the rest add faction-filtered variants.
enum ScalingCondition {
  /// Per champion you control.
  perChampionControlled,

  /// Per ally (same-faction card) played this turn (excludes the source).
  perAllyPlayedThisTurn,

  /// Per distinct (non-none) faction played this turn.
  perFactionPlayedThisTurn,

  /// Per card in your discard pile.
  perCardInDiscard,

  /// Per card of [ScalingResourceEffect.faction] in your discard pile.
  perFactionCardInDiscard,

  /// Per champion of [ScalingResourceEffect.faction] you control.
  perFactionChampionControlled,

  /// Per card of [ScalingResourceEffect.faction] played this turn.
  perFactionCardPlayedThisTurn,

  /// Per ally with a shield (champion of the source faction) played this turn.
  perAllyWithShieldPlayedThisTurn,
}

/// A resource gain that scales with game state rather than a fixed amount.
///
/// Grants `perN` of [resource] for each unit counted by [condition] (optionally
/// filtered by [faction]). Generalises [ConditionalPowerEffect] across all four
/// resource pools.
final class ScalingResourceEffect extends CardEffect {
  const ScalingResourceEffect({
    required this.resource,
    required this.condition,
    this.perN = 1,
    this.faction,
  });

  final ScalingResource resource;
  final ScalingCondition condition;

  /// How much of [resource] to grant per counted unit (default 1).
  final int perN;

  /// The faction filter for the `perFaction*` conditions. Null = use the source
  /// card's faction.
  final Faction? faction;

  String get _unit {
    switch (condition) {
      case ScalingCondition.perChampionControlled:
        return 'champion you control';
      case ScalingCondition.perAllyPlayedThisTurn:
        return 'ally played this turn';
      case ScalingCondition.perFactionPlayedThisTurn:
        return 'faction played this turn';
      case ScalingCondition.perCardInDiscard:
        return 'card in your discard pile';
      case ScalingCondition.perFactionCardInDiscard:
        return '${faction?.name ?? 'faction'} card in your discard pile';
      case ScalingCondition.perFactionChampionControlled:
        return '${faction?.name ?? 'faction'} champion you control';
      case ScalingCondition.perFactionCardPlayedThisTurn:
        return '${faction?.name ?? 'faction'} card played this turn';
      case ScalingCondition.perAllyWithShieldPlayedThisTurn:
        return 'ally with shield played this turn';
    }
  }

  @override
  String get description => 'Gain $perN ${resource.name} for each $_unit';
}

/// The cost a player must pay to use an [ActivatedAbility].
///
/// Activated abilities in Shards of Infinity sometimes cost resources on top of
/// the Exhaust (e.g. "Exhaust, pay 1 mastery: ..."). Each field is the amount
/// deducted from the corresponding player pool when the ability is used; 0 means
/// that resource is not part of the cost. All fields default to 0 so the common
/// "Exhaust only" ability needs no cost at all (use [ActivationCost.none]).
final class ActivationCost {
  const ActivationCost({this.gems = 0, this.mastery = 0, this.health = 0});

  /// Gems spent from the player's gem pool.
  final int gems;

  /// Mastery spent (permanently reduced) from the player's mastery.
  final int mastery;

  /// Health paid from the player's current health total.
  final int health;

  /// A free cost — Exhaust is the only requirement.
  static const ActivationCost none = ActivationCost();

  /// Whether this cost requires no resources (Exhaust-only ability).
  bool get isFree => gems == 0 && mastery == 0 && health == 0;
}

/// An Exhaust-gated activated ability attached to a champion (Shards of
/// Infinity's "Exhaust: <effect>" abilities).
///
/// This is deliberately NOT a [CardEffect] subtype. The original design note
/// (now removed) explained why: an activated ability has a *lifecycle* the flat
/// effect vocabulary can't express — it costs an activation (and optionally
/// resources), then leaves the champion **exhausted** (tapped) until the start
/// of the owner's next turn. Modelling it as a value type that *contains* a list
/// of ordinary [CardEffect]s keeps the effect vocabulary unchanged while giving
/// the champion instance the structural state (exhaustion) the mechanic needs.
///
/// Resolution and the per-champion exhausted state live in `GameService`
/// (`useActivatedAbility`), distinct from a champion's free once-per-turn
/// [CardModel.playEffects] activation (`activateChampion`).
final class ActivatedAbility {
  const ActivatedAbility({
    required this.effects,
    this.cost = ActivationCost.none,
  });

  /// The effects resolved when this ability is used. Reuses the existing
  /// [CardEffect] vocabulary — an activated ability is a *container* of effects,
  /// not a new effect kind.
  final List<CardEffect> effects;

  /// The resource cost (beyond Exhaust) to use the ability.
  final ActivationCost cost;

  /// Human-readable summary for UI display.
  String get description {
    final body = effects.map((e) => e.description).join(', ');
    return 'Exhaust: $body';
  }
}

/// The Infinity Shard — scales with mastery.
/// Always grants 1 mastery. Power scales: 0/3/6/10/15/20 at mastery 0/5/10/15/20/25.
/// At mastery 30+: instant win (infinite damage).
final class InfinityShardEffect extends CardEffect {
  const InfinityShardEffect();

  @override
  String get description => '+1 mastery, power scales with mastery';
}
