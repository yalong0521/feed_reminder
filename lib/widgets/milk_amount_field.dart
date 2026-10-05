import 'package:flutter/cupertino.dart';

import '../services/app_haptics.dart';
import '../theme/app_typography.dart';
import '../utils/constants.dart';
import 'app_controls.dart';
import 'milk_amount_ruler.dart';

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

  void _stepAmount(int amount) {
    if (int.tryParse(controller.text) == amount) return;
    _setAmount(amount);
    AppHaptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final inputStyle = CupertinoTheme.of(context).textTheme.textStyle.merge(
      TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w400,
        color: colors.primary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final unitStyle = DefaultTextStyle.of(
      context,
    ).style.merge(AppTypography.supporting(context));
    double textWidth(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    // Reserve all four legal digits, field padding and the caret before
    // deciding whether the two step buttons can share the input's row.
    final numberWidth = textWidth('2000', inputStyle) + 24 + 6;
    final unitWidth = textWidth('mL', unitStyle) + 14;
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    final inline =
                        constraints.maxWidth >=
                        numberWidth + unitWidth + 44 * 2 + 10 * 2;
                    final inlineUnit =
                        constraints.maxWidth >= numberWidth + unitWidth;
                    final decrease = AppButton(
                      key: const ValueKey('milk-amount-decrease'),
                      compact: true,
                      padding: const EdgeInsets.all(10),
                      semanticLabel: '减少 10 毫升',
                      onPressed: enabled && amount != null && amount > 0
                          ? () => _stepAmount((amount - 10).clamp(0, 2000))
                          : null,
                      child: const Icon(CupertinoIcons.minus, size: 18),
                    );
                    final increase = AppButton(
                      key: const ValueKey('milk-amount-increase'),
                      compact: true,
                      padding: const EdgeInsets.all(10),
                      semanticLabel: '增加 10 毫升',
                      onPressed: enabled && amount != null && amount < 2000
                          ? () => _stepAmount((amount + 10).clamp(0, 2000))
                          : null,
                      child: const Icon(CupertinoIcons.plus, size: 18),
                    );
                    final field = Semantics(
                      label: '$label，毫升',
                      child: CupertinoTextField(
                        key: const ValueKey('milk-amount-input'),
                        controller: controller,
                        enabled: enabled,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        style: inputStyle,
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
                        suffix: inlineUnit
                            ? Padding(
                                padding: const EdgeInsets.only(right: 14),
                                child: Text('mL', style: unitStyle),
                              )
                            : null,
                        onChanged: (_) => onChanged?.call(),
                        onSubmitted: (_) => onSubmitted?.call(),
                      ),
                    );
                    if (inline) {
                      return Row(
                        children: [
                          decrease,
                          const SizedBox(width: 10),
                          Expanded(child: field),
                          const SizedBox(width: 10),
                          increase,
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        field,
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            decrease,
                            const SizedBox(width: 12),
                            if (!inlineUnit) ...[
                              Text('mL', style: unitStyle),
                              const SizedBox(width: 12),
                            ],
                            increase,
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                MilkAmountRuler(
                  key: const ValueKey('milk-amount-ruler'),
                  controller: controller,
                  enabled: enabled,
                  label: label,
                  onChanged: _setAmount,
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
