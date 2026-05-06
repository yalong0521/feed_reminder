import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // macOS settings for desktop platforms
    const macOSSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    InitializationSettings initSettings;
    if (Platform.isIOS) {
      initSettings = const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
    } else if (Platform.isMacOS) {
      initSettings = const InitializationSettings(
        android: androidSettings,
        macOS: macOSSettings,
      );
    } else {
      initSettings = const InitializationSettings(
        android: androidSettings,
      );
    }

    await _notifications.initialize(initSettings);
    _initialized = true;
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final android = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      final ios = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    } else if (Platform.isMacOS) {
      final macOS = _notifications.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      await macOS?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  Future<void> showFeedReminder() async {
    const androidDetails = AndroidNotificationDetails(
      'feed_reminder',
      '喂奶提醒',
      channelDescription: '喂奶时间提醒',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const macOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    NotificationDetails details;
    if (Platform.isIOS) {
      details = const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
    } else if (Platform.isMacOS) {
      details = const NotificationDetails(
        android: androidDetails,
        macOS: macOSDetails,
      );
    } else {
      details = const NotificationDetails(android: androidDetails);
    }

    await _notifications.show(
      0,
      '喂奶时间到了！',
      '宝宝该喂奶了 🍼',
      details,
    );
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}
