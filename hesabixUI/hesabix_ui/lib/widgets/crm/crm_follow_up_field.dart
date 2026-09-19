import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';

/// انتخاب تاریخ/ساعت پیگیری با میانبرهای سریع (امروز / فردا / +۳ روز).
class CrmFollowUpField extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final CalendarController? calendarController;
  final String label;

  const CrmFollowUpField({
    super.key,
    required this.value,
    required this.onChanged,
    this.calendarController,
    this.label = 'یادآور پیگیری',
  });

  bool get _isJalali =>
      calendarController?.isJalali ?? ApiClient.getCalendarController()?.isJalali ?? true;

  Future<void> _pickCustom(BuildContext context) async {
    final date = await showAdaptiveDatePicker(
      context: context,
      calendarController: calendarController,
      initialDate: value ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: value != null ? TimeOfDay.fromDateTime(value!) : const TimeOfDay(hour: 10, minute: 0),
    );
    if (time == null || !context.mounted) return;
    onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  DateTime _atHour(DateTime day, {int hour = 10}) =>
      DateTime(day.year, day.month, day.day, hour, 0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final display = value == null
        ? 'تعیین نشده'
        : HesabixDateUtils.formatDateTime(value, _isJalali);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.notifications_active_outlined, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(display, style: theme.textTheme.bodyMedium)),
              TextButton(onPressed: () => _pickCustom(context), child: const Text('انتخاب')),
              if (value != null)
                TextButton(onPressed: () => onChanged(null), child: const Text('پاک کردن')),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              label: const Text('امروز ۱۰:۰۰'),
              onPressed: () => onChanged(_atHour(today)),
            ),
            ActionChip(
              label: const Text('فردا ۱۰:۰۰'),
              onPressed: () => onChanged(_atHour(today.add(const Duration(days: 1)))),
            ),
            ActionChip(
              label: const Text('+۳ روز'),
              onPressed: () => onChanged(_atHour(today.add(const Duration(days: 3)))),
            ),
          ],
        ),
      ],
    );
  }
}
