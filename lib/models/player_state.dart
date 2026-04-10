import 'package:simple_card_game/services/deck_service.dart';

class PlayerState {
  PlayerState({required this.id, required this.name, required this.deckService});

  final String id;
  final String name;
  final DeckService deckService;
}
