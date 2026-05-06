import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/countdown_ring.dart';
import '../widgets/feed_button.dart';
import '../widgets/time_display.dart';
import '../utils/constants.dart';
import '../services/audio_service.dart';
import '../services/notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 1));
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<FeedProvider, SettingsProvider>(
      builder: (context, feedProvider, settingsProvider, child) {
        final isAlerting = feedProvider.state == FeedState.alerting;

        return Stack(
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
        final verticalPadding = 40.0;
        final spacing = 24.0;

        return Padding(
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
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
              SizedBox(height: spacing),
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
                    context.read<AudioService>().stopReminder();
                    context.read<NotificationService>().cancelAll();
                  },
                  child: const Text(
                    '🔇 停止提醒',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              // Feed Button
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: FeedButton(
                  onPressed: () async {
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
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
                        context.read<AudioService>().stopReminder();
                      },
                      child: const Text(
                        '🔇 停止提醒',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                // Feed Button
                FeedButton(
                  onPressed: () async {
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
        ),
      ],
    );
  }
}
