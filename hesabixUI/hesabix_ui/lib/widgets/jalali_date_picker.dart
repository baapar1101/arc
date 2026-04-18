import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../core/api_client.dart';
import '../core/calendar_controller.dart';

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
    // Clamp initial within range if provided
    if (widget.firstDate != null && _selectedDate.isBefore(widget.firstDate!)) {
      _selectedDate = widget.firstDate!;
    }
    if (widget.lastDate != null && _selectedDate.isAfter(widget.lastDate!)) {
      _selectedDate = widget.lastDate!;
    }
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
                  onPressed: () => context.pop(),
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
    return _CustomPersianCalendar(
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

/// انتخاب تاریخ متناسب با تقویم انتخاب‌شده کاربر (شمسی یا میلادی).
///
/// اگر [calendarController] نباشد، از [ApiClient.getCalendarController] و در نهایت
/// [CalendarController.load] استفاده می‌شود.
Future<DateTime?> showAdaptiveDatePicker({
  required BuildContext context,
  CalendarController? calendarController,
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String? helpText,
}) async {
  final cal = calendarController ?? ApiClient.getCalendarController();
  final controller = cal ?? await CalendarController.load();
  final now = DateTime.now();
  final initial = initialDate ?? now;
  final first = firstDate ?? DateTime(now.year - 10);
  final last = lastDate ?? DateTime(now.year + 10);

  if (controller.isJalali) {
    return showJalaliDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: helpText,
    );
  }
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first,
    lastDate: last,
    helpText: helpText,
    locale: const Locale('en', 'US'),
  );
}

/// Custom Persian Calendar Widget with proper Persian month names
class _CustomPersianCalendar extends StatefulWidget {
  final Jalali initialDate;
  final Jalali firstDate;
  final Jalali lastDate;
  final ValueChanged<Jalali> onDateChanged;

  const _CustomPersianCalendar({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDateChanged,
  });

  @override
  State<_CustomPersianCalendar> createState() => _CustomPersianCalendarState();
}

class _CustomPersianCalendarState extends State<_CustomPersianCalendar> {
  late Jalali _currentDate;
  late Jalali _selectedDate;

  // Persian month names
  static const List<String> _monthNames = [
    'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
    'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'
  ];

  // Persian day names (abbreviated)
  static const List<String> _dayNames = [
    'ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'
  ];

  @override
  void initState() {
    super.initState();
    _currentDate = widget.initialDate;
    _selectedDate = widget.initialDate;
  }

  void _previousMonth() {
    setState(() {
      if (_currentDate.month == 1) {
        _currentDate = Jalali(_currentDate.year - 1, 12, 1);
      } else {
        _currentDate = Jalali(_currentDate.year, _currentDate.month - 1, 1);
      }
    });
  }

  void _nextMonth() {
    setState(() {
      if (_currentDate.month == 12) {
        _currentDate = Jalali(_currentDate.year + 1, 1, 1);
      } else {
        _currentDate = Jalali(_currentDate.year, _currentDate.month + 1, 1);
      }
    });
  }

  void _selectDate(Jalali date) {
    // Enforce range limits
    if (date.compareTo(widget.firstDate) < 0 || date.compareTo(widget.lastDate) > 0) {
      return;
    }
    setState(() {
      _selectedDate = date;
    });
    widget.onDateChanged(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Get the first day of the month and calculate the starting day
    final firstDayOfMonth = Jalali(_currentDate.year, _currentDate.month, 1);
    final lastDayOfMonth = Jalali(_currentDate.year, _currentDate.month, _currentDate.monthLength);
    
    // Calculate the starting weekday (0 = Saturday, 6 = Friday)
    // Convert Jalali to DateTime to get weekday, then adjust for Persian calendar
    final gregorianFirstDay = firstDayOfMonth.toDateTime();
    final startWeekday = (gregorianFirstDay.weekday + 1) % 7; // Adjust for Persian week start (Saturday)
    
    return Column(
      children: [
        // Month/Year header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _previousMonth,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                '${_monthNames[_currentDate.month - 1]} ${_currentDate.year}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: _nextMonth,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        
        // Day names header
        Row(
          children: _dayNames.map((day) => Expanded(
            child: Center(
              child: Text(
                day,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          )).toList(),
        ),
        
        const SizedBox(height: 8),
        
        // Calendar grid
        Expanded(
          child: GridView.builder(
            physics: const ClampingScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.0,
            ),
            itemCount: 42, // 6 weeks * 7 days
            itemBuilder: (context, index) {
              final dayIndex = index - startWeekday;
              final day = dayIndex + 1;
              
              if (dayIndex < 0 || day > lastDayOfMonth.day.toInt()) {
                return const SizedBox.shrink();
              }
              
              final date = Jalali(_currentDate.year, _currentDate.month, day);
              final isSelected = date.year == _selectedDate.year &&
                                date.month == _selectedDate.month &&
                                date.day == _selectedDate.day;
              final isToday = date.year == Jalali.now().year &&
                             date.month == Jalali.now().month &&
                             date.day == Jalali.now().day;
              
              final isDisabled = date.compareTo(widget.firstDate) < 0 || date.compareTo(widget.lastDate) > 0;
              return GestureDetector(
                onTap: isDisabled ? null : () => _selectDate(date),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isDisabled
                        ? theme.disabledColor.withValues(alpha: 0.1)
                        : isSelected 
                        ? theme.colorScheme.primary
                        : isToday 
                            ? theme.colorScheme.primary.withValues(alpha: 0.1)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: isDisabled
                        ? Border.all(color: theme.disabledColor.withValues(alpha: 0.3), width: 1)
                        : isToday && !isSelected
                        ? Border.all(color: theme.colorScheme.primary, width: 1)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      day.toString(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDisabled
                            ? theme.disabledColor
                            : isSelected 
                            ? theme.colorScheme.onPrimary
                            : isToday
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                        fontWeight: isSelected || isToday 
                            ? FontWeight.bold 
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}