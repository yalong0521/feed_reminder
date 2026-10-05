import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/home_widget_snapshot.dart';

/// Publishes an optional native projection; errors never roll back feed data.
class HomeWidgetService {
  HomeWidgetService({MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel('feed_reminder/home_widget'),
      isSupported =
          supported ?? (!kIsWeb && defaultTargetPlatform.name == 'ohos') {
    if (isSupported) _channel.setMethodCallHandler(_onNativeCall);
  }

  final MethodChannel _channel;
  final bool isSupported;
  Future<void> _updates = Future<void>.value();
  String? _lastPublished;
  String? lastError;
  ValueChanged<String>? _actionHandler;
  bool _disposed = false;

  void setActionHandler(ValueChanged<String>? handler) {
    _actionHandler = handler;
  }

  Future<void> update(HomeWidgetSnapshot snapshot) {
    if (!isSupported || _disposed) return Future<void>.value();
    final payload = snapshot.toMap();
    final comparison = Map<String, Object?>.of(payload)
      ..remove('generatedAtMs');
    final fingerprint = jsonEncode(comparison);
    // Check after earlier writes complete. Failed snapshots are never cached as
    // successful, so the same content can retry on the next provider/resume event.
    _updates = _updates.then((_) async {
      if (_disposed || _lastPublished == fingerprint) return;
      try {
        await _channel.invokeMethod<void>('updateSnapshot', payload);
        _lastPublished = fingerprint;
        lastError = null;
      } catch (error) {
        // The native call may have saved its projection before a particular
        // card refresh failed. Even the previously successful content must be
        // republished if the user now undoes that partially published change.
        _lastPublished = null;
        lastError = '桌面卡片更新失败，下次打开应用时重试。';
        debugPrint('Home widget update unavailable: ${error.runtimeType}');
      }
    });
    return _updates;
  }

  /// Consumes an in-memory launch request, once. Native code never saves a feed.
  Future<String?> consumePendingAction() async {
    if (!isSupported || _disposed) return null;
    try {
      final action = await _channel.invokeMethod<String>('getPendingAction');
      return _validAction(action) ? action : null;
    } catch (error) {
      debugPrint('Home widget launch unavailable: ${error.runtimeType}');
      return null;
    }
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (_disposed || call.method != 'widgetAction' || _actionHandler == null) {
      return;
    }
    // The notification is only a wake-up signal. The native queue is consumed
    // atomically, avoiding duplicates when startup and onNewWant overlap.
    final action = await consumePendingAction();
    if (!_disposed && action != null) _actionHandler?.call(action);
  }

  static bool _validAction(String? action) =>
      action == 'open_timer' || action == 'record_feed';

  void dispose() {
    _disposed = true;
    _actionHandler = null;
    if (isSupported) _channel.setMethodCallHandler(null);
  }
}
