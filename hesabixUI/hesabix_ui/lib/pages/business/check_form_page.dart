import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../widgets/invoice/person_combobox_widget.dart';
import '../../widgets/date_input_field.dart';
import '../../widgets/banking/currency_picker_widget.dart';
import '../../services/check_service.dart';
import '../../services/person_service.dart';
import '../../models/person_model.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/number_formatters.dart';

class CheckFormDialog extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final int? checkId; // null => new, not null => edit
  final CalendarController? calendarController;
  final VoidCallback? onSuccess;

  const CheckFormDialog({
    super.key,
    required this.businessId,
    required this.authStore,
    this.checkId,
    this.calendarController,
    this.onSuccess,
  });

  @override
  State<CheckFormDialog> createState() => _CheckFormDialogState();
}

// Keep the old class name for backward compatibility with routing
class CheckFormPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final int? checkId;
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
  @override
  Widget build(BuildContext context) {
    return CheckFormDialog(
      businessId: widget.businessId,
      authStore: widget.authStore,
      checkId: widget.checkId,
      calendarController: widget.calendarController,
      onSuccess: () => Navigator.of(context).maybePop(),
    );
  }
}

class _CheckFormDialogState extends State<CheckFormDialog> {
  final _service = CheckService();
  final _personService = PersonService();

  String? _type; // 'received' | 'transferred'
  DateTime? _issueDate;
  DateTime? _dueDate;
  int? _currencyId;
  Person? _selectedPerson;
  DateTime? _documentDate;

  final _checkNumberCtrl = TextEditingController();
  final _sayadCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _docDescCtrl = TextEditingController();

  bool _loading = false;
  bool _isFormattingAmount = false;

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
    _amountCtrl.addListener(_handleAmountInput);
  }

  @override
  void dispose() {
    _checkNumberCtrl.dispose();
    _sayadCtrl.dispose();
    _bankCtrl.dispose();
    _branchCtrl.dispose();
    _amountCtrl.removeListener(_handleAmountInput);
    _amountCtrl.dispose();
    _docDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getById(widget.checkId!);
      final personId = data['person_id'] as int?;
      
      // بارگذاری شخص اگر person_id وجود داشته باشد
      Person? loadedPerson;
      if (personId != null) {
        try {
          loadedPerson = await _personService.getPerson(personId);
        } catch (e) {
          // اگر شخص پیدا نشد، ادامه می‌دهیم بدون شخص
        }
      }
      
      if (!mounted) return;
      setState(() {
        _type = (data['type'] as String?) ?? 'received';
        _checkNumberCtrl.text = (data['check_number'] ?? '') as String;
        _sayadCtrl.text = (data['sayad_code'] ?? '') as String;
        _bankCtrl.text = (data['bank_name'] ?? '') as String;
        _branchCtrl.text = (data['branch_name'] ?? '') as String;
        final amount = data['amount'];
        _amountCtrl.text = amount == null ? '' : amount.toString();
        _formatAmountControllerValue();
        final issue = data['issue_date'] as String?;
        final due = data['due_date'] as String?;
        _issueDate = issue != null ? DateTime.tryParse(issue) : _issueDate;
        _dueDate = due != null ? DateTime.tryParse(due) : _dueDate;
        _currencyId = (data['currency_id'] is int) ? data['currency_id'] as int : _currencyId;
        _selectedPerson = loadedPerson;
      });
    } catch (e) {
      if (mounted) {
        _showError('خطا در بارگذاری اطلاعات چک: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleAmountInput() {
    if (_isFormattingAmount) return;
    _formatAmountControllerValue();
  }

  void _formatAmountControllerValue() {
    final raw = _amountCtrl.text.replaceAll(',', '').trim();
    if (raw.isEmpty) {
      _amountCtrl.value = TextEditingValue(
        text: '',
        selection: const TextSelection.collapsed(offset: 0),
      );
      return;
    }

    final normalized = toEnglishDigits(raw);
    final value = num.tryParse(normalized);
    if (value == null) return;

    final formatted = formatWithThousands(value);
    if (formatted == _amountCtrl.text) return;

    _isFormattingAmount = true;
    _amountCtrl.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _isFormattingAmount = false;
  }

  String? _validate() {
    if (_type != 'received' && _type != 'transferred') return 'نوع چک الزامی است';
    if (_selectedPerson == null) {
      return _type == 'received' 
          ? 'انتخاب شخص برای چک دریافتی الزامی است'
          : 'انتخاب شخص برای چک واگذار شده الزامی است';
    }
    if ((_checkNumberCtrl.text.trim()).isEmpty) return 'شماره چک الزامی است';
    final sayadText = _sayadCtrl.text.trim();
    if (sayadText.isNotEmpty) {
      if (sayadText.length != 16) return 'شناسه صیاد باید 16 رقم باشد';
      if (!RegExp(r'^\d+$').hasMatch(sayadText)) return 'شناسه صیاد باید فقط عدد باشد';
    }
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
        'person_id': _selectedPerson!.id, // همیشه باید مقدار داشته باشد (توسط اعتبارسنجی بررسی شده)
        'issue_date': _issueDate!.toIso8601String(),
        'due_date': _dueDate!.toIso8601String(),
        'check_number': _checkNumberCtrl.text.trim(),
        if (_sayadCtrl.text.trim().isNotEmpty) 'sayad_code': _sayadCtrl.text.trim(),
        if (_bankCtrl.text.trim().isNotEmpty) 'bank_name': _bankCtrl.text.trim(),
        if (_branchCtrl.text.trim().isNotEmpty) 'branch_name': _branchCtrl.text.trim(),
        'amount': num.tryParse(_amountCtrl.text.replaceAll(',', '').trim()),
        'currency_id': _currencyId,
        // ثبت سند همیشه انجام می‌شود
        'document_date': (_documentDate ?? _issueDate)!.toIso8601String(),
        if (_docDescCtrl.text.trim().isNotEmpty) 'document_description': _docDescCtrl.text.trim(),
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
      Navigator.of(context).pop(true);
      widget.onSuccess?.call();
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
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isEdit = widget.checkId != null;
    final canAccountingWrite = widget.authStore.canWriteSection('accounting');

    if (!widget.authStore.canWriteSection('checks')) {
      return AlertDialog(
        title: Text(t.accessDenied),
        content: const Text('شما دسترسی لازم برای ویرایش چک را ندارید'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.cancel),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(isEdit ? t.edit : t.add)),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(left: 12),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: IgnorePointer(
          ignoring: _loading,
          child: AbsorbPointer(
            absorbing: _loading,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_loading) const LinearProgressIndicator(),
                  const SizedBox(height: 8),

                  // نوع چک
                  DropdownButtonFormField<String>(
                    initialValue: _type,
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

                  // شخص (برای دریافتی و واگذار شده)
                  PersonComboboxWidget(
                    businessId: widget.businessId,
                    selectedPerson: _selectedPerson,
                    onChanged: (p) => setState(() => _selectedPerson = p),
                    isRequired: true,
                    label: _type == 'received' 
                        ? 'شخص (برای چک دریافتی)' 
                        : 'شخص (برای چک واگذار شده)',
                    hintText: _type == 'received'
                        ? 'جست‌وجو و انتخاب شخص'
                        : 'جست‌وجو و انتخاب شخصی که چک به او داده می‌شود',
                  ),
                  const SizedBox(height: 12),

                  // تاریخ‌ها
                  Row(
                    children: [
                      Expanded(
                        child: widget.calendarController != null
                            ? DateInputField(
                                value: _issueDate,
                                labelText: 'تاریخ صدور *',
                                hintText: 'انتخاب تاریخ صدور',
                                calendarController: widget.calendarController!,
                                onChanged: (d) => setState(() => _issueDate = d),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: widget.calendarController != null
                            ? DateInputField(
                                value: _dueDate,
                                labelText: 'تاریخ سررسید *',
                                hintText: 'انتخاب تاریخ سررسید',
                                calendarController: widget.calendarController!,
                                onChanged: (d) => setState(() => _dueDate = d),
                              )
                            : const SizedBox.shrink(),
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
                          inputFormatters: [
                            EnglishDigitsFormatter(),
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                          ],
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
                    Row(
                      children: [
                        Expanded(
                          child: widget.calendarController != null
                              ? DateInputField(
                                  value: _documentDate,
                                  labelText: 'تاریخ سند',
                                  hintText: 'انتخاب تاریخ سند',
                                  calendarController: widget.calendarController!,
                                  onChanged: (d) => setState(() => _documentDate = d),
                                )
                              : const SizedBox.shrink(),
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
              ),
            ),
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        FilledButton.icon(
          onPressed: _loading ? null : _save,
          icon: const Icon(Icons.save),
          label: Text(t.save),
        ),
      ],
    );
  }
}


