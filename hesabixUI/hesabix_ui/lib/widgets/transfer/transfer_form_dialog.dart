import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/calendar_controller.dart';
import '../date_input_field.dart';
import '../invoice/bank_account_combobox_widget.dart';
import '../invoice/cash_register_combobox_widget.dart';
import '../invoice/petty_cash_combobox_widget.dart';
import '../../core/auth_store.dart';
import '../../core/api_client.dart';
import '../../services/transfer_service.dart';
import '../../widgets/banking/currency_picker_widget.dart';
import '../../utils/number_normalizer.dart';

class TransferFormDialog extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final VoidCallback? onSuccess;
  final AuthStore? authStore;
  final ApiClient? apiClient;
  final Map<String, dynamic>? initial; // اگر موجود باشد، حالت ویرایش

  const TransferFormDialog({
    super.key,
    required this.businessId,
    required this.calendarController,
    this.onSuccess,
    this.authStore,
    this.apiClient,
    this.initial,
  });

  @override
  State<TransferFormDialog> createState() => _TransferFormDialogState();
}

class _TransferFormDialogState extends State<TransferFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _commissionController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  bool _isLoading = false;
  DateTime _transferDate = DateTime.now();
  int? _currencyId;
  
  // انتخاب مبدا و مقصد
  String? _fromType = 'bank'; // پیش‌فرض بانک
  String? _toType = 'bank';   // پیش‌فرض بانک
  String? _fromId;
  String? _toId;

  @override
  void initState() {
    super.initState();
    // Prefill when editing
    final init = widget.initial;
    if (init != null) {
      try {
        final docDate = init['document_date'] as String?;
        if (docDate != null) {
          _transferDate = DateTime.tryParse(docDate) ?? _transferDate;
        }
        _descriptionController.text = (init['description'] as String?) ?? '';
        final amount = (init['total_amount'] as num?)?.toDouble();
        if (amount != null && amount > 0) {
          _amountController.text = formatNumberForInput(amount);
        }
        _currencyId = (init['currency_id'] as int?);
        // Infer commission from lines
        final lines = List<Map<String, dynamic>>.from(init['account_lines'] as List? ?? const []);
        final commissionLine = lines.firstWhere(
          (l) => (l['is_commission_line'] as bool?) == true && (l['account_code'] == '70902'),
          orElse: () => <String, dynamic>{},
        );
        final commissionVal = (commissionLine['amount'] as num?)?.toDouble();
        if (commissionVal != null && commissionVal > 0) {
          _commissionController.text = formatNumberForInput(commissionVal);
        }
        // Detect source/destination lines
        final src = lines.firstWhere(
          (l) => (l['side'] as String?) == 'source' && (l['is_commission_line'] as bool?) != true,
          orElse: () => <String, dynamic>{},
        );
        final dst = lines.firstWhere(
          (l) => (l['side'] as String?) == 'destination' && (l['is_commission_line'] as bool?) != true,
          orElse: () => <String, dynamic>{},
        );
        if (src.isNotEmpty) {
          _fromType = (src['source_type'] as String?) ?? _fromType;
          final bid = src['bank_account_id'];
          final cid = src['cash_register_id'];
          final pid = src['petty_cash_id'];
          _fromId = (bid ?? cid ?? pid)?.toString();
        }
        if (dst.isNotEmpty) {
          _toType = (dst['destination_type'] as String?) ?? _toType;
          final bid = dst['bank_account_id'];
          final cid = dst['cash_register_id'];
          final pid = dst['petty_cash_id'];
          _toId = (bid ?? cid ?? pid)?.toString();
        }
      } catch (_) {}
    }
    // If still not set (create), use business default currency
    _currencyId ??= widget.authStore?.currentBusiness?.defaultCurrency?.id;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _commissionController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }


  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_fromType == null || _toType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لطفاً مبدا و مقصد انتقال را انتخاب کنید'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_fromId == null || _toId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لطفاً مبدا و مقصد انتقال را انتخاب کنید'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_fromType == _toType && _fromId == _toId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('مبدا و مقصد نمی‌توانند یکسان باشند'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final api = widget.apiClient ?? ApiClient();
      final service = TransferService(api);
      final currencyId = _currencyId;
      if (currencyId == null) throw Exception('ارز انتخاب نشده است');

      final double amount = parseFormattedDouble(_amountController.text) ?? 0;
      final double? commission = _commissionController.text.trim().isEmpty
          ? null
          : parseFormattedDouble(_commissionController.text);

      final src = {
        'type': _fromType,
        'id': _fromId != null ? int.tryParse(_fromId!) ?? _fromId : null,
      }..removeWhere((k, v) => v == null);

      final dst = {
        'type': _toType,
        'id': _toId != null ? int.tryParse(_toId!) ?? _toId : null,
      }..removeWhere((k, v) => v == null);

      final isEdit = widget.initial != null && widget.initial!['id'] != null;
      if (isEdit) {
        await service.update(
          documentId: widget.initial!['id'] as int,
          documentDate: _transferDate,
          currencyId: currencyId,
          source: src,
          destination: dst,
          amount: amount,
          commission: commission,
          description: _descriptionController.text.trim(),
        );
      } else {
        await service.create(
          businessId: widget.businessId,
          documentDate: _transferDate,
          currencyId: currencyId,
          source: src,
          destination: dst,
          amount: amount,
          commission: commission,
          description: _descriptionController.text.trim(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'ویرایش با موفقیت انجام شد' : 'انتقال با موفقیت ثبت شد'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
        widget.onSuccess?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در ثبت انتقال: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildAccountSelector({
    required String label,
    required String? selectedType,
    required String? selectedId,
    required ValueChanged<String?> onTypeChanged,
    required ValueChanged<String?> onIdChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with icon and label
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet,
                    color: Theme.of(context).primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Account type selection with improved styling
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(
                      value: 'bank',
                      label: Text('بانک'),
                      icon: Icon(Icons.account_balance, size: 18),
                    ),
                    ButtonSegment<String>(
                      value: 'cash_register',
                      label: Text('صندوق'),
                      icon: Icon(Icons.point_of_sale, size: 18),
                    ),
                    ButtonSegment<String>(
                      value: 'petty_cash',
                      label: Text('تنخواه'),
                      icon: Icon(Icons.money, size: 18),
                    ),
                  ],
                  selected: selectedType != null ? {selectedType} : <String>{},
                  onSelectionChanged: (Set<String> selection) {
                    if (selection.isNotEmpty) {
                      final selectedType = selection.first;
                      onTypeChanged(selectedType);
                      onIdChanged(null);
                    }
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return Theme.of(context).primaryColor;
                      }
                      return Colors.transparent;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return Colors.white;
                      }
                      return Theme.of(context).colorScheme.onSurface;
                    }),
                    minimumSize: WidgetStateProperty.all(const Size(0, 44)),
                    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 12)),
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Account selection combobox
            if (selectedType != null)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: _buildAccountCombobox(selectedType, selectedId, onIdChanged),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCombobox(String accountType, String? selectedId, ValueChanged<String?> onIdChanged) {
    switch (accountType) {
      case 'bank':
        return BankAccountComboboxWidget(
          businessId: widget.businessId,
          selectedAccountId: selectedId,
          onChanged: (option) {
            onIdChanged(option?.id);
          },
          label: 'انتخاب بانک',
          hintText: 'جست‌وجو و انتخاب بانک',
          isRequired: true,
          filterCurrencyId: _currencyId,
        );
      case 'cash_register':
        return CashRegisterComboboxWidget(
          businessId: widget.businessId,
          selectedRegisterId: selectedId,
          onChanged: (option) {
            onIdChanged(option?.id);
          },
          label: 'انتخاب صندوق',
          hintText: 'جست‌وجو و انتخاب صندوق',
          isRequired: true,
          filterCurrencyId: _currencyId,
        );
      case 'petty_cash':
        return PettyCashComboboxWidget(
          businessId: widget.businessId,
          selectedPettyCashId: selectedId,
          onChanged: (option) {
            onIdChanged(option?.id);
          },
          label: 'انتخاب تنخواه گردان',
          hintText: 'جست‌وجو و انتخاب تنخواه گردان',
          isRequired: true,
          filterCurrencyId: _currencyId,
        );
      default:
        return Container();
    }
  }


  Widget _buildInputField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    String? suffixText,
    String? helperText,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            labelText: labelText,
            labelStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            suffixText: suffixText,
            helperText: helperText,
            helperStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).primaryColor,
                width: 2,
              ),
            ),
            prefixIcon: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                icon,
                color: Theme.of(context).primaryColor,
                size: 18,
              ),
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildDateField() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: DateInputField(
          value: _transferDate,
          onChanged: (date) {
            if (date != null) {
              setState(() {
                _transferDate = date;
              });
            }
          },
          labelText: 'تاریخ انتقال',
          calendarController: widget.calendarController,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 12,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.95,
          maxWidth: 1200, // حداکثر عرض برای دسکتاپ
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surface.withValues(alpha: 0.98),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // هدر دیالوگ با طراحی بهبود یافته
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).primaryColor,
                    Theme.of(context).primaryColor.withValues(alpha: 0.85),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.swap_horiz,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ثبت انتقال',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 24,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'انتقال بین حساب‌های مختلف',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white, size: 24),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),
            
            // فرم
            Expanded(
              child: Form(
                key: _formKey,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth > 800;
                    
                    if (isDesktop) {
                      // طراحی دو ستونه برای دسکتاپ با بهبود تراز
                      return SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ردیف 0: انتخاب ارز
                              Row(
                                children: [
                                  SizedBox(
                                    width: 260,
                                    child: CurrencyPickerWidget(
                                      businessId: widget.businessId,
                                      selectedCurrencyId: _currencyId,
                                      onChanged: (id) => setState(() => _currencyId = id),
                                      label: 'ارز',
                                      hintText: 'انتخاب ارز',
                                    ),
                                  ),
                                  const Spacer(),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // ردیف اول: انتخاب مبدا و مقصد
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildAccountSelector(
                                      label: 'از (مبدا)',
                                      selectedType: _fromType,
                                      selectedId: _fromId,
                                      onTypeChanged: (value) {
                                        setState(() {
                                          _fromType = value;
                                          _fromId = null;
                                        });
                                      },
                                      onIdChanged: (value) {
                                        setState(() {
                                          _fromId = value;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 32),
                                  Expanded(
                                    child: _buildAccountSelector(
                                      label: 'به (مقصد)',
                                      selectedType: _toType,
                                      selectedId: _toId,
                                      onTypeChanged: (value) {
                                        setState(() {
                                          _toType = value;
                                          _toId = null;
                                        });
                                      },
                                      onIdChanged: (value) {
                                        setState(() {
                                          _toId = value;
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 32),
                              
                              // ردیف دوم: مبلغ و کارمزد با طراحی بهبود یافته
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildInputField(
                                      controller: _amountController,
                                      labelText: 'مبلغ انتقال',
                                      icon: Icons.attach_money,
                                      suffixText: 'ریال',
                                      keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    EnglishDigitsFormatter(),
                                    ThousandsSeparatorInputFormatter(allowDecimal: false),
                                  ],
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'لطفاً مبلغ را وارد کنید';
                                        }
                                        final val = parseFormattedDouble(value);
                                        if (val == null) {
                                          return 'لطفاً مبلغ معتبر وارد کنید';
                                        }
                                        if (val <= 0) {
                                          return 'مبلغ باید بزرگتر از صفر باشد';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 32),
                                  Expanded(
                                    child: _buildInputField(
                                      controller: _commissionController,
                                      labelText: 'کارمزد',
                                      icon: Icons.percent,
                                      suffixText: 'ریال',
                                      helperText: 'اختیاری',
                                      keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    EnglishDigitsFormatter(),
                                    ThousandsSeparatorInputFormatter(allowDecimal: false),
                                  ],
                                      validator: (value) {
                                        if (value != null && value.isNotEmpty) {
                                          final val = parseFormattedDouble(value);
                                          if (val == null) {
                                            return 'لطفاً مبلغ معتبر وارد کنید';
                                          }
                                          if (val < 0) {
                                            return 'کارمزد نمی‌تواند منفی باشد';
                                          }
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 32),
                              
                              // ردیف سوم: تاریخ و توضیحات
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildDateField(),
                                  ),
                                  const SizedBox(width: 32),
                                  Expanded(
                                    child: _buildInputField(
                                      controller: _descriptionController,
                                      labelText: 'توضیحات',
                                      icon: Icons.description,
                                      maxLines: 3,
                                      // اختیاری: بدون اعتبارسنجی اجباری
                                      validator: (value) => null,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    } else {
                      // طراحی تک ستونه برای موبایل با بهبود تراز
                      return SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ارز
                              CurrencyPickerWidget(
                                businessId: widget.businessId,
                                selectedCurrencyId: _currencyId,
                                onChanged: (id) => setState(() => _currencyId = id),
                                label: 'ارز',
                                hintText: 'انتخاب ارز',
                              ),
                              const SizedBox(height: 16),
                              // انتخاب مبدا
                              _buildAccountSelector(
                                label: 'از (مبدا)',
                                selectedType: _fromType,
                                selectedId: _fromId,
                                onTypeChanged: (value) {
                                  setState(() {
                                    _fromType = value;
                                    _fromId = null;
                                  });
                                },
                                onIdChanged: (value) {
                                  setState(() {
                                    _fromId = value;
                                  });
                                },
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // انتخاب مقصد
                              _buildAccountSelector(
                                label: 'به (مقصد)',
                                selectedType: _toType,
                                selectedId: _toId,
                                onTypeChanged: (value) {
                                  setState(() {
                                    _toType = value;
                                    _toId = null;
                                  });
                                },
                                onIdChanged: (value) {
                                  setState(() {
                                    _toId = value;
                                  });
                                },
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // مبلغ
                              _buildInputField(
                                controller: _amountController,
                                labelText: 'مبلغ انتقال',
                                icon: Icons.attach_money,
                                suffixText: 'ریال',
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  ThousandsSeparatorInputFormatter(allowDecimal: false),
                                ],
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'لطفاً مبلغ را وارد کنید';
                                  }
                                  final val = parseFormattedDouble(value);
                                  if (val == null) {
                                    return 'لطفاً مبلغ معتبر وارد کنید';
                                  }
                                  if (val <= 0) {
                                    return 'مبلغ باید بزرگتر از صفر باشد';
                                  }
                                  return null;
                                },
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // کارمزد
                              _buildInputField(
                                controller: _commissionController,
                                labelText: 'کارمزد',
                                icon: Icons.percent,
                                suffixText: 'ریال',
                                helperText: 'اختیاری',
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  ThousandsSeparatorInputFormatter(allowDecimal: false),
                                ],
                                validator: (value) {
                                  if (value != null && value.isNotEmpty) {
                                    final val = parseFormattedDouble(value);
                                    if (val == null) {
                                      return 'لطفاً مبلغ معتبر وارد کنید';
                                    }
                                    if (val < 0) {
                                      return 'کارمزد نمی‌تواند منفی باشد';
                                    }
                                  }
                                  return null;
                                },
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // تاریخ
                              _buildDateField(),
                              
                              const SizedBox(height: 24),
                              
                              // توضیحات
                              _buildInputField(
                                controller: _descriptionController,
                                labelText: 'توضیحات',
                                icon: Icons.description,
                                maxLines: 3,
                                validator: (value) => null,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
            
            // دکمه‌های عملیات با طراحی بهبود یافته
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    label: const Text('انصراف'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _save,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save, size: 20),
                    label: Text(
                      _isLoading ? 'در حال ثبت...' : 'ثبت انتقال',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
