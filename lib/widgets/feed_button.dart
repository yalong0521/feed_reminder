import 'package:flutter/material.dart';
import '../utils/constants.dart';

class FeedButton extends StatefulWidget {
  final VoidCallback onPressed;

  const FeedButton({super.key, required this.onPressed});

  @override
  State<FeedButton> createState() => _FeedButtonState();
}

class _FeedButtonState extends State<FeedButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onPressed();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: double.infinity,
              height: AppDimensions.buttonHeight,
              margin: const EdgeInsets.symmetric(horizontal: 40),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.pink, AppColors.orange],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius:
                    BorderRadius.circular(AppDimensions.buttonRadius),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.pink.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  AppStrings.recordFeed,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
