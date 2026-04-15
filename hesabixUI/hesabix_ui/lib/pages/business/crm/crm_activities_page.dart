import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/services/person_service.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_responsive_dialog.dart';
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف فعالیت'),
        content: Text('آیا از حذف این فعالیت${subject.isNotEmpty ? ' «$subject»' : ''} اطمینان دارید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('خیر')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('بله، حذف')),
        ],
      ),
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
  late TextEditingController _leadIdController;
  bool _codeAuto = true;
  String _activityType = 'call';
  DateTime _activityDate = DateTime.now();
  int? _personId;
  Person? _selectedPerson;
  int? _dealId;
  bool _saving = false;
  bool _loadingSuggest = false;

  static const Map<String, String> _activityTypes = {
    'call': 'تماس',
    'email': 'ایمیل',
    'meeting': 'جلسه',
    'note': 'یادداشت',
  };

  @override
  void initState() {
    super.initState();
    final i = widget.initial ?? <String, dynamic>{};
    _subjectController = TextEditingController(text: i['subject']?.toString() ?? '');
    _codeController = TextEditingController(text: i['code']?.toString() ?? '');
    _codeAuto = i['id'] == null;
    _descController = TextEditingController(text: i['description']?.toString() ?? '');
    final lid = (i['lead_id'] as num?)?.toInt();
    _leadIdController = TextEditingController(text: lid != null ? '$lid' : '');
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
    _leadIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = (widget.initial?['id']) != null;
    final cal = widget.calendarController;
    return CrmResponsiveDialog(
      title: isEdit ? 'ویرایش فعالیت' : 'ثبت فعالیت',
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
              decoration: const InputDecoration(labelText: 'کد'),
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
                decoration: const InputDecoration(labelText: 'کد دستی', hintText: 'مثال: A-001'),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 12),
            ],
          ],
          PersonComboboxWidget(
            businessId: widget.businessId,
            label: 'مشتری (در صورت ثبت برای سرنخ می‌توان خالی بماند)',
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
          const SizedBox(height: 8),
          TextFormField(
            controller: _leadIdController,
            enabled: !isEdit,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'شناسه سرنخ (اختیاری)',
              helperText: 'برای تماس قبل از تبدیل به مشتری؛ در غیر این صورت مشتری را انتخاب کنید',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
              value: _activityType,
              decoration: const InputDecoration(labelText: 'نوع فعالیت'),
              items: _activityTypes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setState(() => _activityType = v ?? _activityType),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subjectController,
              decoration: const InputDecoration(labelText: 'موضوع'),
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
              decoration: const InputDecoration(labelText: 'توضیحات', alignLabelWithHint: true),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            if (cal != null) ...[
              DateInputField(
                calendarController: cal,
                labelText: 'تاریخ فعالیت',
                value: DateTime(_activityDate.year, _activityDate.month, _activityDate.day),
                onChanged: (d) {
                  if (d != null) setState(() => _activityDate = DateTime(d.year, d.month, d.day, _activityDate.hour, _activityDate.minute));
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                title: Text('ساعت: ${DateFormat('HH:mm').format(_activityDate)}'),
                trailing: TextButton(
                  onPressed: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_activityDate),
                    );
                    if (t != null) setState(() => _activityDate = DateTime(_activityDate.year, _activityDate.month, _activityDate.day, t.hour, t.minute));
                  },
                  child: const Text('تغییر'),
                ),
              ),
            ] else
              ListTile(
                title: Text('تاریخ و زمان: ${DateFormat('y/MM/dd HH:mm').format(_activityDate)}'),
                trailing: TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _activityDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _activityDate = DateTime(picked.year, picked.month, picked.day, _activityDate.hour, _activityDate.minute));
                  },
                  child: const Text('تغییر'),
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
    final leadRaw = _leadIdController.text.trim();
    int? leadId;
    if (leadRaw.isNotEmpty) {
      leadId = int.tryParse(leadRaw);
      if (leadId == null || leadId <= 0) {
        SnackBarHelper.show(context, message: 'شناسه سرنخ نامعتبر است', isError: true);
        return;
      }
    }
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

  bool get isEdit => (widget.initial?['id']) != null;
}
