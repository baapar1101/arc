import 'package:flutter/material.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart' as picker;
import 'package:shamsi_date/shamsi_date.dart';

/// DatePicker سفارشی برای تقویم شمسی
class JalaliDatePicker extends StatefulWidget {
  final DateTime? initialDate;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String? helpText;
  final ValueChanged<DateTime>? onDateChanged;

  const JalaliDatePicker({
    super.key,
    this.initialDate,
    this.firstDate,
    this.lastDate,
    this.helpText,
    this.onDateChanged,
  });

  @override
  State<JalaliDatePicker> createState() => _JalaliDatePickerState();
}

class _JalaliDatePickerState extends State<JalaliDatePicker> {
  late DateTime _selectedDate;
  late Jalali _selectedJalali;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _selectedJalali = Jalali.fromDateTime(_selectedDate);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final jalali = Jalali.fromDateTime(_selectedDate);
    
    return Dialog(
      backgroundColor: theme.dialogTheme.backgroundColor,
      child: Container(
        width: 350,
        height: 450,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.dialogTheme.backgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            if (widget.helpText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  widget.helpText!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.textTheme.titleMedium?.color,
                  ),
                ),
              ),
            
            // Selected date display
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.calendar_today,
                    color: theme.primaryColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${jalali.year}/${jalali.month.toString().padLeft(2, '0')}/${jalali.day.toString().padLeft(2, '0')}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            // Calendar
            Expanded(
              child: _buildCalendar(),
            ),
            
            // Buttons
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'انصراف',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    widget.onDateChanged?.call(_selectedDate);
                    Navigator.of(context).pop(_selectedDate);
                  },
                  child: const Text('تایید'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    return picker.PersianCalendarDatePicker(
      initialDate: _selectedJalali,
      firstDate: Jalali.fromDateTime(widget.firstDate ?? DateTime(1900)),
      lastDate: Jalali.fromDateTime(widget.lastDate ?? DateTime(2100)),
      onDateChanged: (jalali) {
        setState(() {
          _selectedJalali = jalali;
          _selectedDate = jalali.toDateTime();
        });
      },
    );
  }
}

/// تابع کمکی برای نمایش Jalali DatePicker
Future<DateTime?> showJalaliDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (context) => JalaliDatePicker(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: helpText,
    ),
  );
}