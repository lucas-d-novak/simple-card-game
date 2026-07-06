import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/data/database/card_serialization.dart';
import 'package:simple_card_game/data/database/game_state_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Owner-authoritative shield data + combat corrections (2026-07-01):
///  - JOB 1: static ally/champion shield values in cards.json.
///  - JOB 2: datic_robes — DYNAMIC in-hand shield = current mastery.
///  - JOB 3: praetorian_02 (champion-sourced mastery-scaled shieldBuff) +
///           praetorian_01 (mastery-replace power + on-champion-play return).
///  - JOB 4: one_mind_one_army — your Champions have +2 HEALTH (not shields).
final CardDatabase _db = CardDatabase.fromJsonString(
  File('assets/card_db/cards.json').readAsStringSync(),
);

CardModel _model(String id) => _db.byId(id)!.model;

CardModel _champ(String id, int health) => CardModel(
      id: id,
      name: id,
      cost: 0,
      playEffects: const [],
      cardType: CardType.champion,
      health: health,
    );

void main() {
  // Zetta, The Encryptor — the champion the owner flagged as having BOTH stats.
  // health (in-play toughness) and shield (in-hand reduction) are INDEPENDENT:
  // holding Zetta reduces damage by its shield; playing it out gives no in-hand
  // reduction and it needs power >= its health to destroy.
  group('Zetta — a champion with BOTH health and shield (independent)', () {
    test('the DB carries both: health 5 (toughness) and shield 5 (in-hand)', () {
      final z = _model('zetta_the_encryptor');
      expect(z.cardType, CardType.champion);
      expect(z.health, 5, reason: 'in-play toughness');
      expect(z.shield, 5, reason: 'in-hand damage reduction');
    });

    test('in HAND: Zetta reduces the player\'s incoming damage by its shield',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];
      target.hand
        ..clear()
        ..add(_model('zetta_the_encryptor'));
      attacker.powerPool = 20;
      final before = target.health;
      // 10 - 5 (Zetta's in-hand shield) = 5 lands.
      expect(game.attackPlayer('p1', 10), true);
      expect(target.health, before - 5);
    });

    test('in PLAY: Zetta needs power >= its HEALTH and gives NO in-hand reduction',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];
      // NOTE: play it out via championsInPlay directly; Zetta's own aura makes it
      // (and its owner) unattackable, so use a plain copy without that modifier
      // to isolate the health-threshold behaviour.
      target.championsInPlay.add(const CardModel(
        id: 'zetta_the_encryptor',
        name: 'Zetta, The Encryptor',
        cost: 5,
        playEffects: [],
        cardType: CardType.champion,
        health: 5,
        shield: 5,
      ));
      target.hand.clear();

      // Its shield does NOT reduce damage while in play: attack the player is
      // gated only by nothing here (no guard), full damage lands.
      attacker.powerPool = 4;
      // 4 < health 5 → cannot destroy.
      expect(game.attackChampion('zetta_the_encryptor', 'p1'), false);
      attacker.powerPool = 5;
      expect(game.attackChampion('zetta_the_encryptor', 'p1'), true,
          reason: 'power == health 5 destroys it');
      expect(target.championsInPlay, isEmpty);
    });
  });

  group('JOB 1 — static shield values (from cards.json)', () {
    const expected = {
      'dash': 2,
      'red_fortune': 2,
      'brute': 2,
      'crimson_operative': 3,
      'lucky': 2,
      'breaker': 4,
      'keeper_of_datic_vessels': 2,
      'mainframe_abbot': 3,
      'command_seer': 5,
      'querry_monk': 3,
      'cryptofist_monk': 8,
      'subversion_elders': 4,
      'zetta_the_encryptor': 5,
      'thorn_zealot': 3,
      'concussio_and_mirus': 2,
      'korvus_legionnaire': 2,
      'torian_commandos': 4,
      'synthetica_artifex': 2,
    };
    expected.forEach((id, shield) {
      test('$id has shield $shield', () {
        expect(_model(id).shield, shield);
      });
    });

    test('a hand full of these shields sums into player damage reduction', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];
      target.hand
        ..clear()
        ..addAll([_model('brute'), _model('command_seer')]); // 2 + 5 = 7
      attacker.powerPool = 30;
      final before = target.health;
      expect(game.attackPlayer('p1', 10), true);
      expect(target.health, before - 3, reason: '10 - (2+5) = 3');
    });
  });

  group('JOB 2 — datic_robes dynamic shield = current mastery', () {
    test('flag decodes from JSON', () {
      expect(_model('datic_robes').shieldEqualsMastery, true);
      // Static shield stays 0 — the dynamic path supplies the value.
      expect(_model('datic_robes').shield, 0);
    });

    test('mastery 7 → +7 reduction from datic_robes in hand', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];
      target.hand
        ..clear()
        ..add(_model('datic_robes'));
      target.mastery = 7;
      attacker.powerPool = 30;
      final before = target.health;
      // 10 - 7 (= mastery) = 3 lands.
      expect(game.attackPlayer('p1', 10), true);
      expect(target.health, before - 3);
    });

    test('reduction tracks mastery: 0 → full damage, then scales up', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];
      target.hand
        ..clear()
        ..add(_model('datic_robes'));
      attacker.powerPool = 60;

      target.mastery = 0;
      var before = target.health;
      expect(game.attackPlayer('p1', 6), true);
      expect(target.health, before - 6, reason: 'mastery 0 → shield 0');

      target.mastery = 4;
      before = target.health;
      expect(game.attackPlayer('p1', 6), true);
      expect(target.health, before - 2, reason: 'mastery 4 → shield 4');
    });

    test('a played-OUT (not-in-hand) datic_robes gives no reduction', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final attacker = game.currentPlayer;
      final target = game.players[1];
      target.mastery = 9;
      // discard, not hand → no contribution.
      target.discardPile.add(_model('datic_robes'));
      attacker.powerPool = 30;
      final before = target.health;
      expect(game.attackPlayer('p1', 8), true);
      expect(target.health, before - 8);
    });

    test('flag round-trips through card serialization', () {
      final restored = cardModelFromJson(cardModelToJson(_model('datic_robes')));
      expect(restored.shieldEqualsMastery, true);
    });
  });

  group('JOB 3a — praetorian_02 mastery-scaled champion shieldBuff', () {
    test('playEffects decode to a mastery-scaled shieldBuff (4 / 8 @ M20)', () {
      final effect = _model('praetorian_02').playEffects.single;
      expect(effect, isA<AddStaticModifierEffect>());
      final m = (effect as AddStaticModifierEffect).modifier;
      expect(m.kind, StaticModifierKind.shieldBuff);
      expect(m.amount, 4);
      expect(m.masteryThreshold, 20);
      expect(m.masteryAmount, 8);
      expect(m.amountFor(5), 4);
      expect(m.amountFor(20), 8);
      // The old wrong gainPower encoding is gone; it stays a champion.
      expect(_model('praetorian_02').cardType, CardType.champion);
      expect(_model('praetorian_02').masteryBonus, isEmpty);
    });

    test('grants YOU 4 shield while in play (8 at mastery >= 20)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final owner = game.currentPlayer; // p0
      owner.hand
        ..clear()
        ..add(_model('praetorian_02'));
      owner.mastery = 5;
      expect(game.playCard('praetorian_02'), true);

      // A single champion-sourced shieldBuff modifier was added.
      final buffs = owner.staticModifiers
          .where((m) => m.kind == StaticModifierKind.shieldBuff)
          .toList();
      expect(buffs, hasLength(1));
      expect(buffs.single.sourceChampionId, 'praetorian_02');
      expect(owner.championsInPlay.any((c) => c.id == 'praetorian_02'), true);

      // Re-activating the champion must NOT stack a duplicate buff.
      game.activateChampion('praetorian_02');
      expect(
        owner.staticModifiers
            .where((m) => m.kind == StaticModifierKind.shieldBuff)
            .length,
        1,
      );

      // p1 attacks p0.
      game.endTurn();
      owner.hand.clear(); // drop any drawn shields for a clean measurement
      final atk = game.currentPlayer; // p1
      atk.powerPool = 40;

      var before = owner.health;
      expect(game.attackPlayer('p0', 10), true);
      expect(owner.health, before - 6, reason: 'mastery 5 → 4 shield → 10-4=6');

      // Bump owner mastery to 20: the SAME modifier now contributes 8 (dynamic).
      owner.mastery = 20;
      before = owner.health;
      expect(game.attackPlayer('p0', 10), true);
      expect(owner.health, before - 2, reason: 'mastery 20 → 8 shield → 10-8=2');
    });

    test('the shieldBuff disappears when the champion leaves play', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final owner = game.currentPlayer;
      owner.hand
        ..clear()
        ..add(_model('praetorian_02'));
      owner.mastery = 5;
      game.playCard('praetorian_02');
      game.endTurn();

      final atk = game.currentPlayer;
      atk.powerPool = 40;
      // Destroy praetorian_02 (its HEALTH is 9).
      expect(game.attackChampion('praetorian_02', 'p0'), true);

      owner.hand.clear();
      final before = owner.health;
      expect(game.attackPlayer('p0', 10), true);
      expect(owner.health, before - 10,
          reason: 'buff released with the champion → no reduction');
    });

    test('modifier round-trips through the full game-state codec', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final owner = game.currentPlayer;
      owner.hand
        ..clear()
        ..add(_model('praetorian_02'));
      owner.mastery = 22;
      game.playCard('praetorian_02');

      final restored = GameStateCodec.decode(GameStateCodec.encode(game));
      final rOwner = restored.currentPlayer;
      final m = rOwner.staticModifiers
          .firstWhere((m) => m.kind == StaticModifierKind.shieldBuff);
      expect(m.amount, 4);
      expect(m.masteryThreshold, 20);
      expect(m.masteryAmount, 8);
      expect(m.amountFor(22), 8);
    });
  });

  group('JOB 3b — praetorian_01 mastery-replace power + return trigger', () {
    test('playEffects: gainPower 8 + return-on-champion-play marker', () {
      final card = _model('praetorian_01');
      expect(card.playEffects.whereType<GainPowerEffect>().single.amount, 8);
      expect(
        card.playEffects.whereType<ReturnSelfWhenChampionPlayedEffect>(),
        hasLength(1),
      );
      // Mastery-20 replace → 12 power.
      expect(card.masteryReplaces, true);
      expect(card.masteryThreshold, 20);
      expect(card.masteryBonus.whereType<GainPowerEffect>().single.amount, 12);
    });

    test('gains 8 power on play (12 at mastery >= 20)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.hand
        ..clear()
        ..add(_model('praetorian_01'));
      final before = me.powerPool;
      game.playCard('praetorian_01');
      expect(me.powerPool, before + 8);

      final game2 = GameService(playerCount: 2, random: Random(7));
      final me2 = game2.currentPlayer;
      me2.mastery = 20;
      me2.hand
        ..clear()
        ..add(_model('praetorian_01'));
      final before2 = me2.powerPool;
      game2.playCard('praetorian_01');
      expect(me2.powerPool, before2 + 12);
    });

    test('playing a Champion returns praetorian_01 from discard to hand', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.discardPile.add(_model('praetorian_01'));
      me.hand
        ..clear()
        ..add(_champ('my_champ', 3));

      expect(game.playCard('my_champ'), true);
      expect(me.championsInPlay.any((c) => c.id == 'my_champ'), true);
      expect(me.hand.any((c) => c.id == 'praetorian_01'), true);
      expect(me.discardPile.any((c) => c.id == 'praetorian_01'), false);
    });

    test('the trigger only fires on CHAMPION plays, not regular cards', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.discardPile.add(_model('praetorian_01'));
      me.hand
        ..clear()
        ..add(const CardModel(
          id: 'reg',
          name: 'reg',
          cost: 0,
          playEffects: [GainGemsEffect(1)],
        ));
      game.playCard('reg');
      expect(me.hand.any((c) => c.id == 'praetorian_01'), false,
          reason: 'a regular card does not trigger the return');
      expect(me.discardPile.any((c) => c.id == 'praetorian_01'), true);
    });

    test('works at mastery 20 (marker is passive, survives replace)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final me = game.currentPlayer;
      me.mastery = 20;
      me.discardPile.add(_model('praetorian_01'));
      me.hand
        ..clear()
        ..add(_champ('my_champ', 3));
      game.playCard('my_champ');
      expect(me.hand.any((c) => c.id == 'praetorian_01'), true);
    });
  });

  group('JOB 4 — one_mind_one_army gives Champions +2 HEALTH', () {
    test('re-encoded to a champion healthBuff (not shieldBuff)', () {
      final effect = _model('one_mind_one_army').playEffects.single;
      final m = (effect as AddStaticModifierEffect).modifier;
      expect(m.kind, StaticModifierKind.healthBuff);
      expect(m.amount, 2);
      expect(m.cardType, CardType.champion);
    });

    test('your champion needs power >= health+2 to be destroyed', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final owner = game.currentPlayer; // p0
      owner.championsInPlay.add(_champ('bulwark', 5)); // base health 5
      owner.hand
        ..clear()
        ..add(_model('one_mind_one_army'));
      expect(game.playCard('one_mind_one_army'), true);

      game.endTurn();
      final atk = game.currentPlayer; // p1

      // Effective health = 5 + 2 = 7.
      atk.powerPool = 6;
      expect(game.attackChampion('bulwark', 'p0'), false);
      expect(owner.championsInPlay, hasLength(1));

      atk.powerPool = 7;
      expect(game.attackChampion('bulwark', 'p0'), true);
      expect(owner.championsInPlay, isEmpty);
    });

    test('healthBuff does NOT reduce the owner player damage', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final owner = game.currentPlayer;
      owner.championsInPlay.add(_champ('bulwark', 5));
      owner.hand
        ..clear()
        ..add(_model('one_mind_one_army'));
      game.playCard('one_mind_one_army');
      game.endTurn();
      owner.hand.clear();

      final atk = game.currentPlayer;
      atk.powerPool = 30;
      final before = owner.health;
      expect(game.attackPlayer('p0', 8), true);
      expect(owner.health, before - 8,
          reason: 'healthBuff is not player damage reduction');
    });

    test('healthBuff round-trips through the game-state codec', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final owner = game.currentPlayer;
      owner.hand
        ..clear()
        ..add(_model('one_mind_one_army'));
      game.playCard('one_mind_one_army');
      final restored = GameStateCodec.decode(GameStateCodec.encode(game));
      final m = restored.currentPlayer.staticModifiers
          .firstWhere((m) => m.kind == StaticModifierKind.healthBuff);
      expect(m.amount, 2);
      expect(m.cardType, CardType.champion);
    });
  });
}
