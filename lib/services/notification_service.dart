import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// One native reminder per feeding cycle. Unsupported preview platforms are safe.
class NotificationService {
  final FlutterLocalNotificationsPlugin _notifications;
  Future<void>? _initialization;

  NotificationService({FlutterLocalNotificationsPlugin? notifications})
    : _notifications = notifications ?? FlutterLocalNotificationsPlugin();

  bool get isSupported =>
      !kIsWeb &&
      const [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ].contains(defaultTargetPlatform);

  Future<void> init() => _initialization ??= _initialize().catchError((
    Object error,
    StackTrace stack,
  ) {
    // A transient platform error must not disable every later reminder.
    _initialization = null;
    Error.throwWithStackTrace(error, stack);
  });

  Future<void> _initialize() async {
    if (!isSupported) return;
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: darwin,
        macOS: darwin,
      ),
    );
  }

  Future<void> requestPermissions() async {
    if (!isSupported) return;
    await init();
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        await _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      case TargetPlatform.iOS:
        await _notifications
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      case TargetPlatform.macOS:
        await _notifications
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      default:
        break;
    }
  }

  Future<void> requestExactAlarmPermission() async {
    if (!isSupported || defaultTargetPlatform != TargetPlatform.android) return;
    await init();
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();
  }

  NotificationDetails _details(bool playSound) => NotificationDetails(
    android: AndroidNotificationDetails(
      playSound ? 'feeding_reminders_sound_v2' : 'feeding_reminders_silent_v2',
      playSound ? '喂奶声音提醒' : '喂奶静音提醒',
      channelDescription: '根据最近一次喂奶时间发送提醒',
      importance: Importance.high,
      priority: Priority.high,
      playSound: playSound,
      sound: playSound
          ? const RawResourceAndroidNotificationSound('reminder')
          : null,
      enableVibration: playSound,
      onlyAlertOnce: true,
      icon: '@drawable/ic_notification',
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: playSound,
    ),
    macOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: playSound,
    ),
  );

  Future<void> showFeedReminder({bool playSound = true}) async {
    if (!isSupported) return;
    await init();
    await _notifications.show(
      0,
      '到设定的喂奶时间了',
      '留意宝宝的状态，准备好后记下这一餐。',
      _details(playSound),
    );
  }

  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async {
    if (!isSupported) return;
    await init();
    if (!when.isAfter(DateTime.now())) return;
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final exact = await android?.canScheduleExactNotifications() ?? false;
    // UTC preserves the absolute deadline without needing a device-timezone plugin.
    Future<void> schedule(AndroidScheduleMode mode) =>
        _notifications.zonedSchedule(
          0,
          '到设定的喂奶时间了',
          '留意宝宝的状态，准备好后记下这一餐。',
          tz.TZDateTime.from(when.toUtc(), tz.UTC),
          _details(playSound),
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
    try {
      await schedule(
        exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } on PlatformException catch (error) {
      if (!exact || error.code != 'exact_alarms_not_permitted') rethrow;
      await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  Future<void> cancelAll() async {
    if (!isSupported) return;
    await init();
    await _notifications.cancelAll();
  }
}
