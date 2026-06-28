import 'package:flutter/material.dart';
import 'package:simple_card_game/services/ai_service.dart';
import 'package:simple_card_game/services/game_service.dart';
import 'package:simple_card_game/ui/screens/game_screen.dart';
import 'package:simple_card_game/ui/theme/game_theme.dart';
import 'package:simple_card_game/ui/theme/responsive.dart';

/// Game setup screen where the player picks number of players and starts the game.
class GameSetupScreen extends StatefulWidget {
  const GameSetupScreen({super.key});

  @override
  State<GameSetupScreen> createState() => _GameSetupScreenState();
}

class _GameSetupScreenState extends State<GameSetupScreen> {
  int _playerCount = 2;
  bool _vsAi = false;

  void _startGame() {
    final gameService = GameService(playerCount: _playerCount);
    AiService? aiService;
    if (_vsAi && _playerCount == 2) {
      aiService = AiService(
        game: gameService,
        aiPlayerId: 'p1',
      )..phaseDelay = const Duration(milliseconds: 300);
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameScreen(
          gameService: gameService,
          aiService: aiService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameTheme.boardBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = Responsive.isMobile(constraints.maxWidth);
            final titleSize = isMobile ? 34.0 : 42.0;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 32),
                child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Title
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [GameTheme.gold, GameTheme.accent],
              ).createShader(bounds),
              child: Text(
                'SHARDS OF\nINFINITY',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.1,
                  letterSpacing: 3,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Deck-Building Card Game',
              style: TextStyle(
                color: GameTheme.textSecondary,
                fontSize: 16,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 48),

            // Player count selector
            const Text(
              'PLAYERS',
              style: TextStyle(
                color: GameTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [2, 3, 4].map((count) {
                final isSelected = _playerCount == count;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _playerCount = count),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? GameTheme.accent
                            : GameTheme.surfaceDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? GameTheme.gold
                              : Colors.white.withValues(alpha: 0.2),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$count',
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : GameTheme.textSecondary,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // vs AI toggle (only meaningful for 2 players)
            if (_playerCount == 2)
              GestureDetector(
                onTap: () => setState(() => _vsAi = !_vsAi),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _vsAi,
                        onChanged: (v) =>
                            setState(() => _vsAi = v ?? false),
                        activeColor: GameTheme.accent,
                        checkColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'vs AI',
                      style: TextStyle(
                        color: GameTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),

            // Start button
            ElevatedButton(
              onPressed: _startGame,
              style: ElevatedButton.styleFrom(
                backgroundColor: GameTheme.endTurnGreen,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
              child: const Text(
                'START GAME',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
