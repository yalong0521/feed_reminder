import 'package:flutter/material.dart';

import '../theme/app_typography.dart';
import 'app_controls.dart';
import 'app_message_dialog.dart';

Future<int?> showSnoozeReminderDialog(BuildContext context) {
  var closing = false;
  return Navigator.of(context, rootNavigator: true).push<int>(
    createAppMessageDialogRoute<int>(
      context,
      builder: (dialogContext) {
        void close([int? minutes]) {
          if (closing || ModalRoute.of(dialogContext)?.isCurrent != true) {
            return;
          }
          closing = true;
          Navigator.of(dialogContext).pop(minutes);
        }

        return AppMessageDialog(
          title: '稍后提醒',
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '从确认时起延后本次提醒，不会新增喂奶记录，也不改变默认间隔。',
                style: AppTypography.supporting(context),
              ),
              const SizedBox(height: 16),
              for (final minutes in [10, 20, 30]) ...[
                AppButton(
                  key: ValueKey('snooze-$minutes'),
                  onPressed: () => close(minutes),
                  child: Text('$minutes 分钟后'),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
          actions: [AppButton(onPressed: close, child: const Text('取消'))],
        );
      },
    ),
  );
}
