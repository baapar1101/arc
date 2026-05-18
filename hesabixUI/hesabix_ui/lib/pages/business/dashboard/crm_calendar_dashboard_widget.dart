import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

const _jalaliWeekdayShort = ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];
const _gregorianWeekdayShortMonFirst = ['د', 'س', 'چ', 'پ', 'ج', 'ش', 'ی'];

/// اگر `dashboardColSpan` از داشبورد پاس داده شود و کمتر از این باشد، نمای فشرده (دو هفته اول) فعال می‌شود.
const int kCrmCalendarMiniColSpanThreshold = 6;

/// حداکثر سلول‌های شبکه در حالت مینی (دو ردیف × ۷).
const int kCrmCalendarMiniMaxCells = 14;

String _jalaliMonthName(int m) {
  const months = [
    '',
    'فروردین',
    'اردیبهشت',
    'خرداد',
    'تیر',
    'مرداد',
    'شهریور',
    'مهر',
    'آبان',
    'آذر',
    'دی',
    'بهمن',
    'اسفند',
  ];
  if (m >= 1 && m <= 12) return months[m];
  return '$m';
}

const _gregorianMonthsFa = [
  '',
  'ژانویه',
  'فوریه',
  'مارس',
  'آوریل',
  'مه',
  'ژوئن',
  'ژوئیه',
  'اوت',
  'سپتامبر',
  'اکتبر',
  'نوامبر',
  'دسامبر',
];

String _isoDate(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

/// نشانگر رویداد: در عرض کم فقط نقطه‌ها؛ در عرض بزرگتر بج عددی.
Widget _buildEventIndicator({
  required int count,
  required ThemeData theme,
  required bool ultraCompact,
  required bool compact,
}) {
  if (count <= 0) return const SizedBox.shrink();

  if (!ultraCompact) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 5,
        vertical: compact ? 2 : 1,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontSize: compact ? 10 : 9,
        ),
      ),
    );
  }

  const maxDots = 3;
  final shown = math.min(count, maxDots);
  const dot = 4.5;
  return Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0.5),
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        if (count > maxDots)
          Text(
            '+',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.primary,
              height: 1,
            ),
          ),
      ],
    ),
  );
}

void _showDayEventsSheet(BuildContext context, String dayKey, List<Map<String, dynamic>> items) {
  final theme = Theme.of(context);
  final count = items.length;

  const double minChild = 0.22;
  const double maxChild = 0.92;
  double initial;
  if (count <= 0) {
    initial = 0.28;
  } else if (count <= 2) {
    initial = 0.34;
  } else if (count <= 6) {
    initial = 0.42;
  } else {
    initial = (0.36 + count * 0.038).clamp(0.48, 0.78);
  }
  initial = initial.clamp(minChild, maxChild);

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: initial,
        minChildSize: minChild,
        maxChildSize: maxChild,
        builder: (sheetCtx, scrollController) {
          return Material(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text(
                      dayKey,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                if (items.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'رویدادی نیست.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final e = items[index];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              (e['kind']?.toString() == 'note')
                                  ? Icons.sticky_note_2_outlined
                                  : Icons.phone_callback_outlined,
                              size: 22,
                            ),
                            title: Text(
                              (e['title'] ?? e['activity_type'] ?? '-').toString(),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              (e['kind']?.toString() == 'note') ? 'یادداشت تقویم' : 'فعالیت',
                              style: theme.textTheme.bodySmall,
                            ),
                          );
                        },
                        childCount: items.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// ویجت تقویم CRM برای داشبورد (داده از batch API).
class CrmCalendarDashboardWidget extends StatefulWidget {
  final dynamic data;
  final bool isJalali;
  final void Function(int year, int month) onMonthChanged;

  /// اگر از داشبورد ست شود: با `colSpan < 6` نمای مینی (دو هفته) به‌صورت خودکار فعال می‌شود.
  final int? dashboardColSpan;

  const CrmCalendarDashboardWidget({
    super.key,
    required this.data,
    required this.isJalali,
    required this.onMonthChanged,
    this.dashboardColSpan,
  });

  @override
  State<CrmCalendarDashboardWidget> createState() => _CrmCalendarDashboardWidgetState();
}

class _CrmCalendarDashboardWidgetState extends State<CrmCalendarDashboardWidget> {
  int? _selectedDay;

  bool get _miniLayout {
    final s = widget.dashboardColSpan;
    if (s == null) return false;
    return s < kCrmCalendarMiniColSpanThreshold;
  }

  @override
  void didUpdateWidget(covariant CrmCalendarDashboardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _selectedDay = null;
    }
    if (oldWidget.dashboardColSpan != widget.dashboardColSpan) {
      _selectedDay = null;
    }
  }

  void _showDaySheet(BuildContext context, String dayKey, List<Map<String, dynamic>> items) {
    _showDayEventsSheet(context, dayKey, items);
  }

  void _showFullMonthBottomSheet({
    required BuildContext context,
    required ThemeData theme,
    required String monthTitle,
    required bool isJalali,
    required int dy,
    required int dm,
    required int monthLength,
    required int leadingBlanks,
    required List<String> weekdayLabels,
    required Map<String, List<Map<String, dynamic>>> itemsByDay,
    required Jalali todayJ,
    required DateTime todayG,
  }) {
    final screenH = MediaQuery.sizeOf(context).height;
    final sheetH = (screenH * 0.58).clamp(320.0, 560.0);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        return SizedBox(
          height: sheetH,
          child: Material(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$monthTitle — ماه کامل',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        tooltip: 'بستن',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return _buildMonthGrid(
                          context: context,
                          theme: theme,
                          gridW: constraints.maxWidth,
                          dy: dy,
                          dm: dm,
                          isJalali: isJalali,
                          monthLength: monthLength,
                          leadingBlanks: leadingBlanks,
                          weekdayLabels: weekdayLabels,
                          itemsByDay: itemsByDay,
                          todayJ: todayJ,
                          todayG: todayG,
                          maxCells: null,
                          showWeekdayHeader: true,
                          forceMiniSizing: false,
                          onDayTap: (day, dayKey, dayItems) {
                            setState(() => _selectedDay = day);
                            _showDaySheet(context, dayKey, dayItems);
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMonthGrid({
    required BuildContext context,
    required ThemeData theme,
    required double gridW,
    required int dy,
    required int dm,
    required bool isJalali,
    required int monthLength,
    required int leadingBlanks,
    required List<String> weekdayLabels,
    required Map<String, List<Map<String, dynamic>>> itemsByDay,
    required Jalali todayJ,
    required DateTime todayG,
    required int? maxCells,
    required bool showWeekdayHeader,
    required bool forceMiniSizing,
    required void Function(int day, String dayKey, List<Map<String, dynamic>> items) onDayTap,
  }) {
    const crossCount = 7;
    const mainSpacing = 3.0;
    const crossSpacing = 3.0;
    final mq = MediaQuery.of(context);
    final ultraCompact = gridW < 360 || forceMiniSizing;
    final isCompact = mq.size.width < 600 || forceMiniSizing;
    final totalCrossGaps = crossSpacing * (crossCount - 1);
    final cellW = math.max(8.0, (gridW - totalCrossGaps) / crossCount);
    final minCellH = isCompact ? (ultraCompact ? 36.0 : 40.0) : 34.0;
    final maxCellH = forceMiniSizing
        ? 44.0
        : (isCompact ? (ultraCompact ? 50.0 : 52.0) : 50.0);
    final idealH = ultraCompact ? cellW / 1.45 : cellW / 1.75;
    final cellH = idealH.clamp(minCellH, maxCellH);
    final aspectRatio = cellW / cellH;

    final totalCells = leadingBlanks + monthLength;
    final cellCount = maxCells == null ? totalCells : math.min(totalCells, maxCells);

    final weekdayStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      fontSize: isCompact ? (ultraCompact ? 10.5 : 11.5) : null,
    );
    final dayNumStyle = theme.textTheme.labelLarge?.copyWith(
      fontSize: isCompact ? (ultraCompact ? 12.0 : 14.0) : null,
    );

    final grid = GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        mainAxisSpacing: mainSpacing,
        crossAxisSpacing: crossSpacing,
        childAspectRatio: aspectRatio,
      ),
      itemCount: cellCount,
      itemBuilder: (context, index) {
        if (index < leadingBlanks) {
          return const SizedBox.shrink();
        }
        final day = index - leadingBlanks + 1;
        if (day < 1 || day > monthLength) {
          return const SizedBox.shrink();
        }
        late final String dayKey;
        var isToday = false;
        if (isJalali) {
          final j = Jalali(dy, dm, day);
          final dt = j.toDateTime();
          dayKey = _isoDate(dt);
          isToday = j.year == todayJ.year && j.month == todayJ.month && j.day == todayJ.day;
        } else {
          final dt = DateTime(dy, dm, day);
          dayKey = _isoDate(dt);
          isToday = dt.year == todayG.year && dt.month == todayG.month && dt.day == todayG.day;
        }

        final n = itemsByDay[dayKey]?.length ?? 0;
        final sel = _selectedDay == day;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onDayTap(day, dayKey, itemsByDay[dayKey] ?? const []),
            borderRadius: BorderRadius.circular(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: sel
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.65)
                    : isToday
                        ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.35)
                        : null,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$day',
                    style: dayNumStyle?.copyWith(
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  _buildEventIndicator(
                    count: n,
                    theme: theme,
                    ultraCompact: ultraCompact || forceMiniSizing,
                    compact: isCompact,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!showWeekdayHeader) return grid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (final w in weekdayLabels)
              Expanded(
                child: Text(
                  w,
                  textAlign: TextAlign.center,
                  style: weekdayStyle,
                ),
              ),
          ],
        ),
        SizedBox(height: isCompact ? 5 : 4),
        grid,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payload = (widget.data is Map<String, dynamic>) ? widget.data as Map<String, dynamic> : const <String, dynamic>{};

    if (payload['forbidden'] == true) {
      return Center(
        child: Text(
          'دسترسی به CRM برای مشاهدهٔ این ویجت لازم است.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
          textAlign: TextAlign.center,
        ),
      );
    }

    final err = payload['error'];
    if (err != null && err.toString().isNotEmpty && err != 'NO_CONTEXT') {
      return Center(child: Text('خطا: $err', style: theme.textTheme.bodySmall));
    }

    final dy = (payload['display_year'] as num?)?.toInt();
    final dm = (payload['display_month'] as num?)?.toInt();
    if (dy == null || dm == null) {
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }

    final rawEvents = payload['events'];
    final List<Map<String, dynamic>> events = rawEvents is List
        ? rawEvents.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : const <Map<String, dynamic>>[];

    final itemsByDay = <String, List<Map<String, dynamic>>>{};
    for (final e in events) {
      final d = e['day']?.toString();
      if (d == null || d.length < 8) continue;
      itemsByDay.putIfAbsent(d, () => []).add(e);
    }

    final isJalali = widget.isJalali;
    late final int monthLength;
    late final int leadingBlanks;
    late final List<String> weekdayLabels;

    if (isJalali) {
      final first = Jalali(dy, dm, 1);
      monthLength = first.monthLength;
      leadingBlanks = first.weekDay - 1;
      weekdayLabels = _jalaliWeekdayShort;
    } else {
      monthLength = DateTime(dy, dm + 1, 0).day;
      leadingBlanks = DateTime(dy, dm, 1).weekday - 1;
      weekdayLabels = _gregorianWeekdayShortMonFirst;
    }

    final monthTitle = isJalali ? '${_jalaliMonthName(dm)} $dy' : '${_gregorianMonthsFa[dm]} $dy';

    final todayJ = Jalali.now();
    final todayG = DateTime.now();
    final mq = MediaQuery.of(context);
    final isCompact = mq.size.width < 600;
    final mini = _miniLayout;
    final totalCells = leadingBlanks + monthLength;
    final maxCells = mini ? math.min(totalCells, kCrmCalendarMiniMaxCells) : null;
    final showFullMonthCta = mini && totalCells > (maxCells ?? 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridW = constraints.maxWidth;
        final titleStyle = mini
            ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)
            : (isCompact
                ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)
                : theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600));

        void onDayTap(int day, String dayKey, List<Map<String, dynamic>> items) {
          setState(() => _selectedDay = day);
          _showDaySheet(context, dayKey, items);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'ماه قبل',
                  constraints: mini || isCompact
                      ? const BoxConstraints(minWidth: 40, minHeight: 40)
                      : null,
                  padding: (mini || isCompact) ? EdgeInsets.zero : null,
                  iconSize: mini ? 22 : 24,
                  onPressed: () {
                    if (dm <= 1) {
                      widget.onMonthChanged(dy - 1, 12);
                    } else {
                      widget.onMonthChanged(dy, dm - 1);
                    }
                  },
                  icon: const Icon(Icons.chevron_right),
                ),
                Expanded(
                  child: Text(
                    monthTitle,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
                IconButton(
                  tooltip: 'ماه بعد',
                  constraints: mini || isCompact
                      ? const BoxConstraints(minWidth: 40, minHeight: 40)
                      : null,
                  padding: (mini || isCompact) ? EdgeInsets.zero : null,
                  iconSize: mini ? 22 : 24,
                  onPressed: () {
                    if (dm >= 12) {
                      widget.onMonthChanged(dy + 1, 1);
                    } else {
                      widget.onMonthChanged(dy, dm + 1);
                    }
                  },
                  icon: const Icon(Icons.chevron_left),
                ),
              ],
            ),
            Text(
              mini
                  ? (isJalali ? 'نمای فشرده · تقویم شمسی' : 'نمای فشرده · تقویم میلادی')
                  : (isJalali ? 'تقویم شمسی' : 'تقویم میلادی'),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
                fontSize: isCompact || mini ? 11 : null,
              ),
            ),
            SizedBox(height: isCompact || mini ? 6 : 6),
            _buildMonthGrid(
              context: context,
              theme: theme,
              gridW: gridW,
              dy: dy,
              dm: dm,
              isJalali: isJalali,
              monthLength: monthLength,
              leadingBlanks: leadingBlanks,
              weekdayLabels: weekdayLabels,
              itemsByDay: itemsByDay,
              todayJ: todayJ,
              todayG: todayG,
              maxCells: maxCells,
              showWeekdayHeader: true,
              forceMiniSizing: mini,
              onDayTap: onDayTap,
            ),
            if (showFullMonthCta) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  onPressed: () => _showFullMonthBottomSheet(
                    context: context,
                    theme: theme,
                    monthTitle: monthTitle,
                    isJalali: isJalali,
                    dy: dy,
                    dm: dm,
                    monthLength: monthLength,
                    leadingBlanks: leadingBlanks,
                    weekdayLabels: weekdayLabels,
                    itemsByDay: itemsByDay,
                    todayJ: todayJ,
                    todayG: todayG,
                  ),
                  icon: const Icon(Icons.calendar_view_month_outlined, size: 20),
                  label: const Text('مشاهدهٔ ماه کامل'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
