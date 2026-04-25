import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_note_editor_dialog.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';
import 'package:shamsi_date/shamsi_date.dart';

enum _CalViewMode { week, month }

/// تقویم یادداشت‌های CRM با هماهنگی شمسی/میلادی اپ و API
class CrmNotesCalendarPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const CrmNotesCalendarPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<CrmNotesCalendarPage> createState() => _CrmNotesCalendarPageState();
}

class _CrmNotesCalendarPageState extends State<CrmNotesCalendarPage> {
  static const double _kNarrowBreakpoint = 560;

  final CrmService _crm = CrmService(apiClient: ApiClient());
  late DateTime _monthStartLocal;

  List<dynamic> _noteTypes = [];
  List<dynamic> _notesMonth = [];
  final Map<String, int> _countByDay = {};
  bool _loading = true;
  String? _error;
  DateTime? _selectedDay;

  _CalViewMode _calView = _CalViewMode.week;

  static DateTime _onlyDate(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// شنبه = ستون اول (با الگوی سربرگ هفته در گرید ماه)
  DateTime _saturdayWeekStart(DateTime d) {
    final dt = _onlyDate(d);
    final wd = dt.weekday;
    final fromSat = (wd + 1) % 7;
    return dt.subtract(Duration(days: fromSat));
  }

  void _onSelectDay(DateTime day) {
    final n = _onlyDate(day);
    final monthChanged = _monthStartLocal.year != n.year || _monthStartLocal.month != n.month;
    setState(() {
      _selectedDay = n;
      if (monthChanged) {
        _monthStartLocal = _firstOfMonth(n);
      }
    });
    if (monthChanged) {
      _loadMonth();
    }
  }

  void _shiftWeek(int delta) {
    final base = _selectedDay ?? DateTime.now();
    final nw = base.add(Duration(days: 7 * delta));
    _onSelectDay(nw);
  }

  Future<void> _pickDay() async {
    final picked = await showAdaptiveDatePicker(
      context: context,
      calendarController: widget.calendarController,
      initialDate: _selectedDay ?? DateTime.now(),
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null && mounted) {
      _onSelectDay(picked);
    }
  }

  String _weekRangeLabel() {
    final isJ = widget.calendarController.isJalali;
    final sel = _selectedDay ?? DateTime.now();
    final start = _saturdayWeekStart(sel);
    final end = start.add(const Duration(days: 6));
    return '${HesabixDateUtils.formatForDisplay(start, isJ)} — ${HesabixDateUtils.formatForDisplay(end, isJ)}';
  }

  @override
  void initState() {
    super.initState();
    _monthStartLocal = _firstOfMonth(DateTime.now());
    _selectedDay = _onlyDate(DateTime.now());
    widget.calendarController.addListener(_onCalendarChanged);
    _loadTypes();
    _loadMonth();
  }

  @override
  void dispose() {
    widget.calendarController.removeListener(_onCalendarChanged);
    super.dispose();
  }

  void _onCalendarChanged() {
    if (mounted) setState(() {});
  }

  DateTime _firstOfMonth(DateTime dt) {
    final loc = DateTime(dt.year, dt.month, dt.day);
    if (widget.calendarController.isJalali) {
      final j = Jalali.fromDateTime(loc);
      return Jalali(j.year, j.month, 1).toDateTime();
    }
    return DateTime(loc.year, loc.month, 1);
  }

  void _shiftMonth(int delta) {
    if (widget.calendarController.isJalali) {
      final j = Jalali.fromDateTime(_monthStartLocal);
      int y = j.year;
      int m = j.month + delta;
      while (m < 1) {
        m += 12;
        y -= 1;
      }
      while (m > 12) {
        m -= 12;
        y += 1;
      }
      setState(() {
        _monthStartLocal = Jalali(y, m, 1).toDateTime();
      });
    } else {
      setState(() {
        final d = _monthStartLocal;
        _monthStartLocal = DateTime(d.year, d.month + delta, 1);
      });
    }
    _loadMonth();
  }

  void _goToday() {
    setState(() {
      final now = DateTime.now();
      _monthStartLocal = _firstOfMonth(now);
      _selectedDay = _onlyDate(now);
    });
    _loadMonth();
  }

  Future<void> _loadTypes() async {
    try {
      final items = await _crm.listCrmNoteTypes(businessId: widget.businessId);
      if (!mounted) return;
      setState(() => _noteTypes = items);
    } catch (_) {}
  }

  Future<void> _loadMonth() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final range = _monthGregorianRange();
      final fromS = HesabixDateUtils.formatForApiDate(range.$1);
      final toS = HesabixDateUtils.formatForApiDate(range.$2);
      final list = await _crm.listCrmNotes(
        businessId: widget.businessId,
        fromDate: fromS,
        toDate: toS,
      );
      if (!mounted) return;
      final counts = <String, int>{};
      for (final raw in list) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final key = (m['occurs_on_raw'] ?? m['occurs_on'] ?? '').toString();
        String? dayKey;
        if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(key)) {
          dayKey = key.substring(0, 10);
        }
        if (dayKey != null) {
          counts[dayKey] = (counts[dayKey] ?? 0) + 1;
        }
      }
      setState(() {
        _notesMonth = list;
        _countByDay
          ..clear()
          ..addAll(counts);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorExtractor.forContext(e, context);
      });
    }
  }

  /// اولین و آخرین روز ماه نمایش داده‌شده (میلادی محلی) برای API
  (DateTime, DateTime) _monthGregorianRange() {
    if (widget.calendarController.isJalali) {
      final j = Jalali.fromDateTime(_monthStartLocal);
      final first = Jalali(j.year, j.month, 1).toDateTime();
      final last = Jalali(j.year, j.month, j.monthLength).toDateTime();
      return (DateTime(first.year, first.month, first.day), DateTime(last.year, last.month, last.day));
    }
    final d = _monthStartLocal;
    final lastDay = DateTime(d.year, d.month + 1, 0).day;
    return (
      DateTime(d.year, d.month, 1),
      DateTime(d.year, d.month, lastDay),
    );
  }

  String _monthTitle() {
    if (widget.calendarController.isJalali) {
      final j = Jalali.fromDateTime(_monthStartLocal);
      return HesabixDateUtils.formatForDisplayWithMonthName(
        Jalali(j.year, j.month, 15).toDateTime(),
        true,
      );
    }
    return HesabixDateUtils.formatForDisplayWithMonthName(_monthStartLocal, false);
  }

  List<String> _weekdayHeaders(String lang) {
    if (lang.startsWith('fa')) {
      return const ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];
    }
    return const ['Sa', 'Su', 'Mo', 'Tu', 'We', 'Th', 'Fr'];
  }

  int _leadingBlanksForMonthStart() {
    final first = widget.calendarController.isJalali
        ? Jalali.fromDateTime(_monthStartLocal)
        : null;
    final DateTime gregFirst = widget.calendarController.isJalali
        ? Jalali(first!.year, first.month, 1).toDateTime()
        : DateTime(_monthStartLocal.year, _monthStartLocal.month, 1);
    final wd = gregFirst.weekday;
    return (wd + 1) % 7;
  }

  int _daysInShownMonth() {
    if (widget.calendarController.isJalali) {
      final j = Jalali.fromDateTime(_monthStartLocal);
      return Jalali(j.year, j.month, 1).monthLength;
    }
    return DateTime(_monthStartLocal.year, _monthStartLocal.month + 1, 0).day;
  }

  DateTime _cellDate(int dayIndex1Based) {
    if (widget.calendarController.isJalali) {
      final j = Jalali.fromDateTime(_monthStartLocal);
      return Jalali(j.year, j.month, dayIndex1Based).toDateTime();
    }
    return DateTime(_monthStartLocal.year, _monthStartLocal.month, dayIndex1Based);
  }

  String _dayKey(DateTime dt) {
    return HesabixDateUtils.formatForApiDate(DateTime(dt.year, dt.month, dt.day));
  }

  Iterable<Map<String, dynamic>> _notesForDay(DateTime day) sync* {
    final key = _dayKey(day);
    for (final raw in _notesMonth) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final rk = (m['occurs_on_raw'] ?? '').toString();
      if (rk.length >= 10 && rk.substring(0, 10) == key) {
        yield m;
      }
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showAdaptiveDatePicker(
      context: context,
      calendarController: widget.calendarController,
      initialDate: _monthStartLocal,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null && mounted) {
      final DateTime p = picked;
      setState(() {
        _monthStartLocal = _firstOfMonth(p);
        _selectedDay = _onlyDate(p);
      });
      _loadMonth();
    }
  }

  Widget _buildNoteCard(BuildContext context, AppLocalizations t, Map<String, dynamic> m) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final typeTitle = (m['note_type_title'] ?? '').toString();
    final title = (m['title'] ?? '').toString();
    final body = (m['body'] ?? '').toString();
    final visibility = (m['visibility'] ?? 'business_public').toString();
    final scheduling = (m['scheduling_mode'] ?? 'day_only').toString();
    final IconData visIcon = switch (visibility) {
      'private' => Icons.lock_outline,
      'shared' => Icons.person_search_outlined,
      _ => Icons.groups_2_outlined,
    };
    String? timeLine;
    if (scheduling == 'meeting') {
      final raw = (m['starts_at_raw'] ?? m['starts_at'] ?? '').toString();
      final dt = DateTime.tryParse(raw);
      if (dt != null) {
        timeLine = HesabixDateUtils.formatDateTime(dt, widget.calendarController.isJalali);
      }
    }
    final headline = title.isNotEmpty ? title : typeTitle;
    final sub = title.isNotEmpty && body.isNotEmpty
        ? body
        : (title.isNotEmpty ? '' : body);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cs.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openNoteEditor(existing: m),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (typeTitle.isNotEmpty)
                            Chip(
                              label: Text(typeTitle, style: theme.textTheme.labelMedium),
                              padding: EdgeInsets.zero,
                              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              backgroundColor: Color.lerp(cs.primaryContainer, cs.surface, 0.25),
                              side: BorderSide.none,
                            ),
                          Icon(visIcon, size: 17, color: cs.onSurfaceVariant),
                          if (scheduling == 'meeting' && timeLine != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.schedule, size: 15, color: cs.primary),
                                const SizedBox(width: 4),
                                Text(
                                  timeLine,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                  ],
                ),
                if (headline.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    headline,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    sub,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDaySection(BuildContext context, AppLocalizations t) {
    final day = _selectedDay!;
    final items = _notesForDay(day).toList();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final canWrite = widget.authStore.canWriteSection('crm');
    if (items.isEmpty) {
      return [
        Text(t.crmNotesDayNotes, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Icon(Icons.note_add_outlined, size: 52, color: cs.outline),
                const SizedBox(height: 12),
                Text(
                  t.crmNotesEmptyDayHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (canWrite) ...[
                  const SizedBox(height: 18),
                  FilledButton.tonalIcon(
                    onPressed: () => _openNoteEditor(presetDay: day),
                    icon: const Icon(Icons.add_comment_outlined),
                    label: Text(t.crmNotesAdd),
                  ),
                ],
              ],
            ),
          ),
        ),
      ];
    }
    return [
      Text(t.crmNotesDayNotes, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      ...items.map((m) => _buildNoteCard(context, t, Map<String, dynamic>.from(m))),
    ];
  }

  Future<void> _openNoteEditor({Map<String, dynamic>? existing, DateTime? presetDay}) async {
    final t = AppLocalizations.of(context);
    final noteId = existing == null ? null : (existing['id'] as num?)?.toInt();
    if (noteId != null) {
      try {
        final full = await _crm.getCrmNote(businessId: widget.businessId, noteId: noteId);
        if (!mounted) return;
        await showCrmNoteEditorDialog(
          context,
          businessId: widget.businessId,
          authStore: widget.authStore,
          calendarController: widget.calendarController,
          noteTypes: _noteTypes,
          existing: full,
          presetDay: null,
          onSaved: () {
            _loadMonth();
            _loadTypes();
          },
        );
      } catch (e) {
        SnackBarHelper.show(
          context,
          message: '${t.crmNotesErrorLoading}: ${ErrorExtractor.forContext(e, context)}',
          isError: true,
        );
      }
      return;
    }
    await showCrmNoteEditorDialog(
      context,
      businessId: widget.businessId,
      authStore: widget.authStore,
      calendarController: widget.calendarController,
      noteTypes: _noteTypes,
      existing: null,
      presetDay: presetDay ?? _selectedDay ?? DateTime.now(),
      onSaved: () {
        _loadMonth();
        _loadTypes();
      },
    );
  }

  Widget _buildMonthGrid(
    BuildContext context, {
    required int blanks,
    required int dim,
    required double aspect,
    required AppLocalizations t,
    required ThemeData theme,
    required ColorScheme cs,
  }) {
    final lang = Localizations.localeOf(context).languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: _weekdayHeaders(lang)
              .map(
                (wd) => Expanded(
                  child: Center(
                    child: Text(
                      wd,
                      style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 11),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: aspect,
          ),
          itemCount: blanks + dim,
          itemBuilder: (context, index) {
            if (index < blanks) {
              return const SizedBox.shrink();
            }
            final dayNum = index - blanks + 1;
            final cell = _cellDate(dayNum);
            final k = _dayKey(cell);
            final n = _countByDay[k] ?? 0;
            final sel = _selectedDay != null && _dayKey(_selectedDay!) == k;
            final isToday = _sameDay(cell, DateTime.now());
            final isFriday = cell.weekday == DateTime.friday;
            Color? cellBg;
            if (sel) {
              cellBg = cs.primaryContainer.withValues(alpha: 0.5);
            } else if (isFriday) {
              cellBg = cs.surfaceContainerHighest.withValues(alpha: 0.4);
            }
            final borderColor = isToday ? cs.primary : cs.outlineVariant.withValues(alpha: 0.55);
            final borderW = isToday ? 2.0 : 1.0;
            final tip = isToday ? '${t.crmNotesToday} · $dayNum' : '$dayNum';
            return Tooltip(
              message: tip,
              child: Material(
                color: cellBg,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _onSelectDay(cell),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor, width: borderW),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$dayNum',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 13,
                            color: isToday ? cs.primary : null,
                          ),
                        ),
                        if (n > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: cs.primary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$n',
                                style: TextStyle(color: cs.onPrimary, fontSize: 9, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildWeekStrip(BuildContext context, AppLocalizations t) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final lang = Localizations.localeOf(context).languageCode;
    final headers = _weekdayHeaders(lang);
    final sel = _selectedDay ?? DateTime.now();
    final start = _saturdayWeekStart(sel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: List.generate(7, (i) {
            return Expanded(
              child: Center(
                child: Text(
                  headers[i],
                  style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 10),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 46,
          child: Row(
            children: List.generate(7, (i) {
              final cell = start.add(Duration(days: i));
              final k = _dayKey(cell);
              final n = _countByDay[k] ?? 0;
              final selected = _selectedDay != null && _dayKey(_selectedDay!) == k;
              final isToday = _sameDay(cell, DateTime.now());
              final borderColor = isToday ? cs.primary : cs.outlineVariant.withValues(alpha: 0.55);
              final borderW = isToday ? 2.0 : 1.0;
              Color? bg;
              if (selected) {
                bg = cs.primaryContainer.withValues(alpha: 0.55);
              } else if (cell.weekday == DateTime.friday) {
                bg = cs.surfaceContainerHighest.withValues(alpha: 0.35);
              }
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Tooltip(
                    message: HesabixDateUtils.formatForDisplay(cell, widget.calendarController.isJalali),
                    child: Material(
                      color: bg,
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _onSelectDay(cell),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor, width: borderW),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${cell.day}',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                                  fontSize: 13,
                                  color: isToday ? cs.primary : null,
                                ),
                              ),
                              if (n > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$n',
                                      style: TextStyle(color: cs.onPrimary, fontSize: 8, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedDayCard(BuildContext context, AppLocalizations t) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final d = _selectedDay;
    if (d == null) return const SizedBox.shrink();
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _pickDay,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.edit_calendar_outlined, color: cs.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.crmNotesPickDayTooltip,
                      style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    Text(
                      HesabixDateUtils.formatForDisplay(d, widget.calendarController.isJalali),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: t.crmNotesPickDayTooltip,
                onPressed: _pickDay,
                icon: const Icon(Icons.calendar_month_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, AppLocalizations t) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 52, color: cs.error),
              const SizedBox(height: 16),
              Text(
                t.crmNotesErrorLoading,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? '',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadMonth,
                icon: const Icon(Icons.refresh),
                label: Text(t.crmNotesRetry),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!widget.authStore.canReadSection('crm')) {
      return AccessDeniedPage(message: t.accessDenied);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.crmNotesCalendarTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) context.pop();
          },
        ),
        actions: [
          IconButton(onPressed: _goToday, tooltip: t.crmNotesToday, icon: const Icon(Icons.today_outlined)),
          IconButton(onPressed: _loadMonth, tooltip: t.crmNotesRefresh, icon: const Icon(Icons.refresh)),
          if (widget.authStore.canWriteSection('crm'))
            IconButton(
              onPressed: () => _openNoteEditor(presetDay: _selectedDay ?? DateTime.now()),
              tooltip: t.crmNotesAdd,
              icon: const Icon(Icons.add_comment_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState(context, t)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < _kNarrowBreakpoint;
                    final padW = constraints.maxWidth - 24;
                    final monthAspect = padW < 340 ? 1.56 : (padW < 480 ? 1.68 : 1.78);
                    final blanks = _leadingBlanksForMonthStart();
                    final dim = _daysInShownMonth();
                    final theme = Theme.of(context);
                    final cs = theme.colorScheme;

                    final toggle = Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SegmentedButton<_CalViewMode>(
                        segments: [
                          ButtonSegment(
                            value: _CalViewMode.week,
                            label: Text(t.crmNotesViewWeek),
                            icon: const Icon(Icons.view_week_outlined, size: 18),
                          ),
                          ButtonSegment(
                            value: _CalViewMode.month,
                            label: Text(t.crmNotesViewMonth),
                            icon: const Icon(Icons.calendar_month_outlined, size: 18),
                          ),
                        ],
                        selected: {_calView},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) {
                          if (s.isEmpty) return;
                          setState(() => _calView = s.first);
                        },
                      ),
                    );

                    final navRow = _calView == _CalViewMode.week
                        ? Row(
                            children: [
                              IconButton(
                                onPressed: () => _shiftWeek(-1),
                                tooltip: t.crmNotesWeekPrev,
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Expanded(
                                child: Text(
                                  _weekRangeLabel(),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                onPressed: () => _shiftWeek(1),
                                tooltip: t.crmNotesWeekNext,
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              IconButton(
                                onPressed: () => _shiftMonth(-1),
                                tooltip: t.crmNotesMonthPrev,
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: _pickMonth,
                                  child: Text(
                                    _monthTitle(),
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => _shiftMonth(1),
                                tooltip: t.crmNotesMonthNext,
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          );

                    final notes = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_selectedDay != null) ..._buildDaySection(context, t),
                      ],
                    );

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          toggle,
                          navRow,
                          const SizedBox(height: 8),
                          if (_calView == _CalViewMode.week) ...[
                            _buildWeekStrip(context, t),
                            const SizedBox(height: 12),
                          ],
                          if (!narrow && _calView == _CalViewMode.month) ...[
                            _buildMonthGrid(
                              context,
                              blanks: blanks,
                              dim: dim,
                              aspect: monthAspect,
                              t: t,
                              theme: theme,
                              cs: cs,
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (narrow && _calView == _CalViewMode.month) ...[
                            _buildSelectedDayCard(context, t),
                            const SizedBox(height: 12),
                          ],
                          notes,
                          if (narrow && _calView == _CalViewMode.month) ...[
                            const SizedBox(height: 8),
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(t.crmNotesMonthCalendarExpandTitle),
                              childrenPadding: const EdgeInsets.only(bottom: 8),
                              children: [
                                _buildMonthGrid(
                                  context,
                                  blanks: blanks,
                                  dim: dim,
                                  aspect: monthAspect + 0.06,
                                  t: t,
                                  theme: theme,
                                  cs: cs,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

