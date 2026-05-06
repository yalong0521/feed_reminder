import 'package:flutter/material.dart';

import '../utils/constants.dart';

class FeedButton extends StatefulWidget {
  final VoidCallback onPressed;
  final VoidCallback? onSuccess;

  const FeedButton({super.key, required this.onPressed, this.onSuccess});

  @override
  State<FeedButton> createState() => _FeedButtonState();
}

class _FeedButtonState extends State<FeedButton>
    with SingleTickerProviderStateMixin {
  double _dragPosition = 0;
  bool _isCompleted = false;
  late AnimationController _resetController;
  late Animation<double> _resetAnimation;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details, double maxWidth) {
    if (_isCompleted) return;
    setState(() {
      _dragPosition = (_dragPosition + details.delta.dx).clamp(0.0, maxWidth);
    });
  }

  void _onDragEnd(DragEndDetails details, double maxWidth) {
    if (_isCompleted) return;
    if (_dragPosition >= maxWidth) {
      setState(() => _isCompleted = true);
      widget.onPressed();
      widget.onSuccess?.call();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _reset();
        }
      });
    } else {
      _reset();
    }
  }

  void _reset() {
    _resetAnimation =
        Tween<double>(begin: _dragPosition, end: 0).animate(
          CurvedAnimation(parent: _resetController, curve: Curves.easeOut),
        )..addListener(() {
          setState(() => _dragPosition = _resetAnimation.value);
        });
    _resetController.forward(from: 0).then((_) {
      if (mounted) setState(() => _isCompleted = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: AppDimensions.buttonHeight,
      margin: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth - 70;
          final progress = (_dragPosition / maxWidth).clamp(0.0, 1.0);

          return Stack(
            children: [
              // Progress fill
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: _dragPosition + 70,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        AppDimensions.buttonRadius,
                      ),
                      gradient: LinearGradient(
                        colors: _isCompleted
                            ? [AppColors.green, AppColors.green]
                            : [
                                AppColors.pink.withValues(alpha: 0.3),
                                AppColors.orange.withValues(alpha: 0.3),
                              ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                ),
              ),
              // Hint text
              Center(
                child: Opacity(
                  opacity: 1 - progress,
                  child: Text(
                    _isCompleted ? '完成' : AppStrings.recordFeed,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textLight,
                    ),
                  ),
                ),
              ),
              // Slider thumb
              Positioned(
                left: _dragPosition,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) =>
                      _onDragUpdate(details, maxWidth),
                  onHorizontalDragEnd: (details) =>
                      _onDragEnd(details, maxWidth),
                  child: Container(
                    width: 70,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isCompleted
                            ? [AppColors.green, AppColors.green]
                            : [AppColors.pink, AppColors.orange],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(
                        AppDimensions.buttonRadius,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              (_isCompleted ? AppColors.green : AppColors.pink)
                                  .withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        _isCompleted ? Icons.check : Icons.arrow_forward,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
