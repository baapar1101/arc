import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/permission/permission_widgets.dart';
import '../../core/auth_store.dart';
import '../../models/bank_account_model.dart';
import '../../widgets/banking/bank_account_form_dialog.dart';
import '../../services/bank_account_service.dart';
import '../../services/currency_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/number_formatters.dart';

class BankAccountsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const BankAccountsPage({super.key, required this.businessId, required this.authStore});

  @override
  State<BankAccountsPage> createState() => _BankAccountsPageState();
}

class _BankAccountsPageState extends State<BankAccountsPage> {
  final _bankAccountService = BankAccountService();
  final _currencyService = CurrencyService(ApiClient());
  final GlobalKey _bankAccountsTableKey = GlobalKey();
  Map<int, String> _currencyNames = {};

  @override
  void initState() {
    super.initState();
    _loadCurrencies();
  }

  Future<void> _loadCurrencies() async {
    try {
      final currencies = await _currencyService.listBusinessCurrencies(
        businessId: widget.businessId,
      );
      final currencyMap = <int, String>{};
      for (final currency in currencies) {
        currencyMap[currency['id'] as int] = '${currency['title']} (${currency['code']})';
      }
      setState(() {
        _currencyNames = currencyMap;
      });
    } catch (e) {
      // Handle error silently for now
    }
  }

  /// Public method to refresh the data table
  void refresh() {
    try {
      (_bankAccountsTableKey.currentState as dynamic)?.refresh();
    } catch (_) {}
  }

  @override
  void didUpdateWidget(BankAccountsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // This will be called when the widget is updated
    // Refresh the data table to show any new data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    if (!widget.authStore.canReadSection('bank_accounts')) {
      return AccessDeniedPage(message: t.accessDenied);
    }

    return Scaffold(
      body: DataTableWidget<BankAccount>(
        key: _bankAccountsTableKey,
        config: _buildDataTableConfig(t),
        fromJson: BankAccount.fromJson,
      ),
    );
  }

  DataTableConfig<BankAccount> _buildDataTableConfig(AppLocalizations t) {
    return DataTableConfig<BankAccount>(
      endpoint: '/api/v1/bank-accounts/businesses/${widget.businessId}/bank-accounts',
      title: t.accounts,
      excelEndpoint: '/api/v1/bank-accounts/businesses/${widget.businessId}/bank-accounts/export/excel',
      pdfEndpoint: '/api/v1/bank-accounts/businesses/${widget.businessId}/bank-accounts/export/pdf',
      businessId: widget.businessId,
      reportModuleKey: 'bank_accounts',
      reportSubtype: 'list',
      getExportParams: () => {'business_id': widget.businessId},
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
      columns: [
        TextColumn(
          'code',
          t.code,
          width: ColumnWidth.small,
          formatter: (account) => (account.code?.toString() ?? '-'),
          textAlign: TextAlign.center,
        ),
        CustomColumn(
          'name',
          t.title,
          width: ColumnWidth.large,
          formatter: (account) => account.name,
          builder: (account, index) {
            final accountName = account.name;
            return InkWell(
              onTap: () {
                if (account.id != null) {
                  context.go(
                    '/business/${widget.businessId}/reports/kardex?bank_account_ids=${account.id}',
                  );
                }
              },
              child: Text(
                accountName,
                style: const TextStyle(decoration: TextDecoration.underline),
              ),
            );
          },
        ),
        TextColumn(
          'branch',
          (t.localeName == 'fa') ? 'شعبه' : 'Branch',
          width: ColumnWidth.medium,
          formatter: (account) => account.branch ?? '-',
        ),
        TextColumn(
          'account_number',
          t.accountNumber,
          width: ColumnWidth.large,
          formatter: (account) => account.accountNumber ?? '-',
        ),
        TextColumn(
          'sheba_number',
          t.shebaNumber,
          width: ColumnWidth.large,
          formatter: (account) => account.shebaNumber ?? '-',
        ),
        TextColumn(
          'card_number',
          t.cardNumber,
          width: ColumnWidth.medium,
          formatter: (account) => account.cardNumber ?? '-',
        ),
        TextColumn(
          'owner_name',
          t.owner,
          width: ColumnWidth.medium,
          formatter: (account) => account.ownerName ?? '-',
        ),
        TextColumn(
          'pos_number',
          (t.localeName == 'fa') ? 'شماره پوز' : 'POS Number',
          width: ColumnWidth.medium,
          formatter: (account) => account.posNumber ?? '-',
        ),
        TextColumn(
          'currency_id',
          t.currency,
          width: ColumnWidth.medium,
          formatter: (account) => _currencyNames[account.currencyId] ?? ((t.localeName == 'fa') ? 'نامشخص' : 'Unknown'),
        ),
        TextColumn(
          'is_active',
          t.active,
          width: ColumnWidth.small,
          formatter: (account) => account.isActive ? t.active : t.inactive,
        ),
        TextColumn(
          'is_default',
          t.isDefault,
          width: ColumnWidth.small,
          formatter: (account) => account.isDefault ? t.yes : t.no,
        ),
        CustomColumn(
          'balance',
          (t.localeName == 'fa') ? 'موجودی' : 'Balance',
          width: ColumnWidth.medium,
          formatter: (account) {
            if (account.balance == null) return '-';
            return formatWithThousands(account.balance, decimalPlaces: 2);
          },
          builder: (account, index) {
            if (account.balance == null) {
              return const Text('-', textAlign: TextAlign.right);
            }
            final balance = account.balance!;
            final formatted = formatWithThousands(balance, decimalPlaces: 2);
            final isNegative = balance < 0;
            
            return Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isNegative)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.error,
                      size: 18,
                    ),
                  ),
                Flexible(
                  child: Text(
                    formatted,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: isNegative 
                          ? Theme.of(context).colorScheme.error 
                          : null,
                      fontWeight: isNegative ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        ActionColumn(
          'actions',
          t.actions,
          actions: [
            DataTableAction(
              icon: Icons.edit,
              label: t.edit,
              onTap: (account) => _editBankAccount(account),
            ),
            DataTableAction(
              icon: Icons.delete,
              label: t.delete,
              color: Colors.red,
              onTap: (account) => _deleteBankAccount(account),
            ),
          ],
        ),
      ],
      searchFields: ['code', 'name', 'branch', 'account_number', 'sheba_number', 'card_number', 'owner_name', 'pos_number', 'payment_id'],
      filterFields: ['is_active', 'is_default', 'currency_id'],
      defaultPageSize: 20,
      customHeaderActions: [
        PermissionButton(
          section: 'bank_accounts',
          action: 'add',
          authStore: widget.authStore,
          child: Tooltip(
            message: t.addBankAccount,
            child: IconButton(
              onPressed: _addBankAccount,
              icon: const Icon(Icons.add),
            ),
          ),
        ),
        if (widget.authStore.canDeleteSection('bank_accounts'))
          Tooltip(
            message: t.deleteBankAccounts,
            child: IconButton(
              onPressed: () async {
                final t = AppLocalizations.of(context);
                try {
                  final state = _bankAccountsTableKey.currentState as dynamic;
                  final selectedIndices = (state?.getSelectedRowIndices() as List<int>?) ?? const <int>[];
                  final items = (state?.getSelectedItems() as List<dynamic>?) ?? const <dynamic>[];
                  if (selectedIndices.isEmpty) {
                    SnackBarHelper.showError(context, message: t.noRowsSelectedError);
                    return;
                  }
                  final ids = <int>[];
                  for (final i in selectedIndices) {
                    if (i >= 0 && i < items.length) {
                      final row = items[i];
                      if (row is BankAccount && row.id != null) {
                        ids.add(row.id!);
                      } else if (row is Map<String, dynamic>) {
                        final id = row['id'];
                        if (id is int) ids.add(id);
                      }
                    }
                  }
                  if (ids.isEmpty) return;

                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(t.deleteBankAccounts),
                      content: Text(t.deleteBankAccounts),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
                        FilledButton.tonal(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.delete)),
                      ],
                    ),
                  );
                  if (confirm != true) return;

                  final client = ApiClient();
                  await client.post<Map<String, dynamic>>(
                    '/api/v1/bank-accounts/businesses/${widget.businessId}/bank-accounts/bulk-delete',
                    data: { 'ids': ids },
                  );
                  try { ( _bankAccountsTableKey.currentState as dynamic)?.refresh(); } catch (_) {}
                  if (mounted) {
                    SnackBarHelper.show(context, message: t.bankAccountDeletedSuccessfully);
                  }
                } catch (e) {
                  if (mounted) {
                    final t = AppLocalizations.of(context);
                    SnackBarHelper.showError(context, message: '${t.error}: $e');
                  }
                }
              },
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ),
      ],
    );
  }

  void _addBankAccount() {
    showDialog(
      context: context,
      builder: (context) => BankAccountFormDialog(
        businessId: widget.businessId,
        onSuccess: () {
          final state = _bankAccountsTableKey.currentState;
          try {
            // Call public refresh() via dynamic to avoid private state typing
            // ignore: avoid_dynamic_calls
            (state as dynamic)?.refresh();
          } catch (_) {}
        },
      ),
    );
  }

  void _editBankAccount(BankAccount account) {
    showDialog(
      context: context,
      builder: (context) => BankAccountFormDialog(
        businessId: widget.businessId,
        account: account,
        onSuccess: () {
          final state = _bankAccountsTableKey.currentState;
          try {
            // ignore: avoid_dynamic_calls
            (state as dynamic)?.refresh();
          } catch (_) {}
        },
      ),
    );
  }

  void _deleteBankAccount(BankAccount account) {
    final t = AppLocalizations.of(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.deleteBankAccount),
        content: Text(t.deleteConfirm(account.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _performDelete(account);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(t.delete),
          ),
        ],
      ),
    );
  }

  Future<void> _performDelete(BankAccount account) async {
    final t = AppLocalizations.of(context);
    try {
      await _bankAccountService.delete(account.id!);
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: t.bankAccountDeletedSuccessfully);
        // Refresh the table after successful deletion
        try { 
          (_bankAccountsTableKey.currentState as dynamic)?.refresh(); 
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: '${t.error}: $e');
      }
    }
  }
}


