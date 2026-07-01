/// Maps card names to their asset image paths under `assets/cards/`.
///
/// Resolution order in [getCardArtAsset]:
///   1. Exact entry in [_artMap] (keyed by a normalised card name).
///   2. Automatic normalised-name match against a bundled asset file
///      (so e.g. "Chaos Imp" → `assets/cards/chaos-imp.jpg` or
///      `assets/cards/chaos_imp.jpg` resolves without an explicit entry).
///   3. `null` → the card falls back to procedural [CardArt].
///
/// Many of our hardcoded catalog cards ([lib/data/card_definitions.dart]) use
/// invented names that have no 1:1 art file, so they are mapped here to a
/// thematically-appropriate real asset (matched by faction + card type) drawn
/// from the authoritative art set in `assets/cards/`. This keeps the board
/// showing painted art everywhere an asset exists, reserving procedural art for
/// the genuinely art-less cards.
String? getCardArtAsset(String cardName) {
  final lower = cardName.toLowerCase();
  // 1. Explicit map (keyed by hyphen-normalised name, apostrophes stripped).
  final hyphenKey = lower.replaceAll(' ', '-').replaceAll("'", '');
  final mapped = _artMap[hyphenKey];
  if (mapped != null) return mapped;

  // 2. Automatic match against a known asset file by normalised name, trying
  //    both the hyphen and underscore conventions used in `assets/cards/`.
  final underscoreKey = lower
      .replaceAll(RegExp(r"[^a-z0-9]+"), '_')
      .replaceAll(RegExp(r"^_+|_+$"), '');
  final hyphenFileKey = lower
      .replaceAll(RegExp(r"[^a-z0-9]+"), '-')
      .replaceAll(RegExp(r"^-+|-+$"), '');
  for (final candidate in ['$underscoreKey.jpg', '$hyphenFileKey.jpg']) {
    if (_assetFiles.contains(candidate)) {
      return 'assets/cards/$candidate';
    }
  }
  return null;
}

/// Explicit name → asset map. Includes the starter/core cards plus thematic
/// art assignments for the invented catalog cards (grouped by faction below).
const _artMap = <String, String>{
  // --- Core / starter --------------------------------------------------------
  // The 4 starter cards now use their REAL printed art (the old stock-photo
  // placeholders were replaced with proper card scans at these paths).
  'crystal': 'assets/cards/crystal.jpg',
  'blaster': 'assets/cards/blaster.jpg',
  'shard-reactor': 'assets/cards/shard-reactor.jpg',
  'infinity-shard': 'assets/cards/infinity-shard.jpg',
  'infinity-engine-fragment': 'assets/cards/infinity-engine.jpg',

  // --- Homodeus (gold) — exact + thematic ------------------------------------
  'reactor-monk': 'assets/cards/reactor-monk.jpg',
  'neural-relay': 'assets/cards/neural-relay.jpg',
  'kor-arbiter': 'assets/cards/kor-arbiter.jpg',
  'infinity-engine': 'assets/cards/infinity-engine.jpg',
  'empowered-researcher': 'assets/cards/empowered-researcher.jpg',
  'thought-broker': 'assets/cards/synthetica_artifex.jpg',
  'knowledge-seeker': 'assets/cards/kiln_drone.jpg',
  'enlightened-architect': 'assets/cards/aedifex_deus_engineer.jpg',
  'neural-overload': 'assets/cards/concussio_and_mirus.jpg',
  'crystal-conduit': 'assets/cards/numeri_drones.jpg',
  'kor-oracle': 'assets/cards/drakonarius.jpg',
  'kor-celebrant': 'assets/cards/optio_crusher.jpg',
  'ascetic-of-the-lidless-eye': 'assets/cards/evokatus.jpg',
  'grand-kor-master': 'assets/cards/axia.jpg',

  // --- Wraethe (purple) — exact + thematic -----------------------------------
  'shadow-fiend': 'assets/cards/shadow-fiend.jpg',
  'blood-ritualist': 'assets/cards/blood-ritualist.jpg',
  'dark-summoner': 'assets/cards/dark-summoner.jpg',
  'chaos-imp': 'assets/cards/chaos-imp.jpg',
  'reaper': 'assets/cards/pall_shades.jpg',
  'venom-striker': 'assets/cards/wraethe_skirmisher.jpg',
  'void-reaver': 'assets/cards/the_world_piercer.jpg',
  'death-bringer': 'assets/cards/shadebound_sentry.jpg',
  'dark-reaver': 'assets/cards/li_hin_the_shattered.jpg',
  'wraith-lord': 'assets/cards/fa_cu_tul_the_formless.jpg',
  'chaos-lord': 'assets/cards/zen_chi_set_godkiller.jpg',
  'shadow-assassin': 'assets/cards/nil_assassin.jpg',
  'apocalypse': 'assets/cards/zara_ra_soulflayer.jpg',

  // --- Order (blue) — exact + thematic ---------------------------------------
  'shield-bearer': 'assets/cards/shield-bearer.jpg',
  'radiant-protector': 'assets/cards/radiant-protector.jpg',
  'dawn-cleric': 'assets/cards/dawn-cleric.jpg',
  'healer': 'assets/cards/order_initiate.jpg',
  'blessed-healer': 'assets/cards/portal_monk.jpg',
  'holy-warrior': 'assets/cards/cloud_oracles.jpg',
  'sanctuary-guard': 'assets/cards/anomaly_cleric.jpg',
  'templar-knight': 'assets/cards/command_seer.jpg',
  'high-templar': 'assets/cards/cryptofist_monk.jpg',
  'radiant-champion': 'assets/cards/zetta_the_encryptor.jpg',
  'divine-aegis': 'assets/cards/cache_warden.jpg',
  'divine-resurrection': 'assets/cards/the_grand_architect.jpg',

  // --- Undergrowth (green) — exact + thematic --------------------------------
  'vine-guardian': 'assets/cards/vine-guardian.jpg',
  'leaf-dancer': 'assets/cards/leaf-dancer.jpg',
  'forest-mystic': 'assets/cards/thorn_zealot.jpg',
  'root-warrior': 'assets/cards/shardwood_guardian.jpg',
  'grove-tender': 'assets/cards/undergrowth_aspirant.jpg',
  'overgrowth': 'assets/cards/furrowing_elemental.jpg',
  'primordial-force': 'assets/cards/ojas_genesis_druid.jpg',
  'thornback': 'assets/cards/chlorophyte_guardian.jpg',
  'elder-tree': 'assets/cards/taur_archpriest.jpg',
  'ancient-protector': 'assets/cards/additri_gaiamancer.jpg',
  'world-tree': 'assets/cards/gian_shard_wyrm.jpg',

  // --- Neutral ---------------------------------------------------------------
  'universal-soldier': 'assets/cards/universal-soldier.jpg',
};

/// Set of bundled `assets/cards/*.jpg` filenames, used for automatic
/// normalised-name resolution (step 2 in [getCardArtAsset]).
const _assetFiles = <String>{
  'crystal.jpg',
  'blaster.jpg',
  'shard-reactor.jpg',
  'infinity-shard.jpg',
  'blood-ritualist.jpg',
  'chaos-imp.jpg',
  'dark-summoner.jpg',
  'dawn-cleric.jpg',
  'empowered-researcher.jpg',
  'infinity-engine.jpg',
  'kor-arbiter.jpg',
  'leaf-dancer.jpg',
  'neural-relay.jpg',
  'radiant-protector.jpg',
  'reactor-monk.jpg',
  'shadow-fiend.jpg',
  'shield-bearer.jpg',
  'universal-soldier.jpg',
  'vine-guardian.jpg',
  // Authoritative DB card "Wraethe Skirmisher" (id wraethe_skirmisher) carries an
  // explicit `art` field so it already resolves via the DB-art path; this entry
  // also lets the NAME-based fallback (step 2) resolve it, closing a gap where a
  // "Wraethe Skirmisher" without a DB art path would have fallen to procedural.
  'wraethe_skirmisher.jpg',
};
