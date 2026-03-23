import 'package:simple_card_game/models/card_effect.dart';

class CardModel {
  final String id;
  final String name;
  final int cost;
  final List<CardEffect> playEffects;

  const CardModel({
    required this.id,
    required this.name,
    required this.cost,
    required this.playEffects,
  });
}
