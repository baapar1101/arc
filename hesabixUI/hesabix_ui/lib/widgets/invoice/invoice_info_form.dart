import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/customer_model.dart';
import 'package:hesabix_ui/models/invoice_type_model.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/widgets/banking/currency_picker_widget.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/inputs/frequent_description_text_field.dart';
import 'package:hesabix_ui/widgets/invoice/code_field_widget.dart';
import 'package:hesabix_ui/widgets/invoice/commission_amount_field.dart';
import 'package:hesabix_ui/widgets/invoice/commission_percentage_field.dart';
import 'package:hesabix_ui/widgets/invoice/commission_type_selector.dart';
import 'package:hesabix_ui/widgets/invoice/customer_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/invoice_form_layout.dart';
import 'package:hesabix_ui/widgets/invoice/invoice_fx_rate_field.dart';
import 'package:hesabix_ui/widgets/invoice/invoice_tags_field.dart';
import 'package:hesabix_ui/widgets/invoice/invoice_type_combobox.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/seller_picker_widget.dart';
import 'package:hesabix_ui/widgets/project/project_selector_widget.dart';

import '../../constants/frequent_description_scope.dart';

/// فرم فشرده تب «اطلاعات فاکتور» — یک گرید هم‌ارتفاع بدون کارت‌های اضافه.
class InvoiceInfoForm extends StatelessWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  final InvoiceType? selectedInvoiceType;
  final ValueChanged<InvoiceType?> onInvoiceTypeChanged;

  final bool isDraft;
  final ValueChanged<bool> onDraftChanged;
  final bool enableDraftToggle;

  final String? invoiceNumber;
  final ValueChanged<String?> onInvoiceNumberChanged;
  final bool autoGenerateInvoiceNumber;
  final ValueChanged<bool> onAutoGenerateInvoiceNumberChanged;
  final bool showAutoGenerateToggle;

  /// در حالت شماره خودکار: دریافت شماره رزروشده از سرور.
  final bool invoiceNumberLoading;
  final String? invoiceNumberReserveError;
  final VoidCallback? onRetryReserveInvoiceNumber;

  final DateTime? invoiceDate;
  final ValueChanged<DateTime?> onInvoiceDateChanged;
  final DateTime? dueDate;
  final ValueChanged<DateTime?> onDueDateChanged;

  final Customer? selectedCustomer;
  final ValueChanged<Customer?> onCustomerChanged;

  final Person? selectedSupplier;
  final ValueChanged<Person?> onSupplierChanged;

  final int? selectedCurrencyId;
  final ValueChanged<int?> onCurrencyChanged;
  final String currencyUnitLabel;

  final bool showFxRateField;
  final bool loadingFxRates;
  final int? manualFxRateId;
  final List<Map<String, dynamic>> fxRateRows;
  final ValueChanged<int?> onFxRateChanged;

  final int? selectedProjectId;
  final ValueChanged<int?> onProjectChanged;

  final List<int> selectedTagIds;
  final ValueChanged<List<int>> onTagsChanged;

  final Person? selectedSeller;
  final ValueChanged<Person?> onSellerChanged;

  final CommissionType? commissionType;
  final ValueChanged<CommissionType?> onCommissionTypeChanged;
  final double? commissionPercentage;
  final ValueChanged<double?> onCommissionPercentageChanged;
  final double? commissionAmount;
  final ValueChanged<double?> onCommissionAmountChanged;

  final String? invoiceReference;
  final ValueChanged<String?> onInvoiceReferenceChanged;

  final TextEditingController invoiceTitleController;
  final ValueChanged<String> onInvoiceTitleChanged;

  final bool showSellerCommissionSection;
  final bool enableTypeChange;
  final List<InvoiceType>? allowedInvoiceTypes;
  final Widget? header;

  const InvoiceInfoForm({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
    required this.selectedInvoiceType,
    required this.onInvoiceTypeChanged,
    required this.isDraft,
    required this.onDraftChanged,
    this.enableDraftToggle = true,
    required this.invoiceNumber,
    required this.onInvoiceNumberChanged,
    required this.autoGenerateInvoiceNumber,
    required this.onAutoGenerateInvoiceNumberChanged,
    this.showAutoGenerateToggle = true,
    this.invoiceNumberLoading = false,
    this.invoiceNumberReserveError,
    this.onRetryReserveInvoiceNumber,
    required this.invoiceDate,
    required this.onInvoiceDateChanged,
    required this.dueDate,
    required this.onDueDateChanged,
    required this.selectedCustomer,
    required this.onCustomerChanged,
    required this.selectedSupplier,
    required this.onSupplierChanged,
    required this.selectedCurrencyId,
    required this.onCurrencyChanged,
    required this.currencyUnitLabel,
    required this.showFxRateField,
    required this.loadingFxRates,
    required this.manualFxRateId,
    required this.fxRateRows,
    required this.onFxRateChanged,
    required this.selectedProjectId,
    required this.onProjectChanged,
    required this.selectedTagIds,
    required this.onTagsChanged,
    required this.selectedSeller,
    required this.onSellerChanged,
    required this.commissionType,
    required this.onCommissionTypeChanged,
    required this.commissionPercentage,
    required this.onCommissionPercentageChanged,
    required this.commissionAmount,
    required this.onCommissionAmountChanged,
    required this.invoiceReference,
    required this.onInvoiceReferenceChanged,
    required this.invoiceTitleController,
    required this.onInvoiceTitleChanged,
    this.showSellerCommissionSection = true,
    this.enableTypeChange = true,
    this.allowedInvoiceTypes,
    this.header,
  });

  bool get _isSalesFamily =>
      selectedInvoiceType == InvoiceType.sales ||
      selectedInvoiceType == InvoiceType.salesReturn;

  bool get _isPurchaseFamily =>
      selectedInvoiceType == InvoiceType.purchase ||
      selectedInvoiceType == InvoiceType.purchaseReturn;

  bool get _showsCounterparty =>
      selectedInvoiceType != null &&
      selectedInvoiceType != InvoiceType.waste &&
      selectedInvoiceType != InvoiceType.directConsumption &&
      selectedInvoiceType != InvoiceType.production;

  Widget? _counterpartyField() {
    if (!_showsCounterparty) return null;
    if (_isSalesFamily) {
      return CustomerComboboxWidget(
        selectedCustomer: selectedCustomer,
        onCustomerChanged: onCustomerChanged,
        businessId: businessId,
        authStore: authStore,
        isRequired: false,
        label: 'طرف حساب',
        hintText: 'انتخاب طرف حساب',
        showFinancialBalance: true,
        dense: true,
      );
    }
    if (_isPurchaseFamily) {
      return PersonComboboxWidget(
        businessId: businessId,
        showFinancialBalance: true,
        selectedPerson: selectedSupplier,
        onChanged: onSupplierChanged,
        isRequired: false,
        label: 'تامین‌کننده',
        hintText: 'انتخاب تامین‌کننده',
        personTypes: const ['تامین‌کننده', 'فروشنده'],
        searchHint: 'جست‌وجو در تامین‌کنندگان...',
        dense: true,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final counterparty = _counterpartyField();
    final showToggles = enableDraftToggle || showAutoGenerateToggle;

    final gridChildren = <Widget>[
      InvoiceTypeCombobox(
        selectedType: selectedInvoiceType,
        onTypeChanged: onInvoiceTypeChanged,
        isDraft: isDraft,
        onDraftChanged: onDraftChanged,
        enableDraftToggle: enableDraftToggle,
        enableTypeChange: enableTypeChange,
        allowedTypes: allowedInvoiceTypes,
        isRequired: true,
        label: 'نوع فاکتور',
        hintText: 'انتخاب نوع فاکتور',
        compact: true,
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CodeFieldWidget(
            initialValue: invoiceNumber,
            onChanged: onInvoiceNumberChanged,
            onAutoGenerateChanged: onAutoGenerateInvoiceNumberChanged,
            isRequired: true,
            label: 'شماره فاکتور',
            hintText: autoGenerateInvoiceNumber && invoiceNumberLoading
                ? 'در حال دریافت شماره...'
                : 'مثال: INV-2024-001',
            autoGenerateCode: autoGenerateInvoiceNumber,
            invoiceDocumentCode: true,
            showAutoManualToggle: showAutoGenerateToggle,
          ),
          if (autoGenerateInvoiceNumber && invoiceNumberLoading)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (autoGenerateInvoiceNumber &&
              invoiceNumberReserveError != null &&
              invoiceNumberReserveError!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      invoiceNumberReserveError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (onRetryReserveInvoiceNumber != null)
                    TextButton(
                      onPressed: onRetryReserveInvoiceNumber,
                      child: const Text('تلاش مجدد'),
                    ),
                ],
              ),
            ),
        ],
      ),
      DateInputField(
        value: invoiceDate,
        labelText: 'تاریخ فاکتور *',
        hintText: 'انتخاب تاریخ',
        calendarController: calendarController,
        onChanged: onInvoiceDateChanged,
        isDense: true,
      ),
      DateInputField(
        value: dueDate,
        labelText: 'تاریخ سررسید',
        hintText: 'انتخاب تاریخ',
        calendarController: calendarController,
        onChanged: onDueDateChanged,
        isDense: true,
      ),
      if (counterparty != null) counterparty,
      CurrencyPickerWidget(
        businessId: businessId,
        selectedCurrencyId: selectedCurrencyId,
        onChanged: onCurrencyChanged,
        label: 'ارز فاکتور',
        hintText: 'انتخاب ارز',
        isDense: true,
      ),
      if (showFxRateField)
        InvoiceFxRateField(
          show: true,
          loading: loadingFxRates,
          manualRateId: manualFxRateId,
          rateRows: fxRateRows,
          onChanged: onFxRateChanged,
        ),
      ProjectSelectorWidget(
        businessId: businessId,
        apiClient: ApiClient(),
        selectedProjectId: selectedProjectId,
        onChanged: onProjectChanged,
        allowNull: true,
        labelText: 'پروژه',
        isDense: true,
      ),
      TextFormField(
        initialValue: invoiceReference,
        onChanged: (value) {
          onInvoiceReferenceChanged(value.trim().isEmpty ? null : value.trim());
        },
        decoration: InvoiceFormFieldMetrics.mergeDecoration(
          context,
          const InputDecoration(
            labelText: 'ارجاع',
            hintText: 'مثال: PO-2024-001',
          ),
        ),
        textInputAction: TextInputAction.next,
      ),
      if (showSellerCommissionSection && _isSalesFamily)
        SellerPickerWidget(
          selectedSeller: selectedSeller,
          onSellerChanged: onSellerChanged,
          businessId: businessId,
          authStore: authStore,
          isRequired: false,
          label: 'فروشنده/بازاریاب',
          hintText: 'انتخاب فروشنده',
          showFinancialBalance: false,
        ),
      if (showSellerCommissionSection && _isSalesFamily && selectedSeller != null)
        CommissionTypeSelector(
          selectedType: commissionType,
          onTypeChanged: onCommissionTypeChanged,
          isRequired: false,
          label: 'نوع کارمزد',
          hintText: 'انتخاب نوع',
          compact: true,
        ),
      if (showSellerCommissionSection &&
          _isSalesFamily &&
          selectedSeller != null &&
          commissionType == CommissionType.percentage)
        CommissionPercentageField(
          initialValue: commissionPercentage,
          onChanged: onCommissionPercentageChanged,
          isRequired: false,
          label: 'درصد کارمزد',
          hintText: 'مثال: 5.5',
        ),
      if (showSellerCommissionSection &&
          _isSalesFamily &&
          selectedSeller != null &&
          commissionType == CommissionType.amount)
        CommissionAmountField(
          initialValue: commissionAmount,
          onChanged: onCommissionAmountChanged,
          isRequired: false,
          label: 'مبلغ کارمزد',
          hintText: 'مثال: 100000',
          currencyUnit: currencyUnitLabel,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (header != null) ...[
          header!,
          const SizedBox(height: InvoiceFormFieldMetrics.blockSpacing),
        ],
        if (showToggles)
          Padding(
            padding: const EdgeInsets.only(bottom: InvoiceFormFieldMetrics.blockSpacing),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (enableDraftToggle)
                  InvoiceFormCompactToggle(
                    label: 'پیش‌نویس',
                    value: isDraft,
                    onChanged: onDraftChanged,
                  ),
                if (showAutoGenerateToggle)
                  InvoiceFormCompactToggle(
                    label: 'شماره خودکار',
                    value: autoGenerateInvoiceNumber,
                    onChanged: onAutoGenerateInvoiceNumberChanged,
                  ),
              ],
            ),
          ),
        InvoiceFormGrid(children: gridChildren),
        const SizedBox(height: InvoiceFormFieldMetrics.blockSpacing),
        InvoiceTagsField(
          businessId: businessId,
          apiClient: ApiClient(),
          selectedTagIds: selectedTagIds,
          onChanged: onTagsChanged,
          embedded: true,
        ),
        const SizedBox(height: InvoiceFormFieldMetrics.blockSpacing),
        FrequentDescriptionTextField(
          businessId: businessId,
          scope: FrequentDescriptionScope.invoice,
          controller: invoiceTitleController,
          onChanged: onInvoiceTitleChanged,
          decoration: InvoiceFormFieldMetrics.mergeDecoration(
            context,
            InputDecoration(
              labelText: t.invoiceHeaderDescriptionLabel,
              hintText: t.invoiceHeaderDescriptionHint,
              alignLabelWithHint: true,
            ),
          ),
          textInputAction: TextInputAction.next,
          maxLines: 2,
        ),
      ],
    );
  }
}
