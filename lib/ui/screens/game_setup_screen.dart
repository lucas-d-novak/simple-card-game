import 'package:flutter/material.dart';
import 'package:simple_card_game/data/database/card_database_asset.dart';
import 'package:simple_card_game/data/market_deck.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/services/ai_service.dart';
import 'package:simple_card_game/services/game_service.dart';
import 'package:simple_card_game/ui/screens/about_screen.dart';
import 'package:simple_card_game/ui/screens/game_screen.dart';
import 'package:simple_card_game/ui/screens/network_lobby_screen.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
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

  /// Authoritative market deck (real cards + per-card copy counts), loaded from
  /// the card database. Null until loaded; a started game falls back to the
  /// legacy hardcoded catalog if loading fails.
  List<MarketCard>? _marketDeck;

  /// The Destiny supply (Into the Horizon) — a SEPARATE deck from the market,
  /// dealt into the shared face-up Destiny row. Null until loaded.
  List<CardModel>? _destinySupply;

  @override
  void initState() {
    super.initState();
    CardDatabaseAsset.load().then((db) {
      if (mounted) {
        setState(() {
          _marketDeck = buildMarketDeckFromDatabase(db);
          _destinySupply = buildDestinySupplyFromDatabase(db);
        });
      }
    }).catchError((_) {/* fall back to legacy market, no destinies */});
  }

  /// Per-player Character selection (null = "None"). Index = player index;
  /// length always 4 (max players) so it survives player-count changes — only
  /// the first [_playerCount] entries are used when starting a game.
  final List<Character?> _characters = List<Character?>.filled(4, null);

  /// Human-readable label for a Character choice in the picker.
  static String _characterLabel(Character? c) {
    switch (c) {
      case null:
        return 'None';
      case Character.decima:
        return 'Decima';
      case Character.tetra:
        return 'Tetra';
      case Character.volos:
        return 'Volos';
      case Character.rez:
        return 'Rez';
      case Character.koSynWu:
        return 'Ko Syn Wu';
      case Character.chroma:
        return 'Chroma';
    }
  }

  void _startGame() {
    final gameService = GameService(
      playerCount: _playerCount,
      characters: _characters.take(_playerCount).toList(),
      marketDeck: _marketDeck,
      destinySupply: _destinySupply,
    );
    AiService? aiService;
    if (_vsAi && _playerCount == 2) {
      // Pace the AI using the global animation speed (instant under reduced
      // motion / tests, so the AI plays through with no artificial delay).
      final phaseDelay = AnimationTiming.of(context).phaseDelay;
      aiService = AiService(
        game: gameService,
        aiPlayerId: 'p1',
      )..phaseDelay = phaseDelay;
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
                      duration: AnimationTiming.of(context).hoverScale,
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

            // Character selector (one dropdown per player; "None" allowed)
            const Text(
              'CHARACTERS',
              style: TextStyle(
                color: GameTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < _playerCount; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        _vsAi && i == 1 ? 'Player ${i + 1} (AI)'
                            : 'Player ${i + 1}',
                        style: const TextStyle(
                          color: GameTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: GameTheme.surfaceDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: DropdownButton<Character?>(
                        key: ValueKey('characterPicker_$i'),
                        value: _characters[i],
                        dropdownColor: GameTheme.surfaceDark,
                        underline: const SizedBox.shrink(),
                        iconEnabledColor: GameTheme.gold,
                        style: const TextStyle(
                          color: GameTheme.textPrimary,
                          fontSize: 14,
                        ),
                        items: <Character?>[null, ...Character.values]
                            .map((c) => DropdownMenuItem<Character?>(
                                  value: c,
                                  child: Text(_characterLabel(c)),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _characters[i] = value),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),

            // Animation speed selector
            const Text(
              'ANIMATION SPEED',
              style: TextStyle(
                color: GameTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            const _SpeedSelector(),

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

            const SizedBox(height: 16),

            // Live online lobby (real multiplayer over the authoritative server).
            OutlinedButton.icon(
              key: const ValueKey('onlineButton'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NetworkLobbyScreen(),
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: GameTheme.accent,
                side: const BorderSide(color: GameTheme.accent),
                padding:
                    const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.public, size: 20),
              label: const Text(
                'ONLINE',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // About — fan-made / non-commercial / own-the-physical-game notice.
            TextButton.icon(
              key: const ValueKey('aboutButton'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              ),
              style: TextButton.styleFrom(
                foregroundColor: GameTheme.textSecondary,
              ),
              icon: const Icon(Icons.favorite_border, size: 16),
              label: const Text(
                'ABOUT',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
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

/// 3-way toggle for the global [AnimationSpeed], backed by [AnimationSettings].
class _SpeedSelector extends StatelessWidget {
  const _SpeedSelector();

  static const _labels = {
    AnimationSpeed.slow: 'SLOW',
    AnimationSpeed.fast: 'FAST',
    AnimationSpeed.instant: 'INSTANT',
  };

  @override
  Widget build(BuildContext context) {
    final controller = AnimationSettings.maybeOf(context);
    // If there is no AnimationSettings in the tree (shouldn't happen in the
    // real app), hide the control rather than crash.
    if (controller == null) return const SizedBox.shrink();
    final current = controller.speed;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: AnimationSpeed.values.map((speed) {
        final isSelected = speed == current;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GestureDetector(
            onTap: () => controller.setSpeed(speed),
            child: AnimatedContainer(
              duration: AnimationTiming.of(context).hoverScale,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color:
                    isSelected ? GameTheme.accent : GameTheme.surfaceDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? GameTheme.gold
                      : Colors.white.withValues(alpha: 0.2),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Text(
                _labels[speed]!,
                style: TextStyle(
                  color:
                      isSelected ? Colors.white : GameTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
