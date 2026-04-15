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
    final lang = Localizations.localeOf(context).languageCode;
    final noteId = existing == null ? null : (existing['id'] as num?)?.toInt();
    if (noteId != null) {
      try {
        final full = await _crm.getCrmNote(businessId: widget.businessId, noteId: noteId);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _CrmNoteEditorDialog(
            businessId: widget.businessId,
            authStore: widget.authStore,
            calendarController: widget.calendarController,
            noteTypes: _noteTypes,
            existing: full,
            presetDay: null,
            lang: lang,
            t: t,
            onSaved: () {
                _loadMonth();
                _loadTypes();
              },
          ),
        );
      } catch (e) {
        SnackBarHelper.show(context, message: '${t.crmNotesErrorLoading}: $e', isError: true);
      }
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CrmNoteEditorDialog(
        businessId: widget.businessId,
        authStore: widget.authStore,
        calendarController: widget.calendarController,
        noteTypes: _noteTypes,
        existing: null,
        presetDay: presetDay ?? _selectedDay ?? DateTime.now(),
        lang: lang,
        t: t,
        onSaved: () {
          _loadMonth();
          _loadTypes();
        },
      ),
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

class _CrmNoteEditorDialog extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;
  final List<dynamic> noteTypes;
  final Map<String, dynamic>? existing;
  final DateTime? presetDay;
  final String lang;
  final AppLocalizations t;
  final VoidCallback onSaved;

  const _CrmNoteEditorDialog({
    required this.businessId,
    required this.authStore,
    required this.calendarController,
    required this.noteTypes,
    required this.existing,
    required this.presetDay,
    required this.lang,
    required this.t,
    required this.onSaved,
  });

  @override
  State<_CrmNoteEditorDialog> createState() => _CrmNoteEditorDialogState();
}

class _CrmNoteEditorDialogState extends State<_CrmNoteEditorDialog> {
  final CrmService _crm = CrmService(apiClient: ApiClient());
  final BusinessDashboardService _membersSvc = BusinessDashboardService(ApiClient());

  int? _typeId;
  String _visibility = 'business_public';
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  DateTime? _occursOn;
  DateTime? _startAt;
  DateTime? _endAt;
  int? _leadId;
  String _leadLabel = '';
  final Set<int> _sharedIds = {};
  List<Map<String, dynamic>> _members = [];
  bool _saving = false;
  List<dynamic> _comments = [];
  List<dynamic> _audit = [];
  final _commentCtrl = TextEditingController();
  late List<dynamic> _noteTypesList;

  String _schedulingModeForType(int? tid) {
    for (final raw in _noteTypesList) {
      if (raw is Map && (raw['id'] as num?)?.toInt() == tid) {
        return (raw['scheduling_mode'] ?? 'day_only').toString();
      }
    }
    return 'day_only';
  }

  @override
  void initState() {
    super.initState();
    _noteTypesList = List<dynamic>.from(widget.noteTypes);
    final e = widget.existing;
    if (e != null) {
      _typeId = (e['note_type_id'] as num?)?.toInt();
      _visibility = (e['visibility'] ?? 'business_public').toString();
      _titleCtrl.text = (e['title'] ?? '').toString();
      _bodyCtrl.text = (e['body'] ?? '').toString();
      final rawDay = (e['occurs_on_raw'] ?? '').toString();
      _occursOn = rawDay.length >= 10 ? HesabixDateUtils.parseFromAPI(rawDay.substring(0, 10)) : null;
      final sRaw = (e['starts_at_raw'] ?? e['starts_at'] ?? '').toString();
      _startAt = DateTime.tryParse(sRaw);
      final eRaw = (e['ends_at_raw'] ?? e['ends_at'] ?? '').toString();
      _endAt = DateTime.tryParse(eRaw);
      _leadId = (e['lead_id'] as num?)?.toInt();
      if (_leadId != null) {
        final cn = (e['lead_code'] ?? '').toString();
        final nm = (e['lead_name'] ?? '').toString();
        _leadLabel = cn.isNotEmpty ? '$cn — $nm' : nm;
      }
      final sh = e['shared_user_ids'];
      if (sh is List) {
        for (final x in sh) {
          if (x is int) _sharedIds.add(x);
          if (x is num) _sharedIds.add(x.toInt());
        }
      }
      _loadThread();
    } else {
      _occursOn = widget.presetDay != null
          ? DateTime(widget.presetDay!.year, widget.presetDay!.month, widget.presetDay!.day)
          : DateTime.now();
      if (_noteTypesList.isNotEmpty && _noteTypesList.first is Map) {
        _typeId = ((_noteTypesList.first as Map)['id'] as num?)?.toInt();
      }
    }
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      final res = await _membersSvc.getMembers(widget.businessId);
      if (!mounted) return;
      setState(() {
        _members = res.items.map((e) => {'user_id': e.userId, 'name': '${e.firstName} ${e.lastName}'.trim()}).toList();
      });
    } catch (_) {}
  }

  Future<void> _loadThread() async {
    final id = (widget.existing?['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      final com = await _crm.listCrmNoteComments(businessId: widget.businessId, noteId: id);
      final au = await _crm.listCrmNoteAudit(businessId: widget.businessId, noteId: id);
      if (!mounted) return;
      setState(() {
        _comments = com;
        _audit = au;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  String _normalizeNoteTypeCode(String raw) {
    var s = raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    return s;
  }

  Future<DateTime?> _pickMeetingDateTime({DateTime? initial}) async {
    final isJ = widget.calendarController.isJalali;
    final base = initial ?? DateTime.now();
    DateTime? day;
    if (isJ) {
      final p = await showJalaliDatePicker(
        context: context,
        initialDate: base,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (p == null || !mounted) return null;
      day = DateTime(p.year, p.month, p.day);
    } else {
      final p = await showDatePicker(
        context: context,
        initialDate: base,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        locale: const Locale('en', 'GB'),
      );
      if (p == null || !mounted) return null;
      day = DateTime(p.year, p.month, p.day);
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? day),
    );
    if (time == null || !mounted) return null;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  Future<void> _openCreateNoteType() async {
    if (!widget.authStore.canWriteSection('crm')) return;
    final codeCtrl = TextEditingController();
    final faCtrl = TextEditingController();
    final enCtrl = TextEditingController();
    String sched = 'day_only';
    bool allowComments = true;
    Map<String, dynamic>? payload;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text(widget.t.crmNotesAddNoteType),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: codeCtrl,
                      decoration: InputDecoration(labelText: widget.t.crmNotesNoteTypeCode),
                    ),
                    TextField(
                      controller: faCtrl,
                      decoration: InputDecoration(labelText: widget.t.crmNotesNoteTypeTitleFa),
                    ),
                    TextField(
                      controller: enCtrl,
                      decoration: InputDecoration(labelText: widget.t.crmNotesNoteTypeTitleEn),
                    ),
                    DropdownButtonFormField<String>(
                      value: sched,
                      decoration: InputDecoration(labelText: widget.t.crmNotesNoteTypeScheduling),
                      items: [
                        DropdownMenuItem(value: 'day_only', child: Text(widget.t.crmNotesNoteTypeDayOnly)),
                        DropdownMenuItem(value: 'meeting', child: Text(widget.t.crmNotesNoteTypeMeeting)),
                      ],
                      onChanged: (v) => setLocal(() => sched = v ?? 'day_only'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(widget.t.crmNotesNoteTypeAllowComments),
                      value: allowComments,
                      onChanged: (v) => setLocal(() => allowComments = v),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(widget.t.crmNotesClose)),
              FilledButton(
                onPressed: () {
                  final code = _normalizeNoteTypeCode(codeCtrl.text);
                  if (code.isEmpty) {
                    SnackBarHelper.show(context, message: widget.t.crmNotesNoteTypeCode, isError: true);
                    return;
                  }
                  if (faCtrl.text.trim().isEmpty || enCtrl.text.trim().isEmpty) {
                    SnackBarHelper.show(context, message: widget.t.crmNotesNoteTypeTitleEn, isError: true);
                    return;
                  }
                  payload = {
                    'code': code,
                    'title_i18n': {'fa': faCtrl.text.trim(), 'en': enCtrl.text.trim()},
                    'scheduling_mode': sched,
                    'allow_comments': allowComments,
                  };
                  Navigator.pop(ctx);
                },
                child: Text(widget.t.crmNotesSave),
              ),
            ],
          );
        },
      ),
    );
    codeCtrl.dispose();
    faCtrl.dispose();
    enCtrl.dispose();
    if (payload == null || !mounted) return;
    var maxSort = 0;
    for (final raw in _noteTypesList) {
      if (raw is Map && raw['sort_order'] is num) {
        final s = (raw['sort_order'] as num).toInt();
        if (s > maxSort) maxSort = s;
      }
    }
    payload!['sort_order'] = maxSort + 10;
    try {
      final created = await _crm.createCrmNoteType(businessId: widget.businessId, body: payload!);
      final list = await _crm.listCrmNoteTypes(businessId: widget.businessId);
      if (!mounted) return;
      final newId = (created['id'] as num?)?.toInt();
      setState(() {
        _noteTypesList = list;
        if (newId != null) {
          _typeId = newId;
          if (_schedulingModeForType(newId) == 'meeting' && _startAt == null && _occursOn != null) {
            _startAt = DateTime(_occursOn!.year, _occursOn!.month, _occursOn!.day, 9);
          }
        }
      });
      SnackBarHelper.show(context, message: widget.t.crmNotesNoteTypeCreated);
    } catch (e) {
      if (mounted) SnackBarHelper.show(context, message: '${widget.t.crmNotesErrorSaving}: $e', isError: true);
    }
  }

  Future<void> _pickDate() async {
    final isJ = widget.calendarController.isJalali;
    DateTime? p;
    if (isJ) {
      p = await showJalaliDatePicker(
        context: context,
        initialDate: _occursOn ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
    } else {
      p = await showDatePicker(
        context: context,
        initialDate: _occursOn ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        locale: const Locale('en', 'GB'),
      );
    }
    if (p != null && mounted) setState(() => _occursOn = DateTime(p!.year, p.month, p.day));
  }

  Future<void> _pickLead() async {
    final ctrl = TextEditingController();
    final q = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.t.crmNotesSearchLeads),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: widget.t.crmNotesSearchLeads),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(widget.t.crmNotesClose)),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(widget.t.crmNotesApplySearch)),
        ],
      ),
    );
    if (q == null || q.isEmpty || !mounted) return;
    try {
      final data = await _crm.listLeads(businessId: widget.businessId, search: q, limit: 20);
      final items = (data['items'] is List) ? data['items'] as List<dynamic> : <dynamic>[];
      if (!mounted) return;
      if (items.isEmpty) {
        SnackBarHelper.show(context, message: widget.t.crmNotesNoNotes);
        return;
      }
      final chosen = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(widget.t.crmNotesLeadOptional),
          children: items.map((raw) {
            final m = Map<String, dynamic>.from(raw as Map);
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: ListTile(
                title: Text((m['name'] ?? '').toString()),
                subtitle: Text((m['code'] ?? '').toString()),
              ),
            );
          }).toList(),
        ),
      );
      if (chosen != null && mounted) {
        setState(() {
          _leadId = (chosen['id'] as num?)?.toInt();
          _leadLabel = '${chosen['code'] ?? ''} — ${chosen['name'] ?? ''}';
        });
      }
    } catch (e) {
      if (mounted) SnackBarHelper.show(context, message: '$e', isError: true);
    }
  }

  Future<void> _save() async {
    final mode = _schedulingModeForType(_typeId);
    if (_typeId == null) {
      SnackBarHelper.show(context, message: widget.t.crmNotesType, isError: true);
      return;
    }
    if (_bodyCtrl.text.trim().isEmpty) {
      SnackBarHelper.show(context, message: widget.t.crmNotesBody, isError: true);
      return;
    }
    if (mode == 'day_only' && _occursOn == null) {
      SnackBarHelper.show(context, message: widget.t.crmNotesDayNotes, isError: true);
      return;
    }
    if (_visibility == 'shared' && _sharedIds.isEmpty) {
      SnackBarHelper.show(context, message: widget.t.crmNotesSharedUsers, isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'note_type_id': _typeId,
        'visibility': _visibility,
        'title': _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
        'body': _bodyCtrl.text.trim(),
        if (mode == 'day_only' && _occursOn != null) 'occurs_on': HesabixDateUtils.formatForApiDate(_occursOn!),
        if (mode == 'meeting' && _startAt != null) 'starts_at': _startAt!.toIso8601String(),
        if (mode == 'meeting' && _endAt != null) 'ends_at': _endAt!.toIso8601String(),
        if (_leadId != null) 'lead_id': _leadId,
        if (_visibility == 'shared') 'shared_user_ids': _sharedIds.toList(),
      };
      final existingId = (widget.existing?['id'] as num?)?.toInt();
      if (existingId == null) {
        await _crm.createCrmNote(businessId: widget.businessId, body: body);
      } else {
        final patch = Map<String, dynamic>.from(body);
        final hadLead = (widget.existing?['lead_id'] as num?) != null;
        if (hadLead && _leadId == null) {
          patch['clear_lead'] = true;
        }
        await _crm.updateCrmNote(businessId: widget.businessId, noteId: existingId, body: patch);
      }
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: '${widget.t.crmNotesErrorSaving}: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final id = (widget.existing?['id'] as num?)?.toInt();
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.t.crmNotesDelete),
        content: Text(widget.t.crmNotesDeleteConfirmMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(widget.t.crmNotesClose)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(widget.t.crmNotesDelete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _crm.deleteCrmNote(businessId: widget.businessId, noteId: id);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } catch (e) {
      SnackBarHelper.show(context, message: '$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = (widget.existing?['id'] as num?)?.toInt();
    final mode = _schedulingModeForType(_typeId);
    final commentsOn = widget.existing?['comments_enabled'] == true;
    final canWrite = widget.authStore.canWriteSection('crm');

    return AlertDialog(
      title: Text(id == null ? widget.t.crmNotesAdd : widget.t.crmNotesEdit),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _typeId,
                      decoration: InputDecoration(labelText: widget.t.crmNotesType),
                      isExpanded: true,
                      items: _noteTypesList.map((raw) {
                        if (raw is! Map) return null;
                        final m = Map<String, dynamic>.from(raw as Map);
                        final tid = (m['id'] as num?)?.toInt();
                        final label = (m['title'] ?? m['code'] ?? '').toString();
                        return DropdownMenuItem(value: tid, child: Text(label));
                      }).whereType<DropdownMenuItem<int>>().toList(),
                      onChanged: canWrite
                          ? (v) => setState(() {
                                _typeId = v;
                                if (_schedulingModeForType(v) == 'meeting' && _startAt == null && _occursOn != null) {
                                  _startAt = DateTime(_occursOn!.year, _occursOn!.month, _occursOn!.day, 9);
                                }
                              })
                          : null,
                    ),
                  ),
                  if (canWrite) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: widget.t.crmNotesAddNoteType,
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _openCreateNoteType,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _visibility,
                decoration: InputDecoration(labelText: widget.t.crmNotesVisibilityLabel),
                items: [
                  DropdownMenuItem(value: 'private', child: Text(widget.t.crmNotesVisibilityPrivate)),
                  DropdownMenuItem(value: 'business_public', child: Text(widget.t.crmNotesVisibilityBusiness)),
                  DropdownMenuItem(value: 'shared', child: Text(widget.t.crmNotesVisibilityShared)),
                ],
                onChanged: canWrite
                    ? (v) => setState(() {
                          if (v != null) _visibility = v;
                        })
                    : null,
              ),
              if (_visibility == 'shared') ...[
                const SizedBox(height: 8),
                Text(widget.t.crmNotesSharedUsers, style: Theme.of(context).textTheme.labelLarge),
                Wrap(
                  spacing: 6,
                  children: _members.map((u) {
                    final uid = u['user_id'] as int;
                    final selfId = widget.authStore.currentUserId;
                    if (selfId != null && uid == selfId) return const SizedBox.shrink();
                    final sel = _sharedIds.contains(uid);
                    return FilterChip(
                      label: Text((u['name'] ?? '$uid').toString()),
                      selected: sel,
                      onSelected: canWrite
                          ? (b) => setState(() {
                                if (b) {
                                  _sharedIds.add(uid);
                                } else {
                                  _sharedIds.remove(uid);
                                }
                              })
                          : null,
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 8),
              if (mode == 'day_only')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(widget.t.crmNotesDayNotes),
                  subtitle: Text(
                    _occursOn == null ? '—' : HesabixDateUtils.formatForDisplay(_occursOn!, widget.calendarController.isJalali),
                  ),
                  trailing: IconButton(icon: const Icon(Icons.date_range), onPressed: canWrite ? _pickDate : null),
                ),
              if (mode == 'meeting') ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(widget.t.crmNotesMeetingStart),
                  subtitle: Text(
                    _startAt == null
                        ? '—'
                        : HesabixDateUtils.formatDateTime(_startAt, widget.calendarController.isJalali),
                  ),
                  trailing: IconButton(
                    tooltip: widget.t.crmNotesPickDateTime,
                    icon: const Icon(Icons.schedule),
                    onPressed: !canWrite
                        ? null
                        : () async {
                            final dt = await _pickMeetingDateTime(initial: _startAt ?? DateTime.now());
                            if (dt == null || !mounted) return;
                            setState(() {
                              _startAt = dt;
                              _occursOn = DateTime(dt.year, dt.month, dt.day);
                            });
                          },
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(widget.t.crmNotesMeetingEnd),
                  subtitle: Text(
                    _endAt == null ? '—' : HesabixDateUtils.formatDateTime(_endAt, widget.calendarController.isJalali),
                  ),
                  trailing: IconButton(
                    tooltip: widget.t.crmNotesPickDateTime,
                    icon: const Icon(Icons.schedule_outlined),
                    onPressed: !canWrite
                        ? null
                        : () async {
                            final dt = await _pickMeetingDateTime(initial: _endAt ?? _startAt ?? DateTime.now());
                            if (dt == null || !mounted) return;
                            setState(() => _endAt = dt);
                          },
                  ),
                ),
              ],
              TextField(controller: _titleCtrl, decoration: InputDecoration(labelText: widget.t.crmNotesTitleOptional), readOnly: !canWrite),
              TextField(controller: _bodyCtrl, decoration: InputDecoration(labelText: widget.t.crmNotesBody), maxLines: 4, readOnly: !canWrite),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(widget.t.crmNotesLeadOptional),
                subtitle: Text(_leadLabel.isEmpty ? '—' : _leadLabel),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_leadId != null && canWrite)
                      TextButton(onPressed: () => setState(() { _leadId = null; _leadLabel = ''; }), child: Text(widget.t.crmNotesClearLead)),
                    IconButton(onPressed: canWrite ? _pickLead : null, icon: const Icon(Icons.search)),
                  ],
                ),
              ),
              if (id != null && commentsOn) ...[
                const Divider(),
                Text(widget.t.crmNotesComments, style: Theme.of(context).textTheme.titleSmall),
                ..._comments.map(
                  (c) {
                    final m = Map<String, dynamic>.from(c as Map);
                    return ListTile(
                      dense: true,
                      title: Text(m['body']?.toString() ?? ''),
                      subtitle: Text((m['created_by_name'] ?? '').toString()),
                    );
                  },
                ),
                if (canWrite) ...[
                  TextField(controller: _commentCtrl, decoration: InputDecoration(hintText: widget.t.crmNotesCommentHint)),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton(
                      onPressed: () async {
                        final txt = _commentCtrl.text.trim();
                        if (txt.isEmpty) return;
                        try {
                          await _crm.addCrmNoteComment(businessId: widget.businessId, noteId: id, body: txt);
                          _commentCtrl.clear();
                          await _loadThread();
                          if (mounted) setState(() {});
                        } catch (e) {
                          SnackBarHelper.show(context, message: '$e', isError: true);
                        }
                      },
                      child: Text(widget.t.crmNotesSendComment),
                    ),
                  ),
                ],
              ],
              if (id != null && _audit.isNotEmpty) ...[
                const Divider(),
                Text(widget.t.crmNotesAudit, style: Theme.of(context).textTheme.titleSmall),
                ..._audit.take(15).map((e) {
                  final m = Map<String, dynamic>.from(e as Map);
                  return ListTile(
                    dense: true,
                    title: Text((m['action'] ?? '').toString()),
                    subtitle: Text((m['payload_text'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: Text(widget.t.crmNotesClose)),
        if (id != null && canWrite)
          TextButton(onPressed: _saving ? null : _delete, child: Text(widget.t.crmNotesDelete)),
        if (canWrite) FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.t.crmNotesSave)),
      ],
    );
  }
}
