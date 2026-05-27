import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import '../../utils/number_formatters.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/permission/permission_widgets.dart';
import '../../widgets/invoice/person_combobox_widget.dart';
import '../../models/person_model.dart';
import '../../services/check_service.dart';
import '../../widgets/invoice/bank_account_combobox_widget.dart';
import 'check_form_page.dart';
import 'check_details_dialog.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../services/list_filter_preferences_service.dart';

class ChecksPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const ChecksPage({super.key, required this.businessId, required this.authStore, required this.calendarController});

  @override
  State<ChecksPage> createState() => _ChecksPageState();

  /// Static map to store page states by business ID for external refresh
  static final Map<int, _ChecksPageState> _pageStates = {};

  /// Get the page state for a specific business ID
  // ignore: library_private_types_in_public_api
  static _ChecksPageState? getPageState(int businessId) {
    return _pageStates[businessId];
  }

  /// Clear the page state for a specific business ID
  static void clearPageState(int businessId) {
    _pageStates.remove(businessId);
  }
}

class _ChecksPageState extends State<ChecksPage> {
  final GlobalKey _tableKey = GlobalKey();
  Person? _selectedPerson;
  final _checkService = CheckService();

  @override
  void initState() {
    super.initState();
    // Register this page instance for external refresh access
    ChecksPage._pageStates[widget.businessId] = this;
  }

  @override
  void dispose() {
    // Clean up the page state when disposed
    ChecksPage._pageStates.remove(widget.businessId);
    super.dispose();
  }

  void _refresh() {
    try {
      (_tableKey.currentState as dynamic)?.refresh();
    } catch (_) {}
  }

  /// Public method to refresh the data table
  void refresh() {
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    if (!widget.authStore.canReadSection('checks')) {
      return AccessDeniedPage(message: t.accessDenied);
    }

    return Scaffold(
      body: SingleChildScrollView(
        child: DataTableWidget<Map<String, dynamic>>(
          key: _tableKey,
          config: _buildConfig(t, context),
          fromJson: (json) => json,
          calendarController: widget.calendarController,
        ),
      ),
    );
  }

  DataTableConfig<Map<String, dynamic>> _buildConfig(AppLocalizations t, BuildContext context) {
    String formatCheckDate(Map<String, dynamic> row, String key) {
      return HesabixDateUtils.formatApiDateForDisplay(
        row[key],
        widget.calendarController.isJalali,
        rawValue: row['${key}_raw'],
      );
    }

    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/checks/businesses/${widget.businessId}/checks',
      businessId: widget.businessId,
      persistTableFiltersPageId: ListFilterPageIds.checksTable,
      title: (t.localeName == 'fa') ? 'چک‌ها' : 'Checks',
      excelEndpoint: '/api/v1/checks/businesses/${widget.businessId}/checks/export/excel',
      pdfEndpoint: '/api/v1/checks/businesses/${widget.businessId}/checks/export/pdf',
      getExportParams: () => {
        'business_id': widget.businessId,
        if (_selectedPerson != null) 'person_id': _selectedPerson!.id,
      },
      additionalParams: {if (_selectedPerson != null) 'person_id': _selectedPerson!.id},
      showBackButton: true,
      onBack: () {
        if (!mounted) return;
        if (context.canPop()) {
          context.pop();
        }
      },
      showTableIcon: false,
      showRowNumbers: true,
      enableRowSelection: true,
      enableMultiRowSelection: true,
      showColumnSearch: true,
      showActiveFilters: true,
      showClearFiltersButton: true,
      columns: [
        TextColumn(
          'type',
          'نوع',
          width: ColumnWidth.small,
          filterType: ColumnFilterType.multiSelect,
          filterOptions: const [
            FilterOption(value: 'received', label: 'دریافتی'),
            FilterOption(value: 'transferred', label: 'پرداختنی'),
          ],
          formatter: (row) =>
              (row['type'] == 'received') ? 'دریافتی' : (row['type'] == 'transferred' ? 'پرداختنی' : '-'),
        ),
        TextColumn(
          'person_name',
          'صادرکننده / طرف',
          width: ColumnWidth.large,
          formatter: (row) => (row['drawer_person_name'] ?? row['person_name'] ?? '-'),
        ),
        TextColumn(
          'endorsed_to_person_name',
          'واگذار به',
          width: ColumnWidth.medium,
          formatter: (row) {
            final name = row['endorsed_to_person_name'] ?? row['current_holder_name'];
            if (name != null && name.toString().isNotEmpty) return name.toString();
            final status = (row['status'] ?? '').toString();
            return status == 'ENDORSED' ? '-' : '';
          },
        ),
        DateColumn(
          'issue_date',
          'تاریخ صدور',
          width: ColumnWidth.medium,
          filterType: ColumnFilterType.dateRange,
          formatter: (row) => formatCheckDate(row, 'issue_date'),
        ),
        DateColumn(
          'due_date',
          'تاریخ سررسید',
          width: ColumnWidth.medium,
          filterType: ColumnFilterType.dateRange,
          formatter: (row) => formatCheckDate(row, 'due_date'),
        ),
        TextColumn(
          'check_number',
          'شماره چک',
          width: ColumnWidth.medium,
          formatter: (row) => (row['check_number'] ?? '-'),
        ),
        TextColumn(
          'sayad_code',
          'شناسه صیاد',
          width: ColumnWidth.medium,
          formatter: (row) => (row['sayad_code'] ?? '-'),
        ),
        TextColumn('bank_name', 'بانک', width: ColumnWidth.medium, formatter: (row) => (row['bank_name'] ?? '-')),
        TextColumn('branch_name', 'شعبه', width: ColumnWidth.medium, formatter: (row) => (row['branch_name'] ?? '-')),
        NumberColumn(
          'amount',
          'مبلغ',
          width: ColumnWidth.medium,
          formatter: (row) => formatWithThousands(row['amount']),
        ),
        TextColumn('currency', 'ارز', width: ColumnWidth.small, formatter: (row) => (row['currency'] ?? '-')),
        TextColumn(
          'status',
          'وضعیت',
          width: ColumnWidth.medium,
          filterType: ColumnFilterType.multiSelect,
          filterOptions: const [
            FilterOption(value: 'RECEIVED_ON_HAND', label: 'در دست (دریافتی)'),
            FilterOption(value: 'TRANSFERRED_ISSUED', label: 'صادر شده (پرداختنی)'),
            FilterOption(value: 'DEPOSITED', label: 'سپرده به بانک'),
            FilterOption(value: 'CLEARED', label: 'پاس/وصول شده'),
            FilterOption(value: 'ENDORSED', label: 'واگذاری به شخص'),
            FilterOption(value: 'RETURNED', label: 'عودت شده'),
            FilterOption(value: 'BOUNCED', label: 'برگشت خورده'),
            FilterOption(value: 'CANCELLED', label: 'ابطال'),
          ],
          formatter: (row) {
            final s = (row['status'] ?? '').toString();
            switch (s) {
              case 'RECEIVED_ON_HAND':
                return 'در دست (دریافتی)';
              case 'TRANSFERRED_ISSUED':
                return 'صادر شده (پرداختنی)';
              case 'DEPOSITED':
                return 'سپرده به بانک';
              case 'CLEARED':
                return 'پاس/وصول شده';
              case 'ENDORSED':
                return 'واگذاری به شخص';
              case 'RETURNED':
                return 'عودت شده';
              case 'BOUNCED':
                return 'برگشت خورده';
              case 'CANCELLED':
                return 'ابطال';
            }
            return '-';
          },
        ),
        ActionColumn(
          'actions',
          t.actions,
          actions: [
            DataTableAction(
              icon: Icons.edit,
              label: t.edit,
              onTap: (row) {
                final id = row is Map<String, dynamic> ? row['id'] : null;
                if (id is int) {
                  _showCheckFormDialog(context, checkId: id);
                }
              },
            ),
            DataTableAction(
              icon: Icons.arrow_forward,
              label: 'واگذاری',
              onTap: (row) {
                final type = (row['type'] ?? '').toString();
                final status = (row['status'] ?? '').toString();
                final can =
                    type == 'received' &&
                    (status.isEmpty || ['RECEIVED_ON_HAND', 'RETURNED', 'BOUNCED'].contains(status));
                if (can) {
                  _openEndorseDialog(context, row as Map<String, dynamic>);
                } else {
                  SnackBarHelper.show(context, message: 'این عملیات برای وضعیت فعلی مجاز نیست');
                }
              },
            ),
            DataTableAction(
              icon: Icons.check_circle,
              label: 'وصول',
              onTap: (row) {
                final type = (row['type'] ?? '').toString();
                final status = (row['status'] ?? '').toString();
                if (type == 'received' && status != 'CLEARED') {
                  _openClearDialog(context, row as Map<String, dynamic>);
                } else {
                  SnackBarHelper.show(context, message: 'این عملیات برای این چک قابل انجام نیست');
                }
              },
            ),
            DataTableAction(
              icon: Icons.payment,
              label: 'پرداخت',
              onTap: (row) {
                final type = (row['type'] ?? '').toString();
                final status = (row['status'] ?? '').toString();
                if (type == 'transferred' && status != 'CLEARED') {
                  _openPayDialog(context, row as Map<String, dynamic>);
                } else {
                  SnackBarHelper.show(context, message: 'این عملیات برای این چک قابل انجام نیست');
                }
              },
            ),
            DataTableAction(
              icon: Icons.reply,
              label: 'عودت',
              onTap: (row) => _confirmReturn(context, row as Map<String, dynamic>),
            ),
            DataTableAction(
              icon: Icons.block,
              label: 'برگشت',
              onTap: (row) {
                final type = (row['type'] ?? '').toString();
                final status = (row['status'] ?? '').toString();
                final canBounceReceived =
                    type == 'received' && (status == 'DEPOSITED' || status == 'CLEARED');
                final canBounceTransferred = type == 'transferred' && status != 'CLEARED';
                if (canBounceReceived || canBounceTransferred) {
                  _confirmBounce(context, row as Map<String, dynamic>);
                } else if (type == 'received') {
                  SnackBarHelper.show(
                    context,
                    message: 'برگشت از بانک فقط برای چک سپرده‌شده یا پاس‌شده مجاز است',
                  );
                } else {
                  SnackBarHelper.show(context, message: 'این عملیات برای وضعیت فعلی مجاز نیست');
                }
              },
            ),
            DataTableAction(
              icon: Icons.account_balance,
              label: 'سپرده',
              onTap: (row) {
                final type = (row['type'] ?? '').toString();
                final status = (row['status'] ?? '').toString();
                if (type == 'received' && (status.isEmpty || status == 'RECEIVED_ON_HAND')) {
                  _confirmDeposit(context, row as Map<String, dynamic>);
                } else {
                  SnackBarHelper.show(context, message: 'این عملیات برای وضعیت فعلی مجاز نیست');
                }
              },
            ),
            if (widget.authStore.canWriteSection('checks'))
              DataTableAction(
                icon: Icons.delete,
                label: t.delete,
                onTap: (row) {
                  _confirmDelete(context, row as Map<String, dynamic>);
                },
                isDestructive: true,
              ),
          ],
        ),
      ],
      searchFields: ['check_number', 'sayad_code', 'bank_name', 'branch_name', 'person_name'],
      filterFields: ['type', 'currency', 'issue_date', 'due_date', 'status'],
      defaultPageSize: 20,
      customHeaderActions: [
        // فیلتر شخص
        SizedBox(
          width: 280,
          child: PersonComboboxWidget(
            businessId: widget.businessId,
            selectedPerson: _selectedPerson,
            onChanged: (p) {
              setState(() {
                _selectedPerson = p;
              });
            },
            isRequired: false,
            label: 'شخص',
            hintText: 'جست‌وجوی شخص',
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'راس‌گیری چک‌ها',
          child: IconButton(
            onPressed: () {
              context.go('/business/${widget.businessId}/checks/reconciliation');
            },
            icon: const Icon(Icons.calculate),
          ),
        ),
        const SizedBox(width: 8),
        PermissionButton(
          section: 'checks',
          action: 'add',
          authStore: widget.authStore,
          child: Tooltip(
            message: t.add,
            child: IconButton(onPressed: () => _showCheckFormDialog(context), icon: const Icon(Icons.add)),
          ),
        ),
      ],
      expandBodyHeightToFitRows: true,
      onRowTap: (row) {
        _showCheckDetailsDialog(context, row as Map<String, dynamic>);
      },
    );
  }

  Future<void> _openEndorseDialog(BuildContext context, Map<String, dynamic> row) async {
    Person? selectedPerson;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('واگذاری چک به شخص'),
            content: SizedBox(
              width: 360,
              child: PersonComboboxWidget(
                businessId: widget.businessId,
                showFinancialBalance: true,
                selectedPerson: selectedPerson,
                onChanged: (p) {
                  setDialogState(() {
                    selectedPerson = p;
                  });
                },
                isRequired: true,
                label: 'شخص مقصد',
                hintText: 'انتخاب شخص',
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
              FilledButton(
                onPressed: () async {
                  if (selectedPerson == null) return;
                  if (!context.mounted) return;
                  try {
                    await _checkService.endorse(
                      checkId: row['id'] as int,
                      body: {'target_person_id': selectedPerson!.id},
                    );
                    if (!context.mounted) return;
                    Navigator.pop(ctx);
                    _refresh();
                  } catch (e) {
                    if (!context.mounted) return;
                    Navigator.pop(ctx);
                    SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
                  }
                },
                child: const Text('ثبت'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openClearDialog(BuildContext context, Map<String, dynamic> row) async {
    BankAccountOption? selected;
    final currencyId = row['currency_id'] as int?;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('وصول چک به بانک'),
        content: SizedBox(
          width: 420,
          child: BankAccountComboboxWidget(
            businessId: widget.businessId,
            selectedAccountId: null,
            filterCurrencyId: currencyId,
            onChanged: (opt) => selected = opt,
            label: 'حساب بانکی',
            hintText: 'انتخاب حساب بانکی',
            isRequired: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
            onPressed: () async {
              if (selected == null || (selected!.id).isEmpty) return;
              if (!context.mounted) return;
              try {
                await _checkService.clear(
                  checkId: row['id'] as int,
                  body: {'bank_account_id': int.tryParse(selected!.id) ?? 0},
                );
                if (!context.mounted) return;
                Navigator.pop(ctx);
                _refresh();
              } catch (e) {
                if (!context.mounted) return;
                Navigator.pop(ctx);
                SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
              }
            },
            child: const Text('ثبت'),
          ),
        ],
      ),
    );
  }

  Future<void> _openPayDialog(BuildContext context, Map<String, dynamic> row) async {
    BankAccountOption? selected;
    final currencyId = row['currency_id'] as int?;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('پرداخت چک پرداختنی'),
        content: SizedBox(
          width: 420,
          child: BankAccountComboboxWidget(
            businessId: widget.businessId,
            selectedAccountId: null,
            filterCurrencyId: currencyId,
            onChanged: (opt) => selected = opt,
            label: 'حساب بانکی',
            hintText: 'انتخاب حساب بانکی',
            isRequired: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
            onPressed: () async {
              if (selected == null || (selected!.id).isEmpty) return;
              if (!context.mounted) return;
              try {
                await _checkService.pay(
                  checkId: row['id'] as int,
                  body: {'bank_account_id': int.tryParse(selected!.id) ?? 0},
                );
                if (!context.mounted) return;
                Navigator.pop(ctx);
                _refresh();
              } catch (e) {
                if (!context.mounted) return;
                Navigator.pop(ctx);
                SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
              }
            },
            child: const Text('ثبت'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReturn(BuildContext context, Map<String, dynamic> row) async {
    final type = (row['type'] ?? '').toString();
    final status = (row['status'] ?? '').toString();
    final checkId = row['id'] as int;

    if (status == 'CLEARED') {
      SnackBarHelper.show(context, message: 'چک پاس‌شده قابل عودت نیست');
      return;
    }
    if (status == 'CANCELLED') {
      SnackBarHelper.show(context, message: 'چک ابطال‌شده قابل عودت نیست');
      return;
    }

    String? returnType;
    String confirmMessage;

    if (type == 'transferred') {
      if (status == 'RETURNED') {
        SnackBarHelper.show(context, message: 'این چک قبلاً عودت شده است');
        return;
      }
      confirmMessage = 'چک پرداختنی به وضعیت عودت‌شده منتقل می‌شود. ادامه می‌دهید؟';
    } else if (type == 'received') {
      if (status == 'RETURNED') {
        SnackBarHelper.show(context, message: 'این چک قبلاً به صادرکننده عودت شده است');
        return;
      }
      if (status == 'ENDORSED') {
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) {
            var selected = 'from_endorsee';
            return StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                title: const Text('نوع عودت چک'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'چک به ${row['endorsed_to_person_name'] ?? row['current_holder_name'] ?? 'شخص واگذارشونده'} واگذار شده است.',
                    ),
                    const SizedBox(height: 16),
                    RadioListTile<String>(
                      title: const Text('برگشت از واگذارشونده'),
                      subtitle: const Text('چک دوباره در دست شما می‌ماند (اسناد دریافتنی)'),
                      value: 'from_endorsee',
                      groupValue: selected,
                      onChanged: (v) => setState(() => selected = v ?? 'from_endorsee'),
                    ),
                    RadioListTile<String>(
                      title: const Text('عودت به صادرکننده'),
                      subtitle: Text(
                        'لغو واگذاری و برگشت چک به ${row['drawer_person_name'] ?? row['person_name'] ?? 'صادرکننده'}',
                      ),
                      value: 'to_drawer',
                      groupValue: selected,
                      onChanged: (v) => setState(() => selected = v ?? 'to_drawer'),
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('ادامه')),
                ],
              ),
            );
          },
        );
        if (choice == null || !context.mounted) return;
        returnType = choice;
        confirmMessage = choice == 'from_endorsee'
            ? 'چک از واگذارشونده به دست شما برمی‌گردد. ادامه می‌دهید؟'
            : 'واگذاری لغو و چک به صادرکننده عودت داده می‌شود. ادامه می‌دهید؟';
      } else if (status.isEmpty ||
          status == 'RECEIVED_ON_HAND' ||
          status == 'BOUNCED' ||
          status == 'DEPOSITED') {
        returnType = 'to_drawer';
        final drawer = row['drawer_person_name'] ?? row['person_name'] ?? 'صادرکننده';
        confirmMessage = status == 'DEPOSITED'
            ? 'چک از سپرده خارج و سپس به $drawer عودت داده می‌شود. ادامه می‌دهید؟'
            : 'چک به $drawer (صادرکننده) عودت داده می‌شود. ادامه می‌دهید؟';
      } else {
        SnackBarHelper.show(context, message: 'عودت در وضعیت فعلی مجاز نیست');
        return;
      }
    } else {
      SnackBarHelper.show(context, message: 'نوع چک نامعتبر است');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأیید عودت'),
        content: Text(confirmMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('خیر')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بله')),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    try {
      final body = <String, dynamic>{};
      if (returnType != null) {
        body['return_type'] = returnType;
      }
      if (returnType == 'from_endorsee') {
        final holderId = row['current_holder_id'] ?? row['endorsed_to_person_id'];
        if (holderId != null) {
          body['target_person_id'] = holderId;
        }
      }
      await _checkService.returnCheck(checkId: checkId, body: body);
      _refresh();
      if (context.mounted) {
        SnackBarHelper.showSuccess(context, message: 'عودت با موفقیت ثبت شد');
      }
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  Future<void> _confirmBounce(BuildContext context, Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('برگشت چک'),
        content: const Text('آیا از برگشت این چک مطمئن هستید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('خیر')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بله')),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    try {
      await _checkService.bounce(checkId: row['id'] as int, body: {});
      _refresh();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  Future<void> _confirmDeposit(BuildContext context, Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سپرده چک به بانک'),
        content: const Text('چک به اسناد در جریان وصول منتقل می‌شود.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید')),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    try {
      await _checkService.deposit(checkId: row['id'] as int, body: {});
      _refresh();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  Future<void> _confirmDelete(BuildContext context, Map<String, dynamic> row) async {
    final checkNumber = row['check_number']?.toString() ?? 'نامشخص';
    final status = (row['status'] ?? '').toString();

    // بررسی وضعیت چک
    if (status == 'CLEARED') {
      SnackBarHelper.show(context, message: 'نمی‌توان چک پاس شده را حذف کرد');
      return;
    }

    if (status == 'DEPOSITED') {
      SnackBarHelper.show(context, message: 'نمی‌توان چک سپرده شده را حذف کرد. لطفاً ابتدا چک را از سپرده خارج کنید');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف چک'),
        content: Text(
          'آیا از حذف چک شماره $checkNumber مطمئن هستید؟\n\nتوجه: تمام اسناد حسابداری مرتبط با این چک نیز حذف خواهند شد.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (!context.mounted) return;

    try {
      await _checkService.delete(row['id'] as int);
      if (!context.mounted) return;
      SnackBarHelper.show(context, message: 'چک با موفقیت حذف شد');
      _refresh();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.show(context, message: 'خطا در حذف چک: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  void _showCheckDetailsDialog(BuildContext context, Map<String, dynamic> row) {
    final checkId = row['id'] as int?;
    if (checkId == null) return;

    showDialog(
      context: context,
      builder: (ctx) => CheckDetailsDialog(
        checkId: checkId,
        businessId: widget.businessId,
        authStore: widget.authStore,
        calendarController: widget.calendarController,
        initialData: row,
        onEdit: () {
          Navigator.pop(ctx);
          _showCheckFormDialog(context, checkId: checkId);
        },
      ),
    );
  }

  Future<void> _showCheckFormDialog(BuildContext context, {int? checkId}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => CheckFormDialog(
        businessId: widget.businessId,
        authStore: widget.authStore,
        checkId: checkId,
        calendarController: widget.calendarController,
        onSuccess: () {
          _refresh();
        },
      ),
    );
    if (result == true) {
      _refresh();
    }
  }
}
