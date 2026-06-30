// Flutter-only asset loader for [CardDatabase]. Split out from
// `card_database.dart` so that the core database (parsing, records, lookups)
// stays PURE DART and can be reused by the authoritative multiplayer server
// (which has no Flutter / rootBundle). See ai-docs/multiplayer_architecture.md.
//
// Use this inside the running Flutter app:
//   final db = await CardDatabaseAsset.load();
// The server instead reads the file directly and calls
// CardDatabase.fromJsonString(...).

import 'package:flutter/services.dart' show rootBundle;

import 'package:simple_card_game/data/database/card_database.dart';

extension CardDatabaseAsset on CardDatabase {
  /// Load the database from the bundled Flutter asset.
  static Future<CardDatabase> load({String path = CardDatabase.assetPath}) async {
    final source = await rootBundle.loadString(path);
    return CardDatabase.fromJsonString(source);
  }
}
