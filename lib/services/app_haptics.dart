import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Optional, foreground-only feedback. Never participates in saving user data.
abstract final class AppHaptics {
  static const _channel = MethodChannel('feed_reminder/haptics');
  static final _clock = Stopwatch()..start();
  static int? _lastSelection;
  static int? _lastResult;

  /// A short detent when a deliberate adjustment changes a value.
  static void selection() => _play(_Haptic.selection);

  /// A single confirmation, called only after the operation succeeds.
  static void success() => _play(_Haptic.success);

  /// A slightly firmer cue accompanying a visible, actionable error.
  static void warning() => _play(_Haptic.warning);

  static void _play(_Haptic kind) {
    final platform = defaultTargetPlatform.name;
    if (kIsWeb || !const {'android', 'iOS', 'ohos'}.contains(platform)) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;

    final now = _clock.elapsedMilliseconds;
    if (kind == _Haptic.selection) {
      if (_lastSelection != null && now - _lastSelection! < 70) return;
      _lastSelection = now;
    } else {
      if (_lastResult != null && now - _lastResult! < 180) return;
      _lastResult = now;
      _lastSelection = now;
    }
    // Do not queue delayed pulses: a gesture may already be cancelled or the
    // app backgrounded by the time a delayed callback would fire.
    unawaited(_dispatch(kind, harmony: platform == 'ohos'));
  }

  static Future<void> _dispatch(_Haptic kind, {required bool harmony}) async {
    try {
      if (harmony) {
        // Flutter-OH maps selectionClick to a 100ms vibration. The native
        // channel uses short touch effects instead, respecting system policy.
        await _channel.invokeMethod<void>(kind.name);
      } else {
        switch (kind) {
          case _Haptic.selection:
            await HapticFeedback.selectionClick();
          case _Haptic.success:
            await HapticFeedback.lightImpact();
          case _Haptic.warning:
            await HapticFeedback.mediumImpact();
        }
      }
    } catch (_) {
      // Unsupported hardware, permissions or a detached engine must never
      // turn a successful record into a save error.
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _lastSelection = null;
    _lastResult = null;
  }
}

enum _Haptic { selection, success, warning }
