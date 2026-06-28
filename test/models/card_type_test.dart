import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_type.dart';

void main() {
  group('CardType', () {
    test('has regular, champion, and mercenary', () {
      expect(CardType.values, hasLength(3));
      expect(
        CardType.values.map((t) => t.name).toList(),
        ['regular', 'champion', 'mercenary'],
      );
    });
  });
}
