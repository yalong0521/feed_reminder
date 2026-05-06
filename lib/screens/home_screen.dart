import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../services/audio_service.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';
import '../widgets/countdown_ring.dart';
import '../widgets/feed_button.dart';
import '../widgets/time_display.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late ConfettiController _confettiController;
  OverlayEntry? _dimOverlayEntry;

  bool _isDimmed = false;
  DateTime _lastInteraction = DateTime.now();
  static const _dimTimeout = Duration(seconds: 30);
  int _burnInOffsetIndex = 0;
  final List<Offset> _burnInOffsets = [];

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 1),
    );
    _generateBurnInOffsets();
    _startDimTimer();
  }

  void _generateBurnInOffsets() {
    // First position is center (0, 0), then 8 positions around a circle
    _burnInOffsets.add(Offset.zero);
    for (int i = 1; i < 8; i++) {
      final angle = (i * math.pi * 2) / 8;
      const radius = 50.0;
      _burnInOffsets.add(
        Offset(math.cos(angle) * radius, math.sin(angle) * radius),
      );
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _dimOverlayEntry?.remove();
    super.dispose();
  }

  void _startDimTimer() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_isDimmed) {
        setState(() {
          _burnInOffsetIndex = (_burnInOffsetIndex + 1) % _burnInOffsets.length;
        });
        _dimOverlayEntry?.markNeedsBuild();
      }
      final elapsed = DateTime.now().difference(_lastInteraction);
      if (elapsed >= _dimTimeout && !_isDimmed) {
        _showDimScreen();
      }
      _startDimTimer();
    });
  }

  void _showDimScreen() {
    setState(() => _isDimmed = true);
    _dimOverlayEntry = OverlayEntry(builder: (context) => _buildDimOverlay());
    Overlay.of(context).insert(_dimOverlayEntry!);
  }

  void _wakeScreen() {
    if (_isDimmed) {
      _dimOverlayEntry?.remove();
      _dimOverlayEntry = null;
      setState(() => _isDimmed = false);
      _lastInteraction = DateTime.now();
    }
  }

  void _onUserInteraction() {
    _lastInteraction = DateTime.now();
    if (_isDimmed) {
      _wakeScreen();
    }
  }

  Widget _buildDimOverlay() {
    return Consumer<FeedProvider>(
      builder: (context, feedProvider, child) {
        final offset = _burnInOffsets[_burnInOffsetIndex];
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        final size = isLandscape
            ? screenHeight * 0.5
            : screenWidth * AppDimensions.ringSize;

        return GestureDetector(
          onTap: _wakeScreen,
          behavior: HitTestBehavior.opaque,
          child: Container(
            color: Colors.black,
            child: Center(
              child: Transform.translate(
                offset: offset,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Material(
                    color: Colors.transparent,
                    child: CountdownRing(
                      timeRemaining: feedProvider.timeRemaining,
                      timeElapsed: feedProvider.timeElapsed,
                      feedIntervalMinutes: feedProvider.feedIntervalMinutes,
                      state: feedProvider.state,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<FeedProvider, SettingsProvider>(
      builder: (context, feedProvider, settingsProvider, child) {
        final isAlerting = feedProvider.state == FeedState.alerting;

        return GestureDetector(
          onTap: _onUserInteraction,
          behavior: HitTestBehavior.translucent,
          child: Stack(
            children: [
              Scaffold(
                backgroundColor: isAlerting
                    ? AppColors.accent.withAlpha(25)
                    : AppColors.background,
                body: SafeArea(
                  child: OrientationBuilder(
                    builder: (context, orientation) {
                      if (orientation == Orientation.landscape) {
                        return _buildLandscapeLayout(
                          context,
                          feedProvider,
                          settingsProvider,
                          isAlerting,
                        );
                      } else {
                        return _buildPortraitLayout(
                          context,
                          feedProvider,
                          settingsProvider,
                          isAlerting,
                        );
                      }
                    },
                  ),
                ),
              ),
              // Confetti overlay
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confettiController,
                  blastDirectionality: BlastDirectionality.explosive,
                  particleDrag: 0.05,
                  emissionFrequency: 0.05,
                  numberOfParticles: 30,
                  gravity: 0.2,
                  shouldLoop: false,
                  colors: const [
                    AppColors.pink,
                    AppColors.orange,
                    AppColors.yellow,
                    AppColors.green,
                    AppColors.blue,
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPortraitLayout(
    BuildContext context,
    FeedProvider feedProvider,
    SettingsProvider settingsProvider,
    bool isAlerting,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ringSize = constraints.maxHeight * 0.45;
        const verticalPadding = 40.0;
        const spacing = 24.0;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: verticalPadding),
          child: Column(
            children: [
              // Countdown Ring
              SizedBox(
                width: ringSize,
                height: ringSize,
                child: CountdownRing(
                  timeRemaining: feedProvider.timeRemaining,
                  timeElapsed: feedProvider.timeElapsed,
                  feedIntervalMinutes: feedProvider.feedIntervalMinutes,
                  state: feedProvider.state,
                ),
              ),
              const SizedBox(height: spacing),
              // Time Display
              TimeDisplay(
                timeElapsed: feedProvider.timeElapsed,
                lastFeedTime: feedProvider.lastFeedTime,
              ),
              const Spacer(),
              // Stop sound button (when alerting)
              if (isAlerting)
                TextButton(
                  onPressed: () {
                    _onUserInteraction();
                    context.read<AudioService>().stopReminder();
                    context.read<NotificationService>().cancelAll();
                  },
                  child: const Text(
                    '🔇 停止提醒',
                    style: TextStyle(fontSize: 16, color: AppColors.accent),
                  ),
                ),
              // Feed Button
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: FeedButton(
                  onPressed: () async {
                    _onUserInteraction();
                    await feedProvider.recordFeed();
                    settingsProvider.updateSettings(
                      feedIntervalMinutes: settingsProvider.feedIntervalMinutes,
                      nightModeEnabled: settingsProvider.nightModeEnabled,
                      nightStartTime: settingsProvider.nightStartTime,
                      nightEndTime: settingsProvider.nightEndTime,
                      soundEnabled: settingsProvider.soundEnabled,
                      soundLoopEnabled: settingsProvider.soundLoopEnabled,
                    );
                  },
                  onSuccess: () => _confettiController.play(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLandscapeLayout(
    BuildContext context,
    FeedProvider feedProvider,
    SettingsProvider settingsProvider,
    bool isAlerting,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final ringSize = screenWidth * 0.4;

    return Row(
      children: [
        // Left side - Countdown Ring
        Expanded(
          child: Center(
            child: SizedBox(
              width: ringSize,
              height: ringSize,
              child: CountdownRing(
                timeRemaining: feedProvider.timeRemaining,
                timeElapsed: feedProvider.timeElapsed,
                feedIntervalMinutes: feedProvider.feedIntervalMinutes,
                state: feedProvider.state,
              ),
            ),
          ),
        ),
        // Right side - Controls
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TimeDisplay(
                timeElapsed: feedProvider.timeElapsed,
                lastFeedTime: feedProvider.lastFeedTime,
              ),
              const SizedBox(height: 40),
              // Stop sound button (when alerting)
              if (isAlerting)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextButton(
                    onPressed: () {
                      _onUserInteraction();
                      context.read<AudioService>().stopReminder();
                    },
                    child: const Text(
                      '🔇 停止提醒',
                      style: TextStyle(fontSize: 16, color: AppColors.accent),
                    ),
                  ),
                ),
              // Feed Button
              FeedButton(
                onPressed: () async {
                  _onUserInteraction();
                  await feedProvider.recordFeed();
                  settingsProvider.updateSettings(
                    feedIntervalMinutes: settingsProvider.feedIntervalMinutes,
                    nightModeEnabled: settingsProvider.nightModeEnabled,
                    nightStartTime: settingsProvider.nightStartTime,
                    nightEndTime: settingsProvider.nightEndTime,
                    soundEnabled: settingsProvider.soundEnabled,
                    soundLoopEnabled: settingsProvider.soundLoopEnabled,
                  );
                },
                onSuccess: () => _confettiController.play(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
