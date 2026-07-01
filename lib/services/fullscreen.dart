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

  /// Whether fullscreen is available on this platform (true only on web).
  bool get isSupported;

  /// Whether the document is currently fullscreen.
  bool get isFullscreen;

  /// Enter fullscreen (request on the document element).
  void enter();

  /// Exit fullscreen.
  void exit();

  /// Toggle: exit if currently fullscreen, else enter.
  void toggle() => isFullscreen ? exit() : enter();
}
