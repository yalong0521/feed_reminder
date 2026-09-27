import 'package:flutter/material.dart';
import 'app.dart';
import 'widgets/app_glass.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppGlass.initialize();
  runApp(const FeedReminderApp());
}
