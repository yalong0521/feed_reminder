import 'dart:async';

import 'package:feed_reminder/services/app_haptics.dart';
import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/widgets/feed_button.dart';
import 'package:feed_reminder/widgets/milk_amount_field.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final effects = <String>[];
  var platformFails = false;

  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    AppHaptics.resetForTesting();
    effects.clear();
    platformFails = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          effects.add(call.arguments as String);
          if (platformFails) throw PlatformException(code: 'unavailable');
        }
        return null;
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    debugDefaultTargetPlatformOverride = null;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    AppHaptics.resetForTesting();
  });

  Future<void> slider(WidgetTester tester, Future<void> Function() save) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 360, child: FeedButton(onPressed: save)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> completeSlide(WidgetTester tester) async {
    await tester.drag(
      find.byKey(const ValueKey('feed-slide-thumb')),
      const Offset(320, 0),
    );
    await tester.pump();
  }

  testWidgets(
    'slide is silent until persistence completes, then confirms once',
    (tester) async {
      final save = Completer<void>();
      await slider(tester, () => save.future);
      await tester.drag(
        find.byKey(const ValueKey('feed-slide-thumb')),
        const Offset(65, 0),
      );
      await tester.pumpAndSettle();
      expect(effects, isEmpty);
      await completeSlide(tester);
      expect(effects, isEmpty);
      save.complete();
      await tester.pumpAndSettle();
      expect(effects, ['HapticFeedbackType.lightImpact']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed persistence warns without a success pulse', (
    tester,
  ) async {
    await slider(tester, () async => throw StateError('save failed'));
    await completeSlide(tester);
    await tester.pumpAndSettle();
    expect(effects, ['HapticFeedbackType.mediumImpact']);
    expect(find.text('未保存，右滑重试'), findsOneWidget);
  });

  testWidgets(
    'haptic platform failure cannot change a saved record to failure',
    (tester) async {
      platformFails = true;
      var saved = false;
      await slider(tester, () async {
        saved = true;
      });
      await completeSlide(tester);
      await tester.pumpAndSettle();
      expect(saved, isTrue);
      expect(find.text('已记录'), findsOneWidget);
      expect(find.text('未保存，右滑重试'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  Future<void> field(
    WidgetTester tester,
    TextEditingController controller, {
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: MilkAmountField(controller: controller, enabled: enabled),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'ruler ticks during direct drag, never during input sync or fling',
    (tester) async {
      final controller = TextEditingController(text: '120');
      addTearDown(controller.dispose);
      await field(tester, controller);
      controller.text = '180';
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('milk-amount-input')),
        '120',
      );
      await tester.pumpAndSettle();
      expect(effects, isEmpty);
      final ruler = find.byKey(const ValueKey('milk-amount-ruler-scroll'));
      final gesture = await tester.startGesture(tester.getCenter(ruler));
      await gesture.moveBy(const Offset(-25, 0));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 20));
      expect(effects, isNotEmpty);
      expect(effects.toSet(), {'HapticFeedbackType.selectionClick'});
      await gesture.up();
      await tester.pump();
      effects.clear();
      AppHaptics.resetForTesting();
      await tester.pumpAndSettle();
      expect(effects, isEmpty);
      expect(int.parse(controller.text), greaterThan(120));
    },
  );

  testWidgets('step buttons tick only when enabled and the value changes', (
    tester,
  ) async {
    final controller = TextEditingController(text: '0');
    addTearDown(controller.dispose);
    await field(tester, controller);
    await tester.tap(find.byKey(const ValueKey('milk-amount-decrease')));
    await tester.pump();
    expect(effects, isEmpty);
    await tester.tap(find.byKey(const ValueKey('milk-amount-increase')));
    await tester.pump();
    expect(controller.text, '10');
    expect(effects, ['HapticFeedbackType.selectionClick']);
    effects.clear();
    AppHaptics.resetForTesting();
    await field(tester, controller, enabled: false);
    await tester.drag(
      find.byKey(const ValueKey('milk-amount-ruler-scroll')),
      const Offset(-90, 0),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '10');
    expect(effects, isEmpty);
  });

  testWidgets(
    'feedback is rate limited without replay, and silent in background',
    (tester) async {
      AppHaptics.selection();
      AppHaptics.selection();
      AppHaptics.selection();
      await tester.pump();
      expect(effects, ['HapticFeedbackType.selectionClick']);
      effects.clear();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      AppHaptics.resetForTesting();
      AppHaptics.selection();
      AppHaptics.success();
      AppHaptics.warning();
      await tester.pump(const Duration(seconds: 1));
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(effects, isEmpty);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        AppHaptics.success();
        await tester.pump();
        expect(effects, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
