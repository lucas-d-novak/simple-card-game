import '../../models/card_effect.dart';
import 'resource_icons.dart';

/// A single resource-gain the UI can telegraph with flying pips: a
/// [ResourceIcon] kind plus how many pips to fly.
class ResourceGrant {
  const ResourceGrant(this.icon, this.count);

  final ResourceIcon icon;
  final int count;
}

/// Inspect a card's [effects] and return the flat, unconditional resource gains
/// it grants to the player (gems / power / mastery / health), for driving the
/// pip fly animation.
///
/// This is PRESENTATION only — a best-effort read of the effect list to decide
/// which pips to fly; the engine remains the source of truth for the actual
/// state change. It deliberately covers only the simple, always-on grants
/// ([GainGemsEffect], [GainPowerEffect], [GainMasteryEffect],
/// [GainHealthEffect]). Conditional / scaling / choose-one effects are skipped
/// (they'd need live game state to evaluate); leaving them out just means no pip
/// flies for those — never a wrong pip.
List<ResourceGrant> resourceGrantsOf(Iterable<CardEffect> effects) {
  var gems = 0;
  var power = 0;
  var mastery = 0;
  var health = 0;
  for (final e in effects) {
    switch (e) {
      case GainGemsEffect(:final amount):
        gems += amount;
      case GainPowerEffect(:final amount):
        power += amount;
      case GainMasteryEffect(:final amount):
        mastery += amount;
      case GainHealthEffect(:final amount):
        health += amount;
      default:
        break;
    }
  }
  return [
    if (gems > 0) ResourceGrant(ResourceIcon.gem, gems),
    if (power > 0) ResourceGrant(ResourceIcon.power, power),
    if (mastery > 0) ResourceGrant(ResourceIcon.mastery, mastery),
    if (health > 0) ResourceGrant(ResourceIcon.health, health),
  ];
}
