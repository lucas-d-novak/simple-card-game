/// The three card types in Fragments of Boundlessness.
///
/// - [regular]: Standard cards that go to discard after being played.
/// - [champion]: Persist in play across turns, providing effects each turn.
/// - [mercenary]: Bought from the center row and played immediately, then
///   removed from the game (not discarded).
enum CardType {
  regular,
  champion,
  mercenary,
}
