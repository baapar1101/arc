import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/permission/permission_widgets.dart';
import '../../core/auth_store.dart';
import '../../models/petty_cash.dart';
import '../../services/petty_cash_service.dart';
import '../../services/currency_service.dart';
import '../../widgets/banking/petty_cash_form_dialog.dart';

class PettyCashPage extends StatefulWidget {
	final int businessId;
	final AuthStore authStore;

	const PettyCashPage({super.key, required this.businessId, required this.authStore});

	@override
	State<PettyCashPage> createState() => _PettyCashPageState();
}

class _PettyCashPageState extends State<PettyCashPage> {
	final _service = PettyCashService();
	final _currencyService = CurrencyService(ApiClient());
	final GlobalKey _tableKey = GlobalKey();
	Map<int, String> _currencyNames = {};

	@override
	void initState() {
		super.initState();
		_loadCurrencies();
	}

	@override
	void didUpdateWidget(PettyCashPage oldWidget) {
		super.didUpdateWidget(oldWidget);
		// This will be called when the widget is updated
		// Refresh the data table to show any new data
		WidgetsBinding.instance.addPostFrameCallback((_) {
			refresh();
		});
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
	Widget build(BuildContext context) {
		final t = AppLocalizations.of(context);

		if (!widget.authStore.canReadSection('petty_cash')) {
			return AccessDeniedPage(message: t.accessDenied);
		}

		return Scaffold(
			body: DataTableWidget<PettyCash>(
				key: _tableKey,
				config: _buildConfig(t),
				fromJson: PettyCash.fromJson,
			),
		);
	}

	DataTableConfig<PettyCash> _buildConfig(AppLocalizations t) {
		return DataTableConfig<PettyCash>(
			endpoint: '/api/v1/petty-cash/businesses/${widget.businessId}/petty-cash',
			title: (t.localeName == 'fa') ? 'تنخواه گردان' : 'Petty Cash',
			excelEndpoint: '/api/v1/petty-cash/businesses/${widget.businessId}/petty-cash/export/excel',
			pdfEndpoint: '/api/v1/petty-cash/businesses/${widget.businessId}/petty-cash/export/pdf',
			businessId: widget.businessId,
			reportModuleKey: 'petty_cash',
			reportSubtype: 'list',
			getExportParams: () => {'business_id': widget.businessId},
			showBackButton: true,
			onBack: () => Navigator.of(context).maybePop(),
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
				TextColumn(
					'name',
					t.title,
					width: ColumnWidth.large,
					formatter: (row) => row.name,
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
					'description',
					t.description,
					width: ColumnWidth.large,
					formatter: (row) => row.description ?? '-',
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
			searchFields: ['name','code','description'],
			filterFields: ['is_active','is_default','currency_id'],
			defaultPageSize: 20,
			customHeaderActions: [
				PermissionButton(
					section: 'petty_cash',
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
				if (widget.authStore.canDeleteSection('petty_cash'))
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
			builder: (ctx) => PettyCashFormDialog(
				businessId: widget.businessId,
				onSuccess: () {
					try { (_tableKey.currentState as dynamic)?.refresh(); } catch (_) {}
				},
			),
		);
	}

	void _edit(PettyCash row) async {
		await showDialog<bool>(
			context: context,
			builder: (ctx) => PettyCashFormDialog(
				businessId: widget.businessId,
				pettyCash: row,
				onSuccess: () {
					try { (_tableKey.currentState as dynamic)?.refresh(); } catch (_) {}
				},
			),
		);
	}

	Future<void> _delete(PettyCash row) async {
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
				ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.deletedSuccessfully)));
			}
		} catch (e) {
			if (mounted) {
				ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t.error}: $e')));
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
				ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.noRowsSelectedError)));
				return;
			}
			final ids = <int>[];
			for (final i in selectedIndices) {
				if (i >= 0 && i < items.length) {
					final row = items[i];
					if (row is PettyCash && row.id != null) {
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
				'/api/v1/petty-cash/businesses/${widget.businessId}/petty-cash/bulk-delete',
				data: { 'ids': ids },
			);
			try { (_tableKey.currentState as dynamic)?.refresh(); } catch (_) {}
			if (mounted) {
				ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.deletedSuccessfully)));
			}
		} catch (e) {
			if (mounted) {
				ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t.error}: $e')));
			}
		}
	}
}