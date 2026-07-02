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
  chroma,
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
// Fragments of Boundlessness resource effects
// ---------------------------------------------------------------------------

/// Gain gems (currency used to buy cards from the center row).
/// This is the Fragments of Boundlessness equivalent of GainMoneyEffect.
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

/// Target opponent(s) lose [amount] MASTERY (floored at 0). The mastery version
/// of [OpponentLosesHealthEffect]: a raw mastery subtraction against every living
/// opponent, applied via `GameService._applyOpponentMasteryLoss`. Cannot be
/// prevented by shield/guard (mastery is not health). Cards:
/// venator_of_the_wastes ("an enemy player loses 2 mastery if you have a Champion
/// in play") and skry_77 (Mastery-20: "you gain 2 mastery AND an enemy player
/// loses 2 mastery").
final class OpponentLosesMasteryEffect extends CardEffect {
  const OpponentLosesMasteryEffect(this.amount);

  final int amount;

  @override
  String get description => 'Target opponent loses $amount mastery';
}

/// Every player in the game (INCLUDING the current/controlling player) loses
/// [amount] health directly. Cannot be prevented by shield/guard — it is a raw
/// health subtraction applied to all players simultaneously (e.g. bound_for_life
/// "All players lose N health").
///
/// DESIGN CHOICE: modelled as its own effect rather than overloading
/// [OpponentLosesHealthEffect] with includeSelf/ignoreShield flags. The
/// "all players" semantics are cleaner as a distinct type: there is no target
/// selection, the current player is always affected, and both existing effects
/// already bypass shield (the engine has no per-attack shield gate outside the
/// guard check in `attackPlayer`). Keeping them separate avoids mutating an
/// existing effect's JSON shape and switch cases.
final class AllPlayersLoseHealthEffect extends CardEffect {
  const AllPlayersLoseHealthEffect(this.amount);

  final int amount;

  @override
  String get description => 'All players lose $amount health';
}

// ---------------------------------------------------------------------------
// Banish / scrap effects (deck thinning and market denial)
// ---------------------------------------------------------------------------

/// Where a card can be banished from.
enum BanishSource {
  hand,
  discard,
  handOrDiscard,

  /// A card the player has played this turn (blood_for_blood: "you may banish a
  /// card you have played this turn"). Resolved against `cardsPlayedThisTurn`.
  playedThisTurn,
}

/// Banish a card (permanently remove from the game). The [source] specifies
/// which zone the player can pick from. Most cards in Fragments of Boundlessness say
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
      case BanishSource.playedThisTurn:
        return 'Banish a card you have played this turn';
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

/// "Then, banish this." — the source card removes ITSELF from the game after
/// resolving its other effects. Resolved against the in-flight `sourceCard` in
/// `_resolveEffects`: the source moves to `removedFromGame` and is excised from
/// any zone (playedThisTurn / cardsPlayedThisTurn / championsInPlay) so the
/// end-of-turn cleanup does not also discard it. Must be listed LAST in a card's
/// effect list so the card's other effects resolve before it leaves the game.
/// Cards: aion_guide, wandering_ghost (self-banish half).
final class SelfBanishEffect extends CardEffect {
  const SelfBanishEffect();

  @override
  String get description => 'Then, banish this';
}

/// "Reset another Champion you control." — un-exhausts a champion (clears it
/// from `exhaustedChampions`) so it may use its Exhaust-gated activated ability
/// again this turn. Deferred-selection (like [BanishCardEffect]): a no-op in
/// `_resolveEffects`; the player calls [GameService.resetChampion] with the
/// chosen champion id after selection. Card: g_48.
final class ResetChampionEffect extends CardEffect {
  const ResetChampionEffect();

  @override
  String get description => 'Reset another champion you control';
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
    this.self = false,
    this.all = false,
  });

  final ReturnFilter filter;

  /// Required faction when [filter] is [ReturnFilter.faction]; otherwise null.
  final Faction? faction;

  /// When true, return THIS card (the resolving source card) from discard back
  /// to hand — a SELF return, resolved INLINE (no target selection). Matches by
  /// the source card's NAME (market copies share a name but get per-copy ids), so
  /// a discarded copy of the same card is returned. Used by the_dispossessed
  /// ("you may return this from your discard pile to your hand"). A no-op if no
  /// copy of the source is in the discard pile.
  final bool self;

  /// When true, return ALL matching cards from discard to hand at once, resolved
  /// INLINE (no target selection). Used by the_world_piercer's Mastery-20 ("return
  /// all Mercenaries from your discard pile"). Ignored when [self] is true.
  final bool all;

  @override
  String get description {
    if (self) return 'Return this from your discard pile to your hand';
    final scope = all ? 'all' : 'a';
    switch (filter) {
      case ReturnFilter.any:
        return 'Return $scope card${all ? 's' : ''} from your discard pile to '
            'your hand';
      case ReturnFilter.champion:
        return 'Return $scope champion${all ? 's' : ''} from your discard pile '
            'to your hand';
      case ReturnFilter.mercenary:
        return 'Return $scope mercenary${all ? 's' : ''} from your discard pile '
            'to your hand';
      case ReturnFilter.faction:
        final f = faction?.name ?? 'faction';
        return 'Return $scope $f card${all ? 's' : ''} from your discard pile to '
            'your hand';
    }
  }
}

/// Return a card from your own discard pile to the TOP of your DECK (it becomes
/// your next draw), rather than to your hand. Deferred-selection: a no-op in
/// `_resolveEffects`; the player calls [GameService.returnFromDiscardToDeckTop]
/// with the chosen card id. The [filter]/[faction] restrict eligibility exactly
/// like [ReturnFromDiscardEffect]. Card: dash ("fetch an Aion card from your
/// discard pile and put it on top of your deck", resolved BEFORE its draw).
///
/// NOTE: "Aion" is a catalog GROUP, not a playable [Faction], so the engine
/// cannot filter to Aion cards; dash uses [ReturnFilter.any].
final class ReturnFromDiscardToDeckTopEffect extends CardEffect {
  const ReturnFromDiscardToDeckTopEffect({
    this.filter = ReturnFilter.any,
    this.faction,
  });

  final ReturnFilter filter;
  final Faction? faction;

  @override
  String get description =>
      'Return a card from your discard pile to the top of your deck';
}

/// "Mill the top [count] card(s) of your OWN deck" — move them from the top of
/// your draw pile straight to your discard pile (no reveal/choice). Immediate:
/// resolved inline in `_resolveEffects`. Reshuffles discard into the draw pile if
/// the draw pile runs short (mirrors `_drawCards`), milling as many as available.
/// Card: legion_carrier ("mill the top 3 cards of your deck").
final class MillEffect extends CardEffect {
  const MillEffect(this.count);

  final int count;

  @override
  String get description =>
      'Mill the top $count ${count == 1 ? 'card' : 'cards'} of your deck';
}

/// On-RECRUIT trigger: "when you recruit this, put it into your hand" (instead of
/// the default discard pile). NOT resolved at play time — a no-op in
/// `_resolveEffects`. Instead `GameService.buyCard` / `recruitFromCenter` scan the
/// recruited card's `playEffects` for this effect and, if present (and the
/// optional [character] gate is satisfied by the recruiting player), route the
/// card to hand. Cards: breaker (unconditional) and nexus_datic_hunter
/// (gated on [Character.tetra] — "if you are Tetra, put this into your hand when
/// you Recruit it"). The optional [character] reuses the same player-Character
/// identity check as [GameConditionKind.isCharacter].
final class RecruitToHandEffect extends CardEffect {
  const RecruitToHandEffect({this.character});

  /// When set, the on-recruit-to-hand trigger only fires if the recruiting
  /// player IS this Character. Null = always fires.
  final Character? character;

  @override
  String get description => character == null
      ? 'When you recruit this, put it into your hand'
      : 'If you are ${character!.name}, put this into your hand when you '
          'recruit it';
}

/// A PASSIVE, while-in-discard trigger: "when you play a Champion, return this
/// from your discard pile to your hand" (praetorian_01). This effect is INERT
/// during normal resolution (a no-op in `GameService._resolveEffects`) — it is a
/// marker that `GameService.playCard` scans the discard pile for after a champion
/// is played, moving any card carrying it back to the owner's hand.
final class ReturnSelfWhenChampionPlayedEffect extends CardEffect {
  const ReturnSelfWhenChampionPlayedEffect();

  @override
  String get description =>
      'When you play a Champion, return this from your discard pile to your hand';
}

// ---------------------------------------------------------------------------
// Deferred-selection action effects (Engine Phase 2, wave 3)
//
// Each is a no-op in `GameService._resolveEffects` (like BanishCardEffect): the
// effect merely signals the UI/AI that a selection is needed, and a dedicated
// public GameService method does the work once the target is chosen.
// ---------------------------------------------------------------------------

/// "Recruit / acquire a Center Row card (optionally for free, optionally to a
/// special destination)." Covers portal_monk, datic_inquisitors,
/// the_crystal_gate. Deferred-selection: a no-op in `_resolveEffects`; the
/// player calls [GameService.recruitFromCenter] with the chosen card id.
///
/// - [maxCost] caps which Center Row cards are eligible (null = no cap).
/// - [free] true → the card is acquired without paying its gem cost.
/// - [toHand] true → the acquired card goes straight to the player's hand
///   (instead of the default discard pile).
/// - [toTopOfDeck] true → the acquired card goes to the TOP of the draw pile
///   (it becomes the player's next draw). Mutually exclusive with [toHand];
///   if both are set, [toHand] wins (validated in the GameService method).
final class RecruitFromCenterEffect extends CardEffect {
  const RecruitFromCenterEffect({
    this.maxCost,
    this.free = false,
    this.toHand = false,
    this.toTopOfDeck = false,
  });

  final int? maxCost;
  final bool free;
  final bool toHand;
  final bool toTopOfDeck;

  @override
  String get description {
    final cap = maxCost != null ? ' costing $maxCost or less' : '';
    final cost = free ? ' for free' : '';
    final String dest;
    if (toHand) {
      dest = ' to your hand';
    } else if (toTopOfDeck) {
      dest = ' to the top of your deck';
    } else {
      dest = '';
    }
    return 'Recruit a center row card$cap$cost$dest';
  }
}

/// "Warp / fast-play a Center Row card (cost <= N) for free, immediately, then
/// banish it." Covers aion_egressor, j_chord, deadly_recruits. Deferred-
/// selection: a no-op in `_resolveEffects`; the player calls
/// [GameService.fastPlayFromCenter] with the chosen card id.
///
/// - [maxCost] caps which Center Row cards are eligible (null = no cap).
/// - [alliesOnly] true → only allies (non-champion cards) may be chosen.
final class FastPlayFromCenterEffect extends CardEffect {
  const FastPlayFromCenterEffect({this.maxCost, this.alliesOnly = false});

  final int? maxCost;
  final bool alliesOnly;

  @override
  String get description {
    final cap = maxCost != null ? ' of cost $maxCost or less' : '';
    final who = alliesOnly ? 'ally' : 'card';
    return 'Fast-play a center row $who$cap for free, then banish it';
  }
}

/// Where the NEXT card a player recruits this turn should go, when a
/// [RedirectNextRecruitEffect] is pending.
enum RecruitRedirect {
  /// The recruited card is deployed DIRECTLY INTO PLAY instead of going to the
  /// discard pile (numeri_drones "put the next Homodeus Champion you recruit
  /// this turn directly into play"). Only meaningful for champions — a
  /// non-champion cannot persist in play, so a redirect with this destination
  /// only matches champion recruits.
  intoPlay,

  /// The recruited card goes to the player's HAND instead of the discard pile
  /// (anomaly_cleric Mastery-10 "put the next card you recruit this turn into
  /// your hand").
  toHand,
}

/// "Put the NEXT [faction]/[cardType] card you recruit this turn [destination]."
///
/// A TURN-SCOPED, SINGLE-USE modifier to the next matching recruit's
/// destination — NOT an immediate action with a visible result. Its
/// `_resolveEffects` case installs itself as the current player's
/// [PlayerState.pendingRecruitRedirect]. The NEXT time that player recruits a
/// card matching the [faction]/[cardType] filters (via `buyCard` or a free
/// `recruitFromCenter`), the engine routes that card to [destination] and
/// CONSUMES the pending redirect (it fires exactly once). Any unused redirect is
/// cleared at end of turn by [PlayerState.resetTurnResources].
///
/// Cards:
/// - numeri_drones — Exhaust: put the next Homodeus Champion you recruit this
///   turn directly into play (`destination: intoPlay`, `faction: homodeus`,
///   `cardType: champion`).
/// - anomaly_cleric — Mastery 10: put the next card you recruit this turn into
///   your hand (`destination: toHand`, no filters).
final class RedirectNextRecruitEffect extends CardEffect {
  const RedirectNextRecruitEffect({
    required this.destination,
    this.faction,
    this.cardType,
  });

  /// Where the next matching recruited card goes.
  final RecruitRedirect destination;

  /// Optional faction filter — only a recruit of this faction consumes the
  /// redirect (honours `countsAsAllFactions`). Null = any faction.
  final Faction? faction;

  /// Optional card-type filter — only a recruit of this type consumes the
  /// redirect. Null = any type. (For [RecruitRedirect.intoPlay] the engine
  /// additionally requires the recruit to be a champion regardless of this
  /// filter, since only champions can enter play.)
  final CardType? cardType;

  @override
  String get description {
    final f = faction != null ? '${faction!.name} ' : '';
    final t = cardType != null ? '${cardType!.name} ' : 'card';
    final subject = '$f$t'.trim();
    switch (destination) {
      case RecruitRedirect.intoPlay:
        return 'Put the next $subject you recruit this turn directly into play';
      case RecruitRedirect.toHand:
        return 'Put the next $subject you recruit this turn into your hand';
    }
  }
}

/// What a [ScryEffect] does with the revealed card the player keeps vs. lets go.
enum ScryDisposition {
  /// Keep → draw to hand; let go → discard.
  drawOrDiscard,

  /// Keep → draw to hand; let go → banish (remove from game).
  drawOrBanish,

  /// Keep → put into hand directly (no "draw"); let go → leave on top.
  toHand,

  /// Reveal the top card of YOUR OWN deck, put it into your hand, and lose power
  /// equal to its gem cost (power pool floored at 0). This is mandatory on
  /// reveal (no keep/discard choice) and "ignores Guard" — it is a pure
  /// resource interaction with no targeting. Used by oblivion_gatekeeper.
  /// (Distinct from CenterScryDisposition.toHandLosePowerEqualToCost, which
  /// pulls from the CENTER/infinity deck.)
  toHandLosePowerEqualToCost,

  /// Reveal the top card of YOUR OWN deck, put it into your hand, and the
  /// controller loses HEALTH equal to its gem cost. Mandatory on reveal (no
  /// keep/discard choice) and "cannot be prevented by Guard" — a pure resource
  /// interaction with no targeting. Used by oblivion_gatekeeper's base Exhaust.
  /// Resolves INLINE in `_resolveEffects` (mandatory dispositions do not need
  /// the deferred scryReveal/scryResolve UI flow).
  toHandLoseHealthEqualToCost,

  /// Reveal the top card of YOUR OWN deck, put it into your hand, and ALL
  /// OPPONENTS lose HEALTH equal to its gem cost instead of the controller.
  /// Used by oblivion_gatekeeper's Mastery-20 replacement of the base Exhaust.
  /// Resolves INLINE in `_resolveEffects` (mandatory; ignores Guard).
  toHandOpponentsLoseHealthEqualToCost,
}

/// "Look at the top [count] card(s) of your deck; you may act on them, then
/// draw." keeper_of_datic_vessels-style. Deferred-selection: a no-op in
/// `_resolveEffects`; the player calls [GameService.scryReveal] to peek (without
/// removing), then [GameService.scryResolve] per revealed card.
///
/// Only the single-card self-deck case is implemented this wave; center-deck
/// reveal variants are deferred to a later wave.
final class ScryEffect extends CardEffect {
  const ScryEffect({
    this.count = 1,
    this.disposition = ScryDisposition.drawOrDiscard,
  });

  final int count;
  final ScryDisposition disposition;

  @override
  String get description {
    switch (disposition) {
      case ScryDisposition.drawOrDiscard:
        return 'Look at the top $count of your deck; draw it or discard it';
      case ScryDisposition.drawOrBanish:
        return 'Look at the top $count of your deck; draw it or banish it';
      case ScryDisposition.toHand:
        return 'Look at the top $count of your deck; you may take it to hand';
      case ScryDisposition.toHandLosePowerEqualToCost:
        return 'Reveal the top of your deck, take it to hand, and lose power '
            'equal to its cost';
      case ScryDisposition.toHandLoseHealthEqualToCost:
        return 'Reveal the top of your deck, take it to hand, and lose health '
            'equal to its cost (ignores Guard)';
      case ScryDisposition.toHandOpponentsLoseHealthEqualToCost:
        return 'Reveal the top of your deck, take it to hand; all opponents '
            'lose health equal to its cost (ignores Guard)';
    }
  }
}

// ---------------------------------------------------------------------------
// Turn-scoped matching modifiers (Engine Phase 2, wave 4)
// ---------------------------------------------------------------------------

/// "Treat [from] cards as [to] this turn" (project_yggdrasil; isa_tel_tor
/// mastery-20). A TURN-SCOPED modifier to faction matching, not an immediate
/// action with a visible result. Its `_resolveEffects` case mutates the current
/// player's [PlayerState.factionAliasesThisTurn]: it records `from -> to`, and
/// (when [bidirectional]) also `to -> from`, so the two factions count as each
/// other for ally abilities and faction-filtered scaling/conditions for the rest
/// of the turn. Cleared by [PlayerState.resetTurnResources].
final class TreatFactionAsEffect extends CardEffect {
  const TreatFactionAsEffect({
    required this.from,
    required this.to,
    this.bidirectional = false,
  });

  /// The faction that should be treated as [to].
  final Faction from;

  /// The faction [from] is treated as.
  final Faction to;

  /// When true, [to] is also treated as [from] (the alias works both ways).
  final bool bidirectional;

  @override
  String get description => bidirectional
      ? 'Treat ${from.name} and ${to.name} as the same faction this turn'
      : 'Treat ${from.name} cards as ${to.name} this turn';
}

/// "You ignore shield this turn" (spirit_leech). A TURN-SCOPED modifier: its
/// `_resolveEffects` case sets the current player's
/// [PlayerState.ignoresShieldThisTurn] true, so any of that player's attacks
/// destroy an enemy champion regardless of its shield value (the shield is
/// treated as 0 for the destroy threshold). Cleared by
/// [PlayerState.resetTurnResources].
final class IgnoreShieldThisTurnEffect extends CardEffect {
  const IgnoreShieldThisTurnEffect();

  @override
  String get description => 'You ignore shield this turn';
}

// ---------------------------------------------------------------------------
// Static board-wide modifiers (Engine Phase 2, wave 5a — Family 11)
//
// Persistent buffs/protections/cost-reductions that read off a player's
// [PlayerState.staticModifiers] list while the source card remains in play.
// An [AddStaticModifierEffect] appends one to the list when its source resolves.
// ---------------------------------------------------------------------------

/// The kind of persistent board-wide modifier a [StaticModifier] applies.
enum StaticModifierKind {
  /// Your champions (optionally faction/type-filtered) have +amount shield —
  /// under the owner combat model (backlog §E) a CHAMPION-sourced shieldBuff is a
  /// standing buff to the PLAYER's per-hit damage reduction while that champion is
  /// in play (praetorian_02 "you have 4 shield"). Consulted in
  /// `_playerDamageReduction` (NOT in champion kill thresholds). May be
  /// mastery-scaled via [StaticModifier.masteryThreshold]/[masteryAmount].
  shieldBuff,

  /// Your champions (optionally faction/type-filtered) have +amount HEALTH —
  /// they require that much extra power to destroy (one_mind_one_army "your
  /// Champions have +2 health"). Consulted in `_effectiveHealth`. Distinct from
  /// [shieldBuff]: this raises the champion KILL threshold, it does NOT reduce
  /// player damage.
  healthBuff,

  /// Cards you acquire from the center row cost `amount` less gems, to a
  /// minimum of 1 (aedifex "Champions cost 3 less"). Optional faction/type
  /// filter restricts which cards get the discount. Consulted in `buyCard` and
  /// `recruitFromCenter`.
  cardCostReduction,

  /// You cannot be attacked (zetta_the_encryptor). Consulted in `attackPlayer`
  /// (and `attackChampion` targeting). `amount`/filters are ignored.
  cannotBeAttacked,

  /// Champions (optionally faction/type-filtered) you RECRUIT go to the top of
  /// your deck instead of the discard pile (maglev_tunnels "put recruited
  /// Homodeus Champions on top of deck"). Consulted in `recruitFromCenter`.
  recruitToTopOfDeck,

  /// The SOURCE champion gains `amount` shield for each card currently tucked
  /// under it (carmine_eclipse "+2 shield for each card under this"). Unlike the
  /// other kinds this is SELF-scoped: it only buffs the champion that owns the
  /// modifier, scaling with that champion's under-card count
  /// ([PlayerState.cardsUnderChampion]). Consulted in `attackChampion` via
  /// `_effectiveHealth`. The modifier carries the owning champion's id in
  /// [StaticModifier.sourceChampionId].
  shieldPerCardUnder,
}

/// A persistent, board-wide modifier owned by a player. Carried in
/// [PlayerState.staticModifiers] and consulted by combat / acquisition methods.
///
/// LIFETIME: a modifier added by [AddStaticModifierEffect] stays for the REST OF
/// THE GAME (it is never automatically removed). This is the documented, simple
/// semantics chosen for wave 5a: the engine does not yet model "while this card
/// is in play" removal when a regular card leaves play or a champion is
/// destroyed. It is a defensible approximation because the cards carrying these
/// modifiers are champions (one_mind_one_army, aedifex, zetta_the_encryptor,
/// maglev_tunnels, phasic_technology) that persist anyway; a regular card that
/// granted a static buff would over-stay by design until removal is added.
class StaticModifier {
  const StaticModifier({
    required this.kind,
    this.amount = 0,
    this.faction,
    this.cardType,
    this.sourceChampionId,
    this.masteryThreshold,
    this.masteryAmount = 0,
  });

  final StaticModifierKind kind;

  /// The magnitude (shield bonus, cost reduction; per-card shield bonus for
  /// [StaticModifierKind.shieldPerCardUnder]). Ignored by
  /// [StaticModifierKind.cannotBeAttacked] and [StaticModifierKind.recruitToTopOfDeck].
  final int amount;

  /// Optional mastery tier for a mastery-scaled modifier. When non-null and the
  /// owner's mastery is at/above this threshold, [masteryAmount] is used instead
  /// of [amount] (praetorian_02: 4 shield normally, 8 at mastery >= 20). Null =
  /// the amount never scales. See [amountFor].
  final int? masteryThreshold;

  /// The magnitude used when the owner's mastery is at/above [masteryThreshold].
  /// Ignored when [masteryThreshold] is null.
  final int masteryAmount;

  /// The effective magnitude for an owner at [mastery]: [masteryAmount] when a
  /// [masteryThreshold] is set and reached, otherwise [amount].
  int amountFor(int mastery) =>
      (masteryThreshold != null && mastery >= masteryThreshold!)
          ? masteryAmount
          : amount;

  /// Optional faction filter — the modifier only applies to cards/champions of
  /// this faction. Null = applies regardless of faction.
  final Faction? faction;

  /// Optional card-type filter — the modifier only applies to cards of this
  /// type. Null = applies regardless of type.
  final CardType? cardType;

  /// For [StaticModifierKind.shieldPerCardUnder] ONLY: the id of the champion
  /// this self-scoped buff belongs to. The buff scales with that champion's
  /// under-card count and applies only to that champion. Stamped automatically
  /// when an [AddStaticModifierEffect] resolves with the in-flight champion as
  /// its source card. Null for every other kind.
  final String? sourceChampionId;

  String get description {
    final f = faction != null ? '${faction!.name} ' : '';
    final t = cardType != null ? '${cardType!.name} ' : '';
    switch (kind) {
      case StaticModifierKind.shieldBuff:
        return 'Your $f${t}champions have +$amount shield';
      case StaticModifierKind.healthBuff:
        return 'Your $f${t}champions have +$amount health';
      case StaticModifierKind.cardCostReduction:
        return 'Your $f${t}cards cost $amount less';
      case StaticModifierKind.cannotBeAttacked:
        return 'You cannot be attacked';
      case StaticModifierKind.recruitToTopOfDeck:
        return 'Recruited $f${t}cards go to the top of your deck';
      case StaticModifierKind.shieldPerCardUnder:
        return 'This champion has +$amount shield for each card under it';
    }
  }
}

/// Adds a persistent [StaticModifier] to the controlling player's
/// [PlayerState.staticModifiers] when this effect resolves. Immediate (not
/// deferred): its `_resolveEffects` case appends the modifier inline.
final class AddStaticModifierEffect extends CardEffect {
  const AddStaticModifierEffect(this.modifier);

  final StaticModifier modifier;

  @override
  String get description => modifier.description;
}

// ---------------------------------------------------------------------------
// Under-card stacking (Engine Phase 2, wave 5b — Family 13)
//
// Some champions accumulate other cards "tucked under" them and then reference
// the number of under-cards (carmine_eclipse "+2 shield per card under this")
// or replay their effects (paradigm_the_archivist "copy the effect of all cards
// under this"). The per-champion under-card list lives on
// [PlayerState.cardsUnderChampion] (keyed by champion id). These effects mutate
// or read that state.
// ---------------------------------------------------------------------------

/// Where a [TuckUnderChampionEffect] takes the card it tucks from.
enum TuckSource {
  /// Tuck a card chosen from the controlling player's hand
  /// (paradigm_the_archivist "Put an Ally from your hand under this").
  hand,

  /// Tuck the top card of the CENTER (infinity) deck
  /// (gene_scavs "Ambush — put the top card of the Center Deck under this").
  centerDeck,
}

/// "Put a card under [champion]." DEFERRED-SELECTION for [TuckSource.hand] (the
/// player calls [GameService.tuckUnderChampion] with the chosen champion id and
/// card id after selection); IMMEDIATE for [TuckSource.centerDeck] (resolved
/// inline against the top of the infinity deck — no choice needed).
///
/// The tucked card is removed from its origin zone and appended to the
/// champion's under-card list ([PlayerState.cardsUnderChampion]). It is NOT a
/// regular play (its effects do not resolve when tucked). When [alliesOnly] is
/// true, only allies (non-champion cards) may be tucked from hand.
final class TuckUnderChampionEffect extends CardEffect {
  const TuckUnderChampionEffect({
    this.source = TuckSource.hand,
    this.alliesOnly = false,
  });

  final TuckSource source;

  /// When true (and [source] is [TuckSource.hand]), only non-champion cards may
  /// be tucked.
  final bool alliesOnly;

  @override
  String get description {
    switch (source) {
      case TuckSource.hand:
        final who = alliesOnly ? 'an ally' : 'a card';
        return 'Put $who from your hand under this champion';
      case TuckSource.centerDeck:
        return 'Put the top card of the center deck under this champion';
    }
  }
}

/// "Copy the effect of all cards under this champion"
/// (paradigm_the_archivist). DEFERRED-SELECTION: a no-op in `_resolveEffects`
/// (the champion is identified by the in-flight source card when resolved via
/// an activated ability, so the player calls [GameService.copyUnderCards] with
/// the champion id). Re-resolves the `playEffects` of every card currently
/// tucked under that champion, in tuck order, for the controlling player.
///
/// RE-ENTRANCY GUARD (enforced in [GameService.copyUnderCards]): any
/// [InfinityShardEffect] among an under-card's effects is skipped (mirrors
/// [CopyPlayedCardEffect]), so copying never grants a spurious mastery/win, and
/// a [TuckUnderChampionEffect] / [CopyUnderCardsEffect] among them is skipped to
/// avoid re-entrant tucking/copying.
final class CopyUnderCardsEffect extends CardEffect {
  const CopyUnderCardsEffect();

  @override
  String get description => 'Copy the effect of all cards under this champion';
}

// ---------------------------------------------------------------------------
// Copy-effect (Engine Phase 2, wave 5a — Family 9)
// ---------------------------------------------------------------------------

/// Which previously-played cards a [CopyPlayedCardEffect] may copy.
enum CopyFilter {
  /// Any card played this turn (subject to the universal re-entrancy / shard
  /// exclusions enforced by [GameService.copyPlayedCard]).
  any,

  /// Only non-champion cards played this turn (ojas_genesis_druid,
  /// taur_archpriest "copy a non-Champion card you played this turn").
  nonChampion,
}

/// "Copy the effect of a [filter] card you played this turn"
/// (ojas_genesis_druid, taur_archpriest). DEFERRED-SELECTION: a no-op in
/// `_resolveEffects`; the player calls [GameService.copyPlayedCard] with the
/// chosen card's id, which RE-RESOLVES that card's `playEffects` for the current
/// player.
///
/// RE-ENTRANCY GUARD (enforced in [GameService.copyPlayedCard]): a card that
/// itself contains a [CopyPlayedCardEffect] is NOT copyable (prevents infinite
/// recursion), and an [InfinityShardEffect] is excluded from the re-resolved
/// effects (so copying never causes a spurious mastery/win).
final class CopyPlayedCardEffect extends CardEffect {
  const CopyPlayedCardEffect({this.filter = CopyFilter.nonChampion, this.faction});

  final CopyFilter filter;

  /// When set, the copied card must also match this faction (taur_archpriest:
  /// "copy the effect of an Undergrowth Ally played this turn"). Honours
  /// `countsAsAllFactions` on the candidate card. null = any faction.
  final Faction? faction;

  @override
  String get description {
    final f = faction != null ? '${faction!.name} ' : '';
    switch (filter) {
      case CopyFilter.any:
        return 'Copy the effect of a ${f}card you played this turn';
      case CopyFilter.nonChampion:
        return 'Copy the effect of a ${f}non-champion card you played this turn';
    }
  }
}

// ---------------------------------------------------------------------------
// Opponent draw / discard (Engine Phase 2, wave 5a — Family 13)
// ---------------------------------------------------------------------------

/// "Each OTHER player draws [count] card(s)" (blitz_shard_runner). Immediate:
/// its `_resolveEffects` case makes every player except the controller draw
/// from their own draw pile (reshuffling their discard when empty).
final class OpponentDrawsEffect extends CardEffect {
  const OpponentDrawsEffect({this.count = 1});

  final int count;

  @override
  String get description =>
      'Each other player draws $count ${count == 1 ? 'card' : 'cards'}';
}

/// "Each OTHER player discards [count] card(s)" (blitz_shard_runner mastery
/// variant). Immediate: its `_resolveEffects` case makes every player except the
/// controller discard from their hand (the first [count] cards, or all they have
/// if fewer).
final class OpponentDiscardsEffect extends CardEffect {
  const OpponentDiscardsEffect({this.count = 1});

  final int count;

  @override
  String get description =>
      'Each other player discards $count ${count == 1 ? 'card' : 'cards'}';
}

// ---------------------------------------------------------------------------
// Center-deck scry (Engine Phase 2, wave 5a — extends Family 8)
// ---------------------------------------------------------------------------

/// What a [CenterDeckScryEffect] does with the card revealed off the center /
/// infinity deck.
enum CenterScryDisposition {
  /// Acquire the revealed card (it goes to the player's discard pile — like a
  /// free recruit). the_shard_defiant "reveal top of the center deck and
  /// acquire it".
  acquire,

  /// Put the revealed card into the player's HAND and lose power equal to its
  /// gem cost; the reveal ignores Guard (oblivion_gatekeeper). The lose-power
  /// half is handled inline (no separate effect needed) because it is tied to
  /// the revealed card's cost.
  toHandLosePowerEqualToCost,
}

/// "Reveal the top card of the CENTER (infinity) deck and act on it"
/// (oblivion_gatekeeper, the_shard_defiant). DEFERRED-SELECTION: a no-op in
/// `_resolveEffects`; the player calls [GameService.centerDeckScryReveal] to
/// peek at the top center-deck card, then [GameService.centerDeckScryResolve] to
/// apply the [disposition].
///
/// This is the center-deck counterpart to [ScryEffect] (which reveals the
/// player's OWN draw pile). Modelled as a distinct effect rather than a flag on
/// [ScryEffect] because its dispositions (acquire / lose-power-by-cost) and the
/// deck it reads are different.
final class CenterDeckScryEffect extends CardEffect {
  const CenterDeckScryEffect({
    this.disposition = CenterScryDisposition.acquire,
  });

  final CenterScryDisposition disposition;

  @override
  String get description {
    switch (disposition) {
      case CenterScryDisposition.acquire:
        return 'Reveal the top of the center deck and acquire it';
      case CenterScryDisposition.toHandLosePowerEqualToCost:
        return 'Reveal the top of the center deck, take it to hand and lose '
            'power equal to its cost';
    }
  }
}

// ---------------------------------------------------------------------------
// Complex / composite effects
// ---------------------------------------------------------------------------

/// Player chooses one of several effect groups to resolve.
/// Each choice is a list of effects that are applied together.
final class ChooseOneEffect extends CardEffect {
  const ChooseOneEffect(this.choices, {this.pick = 1});

  /// Each entry is a group of effects applied together when chosen.
  final List<List<CardEffect>> choices;

  /// How many DISTINCT choice groups the player resolves (default 1 =
  /// classic "choose one"). `pick > 1` models "choose N instead (you may not
  /// pick the same choice)" — e.g. red_fortune's Mastery-15 "Choose two
  /// instead." Clamped to the number of available choices at resolution.
  final int pick;

  @override
  String get description {
    final options = choices
        .map((group) => group.map((e) => e.description).join(' and '))
        .join(' OR ');
    return pick > 1 ? 'Choose $pick (distinct): $options' : options;
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

  /// The player's current health is at least `threshold` (e.g. Furrowing
  /// Elemental's "if you have 50 health, gain 6 power").
  healthAtLeast,

  /// At least `threshold` cards of the SAME faction (the source card's faction,
  /// or `faction` when set) have been played this turn (counting the source).
  sameFactionCountPlayed,

  /// The controlling player IS the named `character`.
  isCharacter,

  /// The controlling player has dealt at least `threshold` unblocked damage to
  /// opponents this turn (via `attackPlayer`). Resets at the start of each
  /// player's turn. Used by blood_for_blood ("if you dealt 5+ unblocked damage
  /// this turn").
  unblockedDamageAtLeast,

  // --- Engine Phase 3 additions ---

  /// Unify: at least `threshold` allies of `faction` (or the source card's
  /// faction when null) have been played this turn, OR the player holds at
  /// least one such card in hand they could reveal. The printed Unify clause is
  /// "if you have played another <faction> Ally this turn or reveal one from
  /// your hand" — the reveal is always optional and free, so a card in hand is
  /// modelled as satisfying the predicate (a rational player reveals it).
  /// Used by the Undergrowth Unify allies and the Homodeus/Order Dominion line.
  factionAllyPlayedOrInHand,

  /// Boolean presence: at least one card of `faction` (or the source card's
  /// faction when null) is in the player's discard pile. Distinct from the
  /// SCALING `perFactionCardInDiscard` ScalingResource — this is a yes/no gate.
  /// Used by Echo cards ("if there is a Wraethe card in your discard pile…").
  factionCardInDiscard,

  /// At least `threshold` cards whose gem `cost` is ODD have been played this
  /// turn. The resolving source card is EXCLUDED from the count (consistent with
  /// the other "...Played" kinds) — encoders pick thresholds accordingly.
  /// Used by advanced_weapons.
  oddCostCardsPlayed,

  /// At least `threshold` cards whose gem `cost` is EVEN have been played this
  /// turn. The resolving source card is EXCLUDED from the count. Used by
  /// advanced_medicine.
  evenCostCardsPlayed,

  /// At least `threshold` OTHER cards with the SAME NAME as the source card have
  /// been played this turn (the source itself is EXCLUDED). Used by cinder_scars
  /// ("if you play or have played ANOTHER Cinder Scars this turn"). Matches by
  /// `name` so market copies (which share a name but get per-copy ids) count.
  sameNamePlayedThisTurn,

  /// The controlling player has STRICTLY more mastery than EVERY other
  /// (non-eliminated) player — a sole mastery lead. `threshold` is ignored.
  /// Used by cloud_oracles ("if you have more mastery than all other players,
  /// gain 2 gems"). Ties do NOT satisfy it (must be strictly greater).
  highestMasteryAmongPlayers,
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
      case GameConditionKind.healthAtLeast:
        return 'if your health is $threshold+';
      case GameConditionKind.sameFactionCountPlayed:
        return 'if you have played $threshold+ same-faction cards this turn';
      case GameConditionKind.isCharacter:
        return 'if you are ${character?.name ?? 'a character'}';
      case GameConditionKind.unblockedDamageAtLeast:
        return 'if you dealt $threshold+ unblocked damage this turn';
      case GameConditionKind.factionAllyPlayedOrInHand:
        final f = faction?.name ?? 'same-faction';
        return 'if you played another $f ally this turn or can reveal one '
            'from your hand';
      case GameConditionKind.factionCardInDiscard:
        final f = faction?.name ?? 'same-faction';
        return 'if there is a $f card in your discard pile';
      case GameConditionKind.oddCostCardsPlayed:
        return 'if you have played $threshold+ odd-cost cards this turn';
      case GameConditionKind.evenCostCardsPlayed:
        return 'if you have played $threshold+ even-cost cards this turn';
      case GameConditionKind.sameNamePlayedThisTurn:
        return 'if you have played $threshold+ other copies of this card '
            'this turn';
      case GameConditionKind.highestMasteryAmongPlayers:
        return 'if you have more mastery than all other players';
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
/// Activated abilities in Fragments of Boundlessness sometimes cost resources on top of
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
    this.masteryThreshold,
    this.masteryBonusEffects = const <CardEffect>[],
    this.replaces = false,
  });

  /// The effects resolved when this ability is used. Reuses the existing
  /// [CardEffect] vocabulary — an activated ability is a *container* of effects,
  /// not a new effect kind.
  final List<CardEffect> effects;

  /// The resource cost (beyond Exhaust) to use the ability.
  final ActivationCost cost;

  /// Mastery level at which [masteryBonusEffects] become relevant. Null means
  /// the ability has no mastery scaling (the common case — [effects] always
  /// resolve). Mirrors [CardModel.masteryThreshold] but scopes the gate to this
  /// ability.
  final int? masteryThreshold;

  /// The mastery-tier effects for this ability. When [replaces] is true and the
  /// owner's mastery is at/above [masteryThreshold], these resolve INSTEAD OF
  /// [effects] (e.g. gian_shard_wyrm gives 2/2 normally but 5/5 at mastery 15).
  /// When [replaces] is false, these resolve ADDITIVELY on top of [effects] once
  /// the threshold is met (matching the card-level additive mastery default).
  final List<CardEffect> masteryBonusEffects;

  /// Whether [masteryBonusEffects] replace [effects] (true) or add to them
  /// (false) at/above [masteryThreshold]. Defaults to false so existing
  /// abilities (with no mastery fields) are entirely unaffected.
  final bool replaces;

  /// Human-readable summary for UI display.
  String get description {
    final body = effects.map((e) => e.description).join(', ');
    final base = 'Exhaust: $body';
    if (masteryThreshold == null || masteryBonusEffects.isEmpty) return base;
    final bonus = masteryBonusEffects.map((e) => e.description).join(', ');
    final connector = replaces ? 'instead' : 'also';
    return '$base (at mastery $masteryThreshold: $connector $bonus)';
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
