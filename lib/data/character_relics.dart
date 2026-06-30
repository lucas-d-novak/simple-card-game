// Character → Relic pair mapping (Relics of the Future expansion).
//
// PURE DART (no Flutter imports) so the multiplayer server reuses it.
//
// RULES (researched, see WORKSTREAM brief):
// - Each named Character owns exactly TWO Relics (one offensive, one defensive),
//   set aside beside the player at setup.
// - On reaching Mastery 10, the player recruits ONE of the two for FREE; the
//   OTHER is banished. The chosen relic is SHUFFLED INTO THE PLAYER'S DRAW PILE
//   (unlike Destiny, which stays beside play) and thereafter drawn/played like a
//   normal card.
//
// Each entry lists the relic CARD IDS (matching `assets/card_db/cards.json`),
// conventionally [offensive, defensive].
//
// COVERAGE: decima / tetra / volos / koSynWu are mapped (research-confirmed).
// rez and chroma are intentionally UNMAPPED — the relic pairing for those two
// characters could not be confirmed from research, so they have no relic options
// (a no-op for recruitRelic). Fill these in once their pairs are confirmed.

import 'package:simple_card_game/models/card_effect.dart' show Character;

/// Character → its two relic card ids ([offensive, defensive]). Characters with
/// no confirmed relic pair (rez, chroma) are absent from this map.
const Map<Character, List<String>> characterRelicIds = {
  Character.decima: ['praetorian_01', 'praetorian_02'],
  Character.tetra: ['datic_robes', 'terminal_crescents'],
  Character.volos: ['entropic_talons', 'panconscious_crown'],
  Character.koSynWu: ['the_heart_of_nothing', 'the_world_piercer'],
};

/// The two relic card ids for [character], or null if the character is unmapped
/// (rez / chroma) or null.
List<String>? relicIdsFor(Character? character) {
  if (character == null) return null;
  return characterRelicIds[character];
}
