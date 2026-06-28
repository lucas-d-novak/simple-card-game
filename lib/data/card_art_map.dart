/// Maps card names to their asset image paths.
/// Fallback: returns null for unknown cards (procedural art used instead).
String? getCardArtAsset(String cardName) {
  final key = cardName.toLowerCase().replaceAll(' ', '-').replaceAll("'", '');
  return _artMap[key];
}

const _artMap = <String, String>{
  'crystal': 'assets/cards/crystal.jpg',
  'blaster': 'assets/cards/blaster.jpg',
  'infinity-shard': 'assets/cards/infinity-shard.jpg',
  'shard-reactor': 'assets/cards/shard-reactor.jpg',
  'reactor-monk': 'assets/cards/reactor-monk.jpg',
  'neural-relay': 'assets/cards/neural-relay.jpg',
  'kor-arbiter': 'assets/cards/kor-arbiter.jpg',
  'infinity-engine': 'assets/cards/infinity-engine.jpg',
  'empowered-researcher': 'assets/cards/empowered-researcher.jpg',
  'shadow-fiend': 'assets/cards/shadow-fiend.jpg',
  'blood-ritualist': 'assets/cards/blood-ritualist.jpg',
  'dark-summoner': 'assets/cards/dark-summoner.jpg',
  'chaos-imp': 'assets/cards/chaos-imp.jpg',
  'shield-bearer': 'assets/cards/shield-bearer.jpg',
  'radiant-protector': 'assets/cards/radiant-protector.jpg',
  'dawn-cleric': 'assets/cards/dawn-cleric.jpg',
  'vine-guardian': 'assets/cards/vine-guardian.jpg',
  'leaf-dancer': 'assets/cards/leaf-dancer.jpg',
  'natures-bounty': 'assets/cards/natures-bounty.jpg',
  'universal-soldier': 'assets/cards/universal-soldier.jpg',
};
