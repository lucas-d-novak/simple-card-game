import 'package:simple_card_game/models/faction.dart';

sealed class CardEffect {
  const CardEffect();

  String get description;
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

// TODO(phase2): Exhaust / activated champion abilities are intentionally NOT
// modelled here. They require a structural per-champion ability model (an
// activation cost + once-per-turn "exhausted" state on the champion instance),
// not a flat CardEffect subtype. Adding them as a CardEffect would not capture
// the exhaust lifecycle correctly. Implement as a dedicated ability model in a
// later phase rather than half-implementing it now.

/// The Infinity Shard — scales with mastery.
/// Always grants 1 mastery. Power scales: 0/3/6/10/15/20 at mastery 0/5/10/15/20/25.
/// At mastery 30+: instant win (infinite damage).
final class InfinityShardEffect extends CardEffect {
  const InfinityShardEffect();

  @override
  String get description => '+1 mastery, power scales with mastery';
}
