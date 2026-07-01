import 'package:simple_card_game/models/card_effect.dart';

/// A NEUTRAL Ingeminex entity that lives in the shared Champions Row but belongs
/// to NO player (Ingeminex co-op-boss mechanic, adapted for versus play).
///
/// Unlike a normal champion (which sits in a player's [PlayerState.championsInPlay],
/// is controlled by its owner, and can only be attacked by opponents), an
/// Ingeminex is a shared, ownerless attackable that ANY player may hit
/// (see [GameService.attackIngeminex]). It models three things:
///
/// 1. APPEARANCE → hit everyone. When it appears ([GameService.spawnIngeminex]),
///    its [appearanceEffects] IMMEDIATELY resolve against EVERY player in the game
///    — including whoever caused it to appear. The appearance effects are authored
///    as ALL-PLAYERS-scoped effects (e.g. [AllPlayersLoseHealthEffect]), so a
///    single resolution broadcasts to all seats with no exclusion.
/// 2. NEUTRAL board presence. It occupies the champion row as a shared entity with
///    [maxHealth] (10) that accumulates [damageTaken] across attacks and turns
///    (an HP pool, not the all-or-nothing shield of a normal champion).
/// 3. KILL → reward. Whoever lands the killing blow (drives [damageTaken] to
///    [maxHealth]) — and only that player — receives its [rewardEffects].
///
/// PURE DART (no Flutter). Serialized whole by
/// [GameStateCodec] (`ingeminex` key) so the authoritative server's
/// persistence/undo/redaction can round-trip the entity and its accumulated
/// damage. The entity is ownerless, so it carries its own identity/effects inline
/// rather than referencing a player's card zone.
class IngeminexEntity {
  IngeminexEntity({
    required this.id,
    required this.name,
    this.art,
    this.maxHealth = defaultMaxHealth,
    this.damageTaken = 0,
    this.appearanceEffects = const [],
    this.rewardEffects = const [],
  });

  /// The health an Ingeminex must accumulate in damage before it dies. The
  /// product-owner spec fixes this at 10 for all six Ingeminex cards.
  static const int defaultMaxHealth = 10;

  /// The source card id (e.g. `brutality`, `torment`) — also the entity's stable
  /// identifier within [GameService.ingeminexRow] and the log's `cardId`.
  final String id;

  /// Display name (e.g. "Brutality").
  final String name;

  /// Optional art asset filename, carried through for the future UI pass.
  final String? art;

  /// Total damage needed to kill it (10). Constant, but stored so a future
  /// variant / snapshot is faithful.
  final int maxHealth;

  /// Damage accumulated so far. Persists across attacks and turns (serialized).
  int damageTaken;

  /// The "Attack" effect(s), authored as ALL-PLAYERS-scoped effects, resolved
  /// ONCE on appearance so every player (including the causer) is hit.
  final List<CardEffect> appearanceEffects;

  /// The "Reward" effect(s), resolved for the KILLER only when this entity dies.
  final List<CardEffect> rewardEffects;

  /// Health remaining before death (never negative, never above [maxHealth]).
  int get remainingHealth {
    final r = maxHealth - damageTaken;
    if (r < 0) return 0;
    if (r > maxHealth) return maxHealth;
    return r;
  }

  /// True once accumulated [damageTaken] has reached [maxHealth].
  bool get isDead => damageTaken >= maxHealth;

  /// Accumulate up to [amount] of damage, clamped so we never record more than
  /// lethal. Returns the damage actually applied.
  int applyDamage(int amount) {
    if (amount <= 0) return 0;
    final applied = amount > remainingHealth ? remainingHealth : amount;
    damageTaken += applied;
    return applied;
  }
}
