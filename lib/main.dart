import 'package:flutter/material.dart';
import 'package:simple_card_game/services/deck_service.dart';
import 'package:simple_card_game/ui/screens/home_screen.dart';

void main() {
  runApp(const DeckDrawApp());
}

/// Root widget for the deck drawing demo.
class DeckDrawApp extends StatelessWidget {
  const DeckDrawApp({super.key, this.deckService});

  final DeckService? deckService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deck Draw Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        splashFactory: InkRipple.splashFactory,
        useMaterial3: true,
      ),
      home: HomeScreen(deckService: deckService ?? DeckService()),
    );
  }
}
