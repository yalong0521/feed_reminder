import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'app.dart';
import 'services/storage_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations (landscape for tablet)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Initialize services
  final storageService = StorageService();
  await storageService.init();

  final notificationService = NotificationService();
  await notificationService.init();
  await notificationService.requestPermissions();

  // Enable wakelock if enabled
  if (await storageService.getWakelockEnabled()) {
    await WakelockPlus.enable();
  }

  runApp(const FeedReminderApp());
}
