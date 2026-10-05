import 'package:feed_reminder/services/app_haptics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final harmony = TargetPlatform.values.where((value) => value.name == 'ohos');
  testWidgets(
    'Harmony uses the short touch channel and isolates channel errors',
    (tester) async {
      final calls = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      const channel = MethodChannel('feed_reminder/haptics');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'warning') {
          throw PlatformException(code: 'unavailable');
        }
        return null;
      });
      debugDefaultTargetPlatformOverride = harmony.single;
      try {
        for (final action in [
          AppHaptics.selection,
          AppHaptics.success,
          AppHaptics.warning,
        ]) {
          AppHaptics.resetForTesting();
          action();
          await tester.pump();
        }
        expect(calls, ['selection', 'success', 'warning']);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(channel, null);
        AppHaptics.resetForTesting();
      }
    },
    skip: harmony.isEmpty,
  );
}
