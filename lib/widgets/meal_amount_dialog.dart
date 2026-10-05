import 'package:flutter/material.dart';

import '../theme/app_typography.dart';
import 'app_controls.dart';
import 'app_message_dialog.dart';
import 'milk_amount_field.dart';

/// Null amount explicitly restores the current default; null result cancels.
class MealAmountSelection {
  const MealAmountSelection(this.amount);
  final int? amount;
}

Future<MealAmountSelection?> showMealAmountDialog(
  BuildContext context, {
  required int currentAmount,
  required int defaultAmount,
}) => Navigator.of(context, rootNavigator: true).push<MealAmountSelection>(
  createAppMessageDialogRoute<MealAmountSelection>(
    context,
    builder: (_) => _MealAmountDialog(
      currentAmount: currentAmount,
      defaultAmount: defaultAmount,
    ),
  ),
);

class _MealAmountDialog extends StatefulWidget {
  const _MealAmountDialog({
    required this.currentAmount,
    required this.defaultAmount,
  });
  final int currentAmount;
  final int defaultAmount;

  @override
  State<_MealAmountDialog> createState() => _MealAmountDialogState();
}

class _MealAmountDialogState extends State<_MealAmountDialog> {
  final _amountFieldKey = GlobalKey();
  late final _controller = TextEditingController(
    text: '${widget.currentAmount}',
  );
  String? _error;
  bool _closing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close([MealAmountSelection? choice]) {
    if (_closing || ModalRoute.of(context)?.isCurrent != true) return;
    _closing = true;
    Navigator.of(context).pop(choice);
  }

  void _submit() {
    final error = MilkAmountField.validate(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _closing || _error == null) return;
        final fieldContext = _amountFieldKey.currentContext;
        if (fieldContext == null) return;
        // The error is at the field's bottom, which can be below the fixed
        // action bar on a small screen or with large text.
        Scrollable.ensureVisible(
          fieldContext,
          alignment: 1,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
      });
      return;
    }
    _close(MealAmountSelection(int.parse(_controller.text)));
  }

  @override
  Widget build(BuildContext context) => AppMessageDialog(
    title: '调整本次奶量',
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('仅用于下一条记录，默认奶量保持不变。', style: AppTypography.supporting(context)),
        const SizedBox(height: 20),
        MilkAmountField(
          key: _amountFieldKey,
          controller: _controller,
          errorText: _error,
          onChanged: () {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: _submit,
        ),
        const SizedBox(height: 12),
        AppButton(
          key: const ValueKey('meal-amount-reset'),
          onPressed: () => _close(const MealAmountSelection(null)),
          child: Text('恢复默认 ${widget.defaultAmount} mL'),
        ),
      ],
    ),
    actions: [
      AppButton(
        key: const ValueKey('meal-amount-cancel'),
        onPressed: _close,
        child: const Text('取消'),
      ),
      AppButton(
        key: const ValueKey('meal-amount-apply'),
        filled: true,
        onPressed: _submit,
        child: const Text('使用此奶量'),
      ),
    ],
  );
}
