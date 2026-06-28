import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/faction.dart';

void main() {
  group('Faction', () {
    test('has all four game factions plus none', () {
      expect(Faction.values, hasLength(5));
      expect(
        Faction.values.map((f) => f.name).toList(),
        ['homodeus', 'wraethe', 'order', 'undergrowth', 'none'],
      );
    });
  });
}
