import 'package:flutter/cupertino.dart';

import '../theme/app_typography.dart';
import '../utils/constants.dart';
import 'app_controls.dart';

/// Shared input for a meal's milk amount and the default for future meals.
class MilkAmountField extends StatelessWidget {
  const MilkAmountField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.label = '本次奶量',
  });

  final TextEditingController controller;
  final bool enabled;
  final String? errorText;
  final VoidCallback? onChanged;
  final VoidCallback? onSubmitted;
  final String label;

  static String? validate(String text) {
    final amount = int.tryParse(text);
    if (!RegExp(r'^\d+$').hasMatch(text) ||
        amount == null ||
        amount < 0 ||
        amount > 2000) {
      return '请输入 0–2000 之间的整数（mL）';
    }
    return null;
  }

  void _setAmount(int amount) {
    controller.value = TextEditingValue(
      text: '$amount',
      selection: TextSelection.collapsed(offset: '$amount'.length),
    );
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.label(context)),
        const SizedBox(height: 10),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final amount = int.tryParse(controller.text);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppButton(
                      key: const ValueKey('milk-amount-decrease'),
                      compact: true,
                      padding: const EdgeInsets.all(10),
                      semanticLabel: '减少 10 毫升',
                      onPressed: enabled && amount != null && amount > 0
                          ? () => _setAmount((amount - 10).clamp(0, 2000))
                          : null,
                      child: const Icon(CupertinoIcons.minus, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Semantics(
                        label: '$label，毫升',
                        child: CupertinoTextField(
                          key: const ValueKey('milk-amount-input'),
                          controller: controller,
                          enabled: enabled,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w400,
                            color: colors.primary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          textAlign: TextAlign.center,
                          cursorColor: colors.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: colors.background,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: errorText == null
                                  ? colors.border
                                  : colors.alert,
                            ),
                          ),
                          suffix: Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: Text(
                              'mL',
                              style: AppTypography.supporting(context),
                            ),
                          ),
                          onChanged: (_) => onChanged?.call(),
                          onSubmitted: (_) => onSubmitted?.call(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    AppButton(
                      key: const ValueKey('milk-amount-increase'),
                      compact: true,
                      padding: const EdgeInsets.all(10),
                      semanticLabel: '增加 10 毫升',
                      onPressed: enabled && amount != null && amount < 2000
                          ? () => _setAmount((amount + 10).clamp(0, 2000))
                          : null,
                      child: const Icon(CupertinoIcons.plus, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in const [60, 90, 120, 150, 180])
                      AppPressable(
                        key: ValueKey('milk-amount-preset-$preset'),
                        onPressed: enabled ? () => _setAmount(preset) : null,
                        selected: amount == preset,
                        semanticLabel: '$preset 毫升',
                        excludeSemantics: true,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: amount == preset
                                ? colors.primary.withValues(alpha: .08)
                                : colors.background,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: amount == preset
                                  ? colors.primary
                                  : colors.border,
                            ),
                          ),
                          child: Text(
                            '$preset',
                            style: AppTypography.supporting(context).copyWith(
                              color: amount == preset
                                  ? colors.primary
                                  : colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          '0 mL 表示未记录奶量；可填写 0–2000 mL。',
          style: AppTypography.caption(context),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              errorText!,
              style: AppTypography.supporting(
                context,
              ).copyWith(color: colors.alert),
            ),
          ),
        ],
      ],
    );
  }
}
