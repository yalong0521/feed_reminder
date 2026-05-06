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
            child: Column(
              children: [
                const Spacer(),
                // Countdown Ring
                CountdownRing(
                  timeRemaining: feedProvider.timeRemaining,
                  timeElapsed: feedProvider.timeElapsed,
                  feedIntervalMinutes: feedProvider.feedIntervalMinutes,
                  state: feedProvider.state,
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
            ),
          ),
        );
      },
    );
  }
}
