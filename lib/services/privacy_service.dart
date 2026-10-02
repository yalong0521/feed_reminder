import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// HarmonyOS manages first-launch consent and serves the published declaration.
abstract final class PrivacyService {
  static const _channel = MethodChannel('feed_reminder/privacy');

  static bool get usesHostedPolicy =>
      !kIsWeb && defaultTargetPlatform.name == 'ohos';

  static Future<void> openHostedPolicy() async {
    await _channel.invokeMethod<void>('openHostedPrivacyPolicy');
  }
}
