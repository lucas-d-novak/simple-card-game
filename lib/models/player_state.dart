import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';

/// Mutable per-player state for a Fragments of Boundlessness game.
class PlayerState {
  PlayerState({required this.id, required this.name, this.character});

  final String id;
  final String name;

  /// The Character this player chose, if any. Character selection is wired up
  /// in a later Engine Phase 2 wave; until then this stays null and any
  /// `GameConditionKind.isCharacter` predicate evaluates false.
  Character? character;

  int health = 50;
  int mastery = 0;
  int gemPool = 0;
  int powerPool = 0;

  /// Total unblocked damage this player has dealt to opponents this turn (via
  /// [GameService.attackPlayer]). Read by `GameConditionKind.unblockedDamageAtLeast`
  /// (e.g. blood_for_blood). Reset each turn by [resetTurnResources].
  int unblockedDamageThisTurn = 0;

  /// Turn-scoped faction aliases set by [TreatFactionAsEffect] (e.g.
  /// project_yggdrasil "treat Wraethe cards as Undergrowth this turn"). Each
  /// entry maps a `from` faction to a `to` faction; when matching factions for
  /// ally abilities and faction-filtered scaling/conditions, the engine
  /// canonicalizes a faction through these aliases (`from` is treated as `to`).
  /// Bidirectional effects add both directions. Cleared each turn by
  /// [resetTurnResources] so the alias only lasts the controlling player's turn.
  final List<({Faction from, Faction to})> factionAliasesThisTurn = [];

  /// Turn-scoped flag set by [IgnoreShieldThisTurnEffect] (spirit_leech "you
  /// ignore shield this turn"). While true, this player's attacks treat enemy
  /// champion shield as 0 for the destroy threshold (any power destroys the
  /// champion). Cleared each turn by [resetTurnResources].
  bool ignoresShieldThisTurn = false;

  /// Persistent board-wide modifiers this player owns (Engine Phase 2 wave 5a —
  /// [StaticModifier]). Added by [AddStaticModifierEffect]. LIFETIME: these are
  /// NOT cleared by [resetTurnResources] — a static modifier stays for the rest
  /// of the game (the documented wave-5a semantics; no per-card removal yet).
  /// Consulted by `GameService.attackChampion` (shield buff), `attackPlayer`
  /// (cannot-be-attacked), `buyCard` / `recruitFromCenter` (cost reduction,
  /// recruit-to-top placement).
  final List<StaticModifier> staticModifiers = [];

  /// The two Relics set aside beside this player at setup (Relics of the Future
  /// expansion). Populated by [GameService] only when the player has a Character
  /// that is in the relic-pair table AND relic card templates were injected into
  /// the constructor; otherwise empty. Upon reaching Mastery 10 the player
  /// recruits ONE of these for free via [GameService.recruitRelic] (it is
  /// SHUFFLED INTO [drawPile]); the other is banished to [GameService.removedFromGame].
  /// Once recruited (see [relicRecruited]) this zone is emptied. NOT cleared by
  /// [resetTurnResources] — relics persist beside the player until recruited.
  final List<CardModel> relicOptions = [];

  /// True once this player has recruited (or been forced to forgo) their Relic
  /// via [GameService.recruitRelic]. Guards the once-per-game recruit. Game-long
  /// lifetime — NOT cleared by [resetTurnResources].
  bool relicRecruited = false;

  final List<CardModel> hand = [];
  final List<CardModel> drawPile = [];
  final List<CardModel> discardPile = [];
  final List<CardModel> playedThisTurn = [];
  final List<CardModel> championsInPlay = [];

  /// Cards that were FAST-PLAYED / WARPED this turn — either a free warp
  /// ([GameService.fastPlayFromCenter]) or a paid mercenary fast-play
  /// ([GameService.payAndFastPlayFromCenter]). Per the warp / mercenary rules
  /// these cards are removed from the game (NOT discarded) at end of turn, but
  /// the player should still SEE that they were played. Keeping them here lets
  /// the UI render them in the play area, greyed out, for the rest of the turn.
  ///
  /// These cards are deliberately NOT in [playedThisTurn] (so end-of-turn
  /// cleanup does not send them to discard) but ARE in [cardsPlayedThisTurn]
  /// (their play-history / ally contribution still counts). At end of turn
  /// [cleanupTurn] moves them to the game's removed-from-game zone and clears
  /// this list. Cleared here (not by [resetTurnResources]) so the engine can
  /// scoop them into removed-from-game first.
  final List<CardModel> fastPlayedThisTurn = [];

  /// Cards tucked UNDER a champion (Engine Phase 2 wave 5b — Family 13), keyed
  /// by the champion's id. Populated by [TuckUnderChampionEffect] (carmine_eclipse
  /// fast-play-under, paradigm_the_archivist "put an Ally under this", gene_scavs
  /// ambush). The list per champion is in tuck order. Read by
  /// `GameService._effectiveShield` (carmine_eclipse "+shield per card under")
  /// and `GameService.copyUnderCards` (paradigm). NOT cleared by
  /// [resetTurnResources] — under-cards persist with their champion until it
  /// leaves play.
  final Map<String, List<CardModel>> cardsUnderChampion = {};

  /// The number of cards currently tucked under the champion with [championId]
  /// (0 if none / unknown). Convenience for shield-per-card scaling.
  int cardsUnderCount(String championId) =>
      cardsUnderChampion[championId]?.length ?? 0;

  /// Champion ids that have used their free once-per-turn [CardModel.playEffects]
  /// activation this turn (see GameService.activateChampion).
  final Set<String> activatedChampions = {};

  /// Champion ids that are currently **exhausted** (tapped) — they have used
  /// their Exhaust-gated [CardModel.activatedAbility] and cannot use it again
  /// until the start of the owner's next turn. Distinct from
  /// [activatedChampions]: a champion can have its free play-effect activation
  /// AND its activated ability available independently. Cleared each turn by
  /// [resetTurnResources], so it is fresh at the start of the owner's next turn.
  final Set<String> exhaustedChampions = {};

  /// Every card played this turn (regular, champion, and mercenary), recorded
  /// in play order before any end-of-turn cleanup. Unlike [playedThisTurn],
  /// this includes champions (which move to [championsInPlay]) and is used by
  /// per-turn scaling effects (ConditionalPowerEffect). Cleared each turn by
  /// [resetTurnResources].
  final List<CardModel> cardsPlayedThisTurn = [];

  /// True once the player has used their once-per-turn Character **Focus**
  /// ability this turn (pay 1 gem → gain 1 mastery — the universal base action,
  /// "exhaust your character card"). Cleared each turn by [resetTurnResources].
  bool focusedThisTurn = false;

  /// A pending, SINGLE-USE redirect for the NEXT matching card this player
  /// recruits this turn (numeri_drones "put the next Homodeus Champion you
  /// recruit this turn directly into play"; anomaly_cleric Mastery-10 "put the
  /// next card you recruit this turn into your hand"). Installed by
  /// [RedirectNextRecruitEffect]; consumed (set back to null) by the first
  /// matching recruit in `GameService.buyCard` / `recruitFromCenter`. Cleared
  /// each turn by [resetTurnResources] so an unused redirect never leaks into a
  /// later turn.
  RedirectNextRecruitEffect? pendingRecruitRedirect;

  // --- Destiny system (Into the Horizon expansion) --------------------------

  /// Destinies this player has CLAIMED. This is a NEW PERSISTENT zone that sits
  /// beside the player's play area — it is distinct from the draw/discard deck:
  /// claimed Destinies NEVER enter [drawPile] / [discardPile] / [hand]. A
  /// Destiny is either a persistent passive (its [CardModel.playEffects] resolve
  /// once at claim time — e.g. a [StaticModifier] standing buff) or grants an
  /// extra activated ability (its [CardModel.activatedAbility], usable once per
  /// turn via Exhaust — like a second Focus button). Populated by
  /// [GameService.claimDestiny]. NOT cleared by [resetTurnResources] — Destinies
  /// persist for the rest of the game (a cascade may banish one via
  /// [GameService.banishDestinyToCascade]).
  final List<CardModel> claimedDestinies = [];

  /// Number of Destinies this player has claimed *for free via the base rule*
  /// (reaching Mastery 5). Normally a player may claim only ONE Destiny this
  /// way; a cascade Destiny (Mastery 10) can grant additional claims, tracked by
  /// [destinyClaimGrants]. The base-rule limit is [destinyClaimCount] < 1 +
  /// [destinyClaimGrants]. Persists for the whole game (NOT reset each turn).
  int destinyClaimCount = 0;

  /// Extra Destiny claims granted by cascade effects (e.g. stolen_future at
  /// Mastery 10 banishes itself to grant 2 more claims). Adds to the base
  /// one-per-game allowance. Persists for the whole game.
  int destinyClaimGrants = 0;

  /// Whether this player may still claim a Destiny under the per-game limit:
  /// the base allowance is 1, plus any cascade [destinyClaimGrants].
  bool get canClaimAnotherDestiny =>
      destinyClaimCount < 1 + destinyClaimGrants;

  /// Ids of claimed Destinies that have used their Exhaust-gated
  /// [CardModel.activatedAbility] this turn (the Destiny is "tapped" until the
  /// start of the owner's next turn). Independent of [exhaustedChampions].
  /// Cleared each turn by [resetTurnResources].
  final Set<String> exhaustedDestinies = {};

  bool get isEliminated => health <= 0;

  void addMastery(int amount) {
    if (amount > 0) {
      mastery += amount;
    }
  }

  /// Lose [amount] mastery, floored at 0 (mastery can never go negative).
  /// Used by opponent-loses-mastery effects (venator_of_the_wastes, skry_77).
  void loseMastery(int amount) {
    if (amount > 0) {
      mastery = (mastery - amount).clamp(0, mastery);
    }
  }

  void takeDamage(int amount) {
    health -= amount;
  }

  void heal(int amount) {
    health += amount;
  }

  /// Resets per-turn resource pools. Does not touch mastery or health.
  void resetTurnResources() {
    gemPool = 0;
    powerPool = 0;
    unblockedDamageThisTurn = 0;
    factionAliasesThisTurn.clear();
    ignoresShieldThisTurn = false;
    activatedChampions.clear();
    exhaustedChampions.clear();
    cardsPlayedThisTurn.clear();
    focusedThisTurn = false;
    // An unconsumed "next recruit" redirect expires at end of turn — the card
    // text scopes it to "this turn".
    pendingRecruitRedirect = null;
    // Destinies untap at the start of the owner's next turn. The persistent
    // zone (claimedDestinies) and per-game claim counters are NOT reset — only
    // the per-turn exhaustion state is.
    exhaustedDestinies.clear();
  }

  /// Moves regular played cards to discard pile and returns the cards to be
  /// REMOVED FROM THE GAME — end-of-turn mercenaries (from [playedThisTurn])
  /// plus every card fast-played / warped this turn (from [fastPlayedThisTurn],
  /// which stayed visible in the play area). Clears both [playedThisTurn] and
  /// [fastPlayedThisTurn]. Does NOT move champions — they persist in
  /// [championsInPlay].
  List<CardModel> cleanupTurn() {
    final List<CardModel> removed = [];

    for (final card in playedThisTurn) {
      if (card.cardType == CardType.mercenary) {
        removed.add(card);
      } else {
        discardPile.add(card);
      }
    }
    playedThisTurn.clear();

    // Fast-played / warped cards were kept visible (greyed) during the turn;
    // now they leave the game (never to discard).
    removed.addAll(fastPlayedThisTurn);
    fastPlayedThisTurn.clear();

    return removed;
  }
}
