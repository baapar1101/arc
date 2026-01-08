import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/permission/permission_widgets.dart';
import '../../core/auth_store.dart';
import '../../models/cash_register.dart';
import '../../services/cash_register_service.dart';
import '../../services/currency_service.dart';
import '../../widgets/banking/cash_register_form_dialog.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/number_formatters.dart';

class CashRegistersPage extends StatefulWidget {
	final int businessId;
	final AuthStore authStore;

	const CashRegistersPage({super.key, required this.businessId, required this.authStore});

	@override
	State<CashRegistersPage> createState() => _CashRegistersPageState();
  
  /// Static map to store page states by business ID for external refresh
  static final Map<int, _CashRegistersPageState> _pageStates = {};
  
  /// Get the page state for a specific business ID
  static _CashRegistersPageState? getPageState(int businessId) {
    return _pageStates[businessId];
  }
  
  /// Clear the page state for a specific business ID
  static void clearPageState(int businessId) {
    _pageStates.remove(businessId);
  }
}

class _CashRegistersPageState extends State<CashRegistersPage> {
	final _service = CashRegisterService();
	final _currencyService = CurrencyService(ApiClient());
	final GlobalKey _tableKey = GlobalKey();
	Map<int, String> _currencyNames = {};

	@override
	void initState() {
		super.initState();
		// Register this page instance for external refresh access
		CashRegistersPage._pageStates[widget.businessId] = this;
		_loadCurrencies();
	}
	
	@override
	void dispose() {
		// Clean up the page state when disposed
		CashRegistersPage._pageStates.remove(widget.businessId);
		super.dispose();
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
		} catch (_) {}
	}

	/// Public method to refresh the data table
	void refresh() {
		try {
			(_tableKey.currentState as dynamic)?.refresh();
		} catch (_) {}
	}

	@override
	void didUpdateWidget(CashRegistersPage oldWidget) {
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

		if (!widget.authStore.canReadSection('cash')) {
			return AccessDeniedPage(message: t.accessDenied);
		}

		return Scaffold(
			body: DataTableWidget<CashRegister>(
				key: _tableKey,
				config: _buildConfig(t),
				fromJson: CashRegister.fromJson,
			),
		);
	}

	DataTableConfig<CashRegister> _buildConfig(AppLocalizations t) {
		return DataTableConfig<CashRegister>(
			endpoint: '/api/v1/cash-registers/businesses/${widget.businessId}/cash-registers',
			title: t.cashBox,
			excelEndpoint: '/api/v1/cash-registers/businesses/${widget.businessId}/cash-registers/export/excel',
			pdfEndpoint: '/api/v1/cash-registers/businesses/${widget.businessId}/cash-registers/export/pdf',
			businessId: widget.businessId,
			reportModuleKey: 'cash_registers',
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
					formatter: (row) => (row.code?.toString() ?? '-'),
					textAlign: TextAlign.center,
				),
				CustomColumn(
					'name',
					t.title,
					width: ColumnWidth.large,
					formatter: (row) => row.name,
					builder: (row, index) {
						final registerName = row.name;
						return InkWell(
							onTap: () {
								if (row.id != null) {
									context.go(
										'/business/${widget.businessId}/reports/kardex?cash_register_ids=${row.id}',
									);
								}
							},
							child: Text(
								registerName,
								style: const TextStyle(decoration: TextDecoration.underline),
							),
						);
					},
				),
				TextColumn(
					'currency_id',
					t.currency,
					width: ColumnWidth.medium,
					formatter: (row) => _currencyNames[row.currencyId] ?? (t.localeName == 'fa' ? 'نامشخص' : 'Unknown'),
				),
				TextColumn(
					'is_active',
					t.active,
					width: ColumnWidth.small,
					formatter: (row) => row.isActive ? t.active : t.inactive,
				),
				TextColumn(
					'is_default',
					t.isDefault,
					width: ColumnWidth.small,
					formatter: (row) => row.isDefault ? t.yes : t.no,
				),
				TextColumn(
					'payment_switch_number',
					(t.localeName == 'fa') ? 'شماره سویچ پرداخت' : 'Payment Switch No.',
					width: ColumnWidth.large,
					formatter: (row) => row.paymentSwitchNumber ?? '-',
				),
				TextColumn(
					'payment_terminal_number',
					(t.localeName == 'fa') ? 'شماره ترمینال' : 'Terminal No.',
					width: ColumnWidth.large,
					formatter: (row) => row.paymentTerminalNumber ?? '-',
				),
				TextColumn(
					'merchant_id',
					(t.localeName == 'fa') ? 'پذیرنده' : 'Merchant ID',
					width: ColumnWidth.large,
					formatter: (row) => row.merchantId ?? '-',
				),
				TextColumn(
					'description',
					t.description,
					width: ColumnWidth.large,
					formatter: (row) => row.description ?? '-',
				),
				CustomColumn(
					'balance',
					(t.localeName == 'fa') ? 'موجودی' : 'Balance',
					width: ColumnWidth.medium,
					formatter: (row) {
						if (row.balance == null) return '-';
						return formatWithThousands(row.balance, decimalPlaces: 2);
					},
					builder: (row, index) {
						if (row.balance == null) {
							return const Text('-', textAlign: TextAlign.right);
						}
						final balance = row.balance!;
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
							onTap: (row) => _edit(row),
						),
						DataTableAction(
							icon: Icons.delete,
							label: t.delete,
							color: Colors.red,
							onTap: (row) => _delete(row),
						),
					],
				),
			],
			searchFields: ['name','code','description','payment_switch_number','payment_terminal_number','merchant_id'],
			filterFields: ['is_active','is_default','currency_id'],
			defaultPageSize: 20,
			customHeaderActions: [
				PermissionButton(
					section: 'cash',
					action: 'add',
					authStore: widget.authStore,
					child: Tooltip(
						message: t.add,
						child: IconButton(
							onPressed: _add,
							icon: const Icon(Icons.add),
						),
					),
				),
				if (widget.authStore.canDeleteSection('cash'))
					Tooltip(
						message: t.deleteSelected,
						child: IconButton(
							onPressed: _bulkDelete,
							icon: const Icon(Icons.delete_sweep_outlined),
						),
					),
			],
		);
	}

	void _add() async {
		await showDialog<bool>(
			context: context,
			builder: (ctx) => CashRegisterFormDialog(
				businessId: widget.businessId,
				onSuccess: () {
					try { (_tableKey.currentState as dynamic)?.refresh(); } catch (_) {}
				},
			),
		);
	}

	void _edit(CashRegister row) async {
		await showDialog<bool>(
			context: context,
			builder: (ctx) => CashRegisterFormDialog(
				businessId: widget.businessId,
				register: row,
				onSuccess: () {
					try { (_tableKey.currentState as dynamic)?.refresh(); } catch (_) {}
				},
			),
		);
	}

	Future<void> _delete(CashRegister row) async {
		final t = AppLocalizations.of(context);
		final confirm = await showDialog<bool>(
			context: context,
			builder: (ctx) => AlertDialog(
				title: Text(t.delete),
				content: Text(t.deleteConfirm(row.code ?? '')),
				actions: [
					TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
					FilledButton.tonal(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.delete)),
				],
			),
		);
		if (confirm != true) return;
		try {
			await _service.delete(row.id!);
			try { (_tableKey.currentState as dynamic)?.refresh(); } catch (_) {}
			if (mounted) {
				SnackBarHelper.show(context, message: t.deletedSuccessfully);
			}
		} catch (e) {
			if (mounted) {
				SnackBarHelper.showError(context, message: '${t.error}: $e');
			}
		}
	}

	Future<void> _bulkDelete() async {
		final t = AppLocalizations.of(context);
		try {
			final state = _tableKey.currentState as dynamic;
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
					if (row is CashRegister && row.id != null) {
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
					title: Text(t.deleteSelected),
					content: Text(t.deleteSelected),
					actions: [
						TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
						FilledButton.tonal(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.delete)),
					],
				),
			);
			if (confirm != true) return;
			final client = ApiClient();
			await client.post<Map<String, dynamic>>(
				'/api/v1/cash-registers/businesses/${widget.businessId}/cash-registers/bulk-delete',
				data: { 'ids': ids },
			);
			try { (_tableKey.currentState as dynamic)?.refresh(); } catch (_) {}
			if (mounted) {
				SnackBarHelper.show(context, message: t.deletedSuccessfully);
			}
		} catch (e) {
			if (mounted) {
				SnackBarHelper.showError(context, message: '${t.error}: $e');
			}
		}
	}
}


