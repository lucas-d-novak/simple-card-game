import 'package:flutter/material.dart';
import 'package:simple_card_game/services/deck_service.dart';
import 'package:simple_card_game/ui/screens/game_setup_screen.dart';
import 'package:simple_card_game/ui/screens/home_screen.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/theme/game_theme.dart';

void main() {
  runApp(const ShardsOfInfinityApp());
}

/// Root widget — launches the Shards of Infinity game UI.
class ShardsOfInfinityApp extends StatelessWidget {
  const ShardsOfInfinityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimationSettings(
      // Default to fast (snappy) for real play; tests/goldens fall back to
      // instant since they don't wrap the tree in AnimationSettings.
      initialSpeed: AnimationSpeed.fast,
      child: MaterialApp(
        title: 'Shards of Infinity',
        debugShowCheckedModeBanner: false,
        theme: GameTheme.darkTheme,
        home: const GameSetupScreen(),
      ),
    );
  }
}

/// Legacy demo app — kept for existing widget tests.
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
