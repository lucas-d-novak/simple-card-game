// Remembers the shared access token (and the player's name) across visits, so an
// invited player enters them ONCE. Backed by browser localStorage on web; a
// no-op on other platforms (where there's no shared-link login flow anyway).
//
// Uses a conditional import so the non-web build never references dart:html:
//   - web  → token_storage_web.dart (localStorage)
//   - else → token_storage_stub.dart (in-memory, lost on restart)
import 'token_storage_stub.dart'
    if (dart.library.html) 'token_storage_web.dart';

/// Persistent key/value for the small bits of login state we remember.
abstract class TokenStorage {
  /// The platform implementation (localStorage on web, no-op elsewhere).
  static final TokenStorage instance = createTokenStorage();

  static const _tokenKey = 'shards.accessToken';
  static const _nameKey = 'shards.playerName';

  String? read(String key);
  void write(String key, String value);
  void remove(String key);

  String? get accessToken => read(_tokenKey);
  set accessToken(String? v) =>
      (v == null || v.isEmpty) ? remove(_tokenKey) : write(_tokenKey, v);

  String? get playerName => read(_nameKey);
  set playerName(String? v) =>
      (v == null || v.isEmpty) ? remove(_nameKey) : write(_nameKey, v);

  /// Forget the remembered token (the "sign out / forget" action).
  void forgetToken() => remove(_tokenKey);
}
