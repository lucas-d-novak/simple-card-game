import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';

/// Builds a fresh 10-card starter deck for a player.
///
/// Each player starts with:
/// - 7 Crystals (each provides 1 Gem)
/// - 1 Blaster (provides 1 Power)
/// - 1 Infinity Shard (scales with mastery)
/// - 1 Shard Reactor (choose: 2 gems OR 2 power)
///
/// Card IDs are prefixed with [playerId] to ensure uniqueness across players.
List<CardModel> buildStarterDeck(String playerId) {
  return [
    for (int i = 0; i < 7; i++)
      CardModel(
        id: '${playerId}_crystal_$i',
        name: 'Crystal',
        cost: 0,
        playEffects: const [GainGemsEffect(1)],
      ),
    CardModel(
      id: '${playerId}_blaster_0',
      name: 'Blaster',
      cost: 0,
      playEffects: const [GainPowerEffect(1)],
    ),
    CardModel(
      id: '${playerId}_shard',
      name: 'Infinity Shard',
      cost: 0,
      playEffects: const [InfinityShardEffect()],
    ),
    // Shard Reactor: gain 2 gems, scaling with Mastery via threshold bonuses —
    // 3 gems at Mastery 5, 4 gems at Mastery 15 (the canonical Mastery
    // Threshold Bonus example). Modeled as base 2 + (+1 at >=5) + (+1 at >=15).
    CardModel(
      id: '${playerId}_reactor',
      name: 'Shard Reactor',
      cost: 0,
      playEffects: const [
        GainGemsEffect(2),
        ConditionalEffect(
          condition: GameCondition(
              kind: GameConditionKind.masteryAtLeast, threshold: 5),
          then: [GainGemsEffect(1)],
        ),
        ConditionalEffect(
          condition: GameCondition(
              kind: GameConditionKind.masteryAtLeast, threshold: 15),
          then: [GainGemsEffect(1)],
        ),
      ],
    ),
  ];
}
