import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/services/person_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_ai_assistant_widget.dart';
import 'package:hesabix_ui/widgets/crm/crm_close_deal_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_deal_form_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_delete_confirm_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_follow_up_field.dart';
import 'package:hesabix_ui/widgets/crm/crm_section_card.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// صفحه رکورد فرصت فروش: هدر، اکشن سریع، پایپلاین، تایم‌لاین.
class CrmDealRecordPage extends StatefulWidget {
  final int businessId;
  final int dealId;
  final AuthStore authStore;
  final CalendarController? calendarController;

  const CrmDealRecordPage({
    super.key,
    required this.businessId,
    required this.dealId,
    required this.authStore,
    this.calendarController,
  });

  @override
  State<CrmDealRecordPage> createState() => _CrmDealRecordPageState();
}

class _CrmDealRecordPageState extends State<CrmDealRecordPage> {
  final CrmService _crm = CrmService(apiClient: ApiClient());
  final PersonService _personService = PersonService(apiClient: ApiClient());
  Map<String, dynamic>? _deal;
  List<Map<String, dynamic>> _processDefs = [];
  List<Map<String, dynamic>> _stages = [];
  List<Map<String, dynamic>> _lines = [];
  List<dynamic> _activities = [];
  List<dynamic> _history = [];
  bool _loading = true;
  bool _timelineLoading = false;
  String? _error;
  bool _savingStage = false;

  bool get _canWrite => widget.authStore.hasBusinessPermission('crm', 'write');
  bool get _isClosed => _deal?['closed_at'] != null;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadProcessDefs();
    await _load();
  }

  Future<void> _loadProcessDefs() async {
    try {
      final result = await _crm.listProcessDefinitions(
        businessId: widget.businessId,
        processType: 'sales_pipeline',
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

  void _syncStages() {
    final pid = _deal?['process_definition_id'] as int?;
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
      final deal = await _crm.getDeal(businessId: widget.businessId, dealId: widget.dealId);
      List<Map<String, dynamic>> lines = [];
      try {
        lines = await _crm.getDealLines(businessId: widget.businessId, dealId: widget.dealId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _deal = deal;
        _lines = lines;
        _loading = false;
      });
      _syncStages();
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
        _crm.listActivities(businessId: widget.businessId, dealId: widget.dealId, limit: 40),
        _crm.getDealHistory(businessId: widget.businessId, dealId: widget.dealId, limit: 40),
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

  bool _isTerminalStage(int? stageId) {
    final s = _stages.cast<Map<String, dynamic>?>().firstWhere((e) => e?['id'] == stageId, orElse: () => null);
    return s?['is_win'] == true || s?['is_lost'] == true;
  }

  Future<void> _changeStage(int? stageId) async {
    if (stageId == null || !_canWrite || _isClosed) return;
    if (_isTerminalStage(stageId)) {
      await showCrmCloseDealDialog(
        context,
        businessId: widget.businessId,
        dealId: widget.dealId,
        crmService: _crm,
        stages: _stages,
        currentStageId: stageId,
        documentId: (_deal?['document_id'] as num?)?.toInt(),
        onClosed: _load,
      );
      return;
    }
    setState(() => _savingStage = true);
    try {
      final updated = await _crm.updateDeal(
        businessId: widget.businessId,
        dealId: widget.dealId,
        stageId: stageId,
      );
      if (!mounted) return;
      setState(() {
        _deal = {...?_deal, ...updated};
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
    if (!_canWrite || _isClosed) return;
    try {
      final updated = await _crm.updateDeal(
        businessId: widget.businessId,
        dealId: widget.dealId,
        nextFollowUpAt: at,
      );
      if (!mounted) return;
      setState(() => _deal = {...?_deal, ...updated, 'next_follow_up_at': at?.toIso8601String()});
      SnackBarHelper.show(context, message: at == null ? 'پیگیری پاک شد' : 'پیگیری تنظیم شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  Future<void> _openFullEdit() async {
    if (_deal == null) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => CrmDealFormDialog(
        businessId: widget.businessId,
        authStore: widget.authStore,
        processDefs: _processDefs,
        crmService: _crm,
        personService: _personService,
        calendarController: widget.calendarController,
        initial: _deal,
        onSaved: () {},
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _closeDeal() async {
    await showCrmCloseDealDialog(
      context,
      businessId: widget.businessId,
      dealId: widget.dealId,
      crmService: _crm,
      stages: _stages,
      currentStageId: _deal?['stage_id'] as int?,
      documentId: (_deal?['document_id'] as num?)?.toInt(),
      onClosed: _load,
    );
  }

  Future<void> _issueProforma() async {
    try {
      await _crm.convertDealToInvoice(
        businessId: widget.businessId,
        dealId: widget.dealId,
        isProforma: true,
        closeAsWon: false,
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'پیش‌فاکتور صادر شد');
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  Future<void> _delete() async {
    final t = AppLocalizations.of(context);
    final title = _deal?['title']?.toString() ?? '';
    final ok = await showCrmDeleteConfirmDialog(
      context,
      title: t.crmDeleteDealTitle,
      message: t.crmDeleteDealMessage(title),
    );
    if (ok != true || !mounted) return;
    try {
      await _crm.deleteDeal(businessId: widget.businessId, dealId: widget.dealId);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'فرصت فروش حذف شد');
      context.go('/business/${widget.businessId}/crm/deals');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  Future<void> _quickLogActivity(String type) async {
    if (!_canWrite) return;
    final labels = {'call': 'تماس', 'email': 'ایمیل', 'meeting': 'جلسه', 'note': 'یادداشت'};
    final subjectCtrl = TextEditingController(text: labels[type] ?? type);
    final ok = await showDialog<bool>(
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
        dealId: widget.dealId,
        personId: (_deal?['person_id'] as num?)?.toInt(),
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

  String _money(dynamic v) => NumberFormat('#,##0').format((v as num?) ?? 0);

  String _fmtDt(dynamic iso) {
    final s = iso?.toString();
    if (s == null || s.isEmpty) return '';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    final jalali = widget.calendarController?.isJalali ?? ApiClient.getCalendarController()?.isJalali ?? true;
    return HesabixDateUtils.formatDateTime(dt, jalali);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authStore.canReadSection('crm')) {
      return AccessDeniedPage(message: 'شما دسترسی لازم برای مشاهده CRM را ندارید');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_deal?['title']?.toString() ?? 'فرصت فروش'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/business/${widget.businessId}/crm/deals');
            }
          },
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load, tooltip: 'بروزرسانی'),
          if (_canWrite)
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _deal == null ? null : _openFullEdit, tooltip: 'ویرایش کامل'),
          if (_canWrite)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'close' && !_isClosed) _closeDeal();
                if (v == 'proforma') _issueProforma();
                if (v == 'delete') _delete();
              },
              itemBuilder: (_) => [
                if (!_isClosed) const PopupMenuItem(value: 'close', child: Text('بستن معامله')),
                const PopupMenuItem(value: 'proforma', child: Text('صدور پیش‌فاکتور')),
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
                      if (_canWrite && !_isClosed) ...[
                        _buildQuickActions(),
                        const SizedBox(height: 12),
                      ],
                      _buildStageCard(),
                      const SizedBox(height: 12),
                      _buildMoneyCard(),
                      if (_lines.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _buildLinesCard(),
                      ],
                      const SizedBox(height: 12),
                      if (_canWrite && !_isClosed) ...[
                        CrmSectionCard(
                          title: 'پیگیری',
                          child: CrmFollowUpField(
                            value: DateTime.tryParse(_deal?['next_follow_up_at']?.toString() ?? ''),
                            onChanged: _setFollowUp,
                            calendarController: widget.calendarController,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_deal != null)
                        CrmAIAssistantWidget(
                          businessId: widget.businessId,
                          crmService: _crm,
                          dealId: widget.dealId,
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
    final title = _deal?['title']?.toString() ?? '-';
    final code = _deal?['code']?.toString() ?? '';
    final person = _deal?['person_name']?.toString() ?? '';
    final stageName = _deal?['stage_name']?.toString() ?? '';
    final personId = (_deal?['person_id'] as num?)?.toInt();

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
                  backgroundColor: _isClosed ? cs.tertiaryContainer : cs.primaryContainer,
                  child: Icon(
                    _isClosed ? Icons.check_circle : Icons.trending_up,
                    color: _isClosed ? cs.onTertiaryContainer : cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      if (person.isNotEmpty)
                        InkWell(
                          onTap: personId == null
                              ? null
                              : () => context.go('/business/${widget.businessId}/crm/customer-360?personId=$personId'),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              person,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: personId != null ? cs.primary : null,
                                decoration: personId != null ? TextDecoration.underline : null,
                              ),
                            ),
                          ),
                        ),
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
                          if (_isClosed)
                            Chip(
                              label: const Text('بسته شده'),
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
            onPressed: () => _quickLogActivity('call'),
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
            onPressed: _issueProforma,
            icon: const Icon(Icons.request_quote_outlined, size: 18),
            label: const Text('پیش‌فاکتور'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _closeDeal,
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('بستن'),
          ),
        ],
      ),
    );
  }

  Widget _buildStageCard() {
    final current = _deal?['stage_id'] as int?;
    return CrmSectionCard(
      title: 'مرحله پایپلاین',
      child: _stages.isEmpty
          ? const Text('مراحل پایپلاین در دسترس نیست.')
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _stages.map((s) {
                final id = s['id'] as int?;
                final selected = id == current;
                final terminal = s['is_win'] == true || s['is_lost'] == true;
                return ChoiceChip(
                  label: Text(s['name']?.toString() ?? ''),
                  selected: selected,
                  avatar: terminal
                      ? Icon(s['is_win'] == true ? Icons.emoji_events_outlined : Icons.sentiment_dissatisfied_outlined, size: 16)
                      : null,
                  onSelected: (!_canWrite || _isClosed || _savingStage)
                      ? null
                      : (v) {
                          if (v) _changeStage(id);
                        },
                );
              }).toList(),
            ),
    );
  }

  Widget _buildMoneyCard() {
    final amount = _deal?['amount'];
    final prob = (_deal?['probability_percent'] as num?)?.toInt();
    final expected = _deal?['expected_close_date']?.toString() ?? '';
    final desc = _deal?['description']?.toString() ?? '';
    return CrmSectionCard(
      title: 'مبلغ و جزئیات',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_money(amount), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          if (prob != null) Text('احتمال موفقیت: $prob%'),
          if (expected.isNotEmpty) Text('تاریخ پیش‌بینی بستن: ${_fmtDt(expected)}'),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(desc),
          ],
        ],
      ),
    );
  }

  Widget _buildLinesCard() {
    return CrmSectionCard(
      title: 'خطوط فرصت (${_lines.length})',
      child: Column(
        children: _lines.map((line) {
          final desc = line['description']?.toString() ?? line['product_name']?.toString() ?? 'خط';
          final qty = line['quantity'];
          final price = line['unit_price'];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(desc),
            subtitle: Text('${qty ?? 1} × ${_money(price)}'),
            trailing: Text(_money(((qty as num?) ?? 1) * ((price as num?) ?? 0))),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTimeline() {
    final events = <_DealTimelineItem>[];
    for (final a in _activities) {
      final m = Map<String, dynamic>.from(a as Map);
      events.add(_DealTimelineItem(
        at: DateTime.tryParse(m['activity_at']?.toString() ?? m['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        icon: Icons.history_edu_outlined,
        title: m['subject']?.toString() ?? m['activity_type']?.toString() ?? 'فعالیت',
        subtitle: m['activity_type']?.toString() ?? '',
      ));
    }
    for (final h in _history) {
      final m = Map<String, dynamic>.from(h as Map);
      events.add(_DealTimelineItem(
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
                        [if (e.subtitle.isNotEmpty) e.subtitle, _fmtDt(e.at.toIso8601String())]
                            .where((x) => x.isNotEmpty)
                            .join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}

class _DealTimelineItem {
  final DateTime at;
  final IconData icon;
  final String title;
  final String subtitle;
  _DealTimelineItem({required this.at, required this.icon, required this.title, required this.subtitle});
}
