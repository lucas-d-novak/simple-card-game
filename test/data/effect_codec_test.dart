import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/effect_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/faction.dart';

void main() {
  group('effect_codec — Phase 1 effects', () {
    group('destroyChampion', () {
      test('decodes single-target (no all field) to all == false', () {
        final effect = decodeEffect({'type': 'destroyChampion'});
        expect(effect, isA<DestroyChampionEffect>());
        expect((effect as DestroyChampionEffect).all, false);
      });

      test('decodes all == true', () {
        final effect =
            decodeEffect({'type': 'destroyChampion', 'all': true});
        expect((effect as DestroyChampionEffect).all, true);
      });

      test('encodes round-trip for both variants', () {
        for (final all in [false, true]) {
          final encoded = encodeEffect(DestroyChampionEffect(all: all));
          expect(encoded, {'type': 'destroyChampion', 'all': all});
          final decoded = decodeEffect(encoded) as DestroyChampionEffect;
          expect(decoded.all, all);
        }
      });
    });

    group('returnFromDiscard', () {
      test('decodes default filter (missing) to any', () {
        final effect = decodeEffect({'type': 'returnFromDiscard'});
        expect(effect, isA<ReturnFromDiscardEffect>());
        final r = effect as ReturnFromDiscardEffect;
        expect(r.filter, ReturnFilter.any);
        expect(r.faction, isNull);
      });

      test('decodes champion / mercenary filters', () {
        expect(
          (decodeEffect({'type': 'returnFromDiscard', 'filter': 'champion'})
                  as ReturnFromDiscardEffect)
              .filter,
          ReturnFilter.champion,
        );
        expect(
          (decodeEffect({'type': 'returnFromDiscard', 'filter': 'mercenary'})
                  as ReturnFromDiscardEffect)
              .filter,
          ReturnFilter.mercenary,
        );
      });

      test('decodes faction filter with faction param', () {
        final r = decodeEffect({
          'type': 'returnFromDiscard',
          'filter': 'faction',
          'faction': 'wraethe',
        }) as ReturnFromDiscardEffect;
        expect(r.filter, ReturnFilter.faction);
        expect(r.faction, Faction.wraethe);
      });

      test('non-faction filter ignores faction param (null)', () {
        final r = decodeEffect({
          'type': 'returnFromDiscard',
          'filter': 'champion',
          'faction': 'order',
        }) as ReturnFromDiscardEffect;
        expect(r.faction, isNull);
      });

      test('encode round-trips faction filter (faction key present)', () {
        const effect = ReturnFromDiscardEffect(
          filter: ReturnFilter.faction,
          faction: Faction.order,
        );
        final encoded = encodeEffect(effect);
        expect(encoded, {
          'type': 'returnFromDiscard',
          'filter': 'faction',
          'faction': 'order',
        });
        final decoded = decodeEffect(encoded) as ReturnFromDiscardEffect;
        expect(decoded.filter, ReturnFilter.faction);
        expect(decoded.faction, Faction.order);
      });

      test('encode omits faction key when null', () {
        final encoded =
            encodeEffect(const ReturnFromDiscardEffect(filter: ReturnFilter.any));
        expect(encoded.containsKey('faction'), false);
      });

      test('unknown filter throws FormatException', () {
        expect(
          () => decodeEffect({'type': 'returnFromDiscard', 'filter': 'bogus'}),
          throwsFormatException,
        );
      });
    });

    group('conditionalPower new conditions', () {
      test('decodes all new power conditions', () {
        final pairs = {
          'perAllyPlayedThisTurn': PowerCondition.perAllyPlayedThisTurn,
          'perFactionPlayedThisTurn': PowerCondition.perFactionPlayedThisTurn,
          'perCardInDiscard': PowerCondition.perCardInDiscard,
        };
        pairs.forEach((raw, expected) {
          final effect = decodeEffect(
                  {'type': 'conditionalPower', 'condition': raw})
              as ConditionalPowerEffect;
          expect(effect.condition, expected);
        });
      });

      test('round-trips every power condition', () {
        for (final condition in PowerCondition.values) {
          final encoded = encodeEffect(ConditionalPowerEffect(condition));
          final decoded = decodeEffect(encoded) as ConditionalPowerEffect;
          expect(decoded.condition, condition);
        }
      });
    });
  });
}
