import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/services/person_service.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/crm/crm_ai_assistant_widget.dart';
import 'package:hesabix_ui/widgets/crm/crm_responsive_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_section_card.dart';
import 'package:hesabix_ui/widgets/crm/crm_tag_selector.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/product_combobox_widget.dart';

/// شخص حداقلی برای نمایش در انتخاب‌گر (فقط id و نام)
Person crmMinimalPersonForDisplay(int businessId, int? id, String? name) {
  return Person(
    id: id,
    businessId: businessId,
    aliasName: name?.trim().isNotEmpty == true ? name! : 'مشتری',
    personTypes: [PersonType.customer],
    createdAt: DateTime(2020, 1, 1),
    updatedAt: DateTime(2020, 1, 1),
  );
}

class CrmDealFormDialog extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final List<Map<String, dynamic>> processDefs;
  final CrmService crmService;
  final PersonService personService;
  final CalendarController? calendarController;
  final Map<String, dynamic>? initial;
  final VoidCallback onSaved;

  const CrmDealFormDialog({
    required this.businessId,
    required this.authStore,
    required this.processDefs,
    required this.crmService,
    required this.personService,
    this.calendarController,
    this.initial,
    required this.onSaved,
  });

  @override
  State<CrmDealFormDialog> createState() => _CrmDealFormDialogState();
}

class _CrmDealFormDialogState extends State<CrmDealFormDialog> {
  late TextEditingController _titleController;
  late TextEditingController _amountController;
  late TextEditingController _descController;
  late TextEditingController _documentIdController;
  late TextEditingController _codeController;
  bool _codeAuto = true;
  int? _selectedProcessId;
  int? _selectedStageId;
  int? _selectedPersonId;
  Person? _selectedPerson;
  List<Map<String, dynamic>> _stages = [];
  List<Map<String, dynamic>> _personDocuments = [];
  List<Map<String, dynamic>> _currencies = [];
  int? _selectedCurrencyId;
  bool _loadingProbability = false;
  int? _probabilityPercent;
  DateTime? _expectedCloseDate;
  DateTime? _nextFollowUpAt;
  bool _saving = false;
  bool _loadingDocuments = false;
  int? _selectedDocumentId;
  List<dynamic> _changeHistory = [];
  bool _historyLoading = false;
  List<int> _selectedTagIds = [];
  List<CrmDealLineDraft> _lines = [];
  bool _loadingLines = false;
  String? _wonReasonCode;
  String? _lostReasonCode;
  String? _competitorName;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null && i['tags'] is List) {
      _selectedTagIds = (i['tags'] as List)
          .map((e) => (e is Map ? (e['id'] as num?)?.toInt() : null))
          .whereType<int>()
          .toList();
    }
    _wonReasonCode = i?['won_reason_code']?.toString();
    _lostReasonCode = i?['lost_reason_code']?.toString();
    _competitorName = i?['competitor_name']?.toString();
    _titleController = TextEditingController(text: i?['title']?.toString() ?? '');
    _codeController = TextEditingController(text: i?['code']?.toString() ?? '');
    _codeAuto = i == null;
    _amountController = TextEditingController(text: (i?['amount'] is num) ? '${i!['amount']}' : '');
    _descController = TextEditingController(text: i?['description']?.toString() ?? '');
    final docId = i?['document_id'];
    _documentIdController = TextEditingController(
      text: docId is num ? '$docId' : (docId?.toString() ?? ''),
    );
    if (i != null) {
      _selectedProcessId = i['process_definition_id'] as int?;
      _selectedStageId = i['stage_id'] as int?;
      final pid = (i['person_id'] as num?)?.toInt();
      _selectedPersonId = pid;
      final pName = i['person_name']?.toString();
      if (pid != null) _selectedPerson = crmMinimalPersonForDisplay(widget.businessId, pid, pName);
      _selectedCurrencyId = (i['currency_id'] as num?)?.toInt();
      _probabilityPercent = (i['probability_percent'] as num?)?.toInt();
      final expDate = i['expected_close_date'];
      _expectedCloseDate = expDate != null ? DateTime.tryParse(expDate.toString()) : null;
      final nextAt = i['next_follow_up_at']?.toString();
      _nextFollowUpAt = nextAt != null && nextAt.isNotEmpty ? DateTime.tryParse(nextAt) : null;
      if (_selectedProcessId != null) {
        final proc = widget.processDefs.firstWhere((e) => e['id'] == _selectedProcessId, orElse: () => <String, dynamic>{});
        _stages = (proc['stages'] is List ? (proc['stages'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[]);
      }
    } else if (widget.processDefs.isNotEmpty) {
      _selectedProcessId = widget.processDefs.first['id'] as int?;
      final proc = widget.processDefs.first;
      _stages = (proc['stages'] is List ? (proc['stages'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[]);
      _selectedStageId = _stages.isNotEmpty ? _stages.first['id'] as int? : null;
    }
    _loadCurrencies();
    if (i != null && i['closed_at'] == null && (i['person_id'] as int?) != null) {
      _loadPersonDocuments((i['person_id'] as int?)!);
      _selectedDocumentId = (i['document_id'] as num?)?.toInt();
    }
    if (i != null && (i['id'] as num?) != null) {
      _loadLines((i['id'] as num).toInt());
    }
  }

  Future<void> _loadLines(int dealId) async {
    setState(() => _loadingLines = true);
    try {
      final lines = await widget.crmService.getDealLines(businessId: widget.businessId, dealId: dealId);
      if (!mounted) return;
      setState(() {
        _lines = lines
            .map((l) {
              final pid = (l['product_id'] as num?)?.toInt();
              final desc = l['description']?.toString() ?? '';
              Map<String, dynamic>? product;
              if (pid != null) {
                product = {
                  'id': pid,
                  'name': desc.isNotEmpty ? desc : 'کالا #$pid',
                };
              }
              return CrmDealLineDraft(
                productId: pid,
                product: product,
                description: desc,
                quantity: (l['quantity'] as num?)?.toDouble() ?? 1,
                unitPrice: (l['unit_price'] as num?)?.toDouble() ?? 0,
              );
            })
            .toList();
        _loadingLines = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingLines = false);
    }
  }

  bool _isWinStage(int? stageId) {
    if (stageId == null) return false;
    final s = _stages.cast<Map<String, dynamic>?>().firstWhere((e) => e?['id'] == stageId, orElse: () => null);
    return s?['is_win'] == true;
  }

  bool _isLostStage(int? stageId) {
    if (stageId == null) return false;
    final s = _stages.cast<Map<String, dynamic>?>().firstWhere((e) => e?['id'] == stageId, orElse: () => null);
    return s?['is_lost'] == true;
  }

  Future<void> _onStageChanged(int? v) async {
    setState(() => _selectedStageId = v);
    if (_isWinStage(v)) {
      await _pickCloseReason(isWon: true);
    } else if (_isLostStage(v)) {
      await _pickCloseReason(isWon: false);
    }
  }

  Future<void> _pickCloseReason({required bool isWon}) async {
    List<Map<String, dynamic>> reasons = [];
    try {
      reasons = await widget.crmService.listCloseReasons(
        businessId: widget.businessId,
        reasonType: isWon ? 'won' : 'lost',
      );
    } catch (_) {}
    if (!mounted) return;
    String? selectedCode = isWon ? _wonReasonCode : _lostReasonCode;
    final competitorController = TextEditingController(text: _competitorName ?? '');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        String? localCode = selectedCode;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(isWon ? 'دلیل برد' : 'دلیل باخت'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (reasons.isEmpty)
                  const Text('دلیلی تعریف نشده است. می‌توانید از تنظیمات CRM اضافه کنید.')
                else
                  DropdownButtonFormField<String?>(
                    value: localCode,
                    decoration: const InputDecoration(labelText: 'دلیل', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('انتخاب نشده')),
                      ...reasons.map((r) => DropdownMenuItem<String?>(
                            value: r['code']?.toString(),
                            child: Text(r['name']?.toString() ?? r['code']?.toString() ?? ''),
                          )),
                    ],
                    onChanged: (v) => setLocal(() => localCode = v),
                  ),
                if (!isWon) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: competitorController,
                    decoration: const InputDecoration(labelText: 'نام رقیب (اختیاری)', border: OutlineInputBorder()),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('انصراف')),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop({'code': localCode, 'competitor': competitorController.text.trim()}),
                child: const Text('تأیید'),
              ),
            ],
          ),
        );
      },
    );
    competitorController.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (isWon) {
        _wonReasonCode = result['code']?.toString();
      } else {
        _lostReasonCode = result['code']?.toString();
        _competitorName = (result['competitor']?.toString().isEmpty ?? true) ? null : result['competitor']?.toString();
      }
    });
  }

  Future<void> _issueProforma() async {
    final id = widget.initial?['id'] as int?;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      final result = await widget.crmService.convertDealToInvoice(
        businessId: widget.businessId,
        dealId: id,
        isProforma: true,
        closeAsWon: false,
      );
      if (!mounted) return;
      final invoice = result['invoice'];
      final invCode = invoice is Map ? (invoice['code']?.toString() ?? invoice['id']?.toString()) : null;
      SnackBarHelper.show(context, message: 'پیش‌فاکتور صادر شد${invCode != null ? ' ($invCode)' : ''}');
      Navigator.of(context).pop();
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      final msg = ErrorExtractor.forContext(e, context);
      final display = msg.contains('CRM_DEAL_NO_INVOICEABLE_LINES') || msg.contains('خط دارای کالا')
          ? 'برای صدور پیش‌فاکتور، حداقل یک خط دارای کالا لازم است. ابتدا خطوط فرصت فروش را با کالا کامل کنید.'
          : 'خطا: $msg';
      SnackBarHelper.show(context, message: display, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadPersonDocuments(int personId) async {
    setState(() => _loadingDocuments = true);
    try {
      final docs = await widget.crmService.listDocumentsForPerson(
        businessId: widget.businessId,
        personId: personId,
        limit: 100,
      );
      if (!mounted) return;
      setState(() {
        _personDocuments = docs;
        _loadingDocuments = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDocuments = false);
    }
  }

  Future<void> _loadCurrencies() async {
    try {
      final currencyService = CurrencyService(ApiClient());
      final list = await currencyService.listBusinessCurrencies(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _currencies = list;
        if (_selectedCurrencyId == null && list.isNotEmpty) {
          final def = list.cast<Map<String, dynamic>?>().firstWhere(
            (c) => c?['is_default'] == true,
            orElse: () => list.first,
          );
          _selectedCurrencyId = (def?['id'] as num?)?.toInt();
        }
      });
    } catch (_) {}
  }

  Future<void> _suggestDealProbability() async {
    final id = widget.initial?['id'] as int?;
    if (id == null) return;
    setState(() => _loadingProbability = true);
    try {
      final data = await widget.crmService.aiSuggestDealProbability(
        businessId: widget.businessId,
        dealId: id,
      );
      if (!mounted) return;
      final prob = (data is Map && data['probability_percent'] != null) ? (data['probability_percent'] as num).toInt() : null;
      setState(() {
        _loadingProbability = false;
        if (prob != null) {
          _probabilityPercent = prob;
        } else {
          SnackBarHelper.show(
            context,
            message: AppLocalizations.of(context).crmDealProbabilityUnavailable,
            isError: true,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingProbability = false);
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _codeController.dispose();
    _amountController.dispose();
    _descController.dispose();
    _documentIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    final cal = widget.calendarController;
    final t = AppLocalizations.of(context);
    return CrmResponsiveDialog(
      title: isEdit ? 'ویرایش فرصت فروش' : 'فرصت فروش جدید',
      subtitle: t.crmDealFormSubtitle,
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
          if (isEdit && (widget.initial!['id'] as int?) != null)
            CrmAIAssistantWidget(
              businessId: widget.businessId,
              crmService: widget.crmService,
              dealId: widget.initial!['id'] as int?,
            ),
          if (isEdit && (widget.initial!['id'] as int?) != null) const SizedBox(height: 12),
          CrmSectionCard(
            title: t.crmSectionDealCustomer,
            child: PersonComboboxWidget(
              businessId: widget.businessId,
              label: 'مشتری (شخص)',
              hintText: 'جست‌وجو و انتخاب مشتری',
              isRequired: true,
              personTypes: [PersonType.customer.persianName],
              selectedPerson: _selectedPerson,
              onChanged: (p) {
                setState(() {
                  _selectedPerson = p;
                  _selectedPersonId = p?.id;
                });
                if (p?.id != null) _loadPersonDocuments(p!.id!);
              },
            ),
          ),
          const SizedBox(height: 16),
          CrmSectionCard(
            title: t.crmSectionDealPipeline,
            child: Column(
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
                      decoration: const InputDecoration(labelText: 'کد دستی', hintText: 'مثال: D-001', border: OutlineInputBorder()),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
                DropdownButtonFormField<int?>(
                  value: _selectedProcessId,
                  decoration: const InputDecoration(labelText: 'پایپلاین فروش', border: OutlineInputBorder()),
                  items: widget.processDefs.map((p) => DropdownMenuItem<int?>(value: p['id'] as int?, child: Text(p['name']?.toString() ?? ''))).toList(),
                  onChanged: isEdit
                      ? null
                      : (v) {
                          setState(() {
                            _selectedProcessId = v;
                            _selectedStageId = null;
                            if (v != null) {
                              final proc = widget.processDefs.firstWhere((e) => e['id'] == v, orElse: () => <String, dynamic>{});
                              _stages = (proc['stages'] is List ? (proc['stages'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[]);
                              _selectedStageId = _stages.isNotEmpty ? _stages.first['id'] as int? : null;
                            } else {
                              _stages = [];
                            }
                          });
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  value: _selectedStageId,
                  decoration: const InputDecoration(labelText: 'مرحله', border: OutlineInputBorder()),
                  items: _stages.map((s) => DropdownMenuItem<int?>(value: s['id'] as int?, child: Text(s['name']?.toString() ?? ''))).toList(),
                  onChanged: (v) => _onStageChanged(v),
                ),
                if (_wonReasonCode != null && _wonReasonCode!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Chip(
                      avatar: const Icon(Icons.emoji_events_outlined, size: 16),
                      label: Text('دلیل برد: $_wonReasonCode'),
                      onDeleted: () => setState(() => _wonReasonCode = null),
                    ),
                  ),
                ],
                if (_lostReasonCode != null && _lostReasonCode!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Chip(
                      avatar: const Icon(Icons.sentiment_dissatisfied_outlined, size: 16),
                      label: Text('دلیل باخت: $_lostReasonCode${_competitorName != null ? ' · رقیب: $_competitorName' : ''}'),
                      onDeleted: () => setState(() {
                        _lostReasonCode = null;
                        _competitorName = null;
                      }),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'عنوان *', border: OutlineInputBorder()),
                  validator: (v) => v == null || v.trim().isEmpty ? 'الزامی' : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CrmSectionCard(
            title: t.crmSectionDealMoney,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(labelText: 'مبلغ', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                if (_currencies.isNotEmpty)
                  DropdownButtonFormField<int?>(
                    value: _selectedCurrencyId,
                    decoration: const InputDecoration(labelText: 'ارز', isDense: true, border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('پیش‌فرض')),
                      ..._currencies.map((c) => DropdownMenuItem<int?>(
                            value: (c['id'] as num?)?.toInt(),
                            child: Text(c['code']?.toString() ?? c['title']?.toString() ?? ''),
                          )),
                    ],
                    onChanged: (v) => setState(() => _selectedCurrencyId = v),
                  ),
                if (_currencies.isNotEmpty) const SizedBox(height: 12),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    showValueIndicator: ShowValueIndicator.always,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('احتمال موفقیت: ${_probabilityPercent ?? 0}%', style: Theme.of(context).textTheme.bodySmall),
                          if (isEdit && (widget.initial!['id'] as int?) != null)
                            TextButton.icon(
                              onPressed: _loadingProbability ? null : _suggestDealProbability,
                              icon: _loadingProbability ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome, size: 16),
                              label: Text(_loadingProbability ? '...' : 'پیشنهاد AI'),
                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                            ),
                        ],
                      ),
                      Slider(
                        value: (_probabilityPercent ?? 0).toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 10,
                        label: '${_probabilityPercent ?? 0}%',
                        onChanged: (v) => setState(() => _probabilityPercent = v.round()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (cal != null)
                  DateInputField(
                    calendarController: cal,
                    labelText: 'تاریخ پیش‌بینی بسته شدن',
                    hintText: 'انتخاب تاریخ',
                    value: _expectedCloseDate,
                    onChanged: (v) => setState(() => _expectedCloseDate = v),
                  )
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                    title: Text('تاریخ پیش‌بینی بسته شدن'),
                    subtitle: Text(
                      _expectedCloseDate != null
                          ? HesabixDateUtils.formatForDisplay(
                              _expectedCloseDate,
                              widget.calendarController?.isJalali ??
                                  ApiClient.getCalendarController()?.isJalali ??
                                  true,
                            )
                          : 'انتخاب نشده',
                    ),
                    trailing: TextButton.icon(
                      onPressed: () async {
                        final picked = await showAdaptiveDatePicker(
                          context: context,
                          calendarController: widget.calendarController,
                          initialDate: _expectedCloseDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => _expectedCloseDate = picked);
                      },
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(_expectedCloseDate != null ? 'تغییر' : 'انتخاب'),
                    ),
                  ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                  title: Text(
                    _nextFollowUpAt == null
                        ? 'یادآور پیگیری: تعیین نشده'
                        : 'یادآور پیگیری: ${HesabixDateUtils.formatDateTime(
                            _nextFollowUpAt,
                            widget.calendarController?.isJalali ??
                                ApiClient.getCalendarController()?.isJalali ??
                                true,
                          )}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () async {
                          final date = await showAdaptiveDatePicker(
                            context: context,
                            calendarController: widget.calendarController,
                            initialDate: _nextFollowUpAt ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date == null || !mounted) return;
                          final time = await showTimePicker(
                            context: context,
                            initialTime: _nextFollowUpAt != null ? TimeOfDay.fromDateTime(_nextFollowUpAt!) : TimeOfDay.now(),
                          );
                          if (time != null && mounted) {
                            setState(() => _nextFollowUpAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                          }
                        },
                        child: const Text('انتخاب'),
                      ),
                      if (_nextFollowUpAt != null)
                        TextButton(
                          onPressed: () => setState(() => _nextFollowUpAt = null),
                          child: const Text('پاک کردن'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descController,
                  decoration: const InputDecoration(labelText: 'توضیحات', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CrmSectionCard(
            title: 'برچسب‌ها',
            child: CrmTagSelector(
              businessId: widget.businessId,
              crmService: widget.crmService,
              initialTagIds: _selectedTagIds,
              onChanged: (ids) => _selectedTagIds = ids,
            ),
          ),
          if (isEdit) ...[
            const SizedBox(height: 16),
            CrmSectionCard(
              title: 'خطوط فرصت فروش',
              subtitle: 'برای صدور پیش‌فاکتور، حداقل یک خط دارای کالا لازم است.',
              child: _loadingLines
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_lines.isEmpty)
                          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('خطی اضافه نشده است.'))
                        else
                          ...List.generate(_lines.length, (index) {
                            final line = _lines[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ProductComboboxWidget(
                                          businessId: widget.businessId,
                                          authStore: widget.authStore,
                                          selectedProduct: line.product,
                                          label: 'کالا/خدمت',
                                          onChanged: (p) {
                                            setState(() {
                                              line.product = p;
                                              line.productId = (p?['id'] as num?)?.toInt();
                                              final name = p?['name']?.toString() ?? p?['title']?.toString() ?? '';
                                              if (name.isNotEmpty) line.description = name;
                                              final price = p?['sale_price'] ?? p?['price'] ?? p?['unit_price'];
                                              if (price is num && line.unitPrice == 0) {
                                                line.unitPrice = price.toDouble();
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => setState(() => _lines.removeAt(index)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    initialValue: line.description,
                                    decoration: const InputDecoration(labelText: 'شرح', isDense: true, border: OutlineInputBorder()),
                                    onChanged: (v) => line.description = v,
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: line.quantity == line.quantity.roundToDouble() ? line.quantity.toInt().toString() : line.quantity.toString(),
                                          decoration: const InputDecoration(labelText: 'تعداد', isDense: true, border: OutlineInputBorder()),
                                          keyboardType: TextInputType.number,
                                          onChanged: (v) => line.quantity = double.tryParse(v.trim()) ?? line.quantity,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: line.unitPrice == 0 ? '' : line.unitPrice.toInt().toString(),
                                          decoration: const InputDecoration(labelText: 'قیمت واحد', isDense: true, border: OutlineInputBorder()),
                                          keyboardType: TextInputType.number,
                                          onChanged: (v) => line.unitPrice = double.tryParse(v.trim()) ?? 0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => setState(() => _lines.add(CrmDealLineDraft(quantity: 1, unitPrice: 0))),
                              icon: const Icon(Icons.add),
                              label: const Text('افزودن خط'),
                            ),
                            const Spacer(),
                            FilledButton.tonalIcon(
                              onPressed: _saving ? null : _issueProforma,
                              icon: const Icon(Icons.request_quote_outlined, size: 18),
                              label: const Text('صدور پیش‌فاکتور'),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
              if (isEdit && widget.initial!['closed_at'] == null) ...[
                const SizedBox(height: 16),
                const Divider(),
                Text('بستن معامله و اتصال به فاکتور', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (_loadingDocuments)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                else if (_personDocuments.isNotEmpty)
                  DropdownButtonFormField<int?>(
                    value: _selectedDocumentId,
                    decoration: const InputDecoration(labelText: 'انتخاب سند/فاکتور (اختیاری)', isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('بدون اتصال به سند')),
                      ..._personDocuments.map((d) {
                        final id = d['id'] as int?;
                        final code = d['document_code']?.toString() ?? '';
                        final date = d['document_date']?.toString() ?? '';
                        final type = d['document_type_name'] ?? d['document_type'] ?? '';
                        final label = [code, date, type].where((x) => x.isNotEmpty).join(' · ');
                        return DropdownMenuItem<int?>(
                          value: id,
                          child: Text(label.isEmpty ? 'سند #$id' : label, overflow: TextOverflow.ellipsis),
                        );
                      }),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _selectedDocumentId = v;
                        _documentIdController.text = v?.toString() ?? '';
                      });
                    },
                  )
                else
                  TextFormField(
                    controller: _documentIdController,
                    decoration: const InputDecoration(
                      labelText: 'شناسه سند/فاکتور (اختیاری)',
                      hintText: 'در صورت اتصال به فاکتور، شناسه سند را وارد کنید',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _saving ? null : _closeDeal,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('بستن معامله'),
                ),
              ],
              if (isEdit && widget.initial!['closed_at'] != null)
                Builder(
                  builder: (ctx) {
                    final cs = Theme.of(ctx).colorScheme;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(top: 12),
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.onTertiaryContainer.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: cs.onTertiaryContainer),
                          const SizedBox(width: 8),
                          Text(
                            'معامله بسته شده',
                            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                  color: cs.onTertiaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              if (isEdit && (widget.initial!['id'] as int?) != null) ...[
                const SizedBox(height: 16),
                ExpansionTile(
                  title: const Text('تاریخچه تغییرات'),
                  initiallyExpanded: false,
                  onExpansionChanged: (exp) {
                    if (exp && _changeHistory.isEmpty && !_historyLoading) _loadDealHistory();
                  },
                  children: [
                    if (_historyLoading)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                      )
                    else if (_changeHistory.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('تغییری ثبت نشده است.', style: TextStyle(fontSize: 13)),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _changeHistory.map<Widget>((h) {
                            final m = h is Map ? Map<String, dynamic>.from(h as Map) : <String, dynamic>{};
                            final changedAt = m['changed_at']?.toString() ?? '';
                            final fieldName = m['field_name']?.toString() ?? '';
                            final oldVal = m['old_value']?.toString() ?? '';
                            final newVal = m['new_value']?.toString() ?? '';
                            final by = m['changed_by_name']?.toString() ?? '';
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('$fieldName: $oldVal → $newVal', style: Theme.of(context).textTheme.bodySmall),
                                    const SizedBox(height: 4),
                                    Text('$changedAt · $by', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ],
            ],
        ),
    );
  }

  Future<void> _loadDealHistory() async {
    final id = widget.initial?['id'] as int?;
    if (id == null) return;
    setState(() => _historyLoading = true);
    try {
      final list = await widget.crmService.getDealHistory(businessId: widget.businessId, dealId: id);
      if (!mounted) return;
      setState(() {
        _changeHistory = list;
        _historyLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      SnackBarHelper.show(context, message: 'عنوان الزامی است', isError: true);
      return;
    }
    if (_selectedPersonId == null) {
      SnackBarHelper.show(context, message: 'انتخاب مشتری الزامی است', isError: true);
      return;
    }
    if (_selectedProcessId == null || _selectedStageId == null) {
      SnackBarHelper.show(context, message: 'پایپلاین و مرحله الزامی است', isError: true);
      return;
    }
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    setState(() => _saving = true);
    try {
      if (widget.initial != null) {
        final id = widget.initial!['id'] as int?;
        if (id == null) throw Exception('شناسه نامعتبر');
        await widget.crmService.updateDeal(
          businessId: widget.businessId,
          dealId: id,
          stageId: _selectedStageId,
          code: _codeController.text.trim().isEmpty ? null : _codeController.text.trim(),
          title: _titleController.text.trim(),
          amount: amount > 0 ? amount : null,
          currencyId: _selectedCurrencyId,
          probabilityPercent: _probabilityPercent,
          expectedCloseDate: _expectedCloseDate,
          nextFollowUpAt: _nextFollowUpAt,
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          wonReasonCode: _wonReasonCode,
          lostReasonCode: _lostReasonCode,
          competitorName: _competitorName,
          tagIds: _selectedTagIds,
        );
        try {
          await widget.crmService.replaceDealLines(
            businessId: widget.businessId,
            dealId: id,
            lines: _lines.map((l) => l.toJson()).toList(),
          );
        } catch (_) {}
      } else {
        await widget.crmService.createDeal(
          businessId: widget.businessId,
          personId: _selectedPersonId!,
          processDefinitionId: _selectedProcessId!,
          stageId: _selectedStageId!,
          title: _titleController.text.trim(),
          amount: amount,
          code: _codeAuto ? null : (_codeController.text.trim().isEmpty ? null : _codeController.text.trim()),
          currencyId: _selectedCurrencyId,
          probabilityPercent: _probabilityPercent,
          expectedCloseDate: _expectedCloseDate,
          nextFollowUpAt: _nextFollowUpAt,
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          tagIds: _selectedTagIds,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
      SnackBarHelper.show(context, message: 'ذخیره شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _closeDeal() async {
    final id = widget.initial?['id'] as int?;
    if (id == null) return;
    int? documentId = _selectedDocumentId;
    if (documentId == null) {
      final docIdStr = _documentIdController.text.trim();
      documentId = docIdStr.isNotEmpty ? int.tryParse(docIdStr) : null;
    }
    setState(() => _saving = true);
    try {
      await widget.crmService.updateDeal(
        businessId: widget.businessId,
        dealId: id,
        stageId: _selectedStageId,
        title: _titleController.text.trim(),
        amount: double.tryParse(_amountController.text.trim()),
        description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
        documentId: documentId,
        closedAt: DateTime.now(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
      SnackBarHelper.show(context, message: 'معامله بسته شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class CrmDealLineDraft {
  int? productId;
  Map<String, dynamic>? product;
  String description;
  double quantity;
  double unitPrice;

  CrmDealLineDraft({
    this.productId,
    this.product,
    this.description = '',
    this.quantity = 1,
    this.unitPrice = 0,
  });

  Map<String, dynamic> toJson() => {
        if (productId != null) 'product_id': productId,
        'description': description,
        'quantity': quantity,
        'unit_price': unitPrice,
      };
}
