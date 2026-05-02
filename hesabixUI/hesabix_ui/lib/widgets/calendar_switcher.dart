import 'package:flutter/material.dart';

import '../core/calendar_controller.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class CalendarSwitcher extends StatelessWidget {
  final CalendarController controller;
  final bool toolbarCompact;
  const CalendarSwitcher({super.key, required this.controller, this.toolbarCompact = false});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final bool isJalali = controller.calendarType == CalendarType.jalali;
    final double r = toolbarCompact ? 12 : 14;
    final double iconSz = toolbarCompact ? 14 : 16;

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
        radius: r,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        child: Icon(
          isJalali ? Icons.calendar_today : Icons.calendar_month,
          size: iconSz,
        ),
      ),
    );
  }
}
