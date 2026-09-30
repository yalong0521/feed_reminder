import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Tinos',
    ], await rootBundle.loadString('assets/fonts/OFL-Tinos.txt'));
  });
  runApp(const FeedReminderApp());
}
