import 'package:flutter/services.dart';

/// The current screen's notch/safe-area geometry, queried live per §02 —
/// never hardcoded, since every MacBook size (and any non-notched display)
/// measures differently, and re-pushed by native whenever the display
/// configuration changes (external monitor connected/disconnected, etc.).
class NotchGeometry {
  const NotchGeometry({
    required this.screenWidth,
    required this.screenHeight,
    required this.safeAreaTop,
    required this.menuBarHeight,
    required this.backingScaleFactor,
  });

  factory NotchGeometry._fromMap(Map<String, Object?> map) {
    return NotchGeometry(
      screenWidth: (map['screenWidth'] as num).toDouble(),
      screenHeight: (map['screenHeight'] as num).toDouble(),
      safeAreaTop: (map['safeAreaTop'] as num).toDouble(),
      menuBarHeight: (map['menuBarHeight'] as num).toDouble(),
      backingScaleFactor: (map['backingScaleFactor'] as num).toDouble(),
    );
  }

  final double screenWidth;
  final double screenHeight;
  final double safeAreaTop;

  /// Only meaningful when [hasNotch] is false — the reserved strip at the
  /// very top of the screen the real menu bar occupies there.
  final double menuBarHeight;
  final double backingScaleFactor;

  bool get hasNotch => safeAreaTop > 0;

  /// The distance from the top of the screen to whatever the pill anchors
  /// under — the notch's safe area if there is one, the menu bar otherwise.
  /// Same rule either way (§07): no special case per display type.
  double get topInset => hasNotch ? safeAreaTop : menuBarHeight;
}

/// The one native bridge for the Island shell itself (§01): frame, focus,
/// and live screen geometry — the things AppKit gives Flutter no access to
/// on its own. No activity data ever crosses this channel — only where the
/// pill is, whether it's allowed to take keyboard focus, and what the
/// current display looks like.
class IslandWindowChannel {
  IslandWindowChannel._();

  static const MethodChannel _channel = MethodChannel('islandia/window');

  static VoidCallback? _outsideClickHandler;
  static ValueChanged<NotchGeometry>? _screenChangeHandler;
  static bool _dispatcherInstalled = false;

  static void _ensureDispatcherInstalled() {
    if (_dispatcherInstalled) return;
    _dispatcherInstalled = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'outsideClick':
          _outsideClickHandler?.call();
        case 'screenParametersChanged':
          final map = (call.arguments as Map).cast<String, Object?>();
          _screenChangeHandler?.call(NotchGeometry._fromMap(map));
      }
    });
  }

  static Future<NotchGeometry> notchGeometry() async {
    final map = await _channel.invokeMapMethod<String, Object?>('notchGeometry');
    return NotchGeometry._fromMap(map!);
  }

  /// The window frame IS the pill — animating it natively (rather than a
  /// second Dart-side AnimatedContainer with its own duration/curve) is what
  /// keeps chrome and content moving as one surface. `duration == Duration.zero`
  /// snaps instantly.
  static Future<void> animateToFrame({
    required double x,
    required double y,
    required double width,
    required double height,
    required Duration duration,
  }) {
    return _channel.invokeMethod('animateToFrame', {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'durationMs': duration.inMilliseconds.toDouble(),
    });
  }

  /// Only true while a fake activity genuinely needs keyboard input.
  /// Everything else stays non-key so clicking the pill never steals focus
  /// from whatever app the user was in.
  static Future<void> setInteractive(bool interactive) {
    return _channel.invokeMethod('setInteractive', interactive);
  }

  /// Fires when the user clicks anywhere outside this window. Since the
  /// window frame IS the pill, that's any click elsewhere on the screen —
  /// native watches for it via an `NSEvent` global monitor. Pass `null` to
  /// stop listening.
  static void setOutsideClickHandler(VoidCallback? handler) {
    _ensureDispatcherInstalled();
    _outsideClickHandler = handler;
  }

  /// Fires whenever native detects a display configuration change (external
  /// monitor connected/disconnected, resolution change, …) with the new
  /// screen's geometry already in hand. Pass `null` to stop listening.
  static void setScreenChangeHandler(ValueChanged<NotchGeometry>? handler) {
    _ensureDispatcherInstalled();
    _screenChangeHandler = handler;
  }
}
