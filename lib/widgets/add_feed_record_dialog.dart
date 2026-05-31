import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';
import '../utils/constants.dart';

class AddFeedRecordDialog extends StatefulWidget {
  const AddFeedRecordDialog({super.key});

  @override
  State<AddFeedRecordDialog> createState() => _AddFeedRecordDialogState();
}

class _AddFeedRecordDialogState extends State<AddFeedRecordDialog> {
  DateTime _selectedDate = DateTime.now();
  bool _showDatePicker = true;

  void _goToTimePicker() {
    setState(() {
      _showDatePicker = false;
    });
  }

  void _goToDatePicker() {
    setState(() {
      _showDatePicker = true;
    });
  }

  DateTime _getCombinedDateTime() {
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedDate.hour,
      _selectedDate.minute,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxDialogHeight = screenHeight * 0.85;
    final pickerHeight = min(300.0, maxDialogHeight);

    return Dialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxDialogHeight),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '添加喂奶记录',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTabButton('日期', _showDatePicker, _goToDatePicker),
                    const SizedBox(width: 16),
                    _buildTabButton('时间', !_showDatePicker, _goToTimePicker),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: pickerHeight,
                  child: _showDatePicker
                      ? _buildDatePicker()
                      : _buildTimePicker(),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        '取消',
                        style: TextStyle(color: AppColors.textLight),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final feedProvider = context.read<FeedProvider>();
                        final dateTime = _getCombinedDateTime();
                        if (dateTime.isAfter(DateTime.now())) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('不能选择未来的时间')),
                          );
                          return;
                        }
                        await feedProvider.addFeedRecordWithTime(dateTime);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      child: const Text(
                        '确定',
                        style: TextStyle(color: AppColors.accent),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.textLight,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.white : AppColors.textLight,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildDatePicker() {
    return CalendarDatePicker(
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      onDateChanged: (DateTime newDate) {
        setState(() {
          _selectedDate = DateTime(
            newDate.year,
            newDate.month,
            newDate.day,
            _selectedDate.hour,
            _selectedDate.minute,
          );
        });
      },
    );
  }

  Widget _buildTimePicker() {
    return CupertinoDatePicker(
      mode: CupertinoDatePickerMode.time,
      initialDateTime: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        12,
        0,
      ),
      use24hFormat: true,
      onDateTimeChanged: (DateTime newDateTime) {
        setState(() {
          _selectedDate = DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
            newDateTime.hour,
            newDateTime.minute,
          );
        });
      },
    );
  }
}

void showAddFeedRecordDialog(BuildContext navigatorContext) {
  showDialog(
    context: navigatorContext,
    builder: (dialogContext) => const AddFeedRecordDialog(),
  );
}
