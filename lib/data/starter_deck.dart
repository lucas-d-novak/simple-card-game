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
    CardModel(
      id: '${playerId}_reactor',
      name: 'Shard Reactor',
      cost: 0,
      playEffects: const [
        ChooseOneEffect([
          [GainGemsEffect(2)],
          [GainPowerEffect(2)],
        ]),
      ],
    ),
  ];
}
