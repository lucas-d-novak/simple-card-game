import 'token_storage.dart';

/// Non-web fallback: an in-memory map (no persistence — there's no shared-link
/// login on desktop/mobile builds anyway).
class _StubTokenStorage extends TokenStorage {
  final Map<String, String> _mem = {};
  @override
  String? read(String key) => _mem[key];
  @override
  void write(String key, String value) => _mem[key] = value;
  @override
  void remove(String key) => _mem.remove(key);
}

TokenStorage createTokenStorage() => _StubTokenStorage();
