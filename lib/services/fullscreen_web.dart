// This file is ONLY loaded on web (via the conditional import in
// fullscreen.dart), so dart:html is the correct, available API here.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'fullscreen.dart';

/// Web implementation backed by the browser Fullscreen API.
Fullscreen createFullscreen() => _WebFullscreen();

class _WebFullscreen implements Fullscreen {
  /// iOS Safari (iPhone/iPad) exposes no working document Fullscreen API —
  /// `requestFullscreen` is a no-op there — so the toggle would do nothing.
  /// Detect it (including iPadOS, which reports as "Macintosh" with a touch
  /// screen) so the button is hidden rather than dead.
  bool get _isIos {
    final ua = html.window.navigator.userAgent;
    if (RegExp(r'iPad|iPhone|iPod').hasMatch(ua)) return true;
    // iPadOS 13+ masquerades as desktop Safari; distinguish by touch support.
    final isMacLike = ua.contains('Macintosh');
    final touch = (html.window.navigator.maxTouchPoints ?? 0) > 1;
    return isMacLike && touch;
  }

  // The Fullscreen API works everywhere on web EXCEPT iOS Safari, so hide the
  // toggle there (nothing would happen).
  @override
  bool get isSupported => !_isIos;

  @override
  bool get isFullscreen => html.document.fullscreenElement != null;

  @override
  void enter() {
    html.document.documentElement?.requestFullscreen();
  }

  @override
  void exit() {
    html.document.exitFullscreen();
  }

  @override
  void toggle() => isFullscreen ? exit() : enter();
}
