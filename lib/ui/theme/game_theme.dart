import 'package:flutter/material.dart';

/// Dark-themed game colors for the board, inspired by card game video games.
class GameTheme {
  GameTheme._();

  static const Color boardBackground = Color(0xFF1A1A2E);
  static const Color surfaceDark = Color(0xFF16213E);
  static const Color surfaceMid = Color(0xFF0F3460);
  static const Color accent = Color(0xFFE94560);
  static const Color gold = Color(0xFFFFD700);
  static const Color healthRed = Color(0xFFEF5350);
  static const Color healthGreen = Color(0xFF66BB6A);
  static const Color gemCyan = Color(0xFF26C6DA);
  static const Color powerOrange = Color(0xFFFF7043);
  static const Color masteryPurple = Color(0xFFAB47BC);
  static const Color textPrimary = Color(0xFFE0E0E0);
  static const Color textSecondary = Color(0xFF9E9E9E);
  static const Color cardSurface = Color(0xFF2A2A3E);
  static const Color endTurnGreen = Color(0xFF4CAF50);

  static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: boardBackground,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          secondary: gold,
          surface: surfaceDark,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: textPrimary),
          bodySmall: TextStyle(color: textSecondary),
        ),
        useMaterial3: true,
      );
}
