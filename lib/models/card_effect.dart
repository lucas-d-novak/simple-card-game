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
    }
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
