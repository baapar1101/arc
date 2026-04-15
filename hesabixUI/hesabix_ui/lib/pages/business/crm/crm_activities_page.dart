import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/services/person_service.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_delete_confirm_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_lead_picker_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_responsive_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_section_card.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';
import 'package:intl/intl.dart';

/// صفحه لیست فعالیت‌های CRM
class CrmActivitiesPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController? calendarController;

  const CrmActivitiesPage({
    super.key,
    required this.businessId,
    required this.authStore,
    this.calendarController,
  });

  @override
  State<CrmActivitiesPage> createState() => _CrmActivitiesPageState();
}

class _CrmActivitiesPageState extends State<CrmActivitiesPage> {
  final CrmService _crmService = CrmService(apiClient: ApiClient());
  final PersonService _personService = PersonService(apiClient: ApiClient());
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _filterPersons = [];
  int? _filterPersonId;
  String? _filterActivityType;
  bool _loading = true;
  String? _error;

  static const Map<String, String> _activityTypes = {
    'call': 'تماس',
    'email': 'ایمیل',
    'meeting': 'جلسه',
    'note': 'یادداشت',
  };

  @override
  void initState() {
    super.initState();
    final openAdd = GoRouterState.of(context).uri.queryParameters['openAdd'] == '1';
    _loadFilterPersons().then((_) {
      if (mounted && openAdd) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _onAdd();
        });
      }
    });
    _load();
  }

  Future<void> _loadFilterPersons() async {
    try {
      final result = await _personService.getPersons(
        businessId: widget.businessId,
        page: 1,
        limit: 500,
      );
      if (!mounted) return;
      final data = Map<String, dynamic>.from(result);
      final list = data['items'] ?? [];
      setState(() {
        _filterPersons = list is List
            ? list.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList()
            : <Map<String, dynamic>>[];
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _crmService.listActivities(
        businessId: widget.businessId,
        personId: _filterPersonId,
        activityType: _filterActivityType,
        page: 1,
        limit: 100,
      );
      if (!mounted) return;
      final data = Map<String, dynamic>.from(result as Map);
      final items = data['items'] is List ? (data['items'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      SnackBarHelper.show(context, message: 'خطا در بارگذاری: $e', isError: true);
    }
  }

  IconData _activityIcon(String type) {
    switch (type) {
      case 'call':
        return Icons.phone;
      case 'email':
        return Icons.email;
      case 'meeting':
        return Icons.event;
      case 'note':
        return Icons.note;
      default:
        return Icons.history;
    }
  }

  String _activityLabel(String type) => _activityTypes[type] ?? type;

  @override
  Widget build(BuildContext context) {
    if (!widget.authStore.canReadSection('crm')) {
      return AccessDeniedPage(message: 'شما دسترسی لازم برای مشاهده CRM را ندارید');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('فعالیت‌ها'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) context.pop();
          },
        ),
        actions: [
          if (widget.authStore.hasBusinessPermission('crm', 'write'))
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _onAdd,
              tooltip: 'فعالیت جدید',
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<int?>(
                    value: _filterPersonId,
                    decoration: const InputDecoration(labelText: 'مشتری', isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('همه')),
                      ..._filterPersons.map((p) => DropdownMenuItem<int?>(
                            value: p['id'] as int?,
                            child: Text(
                              p['display_name']?.toString() ?? p['alias_name']?.toString() ?? '-',
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                    ],
                    onChanged: (v) {
                      setState(() => _filterPersonId = v);
                      _load();
                    },
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String?>(
                    value: _filterActivityType,
                    decoration: const InputDecoration(labelText: 'نوع', isDense: true),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('همه')),
                      ..._activityTypes.entries.map((e) => DropdownMenuItem<String?>(
                            value: e.key,
                            child: Text(e.value),
                          )),
                    ],
                    onChanged: (v) {
                      setState(() => _filterActivityType = v);
                      _load();
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('تلاش مجدد'),
                            ),
                          ],
                        ),
                      )
                    : _items.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.history, size: 64, color: Theme.of(context).colorScheme.outline),
                                const SizedBox(height: 16),
                                const Text('هنوز فعالیتی ثبت نشده است.'),
                                const SizedBox(height: 8),
                                Text(
                                  'با دکمه افزودن می‌توانید فعالیت جدید (تماس، جلسه، یادداشت و ...) ثبت کنید.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _items.length,
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                final type = item['activity_type']?.toString() ?? '';
                                final code = item['code']?.toString() ?? '';
                                final subject = item['subject']?.toString() ?? '';
                                final desc = item['description']?.toString() ?? '';
                                final date = item['activity_date'];
                                final dateStr = date != null ? _formatDate(date.toString()) : '';
                                final typeLabel = _activityLabel(type);
                                final id = item['id'] as int?;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                      child: Icon(_activityIcon(type), color: Theme.of(context).colorScheme.onPrimaryContainer),
                                    ),
                                    title: Text(subject.isNotEmpty ? subject : typeLabel),
                                    subtitle: Text([if (code.isNotEmpty) code, desc.isNotEmpty ? desc : null, dateStr].whereType<String>().join(' · ')),
                                    trailing: widget.authStore.hasBusinessPermission('crm', 'write')
                                        ? PopupMenuButton<String>(
                                            onSelected: (v) {
                                              if (v == 'edit') _onEdit(item);
                                              if (v == 'delete' && id != null) _onDelete(id, subject);
                                            },
                                            itemBuilder: (_) => [
                                              const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                              const PopupMenuItem(value: 'delete', child: Text('حذف')),
                                            ],
                                          )
                                        : null,
                                    onTap: () => _onEdit(item),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('y/MM/dd HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }

  void _onEdit(Map<String, dynamic> item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _ActivityFormDialog(
        businessId: widget.businessId,
        crmService: _crmService,
        calendarController: widget.calendarController,
        initial: item,
        onSaved: _load,
      ),
    );
  }

  void _onAdd() {
    if (!widget.authStore.hasBusinessPermission('crm', 'write')) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => _ActivityFormDialog(
        businessId: widget.businessId,
        crmService: _crmService,
        calendarController: widget.calendarController,
        initial: null,
        onSaved: _load,
      ),
    );
  }

  Future<void> _onDelete(int id, String subject) async {
    final t = AppLocalizations.of(context);
    final ok = await showCrmDeleteConfirmDialog(
      context,
      title: t.crmDeleteActivityTitle,
      message: subject.trim().isNotEmpty ? t.crmDeleteActivityMessageNamed(subject.trim()) : t.crmDeleteActivityMessageUnnamed,
    );
    if (ok != true || !mounted) return;
    try {
      await _crmService.deleteActivity(businessId: widget.businessId, activityId: id);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'فعالیت حذف شد');
      _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: $e', isError: true);
    }
  }
}

Person _minimalPersonForActivityDisplay(int businessId, int? id, String? name) {
  return Person(
    id: id,
    businessId: businessId,
    aliasName: name?.trim().isNotEmpty == true ? name! : 'مشتری',
    personTypes: [PersonType.customer],
    createdAt: DateTime(2020, 1, 1),
    updatedAt: DateTime(2020, 1, 1),
  );
}

class _ActivityFormDialog extends StatefulWidget {
  final int businessId;
  final CrmService crmService;
  final CalendarController? calendarController;
  final Map<String, dynamic>? initial;
  final VoidCallback onSaved;

  const _ActivityFormDialog({
    required this.businessId,
    required this.crmService,
    this.calendarController,
    this.initial,
    required this.onSaved,
  });

  @override
  State<_ActivityFormDialog> createState() => _ActivityFormDialogState();
}

class _ActivityFormDialogState extends State<_ActivityFormDialog> {
  late TextEditingController _subjectController;
  late TextEditingController _descController;
  late TextEditingController _codeController;
  int? _leadId;
  String _leadLabel = '';
  bool _codeAuto = true;
  String _activityType = 'call';
  DateTime _activityDate = DateTime.now();
  int? _personId;
  Person? _selectedPerson;
  int? _dealId;
  bool _saving = false;
  bool _loadingSuggest = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initial ?? <String, dynamic>{};
    _subjectController = TextEditingController(text: i['subject']?.toString() ?? '');
    _codeController = TextEditingController(text: i['code']?.toString() ?? '');
    _codeAuto = i['id'] == null;
    _descController = TextEditingController(text: i['description']?.toString() ?? '');
    _leadId = (i['lead_id'] as num?)?.toInt();
    final lc = i['lead_code']?.toString();
    final ln = i['lead_name']?.toString();
    if (_leadId != null) {
      final parts = <String>[];
      if (lc != null && lc.isNotEmpty) parts.add(lc);
      if (ln != null && ln.isNotEmpty) parts.add(ln);
      _leadLabel = parts.isEmpty ? 'ID: $_leadId' : parts.join(' — ');
    }
    _activityType = i['activity_type']?.toString() ?? 'call';
    final pid = (i['person_id'] as num?)?.toInt();
    _personId = pid;
    final pName = i['person_name']?.toString();
    if (pid != null) _selectedPerson = _minimalPersonForActivityDisplay(widget.businessId, pid, pName);
    _dealId = (i['deal_id'] as num?)?.toInt();
    final date = i['activity_date'];
    _activityDate = date != null ? DateTime.tryParse(date.toString()) ?? DateTime.now() : DateTime.now();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _codeController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickLead() async {
    if ((widget.initial?['id']) != null) return;
    final m = await showCrmLeadPickerDialog(context, businessId: widget.businessId);
    if (m != null && mounted) {
      setState(() {
        _leadId = (m['id'] as num?)?.toInt();
        final name = (m['name'] ?? '').toString();
        final code = (m['code'] ?? '').toString();
        _leadLabel = [code, name].where((s) => s.isNotEmpty).join(' — ');
      });
    }
  }

  void _clearLead() {
    setState(() {
      _leadId = null;
      _leadLabel = '';
    });
  }

  Future<void> _pickDateTimeFull() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _activityDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    final tod = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_activityDate),
    );
    if (tod != null && mounted) {
      setState(() => _activityDate = DateTime(picked.year, picked.month, picked.day, tod.hour, tod.minute));
    } else if (mounted) {
      setState(() => _activityDate = DateTime(picked.year, picked.month, picked.day, _activityDate.hour, _activityDate.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isEdit = (widget.initial?['id']) != null;
    final cal = widget.calendarController;
    return CrmResponsiveDialog(
      title: isEdit ? 'ویرایش فعالیت' : 'ثبت فعالیت',
      subtitle: t.crmActivityFormSubtitle,
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('انصراف')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('ذخیره'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isEdit)
            TextFormField(
              controller: _codeController,
              decoration: const InputDecoration(labelText: 'کد', border: OutlineInputBorder()),
              textCapitalization: TextCapitalization.characters,
            ),
          if (isEdit) const SizedBox(height: 12),
          if (!isEdit) ...[
            SwitchListTile(
              title: const Text('کد خودکار'),
              subtitle: Text(_codeAuto ? 'کد به صورت خودکار تولید می‌شود' : 'کد دستی وارد کنید'),
              value: _codeAuto,
              onChanged: (v) => setState(() => _codeAuto = v),
              contentPadding: EdgeInsets.zero,
            ),
            if (!_codeAuto) ...[
              TextFormField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: 'کد دستی', hintText: 'مثال: A-001', border: OutlineInputBorder()),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 12),
            ],
          ],
          CrmSectionCard(
            title: t.crmSectionActivityLink,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PersonComboboxWidget(
                  businessId: widget.businessId,
                  label: 'مشتری (برای سرنخ می‌توان خالی بماند)',
                  hintText: 'جست‌وجو و انتخاب مشتری',
                  isRequired: false,
                  personTypes: [PersonType.customer.persianName],
                  selectedPerson: _selectedPerson,
                  onChanged: (p) {
                    setState(() {
                      _selectedPerson = p;
                      _personId = p?.id;
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (!isEdit) ...[
                  if (_leadId != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                      title: Text(t.crmActivityPickLead, style: Theme.of(context).textTheme.labelMedium),
                      subtitle: Text(_leadLabel, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        tooltip: t.crmActivityClearLead,
                        icon: const Icon(Icons.clear),
                        onPressed: _clearLead,
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _pickLead,
                      icon: const Icon(Icons.person_search_outlined),
                      label: Text(t.crmActivityPickLead),
                    ),
                ] else if (_leadLabel.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.crmActivityPickLead, style: Theme.of(context).textTheme.labelMedium),
                    subtitle: Text(_leadLabel),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CrmSectionCard(
            title: t.crmSectionActivityDetails,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'call', label: Text(t.crmActivityTypeCall), icon: const Icon(Icons.phone_outlined, size: 18)),
                      ButtonSegment(value: 'email', label: Text(t.crmActivityTypeEmail), icon: const Icon(Icons.email_outlined, size: 18)),
                      ButtonSegment(value: 'meeting', label: Text(t.crmActivityTypeMeeting), icon: const Icon(Icons.event_outlined, size: 18)),
                      ButtonSegment(value: 'note', label: Text(t.crmActivityTypeNote), icon: const Icon(Icons.sticky_note_2_outlined, size: 18)),
                    ],
                    selected: {_activityType},
                    emptySelectionAllowed: false,
                    showSelectedIcon: false,
                    onSelectionChanged: (s) {
                      if (s.isEmpty) return;
                      setState(() => _activityType = s.first);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _subjectController,
                  decoration: const InputDecoration(labelText: 'موضوع', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('توضیحات', style: Theme.of(context).textTheme.labelLarge),
                    if (_personId != null)
                      TextButton.icon(
                        onPressed: _loadingSuggest ? null : _suggestActivityText,
                        icon: _loadingSuggest ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome, size: 16),
                        label: Text(_loadingSuggest ? '...' : 'پیشنهاد AI'),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _descController,
                  decoration: const InputDecoration(labelText: 'توضیحات', alignLabelWithHint: true, border: OutlineInputBorder()),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CrmSectionCard(
            title: t.crmSectionActivityScheduling,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (cal != null) ...[
                  DateInputField(
                    calendarController: cal,
                    labelText: 'تاریخ فعالیت',
                    value: DateTime(_activityDate.year, _activityDate.month, _activityDate.day),
                    onChanged: (d) {
                      if (d != null) setState(() => _activityDate = DateTime(d.year, d.month, d.day, _activityDate.hour, _activityDate.minute));
                    },
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final tod = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(_activityDate),
                      );
                      if (tod != null && mounted) {
                        setState(() => _activityDate = DateTime(_activityDate.year, _activityDate.month, _activityDate.day, tod.hour, tod.minute));
                      }
                    },
                    icon: const Icon(Icons.schedule),
                    label: Text('${t.crmNotesPickDateTime} · ${DateFormat('HH:mm').format(_activityDate)}'),
                  ),
                ] else ...[
                  Text(DateFormat('y/MM/dd HH:mm').format(_activityDate), style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _pickDateTimeFull,
                    icon: const Icon(Icons.edit_calendar_outlined),
                    label: Text(t.crmNotesPickDateTime),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _suggestActivityText() async {
    if (_personId == null) return;
    setState(() => _loadingSuggest = true);
    try {
      final data = await widget.crmService.aiSuggestActivityText(
        businessId: widget.businessId,
        personId: _personId!,
        activityType: _activityType,
        dealId: _dealId,
      );
      if (!mounted) return;
      final text = data['suggested_text']?.toString();
      setState(() {
        _loadingSuggest = false;
        if (text != null) _descController.text = text;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSuggest = false);
      SnackBarHelper.show(context, message: 'خطا: $e', isError: true);
    }
  }

  Future<void> _save() async {
    final isEdit = (widget.initial?['id']) != null;
    final personId = _selectedPerson?.id ?? _personId;
    final leadId = _leadId;
    if (!isEdit && personId == null && leadId == null) {
      SnackBarHelper.show(context, message: 'یکی از مشتری یا شناسه سرنخ لازم است', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final id = (widget.initial?['id'] as num?)?.toInt();
      if (id != null) {
        await widget.crmService.updateActivity(
          businessId: widget.businessId,
          activityId: id,
          code: _codeController.text.trim().isEmpty ? null : _codeController.text.trim(),
          activityType: _activityType,
          subject: _subjectController.text.trim().isEmpty ? null : _subjectController.text.trim(),
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          activityDate: _activityDate,
          dealId: _dealId,
        );
      } else {
        await widget.crmService.createActivity(
          businessId: widget.businessId,
          personId: personId,
          leadId: leadId,
          activityType: _activityType,
          code: _codeAuto ? null : (_codeController.text.trim().isEmpty ? null : _codeController.text.trim()),
          subject: _subjectController.text.trim().isEmpty ? null : _subjectController.text.trim(),
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          activityDate: _activityDate,
          dealId: _dealId,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
      SnackBarHelper.show(context, message: 'ذخیره شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
