// This file is ONLY loaded on web (via the conditional import in
// token_storage.dart), so dart:html is the correct, available API here.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'token_storage.dart';

/// Web implementation: persists to the browser's localStorage so a remembered
/// token/name survives reloads and return visits on the same device/browser.
class _WebTokenStorage extends TokenStorage {
  @override
  String? read(String key) => html.window.localStorage[key];
  @override
  void write(String key, String value) =>
      html.window.localStorage[key] = value;
  @override
  void remove(String key) => html.window.localStorage.remove(key);
}

TokenStorage createTokenStorage() => _WebTokenStorage();
