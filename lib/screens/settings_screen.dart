import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/feed_provider.dart';
import '../utils/constants.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsProvider, FeedProvider>(
      builder: (context, settings, feedProvider, child) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text(
              AppStrings.settings,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: AppColors.background,
            elevation: 0,
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Feed Interval
              _buildSectionTitle(AppStrings.feedInterval),
              _buildDropdown(
                context,
                value: settings.feedIntervalMinutes,
                items: const [120, 150, 180, 210, 240],
                labels: const ['2小时', '2.5小时', '3小时', '3.5小时', '4小时'],
                onChanged: (value) {
                  settings.setFeedInterval(value);
                  feedProvider.updateSettings(feedIntervalMinutes: value);
                },
              ),
              const SizedBox(height: 24),

              // Night Mode Section
              _buildSectionTitle(AppStrings.nightMode),
              _buildSwitchTile(
                title: AppStrings.nightMode,
                value: settings.nightModeEnabled,
                onChanged: (value) {
                  settings.setNightModeEnabled(value);
                  feedProvider.updateSettings(nightModeEnabled: value);
                },
              ),
              if (settings.nightModeEnabled) ...[
                _buildTimePicker(
                  context,
                  title: AppStrings.nightStart,
                  value: settings.nightStartTime,
                  onChanged: (time) {
                    settings.setNightStartTime(time);
                    feedProvider.updateSettings(nightStartTime: time);
                  },
                ),
                _buildTimePicker(
                  context,
                  title: AppStrings.nightEnd,
                  value: settings.nightEndTime,
                  onChanged: (time) {
                    settings.setNightEndTime(time);
                    feedProvider.updateSettings(nightEndTime: time);
                  },
                ),
              ],
              const SizedBox(height: 24),

              // Reminder Section
              _buildSectionTitle('提醒设置'),
              _buildSwitchTile(
                title: AppStrings.soundReminder,
                value: settings.soundEnabled,
                onChanged: (value) {
                  settings.setSoundEnabled(value);
                  feedProvider.updateSettings(soundEnabled: value);
                },
              ),
              if (settings.soundEnabled)
                _buildSwitchTile(
                  title: AppStrings.loopSound,
                  value: settings.soundLoopEnabled,
                  onChanged: (value) {
                    settings.setSoundLoopEnabled(value);
                    feedProvider.updateSettings(soundLoopEnabled: value);
                  },
                ),
              const SizedBox(height: 24),

              // Other Section
              _buildSectionTitle('其他'),
              _buildSwitchTile(
                title: AppStrings.keepScreenOn,
                value: settings.wakelockEnabled,
                onChanged: (value) {
                  settings.setWakelockEnabled(value);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppColors.textLight,
        ),
      ),
    );
  }

  Widget _buildDropdown(
    BuildContext context, {
    required int value,
    required List<int> items,
    required List<String> labels,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButton<int>(
        value: value,
        isExpanded: true,
        underline: const SizedBox(),
        items: List.generate(items.length, (index) {
          return DropdownMenuItem<int>(
            value: items[index],
            child: Text(labels[index]),
          );
        }),
        onChanged: (v) => onChanged(v!),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.pink,
          ),
        ],
      ),
    );
  }

  Widget _buildTimePicker(
    BuildContext context, {
    required String title,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          TextButton(
            onPressed: () async {
              final parts = value.split(':');
              final initialTime = TimeOfDay(
                hour: int.parse(parts[0]),
                minute: int.parse(parts[1]),
              );
              final picked = await showTimePicker(
                context: context,
                initialTime: initialTime,
              );
              if (picked != null) {
                final newTime =
                    '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                onChanged(newTime);
              }
            },
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.pink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
