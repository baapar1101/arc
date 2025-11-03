import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../widgets/invoice/person_combobox_widget.dart';
import '../../widgets/date_input_field.dart';
import '../../widgets/banking/currency_picker_widget.dart';
import '../../widgets/permission/access_denied_page.dart';
import '../../services/check_service.dart';

class CheckFormPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final int? checkId; // null => new, not null => edit
  final CalendarController? calendarController;

  const CheckFormPage({
    super.key,
    required this.businessId,
    required this.authStore,
    this.checkId,
    this.calendarController,
  });

  @override
  State<CheckFormPage> createState() => _CheckFormPageState();
}

class _CheckFormPageState extends State<CheckFormPage> {
  final _service = CheckService();

  String? _type; // 'received' | 'transferred'
  DateTime? _issueDate;
  DateTime? _dueDate;
  int? _currencyId;
  dynamic _selectedPerson; // using Person type would be ideal; keep dynamic to avoid imports complexity
  bool _autoPost = false;
  DateTime? _documentDate;

  final _checkNumberCtrl = TextEditingController();
  final _sayadCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _docDescCtrl = TextEditingController();

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _type = 'received';
    _currencyId = widget.authStore.selectedCurrencyId;
    _issueDate = DateTime.now();
    _dueDate = DateTime.now();
    _documentDate = _issueDate;
    if (widget.checkId != null) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getById(widget.checkId!);
      setState(() {
        _type = (data['type'] as String?) ?? 'received';
        _checkNumberCtrl.text = (data['check_number'] ?? '') as String;
        _sayadCtrl.text = (data['sayad_code'] ?? '') as String;
        _bankCtrl.text = (data['bank_name'] ?? '') as String;
        _branchCtrl.text = (data['branch_name'] ?? '') as String;
        final amount = data['amount'];
        _amountCtrl.text = amount == null ? '' : amount.toString();
        final issue = data['issue_date'] as String?;
        final due = data['due_date'] as String?;
        _issueDate = issue != null ? DateTime.tryParse(issue) : _issueDate;
        _dueDate = due != null ? DateTime.tryParse(due) : _dueDate;
        _currencyId = (data['currency_id'] is int) ? data['currency_id'] as int : _currencyId;
        // person_id exists but PersonComboboxWidget needs model; leave unselected for now
      });
    } catch (_) {
      // ignore load errors for now
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validate() {
    if (_type != 'received' && _type != 'transferred') return 'نوع چک الزامی است';
    if (_type == 'received' && _selectedPerson == null) return 'انتخاب شخص برای چک دریافتی الزامی است';
    if ((_checkNumberCtrl.text.trim()).isEmpty) return 'شماره چک الزامی است';
    if (_sayadCtrl.text.trim().isNotEmpty && _sayadCtrl.text.trim().length != 16) return 'شناسه صیاد باید 16 رقم باشد';
    if (_issueDate == null) return 'تاریخ صدور الزامی است';
    if (_dueDate == null) return 'تاریخ سررسید الزامی است';
    if (_issueDate != null && _dueDate != null && _dueDate!.isBefore(_issueDate!)) return 'تاریخ سررسید نمی‌تواند قبل از تاریخ صدور باشد';
    final amount = num.tryParse(_amountCtrl.text.replaceAll(',', '').trim());
    if (amount == null || amount <= 0) return 'مبلغ باید عددی بزرگتر از صفر باشد';
    if (_currencyId == null) return 'واحد پول الزامی است';
    return null;
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      _showError(error);
      return;
    }
    setState(() => _loading = true);
    try {
      final payload = <String, dynamic>{
        'type': _type,
        if (_selectedPerson != null) 'person_id': (_selectedPerson as dynamic).id,
        'issue_date': _issueDate!.toIso8601String(),
        'due_date': _dueDate!.toIso8601String(),
        'check_number': _checkNumberCtrl.text.trim(),
        if (_sayadCtrl.text.trim().isNotEmpty) 'sayad_code': _sayadCtrl.text.trim(),
        if (_bankCtrl.text.trim().isNotEmpty) 'bank_name': _bankCtrl.text.trim(),
        if (_branchCtrl.text.trim().isNotEmpty) 'branch_name': _branchCtrl.text.trim(),
        'amount': num.tryParse(_amountCtrl.text.replaceAll(',', '').trim()),
        'currency_id': _currencyId,
        'auto_post': _autoPost,
        if (_autoPost && _documentDate != null) 'document_date': _documentDate!.toIso8601String(),
        if (_autoPost && _docDescCtrl.text.trim().isNotEmpty) 'document_description': _docDescCtrl.text.trim(),
      };

      if (widget.checkId == null) {
        await _service.create(businessId: widget.businessId, payload: payload);
      } else {
        await _service.update(id: widget.checkId!, payload: payload);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.checkId == null ? 'چک ثبت شد' : 'چک ویرایش شد'),
        ),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      _showError('خطا در ذخیره: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  void dispose() {
    _checkNumberCtrl.dispose();
    _sayadCtrl.dispose();
    _bankCtrl.dispose();
    _branchCtrl.dispose();
    _amountCtrl.dispose();
    _docDescCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isEdit = widget.checkId != null;
    final canAccountingWrite = widget.authStore.canWriteSection('accounting');

    if (!widget.authStore.canWriteSection('checks')) {
      return AccessDeniedPage(message: t.accessDenied);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? t.edit : t.add),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
      body: IgnorePointer(
        ignoring: _loading,
        child: AbsorbPointer(
          absorbing: _loading,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loading) const LinearProgressIndicator(),

                    // نوع چک
                    DropdownButtonFormField<String>(
                      value: _type,
                      items: const [
                        DropdownMenuItem(value: 'received', child: Text('دریافتی')),
                        DropdownMenuItem(value: 'transferred', child: Text('واگذار شده')),
                      ],
                      onChanged: (val) => setState(() => _type = val),
                      decoration: const InputDecoration(
                        labelText: 'نوع چک *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // شخص (برای دریافتی)
                    if (_type == 'received') ...[
                      PersonComboboxWidget(
                        businessId: widget.businessId,
                        selectedPerson: _selectedPerson,
                        onChanged: (p) => setState(() => _selectedPerson = p),
                        isRequired: true,
                        label: 'شخص (برای چک دریافتی)',
                        hintText: 'جست‌وجو و انتخاب شخص',
                      ),
                      const SizedBox(height: 12),
                    ],

                    // تاریخ‌ها
                    Row(
                      children: [
                        Expanded(
                          child: DateInputField(
                            value: _issueDate,
                            labelText: 'تاریخ صدور *',
                            hintText: 'انتخاب تاریخ صدور',
                            calendarController: widget.calendarController!,
                            onChanged: (d) => setState(() => _issueDate = d),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DateInputField(
                            value: _dueDate,
                            labelText: 'تاریخ سررسید *',
                            hintText: 'انتخاب تاریخ سررسید',
                            calendarController: widget.calendarController!,
                            onChanged: (d) => setState(() => _dueDate = d),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // شماره چک و شناسه صیاد
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _checkNumberCtrl,
                            decoration: const InputDecoration(
                              labelText: 'شماره چک *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _sayadCtrl,
                            decoration: const InputDecoration(
                              labelText: 'شناسه صیاد',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // بانک و شعبه
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _bankCtrl,
                            decoration: const InputDecoration(
                              labelText: 'بانک صادرکننده',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _branchCtrl,
                            decoration: const InputDecoration(
                              labelText: 'شعبه',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // مبلغ و ارز
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _amountCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'مبلغ *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CurrencyPickerWidget(
                            businessId: widget.businessId,
                            selectedCurrencyId: _currencyId,
                            onChanged: (id) => setState(() => _currencyId = id),
                            label: 'واحد پول',
                            hintText: 'انتخاب واحد پول',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    if (canAccountingWrite) ...[
                      SwitchListTile(
                        value: _autoPost,
                        onChanged: (v) => setState(() {
                          _autoPost = v;
                          _documentDate ??= _issueDate;
                        }),
                        title: const Text('ثبت سند حسابداری همزمان'),
                      ),
                      if (_autoPost) ...[
                        Row(
                          children: [
                            Expanded(
                              child: DateInputField(
                                value: _documentDate,
                                labelText: 'تاریخ سند',
                                hintText: 'انتخاب تاریخ سند',
                                calendarController: widget.calendarController!,
                                onChanged: (d) => setState(() => _documentDate = d),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _docDescCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'شرح سند',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],

                    const SizedBox(height: 16),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _loading ? null : _save,
                          icon: const Icon(Icons.save),
                          label: Text(t.save),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _loading ? null : () => Navigator.of(context).maybePop(),
                          child: Text(t.cancel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


