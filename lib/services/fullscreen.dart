// Toggle browser fullscreen for the web client (a big win on phones/tablets in
// landscape). Uses a conditional import so the non-web build never references
// dart:html:
//   - web  → fullscreen_web.dart (Fullscreen API)
//   - else → fullscreen_stub.dart (no-op; native apps have their own chrome)
import 'fullscreen_stub.dart' if (dart.library.html) 'fullscreen_web.dart';

/// Platform fullscreen control. On web it drives the browser Fullscreen API; on
/// other platforms it is a no-op (and [isSupported] is false, so callers can
/// hide the button).
abstract class Fullscreen {
  static final Fullscreen instance = createFullscreen();

  /// Whether ANY fullscreen affordance should be shown at all (true only on
  /// web). Native apps manage their own chrome; already-installed PWAs are
  /// already chrome-free (see [isStandalone]).
  bool get isSupported;

  /// Whether the browser Fullscreen API actually WORKS here. iOS Safari exposes
  /// no working document-fullscreen (calling `requestFullscreen` is a no-op), so
  /// this is false there — callers should offer "Add to Home Screen" instead of
  /// a dead toggle. True on desktop browsers and Android Chrome.
  bool get fullscreenApiWorks;

  /// Whether the app is already running as an installed standalone PWA (added to
  /// the home screen / installed). When true it is ALREADY fullscreen with no
  /// browser chrome, so no button is needed.
  bool get isStandalone;

  /// Whether we should offer install instructions ("Add to Home Screen") instead
  /// of a Fullscreen toggle — i.e. the API doesn't work here and we aren't
  /// already standalone (the iOS-Safari-in-a-browser-tab case).
  bool get shouldOfferInstall => isSupported && !fullscreenApiWorks && !isStandalone;

  /// Whether the document is currently fullscreen.
  bool get isFullscreen;

  /// Enter fullscreen (request on the document element).
  void enter();

  /// Exit fullscreen.
  void exit();

  /// Toggle: exit if currently fullscreen, else enter.
  void toggle() => isFullscreen ? exit() : enter();
}
