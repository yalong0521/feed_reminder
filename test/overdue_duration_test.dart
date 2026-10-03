import 'package:feed_reminder/widgets/overdue_duration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _durationKey = ValueKey('overdue-test-duration');
const _neighborKey = ValueKey('overdue-test-neighbor');
const _duration = Duration(hours: 9, minutes: 21, seconds: 20);

Widget _host({
  bool pulse = true,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
  bool tickerEnabled = true,
  Duration duration = _duration,
  TextScaler textScaler = TextScaler.noScaling,
  GlobalKey<NavigatorState>? navigatorKey,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  home: MediaQuery(
    data: MediaQueryData(
      disableAnimations: disableAnimations,
      accessibleNavigation: accessibleNavigation,
      textScaler: textScaler,
    ),
    child: TickerMode(
      enabled: tickerEnabled,
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OverdueDuration(
                key: _durationKey,
                duration: duration,
                color: Colors.red,
                fontSize: 80,
                unitFontSize: 24,
                pulse: pulse,
              ),
              const SizedBox(height: 24),
              const Text('记录喂奶', key: _neighborKey),
            ],
          ),
        ),
      ),
    ),
  ),
);

Finder _insideDuration(Type type, {bool skipOffstage = true}) =>
    find.descendant(
      of: find.byKey(_durationKey, skipOffstage: skipOffstage),
      matching: find.byType(type, skipOffstage: skipOffstage),
      skipOffstage: skipOffstage,
    );

({double opacity, double scale}) _phase(
  WidgetTester tester, {
  bool skipOffstage = true,
}) => (
  opacity: tester
      .widget<FadeTransition>(
        _insideDuration(FadeTransition, skipOffstage: skipOffstage),
      )
      .opacity
      .value,
  scale: tester
      .widget<ScaleTransition>(
        _insideDuration(ScaleTransition, skipOffstage: skipOffstage),
      )
      .scale
      .value,
);

void _expectStatic(WidgetTester tester, {bool skipOffstage = true}) {
  final phase = _phase(tester, skipOffstage: skipOffstage);
  expect(phase.opacity, 1);
  expect(phase.scale, 1);
}

void main() {
  testWidgets('overdue pulse breathes in sync without moving nearby content', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    _expectStatic(tester);
    final bounds = tester.getRect(find.byKey(_durationKey));
    final prefixBounds = tester.getRect(find.text('超时'));
    final unitBounds = tester.getRect(find.text('分钟'));
    final unitStyle = tester.widget<Text>(find.text('分钟')).style!;
    final neighborBounds = tester.getRect(find.byKey(_neighborKey));

    void expectStaticLabels() {
      expect(tester.getRect(find.byKey(_durationKey)), bounds);
      expect(tester.getRect(find.text('超时')), prefixBounds);
      expect(
        tester.getRect(find.text('561')).center.dx,
        closeTo(bounds.center.dx, .001),
      );
      expect(tester.getRect(find.text('分钟')), unitBounds);
      final currentUnitStyle = tester.widget<Text>(find.text('分钟')).style!;
      expect(currentUnitStyle.color, unitStyle.color);
      expect(currentUnitStyle.fontSize, unitStyle.fontSize);
      expect(tester.getRect(find.byKey(_neighborKey)), neighborBounds);
    }

    for (final elapsed in [300, 300, 600, 600, 600]) {
      await tester.pump(Duration(milliseconds: elapsed));
      final phase = _phase(tester);
      expect(phase.opacity, inInclusiveRange(.72, 1));
      expect(phase.scale, inInclusiveRange(.96, 1));
      // Both effects share the same phase, rather than drifting independently.
      expect(
        (1 - phase.opacity) / .28,
        closeTo((1 - phase.scale) / .04, .00001),
      );
      expectStaticLabels();
    }
    _expectStatic(tester);

    await tester.pump(const Duration(milliseconds: 600));
    final midpoint = _phase(tester);
    expect(midpoint.opacity, closeTo(.86, .0001));
    expect(midpoint.scale, closeTo(.98, .0001));
    expectStaticLabels();
    await tester.pump(const Duration(milliseconds: 600));
    final minimum = _phase(tester);
    expect(minimum.opacity, closeTo(.72, .0001));
    expect(minimum.scale, closeTo(.96, .0001));
    expectStaticLabels();

    final fading = _insideDuration(FadeTransition);
    expect(
      find.descendant(of: fading, matching: find.text('超时')),
      findsNothing,
    );
    expect(
      find.descendant(of: fading, matching: find.text('561')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: fading, matching: find.text('分钟')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: _insideDuration(ScaleTransition),
        matching: find.text('分钟'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'time semantics stay readable during motion without announcements',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_host());
        for (final elapsed in [0, 600, 600, 600]) {
          await tester.pump(Duration(milliseconds: elapsed));
          final label = find.bySemanticsLabel('超时 09:21:20');
          expect(label, findsOneWidget);
          final data = tester.getSemantics(label).getSemanticsData();
          expect(data.label, '超时 09:21:20');
          expect(data.flagsCollection.isLiveRegion, isFalse);
          expect(find.bySemanticsLabel('561'), findsNothing);
          expect(find.bySemanticsLabel('分钟'), findsNothing);
        }
        final oldPhase = _phase(tester);
        await tester.pumpWidget(
          _host(duration: _duration + const Duration(seconds: 1)),
        );
        expect(find.bySemanticsLabel('超时 09:21:21'), findsOneWidget);
        expect(_phase(tester), oldPhase);
        await tester.pumpWidget(_host(duration: const Duration(seconds: -1)));
        expect(find.text('0'), findsOneWidget);
        expect(find.bySemanticsLabel('超时 00:00:00'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('short and long minute counts stay centered with scaled text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final textScale in [1.0, 1.8]) {
      for (final minutes in [0, 15, 561, 1353, 11519]) {
        await tester.pumpWidget(
          _host(
            duration: Duration(minutes: minutes),
            textScaler: TextScaler.linear(textScale),
          ),
        );
        expect(find.text('超时'), findsOneWidget);
        expect(find.text('已超时'), findsNothing);
        final rowBounds = tester.getRect(find.byKey(_durationKey));
        final prefixBounds = tester.getRect(find.text('超时'));
        final unitBounds = tester.getRect(find.text('分钟'));
        for (final elapsed in [0, 300, 900, 1200]) {
          await tester.pump(Duration(milliseconds: elapsed));
          final numeralBounds = tester.getRect(find.text('$minutes'));
          expect(numeralBounds.center.dx, closeTo(rowBounds.center.dx, .001));
          expect(tester.getRect(find.byKey(_durationKey)), rowBounds);
          expect(tester.getRect(find.text('超时')), prefixBounds);
          expect(tester.getRect(find.text('分钟')), unitBounds);
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  for (final accessibleNavigation in [false, true]) {
    testWidgets(
      '${accessibleNavigation ? 'accessible navigation' : 'reduced motion'} stops and resets the pulse',
      (tester) async {
        await tester.pumpWidget(_host());
        await tester.pump(const Duration(milliseconds: 600));
        expect(_phase(tester).opacity, lessThan(1));

        await tester.pumpWidget(
          _host(
            disableAnimations: !accessibleNavigation,
            accessibleNavigation: accessibleNavigation,
          ),
        );
        _expectStatic(tester);
        await tester.pump(const Duration(seconds: 3));
        _expectStatic(tester);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);

        await tester.pumpWidget(_host());
        _expectStatic(tester);
        await tester.pump(const Duration(milliseconds: 600));
        expect(_phase(tester).opacity, closeTo(.86, .0001));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('turning emphasis off keeps the time fully visible and idle', (
    tester,
  ) async {
    await tester.pumpWidget(_host(pulse: false));
    _expectStatic(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 600));
    expect(_phase(tester).opacity, lessThan(1));
    await tester.pumpWidget(_host(pulse: false));
    _expectStatic(tester);
    await tester.pump(const Duration(seconds: 3));
    _expectStatic(tester);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 600));
    expect(_phase(tester).opacity, closeTo(.86, .0001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive ticker mode resets and resumes from full visibility', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 600));
    expect(_phase(tester).opacity, lessThan(1));

    await tester.pumpWidget(_host(tickerEnabled: false));
    _expectStatic(tester);
    await tester.pump(const Duration(seconds: 3));
    _expectStatic(tester);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(_host());
    _expectStatic(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(_phase(tester).opacity, closeTo(.86, .0001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dialog pauses the underlying time and dismissal resumes it', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_host(navigatorKey: navigator));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_phase(tester).opacity, lessThan(1));

    navigator.currentState!.push<void>(
      RawDialogRoute<void>(
        barrierDismissible: false,
        transitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            const Center(child: Text('补记喂奶')),
      ),
    );
    await tester.pump();
    _expectStatic(tester, skipOffstage: false);
    await tester.pump(const Duration(seconds: 3));
    _expectStatic(tester, skipOffstage: false);
    expect(tester.binding.transientCallbackCount, 0);

    navigator.currentState!.pop();
    await tester.pump();
    _expectStatic(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(_phase(tester).opacity, closeTo(.86, .0001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing an animating time disposes its ticker', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
