// This file is ONLY loaded on web (via the conditional import in
// fullscreen.dart), so dart:html is the correct, available API here.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'fullscreen.dart';

/// Web implementation backed by the browser Fullscreen API.
Fullscreen createFullscreen() => _WebFullscreen();

class _WebFullscreen implements Fullscreen {
  @override
  bool get isSupported => true;

  /// iOS Safari (iPhone/iPad) exposes no working document Fullscreen API —
  /// `requestFullscreen` is undefined / a no-op there — so the toggle would do
  /// nothing. Detect it (including iPadOS, which reports as "Macintosh" with a
  /// touch screen) so callers can offer "Add to Home Screen" instead.
  bool get _isIos {
    final ua = html.window.navigator.userAgent;
    if (RegExp(r'iPad|iPhone|iPod').hasMatch(ua)) return true;
    // iPadOS 13+ masquerades as desktop Safari; distinguish by touch support.
    final isMacLike = ua.contains('Macintosh');
    final touch = (html.window.navigator.maxTouchPoints ?? 0) > 1;
    return isMacLike && touch;
  }

  @override
  bool get fullscreenApiWorks {
    // The only browser where the API is exposed but doesn't work is iOS Safari;
    // dart:html always types requestFullscreen as present, so gate on iOS.
    return !_isIos;
  }

  @override
  bool get isStandalone {
    // iOS Safari exposes navigator.standalone; other browsers use the
    // display-mode media query set by the manifest's "display": "standalone".
    final iosStandalone = (html.window.navigator as dynamic).standalone;
    if (iosStandalone == true) return true;
    try {
      return html.window.matchMedia('(display-mode: standalone)').matches;
    } catch (_) {
      return false;
    }
  }

  @override
  bool get shouldOfferInstall =>
      isSupported && !fullscreenApiWorks && !isStandalone;

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
