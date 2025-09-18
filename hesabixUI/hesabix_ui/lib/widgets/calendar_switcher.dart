import 'package:flutter/material.dart';

import '../core/calendar_controller.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class CalendarSwitcher extends StatelessWidget {
  final CalendarController controller;
  const CalendarSwitcher({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final bool isJalali = controller.calendarType == CalendarType.jalali;

    return PopupMenuButton<CalendarType>(
      tooltip: t.calendarType,
      itemBuilder: (context) => <PopupMenuEntry<CalendarType>>[
        PopupMenuItem(
          value: CalendarType.jalali,
          child: Text(t.jalali),
        ),
        PopupMenuItem(
          value: CalendarType.gregorian,
          child: Text(t.gregorian),
        ),
      ],
      onSelected: (calendarType) => controller.setCalendarType(calendarType),
      child: CircleAvatar(
        radius: 14,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        child: Icon(
          isJalali ? Icons.calendar_today : Icons.calendar_month,
          size: 16,
        ),
      ),
    );
  }
}
