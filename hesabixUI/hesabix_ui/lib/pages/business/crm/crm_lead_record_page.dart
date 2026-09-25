import 'package:hesabix_ui/theme/glass.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_ai_assistant_widget.dart';
import 'package:hesabix_ui/widgets/crm/crm_delete_confirm_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_follow_up_field.dart';
import 'package:hesabix_ui/widgets/crm/crm_lead_form_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_section_card.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';
import 'package:hesabix_ui/core/hesabix_back.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// صفحه رکورد سرنخ: هدر، اکشن سریع، مرحله، تایم‌لاین.
class CrmLeadRecordPage extends StatefulWidget {
  final int businessId;
  final int leadId;
  final AuthStore authStore;
  final CalendarController? calendarController;

  const CrmLeadRecordPage({
    super.key,
    required this.businessId,
    required this.leadId,
    required this.authStore,
    this.calendarController,
  });

  @override
  State<CrmLeadRecordPage> createState() => _CrmLeadRecordPageState();
}

class _CrmLeadRecordPageState extends State<CrmLeadRecordPage> {
  final CrmService _crm = CrmService(apiClient: ApiClient());
  Map<String, dynamic>? _lead;
  List<Map<String, dynamic>> _processDefs = [];
  List<Map<String, dynamic>> _stages = [];
  List<Map<String, dynamic>> _leadSources = [];
  List<dynamic> _activities = [];
  List<dynamic> _history = [];
  bool _loading = true;
  bool _timelineLoading = false;
  String? _error;
  bool _savingStage = false;

  bool get _canWrite => widget.authStore.hasBusinessPermission('crm', 'write');
  bool get _isConverted =>
      _lead?['converted_at'] != null || _lead?['person_id'] != null;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadProcessDefs(), _loadLeadSources()]);
    await _load();
  }

  Future<void> _loadProcessDefs() async {
    try {
      final result = await _crm.listProcessDefinitions(
        businessId: widget.businessId,
        processType: 'lead_funnel',
        isActive: true,
      );
      final list = result is List
          ? result
          : (result is Map && result['data'] is List ? result['data'] as List : <dynamic>[]);
      if (!mounted) return;
      setState(() {
        _processDefs = list.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {}
  }

  Future<void> _loadLeadSources() async {
    try {
      final result = await _crm.listProcessDefinitions(
        businessId: widget.businessId,
        processType: 'lead_source',
        isActive: true,
      );
      if (!mounted) return;
      final list = result is List
          ? result
          : (result is Map && result['data'] is List ? result['data'] as List : <dynamic>[]);
      final sources = <Map<String, dynamic>>[];
      for (final p in list) {
        final proc = Map<String, dynamic>.from(p as Map);
        final procName = proc['name']?.toString() ?? '';
        for (final s in (proc['stages'] as List? ?? [])) {
          final stage = Map<String, dynamic>.from(s as Map);
          final code = stage['stage_code']?.toString() ?? '';
          if (code.isNotEmpty) {
            sources.add({
              'code': code,
              'label': procName.isNotEmpty ? '$procName - ${stage['name']}' : stage['name'],
            });
          }
        }
      }
      setState(() => _leadSources = sources);
    } catch (_) {}
  }

  void _syncStagesFromLead() {
    final pid = _lead?['process_definition_id'] as int?;
    if (pid == null) {
      _stages = [];
      return;
    }
    final proc = _processDefs.cast<Map<String, dynamic>?>().firstWhere(
          (p) => p?['id'] == pid,
          orElse: () => null,
        );
    _stages = (proc?['stages'] is List
            ? (proc!['stages'] as List).cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[])
        .toList();
    _stages.sort((a, b) => ((a['order_index'] ?? 0) as num).compareTo((b['order_index'] ?? 0) as num));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lead = await _crm.getLead(businessId: widget.businessId, leadId: widget.leadId);
      if (!mounted) return;
      setState(() {
        _lead = lead;
        _loading = false;
      });
      _syncStagesFromLead();
      unawaited(_loadTimeline());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  Future<void> _loadTimeline() async {
    setState(() => _timelineLoading = true);
    try {
      final results = await Future.wait([
        _crm.listActivities(businessId: widget.businessId, leadId: widget.leadId, limit: 40),
        _crm.getLeadHistory(businessId: widget.businessId, leadId: widget.leadId, limit: 40),
      ]);
      if (!mounted) return;
      final actData = results[0] as Map<String, dynamic>;
      final acts = actData['items'] is List ? actData['items'] as List : <dynamic>[];
      setState(() {
        _activities = acts;
        _history = results[1] as List<dynamic>;
        _timelineLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _timelineLoading = false);
    }
  }

  Future<void> _changeStage(int? stageId) async {
    if (stageId == null || !_canWrite || _isConverted) return;
    setState(() => _savingStage = true);
    try {
      final updated = await _crm.updateLead(
        businessId: widget.businessId,
        leadId: widget.leadId,
        stageId: stageId,
      );
      if (!mounted) return;
      setState(() {
        _lead = {...?_lead, ...updated};
        _savingStage = false;
      });
      SnackBarHelper.show(context, message: 'مرحله به‌روز شد');
      unawaited(_loadTimeline());
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingStage = false);
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  Future<void> _setFollowUp(DateTime? at) async {
    if (!_canWrite) return;
    try {
      final updated = await _crm.updateLead(
        businessId: widget.businessId,
        leadId: widget.leadId,
        nextFollowUpAt: at,
      );
      if (!mounted) return;
      setState(() => _lead = {...?_lead, ...updated, 'next_follow_up_at': at?.toIso8601String()});
      SnackBarHelper.show(context, message: at == null ? 'پیگیری پاک شد' : 'پیگیری تنظیم شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  Future<void> _openFullEdit() async {
    if (_lead == null) return;
    await showGlassDialog<void>(
      context: context,
      builder: (ctx) => CrmLeadFormDialog(
        businessId: widget.businessId,
        processDefs: _processDefs,
        leadSources: _leadSources,
        crmService: _crm,
        calendarController: widget.calendarController,
        initial: _lead,
        onSaved: () {
          _load();
        },
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _convert() async {
    final name = _lead?['name']?.toString() ?? '';
    final result = await showGlassDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => CrmConvertLeadDialog(
        businessId: widget.businessId,
        leadId: widget.leadId,
        leadName: name,
        crmService: _crm,
      ),
    );
    if (result == null || !mounted) return;
    try {
      final createDeal = result['create_deal'] as Map<String, dynamic>?;
      await _crm.convertLeadToCustomer(
        businessId: widget.businessId,
        leadId: widget.leadId,
        createDeal: createDeal?.isNotEmpty == true ? createDeal : null,
      );
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: 'سرنخ به مشتری تبدیل شد${createDeal != null ? ' و فرصت فروش ایجاد شد' : ''}',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  Future<void> _delete() async {
    final t = AppLocalizations.of(context);
    final name = _lead?['name']?.toString() ?? '';
    final ok = await showCrmDeleteConfirmDialog(
      context,
      title: t.crmDeleteLeadTitle,
      message: t.crmDeleteLeadMessage(name),
    );
    if (ok != true || !mounted) return;
    try {
      await _crm.deleteLead(businessId: widget.businessId, leadId: widget.leadId);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'سرنخ حذف شد');
      context.go('/business/${widget.businessId}/crm/leads');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  Future<void> _quickLogActivity(String type) async {
    if (!_canWrite) return;
    final labels = {
      'call': 'تماس',
      'email': 'ایمیل',
      'meeting': 'جلسه',
      'note': 'یادداشت',
    };
    final subjectCtrl = TextEditingController(text: labels[type] ?? type);
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ثبت ${labels[type] ?? type}'),
        content: TextField(
          controller: subjectCtrl,
          decoration: const InputDecoration(labelText: 'موضوع', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ثبت')),
        ],
      ),
    );
    final subject = subjectCtrl.text.trim();
    subjectCtrl.dispose();
    if (ok != true || !mounted) return;
    try {
      await _crm.createActivity(
        businessId: widget.businessId,
        leadId: widget.leadId,
        activityType: type,
        subject: subject.isEmpty ? (labels[type] ?? type) : subject,
        activityDate: DateTime.now(),
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'فعالیت ثبت شد');
      unawaited(_loadTimeline());
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  Future<void> _callMobile() async {
    final mobile = _lead?['mobile']?.toString() ?? '';
    if (mobile.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: mobile);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await Clipboard.setData(ClipboardData(text: mobile));
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'شماره کپی شد');
    }
  }

  String _fmtDt(dynamic iso, {bool withTime = true}) {
    final s = iso?.toString();
    if (s == null || s.isEmpty) return '';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    final jalali = widget.calendarController?.isJalali ?? ApiClient.getCalendarController()?.isJalali ?? true;
    if (withTime) return HesabixDateUtils.formatDateTime(dt, jalali);
    return HesabixDateUtils.formatForDisplay(dt, jalali);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authStore.canReadSection('crm')) {
      return AccessDeniedPage(message: 'شما دسترسی لازم برای مشاهده CRM را ندارید');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_lead?['name']?.toString() ?? 'سرنخ'),
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load, tooltip: 'بروزرسانی'),
          if (_canWrite)
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _lead == null ? null : _openFullEdit, tooltip: 'ویرایش کامل'),
          if (_canWrite)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'convert' && !_isConverted) _convert();
                if (v == 'delete') _delete();
              },
              itemBuilder: (_) => [
                if (!_isConverted) const PopupMenuItem(value: 'convert', child: Text('تبدیل به مشتری')),
                const PopupMenuItem(value: 'delete', child: Text('حذف')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 12),
                      FilledButton.tonal(onPressed: _load, child: const Text('تلاش مجدد')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 12),
                      if (_canWrite && !_isConverted) ...[
                        _buildQuickActions(),
                        const SizedBox(height: 12),
                      ],
                      _buildStageCard(),
                      const SizedBox(height: 12),
                      _buildDetailsCard(),
                      const SizedBox(height: 12),
                      if (_canWrite) ...[
                        CrmSectionCard(
                          title: 'پیگیری',
                          child: CrmFollowUpField(
                            value: DateTime.tryParse(_lead?['next_follow_up_at']?.toString() ?? ''),
                            onChanged: _setFollowUp,
                            calendarController: widget.calendarController,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_lead != null)
                        CrmAIAssistantWidget(
                          businessId: widget.businessId,
                          crmService: _crm,
                          leadId: widget.leadId,
                        ),
                      const SizedBox(height: 12),
                      _buildTimeline(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final name = _lead?['name']?.toString() ?? '-';
    final code = _lead?['code']?.toString() ?? '';
    final company = _lead?['company_name']?.toString() ?? '';
    final mobile = _lead?['mobile']?.toString() ?? '';
    final email = _lead?['email']?.toString() ?? '';
    final score = (_lead?['score'] as num?)?.toInt();
    final stageName = _lead?['stage_name']?.toString() ?? '';
    final assignee = _lead?['assigned_to_name']?.toString() ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: _isConverted ? cs.tertiaryContainer : cs.primaryContainer,
                  child: Icon(
                    _isConverted ? Icons.check_circle : Icons.contact_phone,
                    color: _isConverted ? cs.onTertiaryContainer : cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      if (company.isNotEmpty) Text(company, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (code.isNotEmpty) Chip(label: Text(code), visualDensity: VisualDensity.compact),
                          if (stageName.isNotEmpty)
                            Chip(
                              avatar: const Icon(Icons.flag_outlined, size: 16),
                              label: Text(stageName),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (score != null && score > 0)
                            Chip(
                              avatar: Icon(Icons.local_fire_department, size: 16, color: cs.primary),
                              label: Text('$score'),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (_isConverted)
                            Chip(
                              label: Text(_lead?['person_name']?.toString() ?? 'تبدیل‌شده'),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: cs.tertiaryContainer,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (mobile.isNotEmpty || email.isNotEmpty || assignee.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (mobile.isNotEmpty)
                InkWell(
                  onTap: _callMobile,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.phone, size: 16, color: cs.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text(mobile),
                        const Spacer(),
                        Text('تماس', style: theme.textTheme.labelMedium?.copyWith(color: cs.primary)),
                      ],
                    ),
                  ),
                ),
              if (email.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.email_outlined, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(child: Text(email)),
                    ],
                  ),
                ),
              if (assignee.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.person_outline, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text('مسئول: $assignee'),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilledButton.tonalIcon(
            onPressed: () async {
              await _callMobile();
              await _quickLogActivity('call');
            },
            icon: const Icon(Icons.phone_outlined, size: 18),
            label: const Text('تماس'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _quickLogActivity('note'),
            icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
            label: const Text('یادداشت'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _quickLogActivity('meeting'),
            icon: const Icon(Icons.event_outlined, size: 18),
            label: const Text('جلسه'),
          ),
          const SizedBox(width: 8),
          if (!_isConverted)
            FilledButton.icon(
              onPressed: _convert,
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: const Text('تبدیل'),
            ),
        ],
      ),
    );
  }

  Widget _buildStageCard() {
    final current = _lead?['stage_id'] as int?;
    return CrmSectionCard(
      title: 'مرحله فانل',
      child: _stages.isEmpty
          ? const Text('مراحل فانل در دسترس نیست.')
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _stages.map((s) {
                final id = s['id'] as int?;
                final selected = id == current;
                return ChoiceChip(
                  label: Text(s['name']?.toString() ?? ''),
                  selected: selected,
                  onSelected: (!_canWrite || _isConverted || _savingStage)
                      ? null
                      : (v) {
                          if (v) _changeStage(id);
                        },
                );
              }).toList(),
            ),
    );
  }

  Widget _buildDetailsCard() {
    final desc = _lead?['description']?.toString() ?? '';
    final source = _lead?['source_code']?.toString() ?? '';
    final tags = _lead?['tags'] is List ? _lead!['tags'] as List : [];
    return CrmSectionCard(
      title: 'جزئیات',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (source.isNotEmpty) Text('منبع: $source'),
          if (desc.isNotEmpty) ...[
            if (source.isNotEmpty) const SizedBox(height: 8),
            Text(desc),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: tags.map((t) {
                final m = t is Map ? Map<String, dynamic>.from(t) : <String, dynamic>{};
                return Chip(label: Text(m['name']?.toString() ?? ''), visualDensity: VisualDensity.compact);
              }).toList(),
            ),
          ],
          if (source.isEmpty && desc.isEmpty && tags.isEmpty)
            Text(
              'توضیحی ثبت نشده است.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final events = <_TimelineItem>[];
    for (final a in _activities) {
      final m = Map<String, dynamic>.from(a as Map);
      events.add(_TimelineItem(
        at: DateTime.tryParse(m['activity_at']?.toString() ?? m['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        icon: _activityIcon(m['activity_type']?.toString()),
        title: m['subject']?.toString() ?? m['activity_type']?.toString() ?? 'فعالیت',
        subtitle: [
          if (m['activity_type'] != null) m['activity_type'].toString(),
          if (m['is_task'] == true) 'تسک',
        ].join(' · '),
      ));
    }
    for (final h in _history) {
      final m = Map<String, dynamic>.from(h as Map);
      events.add(_TimelineItem(
        at: DateTime.tryParse(m['changed_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        icon: Icons.history,
        title: '${m['field_name'] ?? ''}: ${m['old_value'] ?? ''} → ${m['new_value'] ?? ''}',
        subtitle: m['changed_by_name']?.toString() ?? '',
      ));
    }
    events.sort((a, b) => b.at.compareTo(a.at));

    return CrmSectionCard(
      title: 'تایم‌لاین',
      child: _timelineLoading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          : events.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('هنوز رویدادی ثبت نشده است.'),
                )
              : Column(
                  children: events.take(50).map((e) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(e.icon, size: 20),
                      title: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          if (e.subtitle.isNotEmpty) e.subtitle,
                          _fmtDt(e.at.toIso8601String()),
                        ].where((x) => x.isNotEmpty).join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  }).toList(),
                ),
    );
  }

  IconData _activityIcon(String? type) {
    switch (type) {
      case 'call':
        return Icons.phone_outlined;
      case 'email':
        return Icons.email_outlined;
      case 'meeting':
        return Icons.event_outlined;
      default:
        return Icons.sticky_note_2_outlined;
    }
  }
}

class _TimelineItem {
  final DateTime at;
  final IconData icon;
  final String title;
  final String subtitle;
  _TimelineItem({required this.at, required this.icon, required this.title, required this.subtitle});
}
