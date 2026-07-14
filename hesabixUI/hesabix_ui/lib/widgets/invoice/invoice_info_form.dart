import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/customer_model.dart';
import 'package:hesabix_ui/models/invoice_type_model.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';
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

/// فرم تب «اطلاعات فاکتور» با چیدمان بخش‌بندی‌شده و ارتفاع یکسان فیلدها.
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
  final bool reserveFxLayoutSlot;

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
    this.reserveFxLayoutSlot = true,
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isJalali = calendarController.isJalali == true;
    final dateLabel = invoiceDate == null
        ? null
        : HesabixDateUtils.formatForDisplay(invoiceDate, isJalali);
    final numberLabel = autoGenerateInvoiceNumber && showAutoGenerateToggle
        ? 'خودکار'
        : (invoiceNumber?.trim().isNotEmpty == true ? invoiceNumber!.trim() : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) ...[
          header!,
          const SizedBox(height: InvoiceFormFieldMetrics.sectionSpacing),
        ],
        InvoiceInfoSummaryBar(
          typeLabel: selectedInvoiceType?.label,
          numberLabel: numberLabel,
          dateLabel: dateLabel,
          currencyLabel: currencyUnitLabel,
          isDraft: isDraft,
        ),
        const SizedBox(height: InvoiceFormFieldMetrics.sectionSpacing),
        InvoiceFormSectionCard(
          icon: Icons.badge_outlined,
          title: 'شناسه سند',
          trailing: showAutoGenerateToggle || enableDraftToggle
              ? Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (enableDraftToggle)
                      InvoiceFormInlineToggle(
                        label: 'پیش‌نویس',
                        tooltip: isDraft
                            ? 'حالت پیش‌نویس فعال است'
                            : 'فعال کردن حالت پیش‌نویس',
                        value: isDraft,
                        onChanged: onDraftChanged,
                        icon: Icons.edit_note_outlined,
                      ),
                    if (showAutoGenerateToggle)
                      InvoiceFormInlineToggle(
                        label: 'شماره خودکار',
                        tooltip: autoGenerateInvoiceNumber
                            ? 'تولید خودکار شماره فعال است'
                            : 'تولید دستی شماره فعال است',
                        value: autoGenerateInvoiceNumber,
                        onChanged: onAutoGenerateInvoiceNumberChanged,
                        icon: Icons.auto_fix_high_outlined,
                      ),
                  ],
                )
              : null,
          children: [
            InvoiceFormGrid(
              children: [
                InvoiceFormFieldShell(
                  child: InvoiceTypeCombobox(
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
                  ),
                ),
                InvoiceFormFieldShell(
                  helperText: showAutoGenerateToggle && autoGenerateInvoiceNumber
                      ? 'شماره هنگام ذخیره تولید می‌شود'
                      : null,
                  child: CodeFieldWidget(
                    initialValue: invoiceNumber,
                    onChanged: onInvoiceNumberChanged,
                    onAutoGenerateChanged: onAutoGenerateInvoiceNumberChanged,
                    isRequired: true,
                    label: 'شماره فاکتور',
                    hintText: 'مثال: INV-2024-001',
                    autoGenerateCode: autoGenerateInvoiceNumber,
                    invoiceDocumentCode: true,
                    showAutoManualToggle: showAutoGenerateToggle,
                  ),
                ),
                InvoiceFormFieldShell(
                  child: DateInputField(
                    value: invoiceDate,
                    labelText: 'تاریخ فاکتور *',
                    hintText: 'انتخاب تاریخ فاکتور',
                    calendarController: calendarController,
                    onChanged: onInvoiceDateChanged,
                  ),
                ),
                InvoiceFormFieldShell(
                  child: DateInputField(
                    value: dueDate,
                    labelText: 'تاریخ سررسید',
                    hintText: 'انتخاب تاریخ سررسید',
                    calendarController: calendarController,
                    onChanged: onDueDateChanged,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: InvoiceFormFieldMetrics.sectionSpacing),
        InvoiceFormSectionCard(
          icon: Icons.payments_outlined,
          title: 'تاریخ و ارز',
          children: [
            InvoiceFormGrid(
              children: [
                InvoiceFormFieldShell(
                  child: CurrencyPickerWidget(
                    businessId: businessId,
                    selectedCurrencyId: selectedCurrencyId,
                    onChanged: onCurrencyChanged,
                    label: 'ارز فاکتور',
                    hintText: 'انتخاب ارز فاکتور',
                  ),
                ),
                InvoiceFormAnimatedSlot(
                  visible: showFxRateField || reserveFxLayoutSlot,
                  child: InvoiceFxRateField(
                    show: showFxRateField,
                    loading: loadingFxRates,
                    manualRateId: manualFxRateId,
                    rateRows: fxRateRows,
                    onChanged: onFxRateChanged,
                    reserveLayoutSlot: reserveFxLayoutSlot,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: InvoiceFormFieldMetrics.sectionSpacing),
        InvoiceFormAnimatedSlot(
          visible: _showsCounterparty || (showSellerCommissionSection && _isSalesFamily),
          child: InvoiceFormSectionCard(
            icon: Icons.handshake_outlined,
            title: 'طرف معامله',
            children: [
              InvoiceFormGrid(
                children: [
                  if (_isSalesFamily)
                    InvoiceFormFieldShell(
                      child: CustomerComboboxWidget(
                        selectedCustomer: selectedCustomer,
                        onCustomerChanged: onCustomerChanged,
                        businessId: businessId,
                        authStore: authStore,
                        isRequired: false,
                        label: 'طرف حساب',
                        hintText: 'انتخاب طرف حساب',
                        showFinancialBalance: true,
                      ),
                    ),
                  if (_isPurchaseFamily)
                    InvoiceFormFieldShell(
                      child: PersonComboboxWidget(
                        businessId: businessId,
                        showFinancialBalance: true,
                        selectedPerson: selectedSupplier,
                        onChanged: onSupplierChanged,
                        isRequired: false,
                        label: 'تامین‌کننده',
                        hintText: 'انتخاب تامین‌کننده',
                        personTypes: const ['تامین‌کننده', 'فروشنده'],
                        searchHint: 'جست‌وجو در تامین‌کنندگان...',
                      ),
                    ),
                  if (showSellerCommissionSection && _isSalesFamily)
                    InvoiceFormFieldShell(
                      child: SellerPickerWidget(
                        selectedSeller: selectedSeller,
                        onSellerChanged: onSellerChanged,
                        businessId: businessId,
                        authStore: authStore,
                        isRequired: false,
                        label: 'فروشنده/بازاریاب',
                        hintText: 'جست‌وجو و انتخاب فروشنده یا بازاریاب',
                        showFinancialBalance: false,
                      ),
                    ),
                  if (showSellerCommissionSection && _isSalesFamily && selectedSeller != null)
                    InvoiceFormFieldShell(
                      child: CommissionTypeSelector(
                        selectedType: commissionType,
                        onTypeChanged: onCommissionTypeChanged,
                        isRequired: false,
                        label: 'نوع کارمزد',
                        hintText: 'انتخاب نوع کارمزد',
                      ),
                    ),
                  if (showSellerCommissionSection &&
                      _isSalesFamily &&
                      selectedSeller != null &&
                      commissionType == CommissionType.percentage)
                    InvoiceFormFieldShell(
                      child: CommissionPercentageField(
                        initialValue: commissionPercentage,
                        onChanged: onCommissionPercentageChanged,
                        isRequired: false,
                        label: 'درصد کارمزد',
                        hintText: 'مثال: 5.5',
                      ),
                    ),
                  if (showSellerCommissionSection &&
                      _isSalesFamily &&
                      selectedSeller != null &&
                      commissionType == CommissionType.amount)
                    InvoiceFormFieldShell(
                      child: CommissionAmountField(
                        initialValue: commissionAmount,
                        onChanged: onCommissionAmountChanged,
                        isRequired: false,
                        label: 'مبلغ کارمزد',
                        hintText: 'مثال: 100000',
                        currencyUnit: currencyUnitLabel,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: InvoiceFormFieldMetrics.sectionSpacing),
        InvoiceFormSectionCard(
          icon: Icons.folder_open_outlined,
          title: 'طبقه‌بندی و توضیحات',
          children: [
            InvoiceFormGrid(
              children: [
                InvoiceFormFieldShell(
                  child: ProjectSelectorWidget(
                    businessId: businessId,
                    apiClient: ApiClient(),
                    selectedProjectId: selectedProjectId,
                    onChanged: onProjectChanged,
                    allowNull: true,
                    labelText: 'پروژه (اختیاری)',
                  ),
                ),
                InvoiceFormFieldShell(
                  child: TextFormField(
                    initialValue: invoiceReference,
                    onChanged: (value) {
                      onInvoiceReferenceChanged(
                        value.trim().isEmpty ? null : value.trim(),
                      );
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
                ),
              ],
            ),
            const SizedBox(height: InvoiceFormFieldMetrics.gridSpacing),
            InvoiceTagsField(
              businessId: businessId,
              apiClient: ApiClient(),
              selectedTagIds: selectedTagIds,
              onChanged: onTagsChanged,
              embedded: true,
            ),
            const SizedBox(height: InvoiceFormFieldMetrics.gridSpacing),
            InvoiceFormFieldShell(
              multiline: true,
              minMultilineHeight: ResponsiveHelper.isMobile(context) ? 88 : 96,
              reserveHelperSlot: false,
              child: FrequentDescriptionTextField(
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
                maxLines: 3,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
