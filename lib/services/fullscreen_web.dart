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
