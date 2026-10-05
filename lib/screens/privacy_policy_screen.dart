import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/privacy_service.dart';
import '../theme/app_typography.dart';
import '../utils/constants.dart';
import '../utils/privacy_policy.dart';
import '../widgets/app_controls.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_surface.dart';

final _openPolicies = Expando<Future<void>>('Open privacy policy');

Future<void> showPrivacyPolicy(BuildContext context) {
  final navigator = Navigator.of(context);
  final existing = _openPolicies[navigator];
  if (existing != null) return existing;
  final opening = _showPrivacyPolicy(context, navigator);
  _openPolicies[navigator] = opening;
  return opening.whenComplete(() {
    if (identical(_openPolicies[navigator], opening)) {
      _openPolicies[navigator] = null;
    }
  });
}

Future<void> _showPrivacyPolicy(
  BuildContext context,
  NavigatorState navigator,
) async {
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
  final route = MaterialPageRoute<void>(
    settings: const RouteSettings(name: 'privacy-policy'),
    builder: (_) => const PrivacyPolicyScreen(),
  );
  await navigator.push<void>(route);
  await route.completed;
}

/// Bundled text stays available before consent and without a network connection.
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  bool _closing = false;

  void _close() {
    if (_closing || ModalRoute.of(context)?.isCurrent != true) return;
    _closing = true;
    Navigator.of(context).pop();
  }

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
                          onPressed: _close,
                          child: const Icon(CupertinoIcons.back),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '隐私政策',
                            style: AppTypography.sectionTitle(context),
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
                              style: AppTypography.pageTitle(
                                context,
                                compact: AppPageLayout.compact(context),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              PrivacyPolicy.effectiveDate,
                              style: AppTypography.caption(context),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              PrivacyPolicy.introduction,
                              style: AppTypography.body(context),
                            ),
                            for (final section in PrivacyPolicy.sections) ...[
                              const SizedBox(height: 28),
                              Semantics(
                                header: true,
                                child: Text(
                                  section.title,
                                  style: AppTypography.sectionTitle(context),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                section.content,
                                style: AppTypography.body(
                                  context,
                                ).copyWith(color: colors.textSecondary),
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
