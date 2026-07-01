import 'fullscreen.dart';

/// Non-web platforms: fullscreen is a no-op (native apps manage their own
/// window chrome). [isSupported] is false so the UI hides the button.
Fullscreen createFullscreen() => _StubFullscreen();

class _StubFullscreen implements Fullscreen {
  @override
  bool get isSupported => false;

  @override
  bool get fullscreenApiWorks => false;

  @override
  bool get isStandalone => false;

  @override
  bool get shouldOfferInstall => false;

  @override
  bool get isFullscreen => false;

  @override
  void enter() {}

  @override
  void exit() {}

  @override
  void toggle() {}
}
