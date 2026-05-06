import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/countdown_ring.dart';
import '../widgets/feed_button.dart';
import '../widgets/time_display.dart';
import '../utils/constants.dart';
import '../services/audio_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<FeedProvider, SettingsProvider>(
      builder: (context, feedProvider, settingsProvider, child) {
        final isAlerting = feedProvider.state == FeedState.alerting;

        return Scaffold(
          backgroundColor: isAlerting
              ? AppColors.accent.withOpacity(0.1)
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
    return Column(
      children: [
        const Spacer(),
        // Countdown Ring - wrapped in FittedBox to handle small heights
        FittedBox(
          fit: BoxFit.scaleDown,
          child: CountdownRing(
            timeRemaining: feedProvider.timeRemaining,
            timeElapsed: feedProvider.timeElapsed,
            feedIntervalMinutes: feedProvider.feedIntervalMinutes,
            state: feedProvider.state,
          ),
        ),
        const SizedBox(height: 24),
        // Time Display
        TimeDisplay(
          timeElapsed: feedProvider.timeElapsed,
          lastFeedTime: feedProvider.lastFeedTime,
        ),
        const Spacer(),
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
        Padding(
          padding: const EdgeInsets.only(bottom: 40),
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
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(
    BuildContext context,
    FeedProvider feedProvider,
    SettingsProvider settingsProvider,
    bool isAlerting,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final ringSize = screenWidth * 0.35;

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
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
