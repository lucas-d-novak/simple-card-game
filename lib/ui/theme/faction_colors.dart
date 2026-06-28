import 'package:flutter/material.dart';
import 'package:simple_card_game/models/faction.dart';

/// Faction color palette aligned with Shards of Infinity factions.
/// Homodeus = Gold, Wraethe = Purple, Order = Blue, Undergrowth = Green.
class FactionColors {
  FactionColors._();

  static const Map<Faction, Color> primary = {
    Faction.homodeus: Color(0xFFF9A825), // Rich gold
    Faction.wraethe: Color(0xFF9C27B0), // Deep purple
    Faction.order: Color(0xFF1565C0), // Royal blue
    Faction.undergrowth: Color(0xFF4CAF50), // Forest green
    Faction.none: Color(0xFF757575), // Medium grey
  };

  static const Map<Faction, Color> light = {
    Faction.homodeus: Color(0xFFFFF176), // Pale yellow
    Faction.wraethe: Color(0xFFCE93D8), // Lavender
    Faction.order: Color(0xFF90CAF9), // Sky blue
    Faction.undergrowth: Color(0xFFA5D6A7), // Pale green
    Faction.none: Color(0xFFE0E0E0), // Light grey
  };

  static const Map<Faction, Color> dark = {
    Faction.homodeus: Color(0xFFF57F17), // Deep amber
    Faction.wraethe: Color(0xFF4A0072), // Near-black purple
    Faction.order: Color(0xFF0D47A1), // Navy blue
    Faction.undergrowth: Color(0xFF1B5E20), // Dark forest
    Faction.none: Color(0xFF424242), // Dark grey
  };

  static Color getPrimary(Faction faction) =>
      primary[faction] ?? primary[Faction.none]!;

  static Color getLight(Faction faction) =>
      light[faction] ?? light[Faction.none]!;

  static Color getDark(Faction faction) =>
      dark[faction] ?? dark[Faction.none]!;

  static Color getTextOnPrimary(Faction faction) {
    if (faction == Faction.homodeus) return Colors.black87; // dark text on gold
    return Colors.white;
  }
}
