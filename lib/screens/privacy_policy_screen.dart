import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/privacy_service.dart';
import '../utils/constants.dart';
import '../utils/privacy_policy.dart';
import '../widgets/app_controls.dart';
import '../widgets/app_surface.dart';

Future<void> showPrivacyPolicy(BuildContext context) async {
  if (PrivacyService.usesHostedPolicy) {
    try {
      await PrivacyService.openHostedPolicy();
    } catch (_) {
      if (!context.mounted) return;
      showAppNotice(
        context,
        '隐私政策暂时无法打开，请检查网络后重试。',
        actionLabel: '重试',
        onAction: () => showPrivacyPolicy(context),
      );
    }
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'privacy-policy'),
      builder: (_) => const PrivacyPolicyScreen(),
    ),
  );
}

/// Bundled text stays available before consent and without a network connection.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 24, 8),
                    child: Row(
                      children: [
                        AppButton(
                          key: const ValueKey('privacy-policy-back'),
                          surface: false,
                          compact: true,
                          semanticLabel: '返回',
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Icon(CupertinoIcons.back),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '隐私政策',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: colors.border),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                      child: SelectionArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              PrivacyPolicy.title,
                              style: TextStyle(
                                fontSize: 28,
                                height: 1.4,
                                color: colors.primary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              PrivacyPolicy.effectiveDate,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.6,
                                color: colors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              PrivacyPolicy.introduction,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.7,
                                color: colors.textPrimary,
                              ),
                            ),
                            for (final section in PrivacyPolicy.sections) ...[
                              const SizedBox(height: 28),
                              Semantics(
                                header: true,
                                child: Text(
                                  section.title,
                                  style: TextStyle(
                                    fontSize: 20,
                                    height: 1.5,
                                    fontWeight: FontWeight.w500,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                section.content,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.7,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
