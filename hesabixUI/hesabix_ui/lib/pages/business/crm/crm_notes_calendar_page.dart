import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_note_editor_dialog.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';
import 'package:shamsi_date/shamsi_date.dart';

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
  final CrmService _crm = CrmService(apiClient: ApiClient());
  late DateTime _monthStartLocal;

  List<dynamic> _noteTypes = [];
  List<dynamic> _notesMonth = [];
  final Map<String, int> _countByDay = {};
  bool _loading = true;
  String? _error;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _monthStartLocal = _firstOfMonth(DateTime.now());
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
      _monthStartLocal = _firstOfMonth(DateTime.now());
      _selectedDay = DateTime.now();
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
        final m = Map<String, dynamic>.from(raw as Map);
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
        _error = e.toString();
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
      final m = Map<String, dynamic>.from(raw as Map);
      final rk = (m['occurs_on_raw'] ?? '').toString();
      if (rk.length >= 10 && rk.substring(0, 10) == key) {
        yield m;
      }
    }
  }

  Future<void> _pickMonth() async {
    final isJ = widget.calendarController.isJalali;
    DateTime? picked;
    if (isJ) {
      picked = await showJalaliDatePicker(
        context: context,
        initialDate: _monthStartLocal,
        firstDate: DateTime(DateTime.now().year - 5),
        lastDate: DateTime(DateTime.now().year + 5),
      );
    } else {
      picked = await showDatePicker(
        context: context,
        initialDate: _monthStartLocal,
        firstDate: DateTime(DateTime.now().year - 5),
        lastDate: DateTime(DateTime.now().year + 5),
        locale: const Locale('en', 'GB'),
      );
    }
    if (picked != null && mounted) {
      final month = picked;
      setState(() => _monthStartLocal = _firstOfMonth(month));
      _loadMonth();
    }
  }

  List<Widget> _buildDaySection(BuildContext context, AppLocalizations t) {
    final day = _selectedDay!;
    final items = _notesForDay(day).toList();
    if (items.isEmpty) {
      return [
        Text(t.crmNotesDayNotes, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(t.crmNotesNoNotes),
      ];
    }
    return [
      Text(t.crmNotesDayNotes, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      ...items.map((m) {
        final title = (m['title'] ?? m['note_type_title'] ?? '').toString();
        final body = (m['body'] ?? '').toString();
        return ListTile(
          dense: true,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(10),
          ),
          title: Text(title.isEmpty ? (m['note_type_title'] ?? '').toString() : title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openNoteEditor(existing: m),
        );
      }),
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
        SnackBarHelper.show(context, message: '${t.crmNotesErrorLoading}: $e', isError: true);
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!widget.authStore.canReadSection('crm')) {
      return AccessDeniedPage(message: t.accessDenied);
    }
    final blanks = _leadingBlanksForMonthStart();
    final dim = _daysInShownMonth();

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
              ? Center(child: Text('${t.crmNotesErrorLoading}: $_error'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(onPressed: () => _shiftMonth(-1), tooltip: t.crmNotesMonthPrev, icon: const Icon(Icons.chevron_left)),
                          Expanded(
                            child: InkWell(
                              onTap: _pickMonth,
                              child: Text(
                                _monthTitle(),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ),
                          IconButton(onPressed: () => _shiftMonth(1), tooltip: t.crmNotesMonthNext, icon: const Icon(Icons.chevron_right)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children:
                            _weekdayHeaders(Localizations.localeOf(context).languageCode)
                                .map((w) => Expanded(child: Center(child: Text(w, style: Theme.of(context).textTheme.labelSmall))))
                                .toList(),
                      ),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 1.1),
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
                          return InkWell(
                            onTap: () {
                              setState(() => _selectedDay = DateTime(cell.year, cell.month, cell.day));
                            },
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: sel ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
                                border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('$dayNum', style: Theme.of(context).textTheme.titleSmall),
                                  if (n > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.primary,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '$n',
                                          style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 10),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_selectedDay != null) ..._buildDaySection(context, t),
                    ],
                  ),
                ),
    );
  }
}

