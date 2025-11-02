import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';

class AccountNode {
	final String id;
	final String code;
	final String name;
	final String? accountType;
	final List<AccountNode> children;
	final bool hasChildren;

	const AccountNode({
		required this.id,
		required this.code,
		required this.name,
		this.accountType,
		this.children = const [],
		this.hasChildren = false,
	});

	factory AccountNode.fromJson(Map<String, dynamic> json) {
		final rawChildren = (json['children'] as List?) ?? const [];
		final parsedChildren = rawChildren
			.map((c) => AccountNode.fromJson(Map<String, dynamic>.from(c as Map)))
			.toList();
		return AccountNode(
			id: (json['id']?.toString() ?? json['code']?.toString() ?? UniqueKey().toString()),
			code: json['code']?.toString() ?? '',
			name: json['name']?.toString() ?? '',
			accountType: json['account_type']?.toString(),
			children: parsedChildren,
			hasChildren: (json['has_children'] == true) || parsedChildren.isNotEmpty,
		);
	}
}

class _VisibleNode {
	final AccountNode node;
	final int level;
	const _VisibleNode(this.node, this.level);
}

class AccountsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  const AccountsPage({super.key, required this.businessId, required this.authStore});

	@override
	State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
	bool _loading = true;
	String? _error;
	List<AccountNode> _roots = const [];
	final Set<String> _expandedIds = <String>{};

	@override
	void initState() {
		super.initState();
		_fetch();
	}

	Future<void> _fetch() async {
		setState(() { _loading = true; _error = null; });
		try {
			final api = ApiClient();
			final res = await api.get('/api/v1/accounts/business/${widget.businessId}/tree');
			final items = (res.data['data']['items'] as List?) ?? const [];
			final parsed = items
				.map((n) => AccountNode.fromJson(Map<String, dynamic>.from(n as Map)))
				.toList();
			setState(() { _roots = parsed; });
		} catch (e) {
			setState(() { _error = e.toString(); });
		} finally {
			setState(() { _loading = false; });
		}
	}

	List<Map<String, String>> _flattenNodes() {
		final List<Map<String, String>> items = <Map<String, String>>[];
		void dfs(AccountNode n, int level) {
			items.add({
				"id": n.id,
				"title": ("\u200f" * level) + n.code + " - " + n.name,
			});
			for (final c in n.children) {
				dfs(c, level + 1);
			}
		}
		for (final r in _roots) {
			dfs(r, 0);
		}
		return items;
	}

	Future<void> _openCreateDialog() async {
		final t = AppLocalizations.of(context);
		final codeCtrl = TextEditingController();
		final nameCtrl = TextEditingController();
		final typeCtrl = TextEditingController();
		String? selectedParentId;
		final parents = _flattenNodes();
		final result = await showDialog<bool>(
			context: context,
			builder: (ctx) {
				return AlertDialog(
					title: Text(t.addAccount),
					content: SingleChildScrollView(
						child: Column(
							mainAxisSize: MainAxisSize.min,
							children: [
								TextField(
									controller: codeCtrl,
									decoration: InputDecoration(labelText: t.code),
								),
								TextField(
									controller: nameCtrl,
									decoration: InputDecoration(labelText: t.title),
								),
								TextField(
									controller: typeCtrl,
									decoration: InputDecoration(labelText: t.type),
								),
								DropdownButtonFormField<String>(
									value: selectedParentId,
									items: [
										DropdownMenuItem<String>(value: null, child: Text('بدون والد')),
										...parents.map((p) => DropdownMenuItem<String>(value: p["id"], child: Text(p["title"]!))).toList(),
									],
									onChanged: (v) {
										selectedParentId = v;
									},
									decoration: const InputDecoration(labelText: 'حساب والد'),
								),
							],
						),
					),
					actions: [
						TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
						FilledButton(
							onPressed: () async {
								final name = nameCtrl.text.trim();
								final code = codeCtrl.text.trim();
								final atype = typeCtrl.text.trim();
								if (name.isEmpty || code.isEmpty || atype.isEmpty) {
									return;
								}
								final Map<String, dynamic> payload = {
									"name": name,
									"code": code,
									"account_type": atype,
								};
								if (selectedParentId != null && selectedParentId!.isNotEmpty) {
									final pid = int.tryParse(selectedParentId!);
									if (pid != null) payload["parent_id"] = pid;
								}
									try {
										final api = ApiClient();
										await api.post(
											'/api/v1/accounts/business/${widget.businessId}/create',
											data: payload,
										);
										if (context.mounted) Navigator.of(ctx).pop(true);
									} catch (e) {
										if (context.mounted) {
											ScaffoldMessenger.of(context).showSnackBar(
												SnackBar(content: Text('خطا در ایجاد حساب: $e')),
											);
										}
									}
							},
								child: Text(t.add),
						),
					],
				);
			},
		);
		if (result == true) {
			await _fetch();
		}
	}

	List<_VisibleNode> _buildVisibleNodes() {
		final List<_VisibleNode> result = <_VisibleNode>[];
		void dfs(AccountNode node, int level) {
			result.add(_VisibleNode(node, level));
			if (_expandedIds.contains(node.id)) {
				for (final child in node.children) {
					dfs(child, level + 1);
				}
			}
		}
		for (final r in _roots) {
			dfs(r, 0);
		}
		return result;
	}

	void _toggleExpand(AccountNode node) {
		setState(() {
			if (_expandedIds.contains(node.id)) {
				_expandedIds.remove(node.id);
			} else {
				if (node.hasChildren) {
					_expandedIds.add(node.id);
				}
			}
		});
	}

	Future<void> _openEditDialog(AccountNode node) async {
		final t = AppLocalizations.of(context);
		final codeCtrl = TextEditingController(text: node.code);
		final nameCtrl = TextEditingController(text: node.name);
		final typeCtrl = TextEditingController(text: node.accountType ?? '');
		final parents = _flattenNodes();
		String? selectedParentId;
		final result = await showDialog<bool>(
			context: context,
			builder: (ctx) {
				return AlertDialog(
					title: Text(t.edit),
					content: SingleChildScrollView(
						child: Column(
							mainAxisSize: MainAxisSize.min,
							children: [
								TextField(controller: codeCtrl, decoration: InputDecoration(labelText: t.code)),
								TextField(controller: nameCtrl, decoration: InputDecoration(labelText: t.title)),
								TextField(controller: typeCtrl, decoration: InputDecoration(labelText: t.type)),
								DropdownButtonFormField<String>(
									value: selectedParentId,
									items: [
										DropdownMenuItem<String>(value: null, child: Text('بدون والد')),
										...parents.map((p) => DropdownMenuItem<String>(value: p["id"], child: Text(p["title"]!))).toList(),
									],
									onChanged: (v) { selectedParentId = v; },
									decoration: const InputDecoration(labelText: 'حساب والد'),
								),
							],
						),
					),
					actions: [
						TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
						FilledButton(
							onPressed: () async {
								final name = nameCtrl.text.trim();
								final code = codeCtrl.text.trim();
								final atype = typeCtrl.text.trim();
								if (name.isEmpty || code.isEmpty || atype.isEmpty) return;
								final Map<String, dynamic> payload = {"name": name, "code": code, "account_type": atype};
								if (selectedParentId != null && selectedParentId!.isNotEmpty) {
									final pid = int.tryParse(selectedParentId!);
									if (pid != null) payload["parent_id"] = pid;
								}
									try {
									final id = int.tryParse(node.id);
									if (id == null) return;
									final api = ApiClient();
									await api.put('/api/v1/accounts/account/$id', data: payload);
									if (context.mounted) Navigator.of(ctx).pop(true);
									} catch (e) {
										if (context.mounted) {
											ScaffoldMessenger.of(context).showSnackBar(
												SnackBar(content: Text('خطا در ویرایش حساب: $e')),
											);
										}
									}
							},
							child: Text(t.save),
						),
					],
				);
			},
		);
		if (result == true) {
			await _fetch();
		}
	}

	Future<void> _confirmDelete(AccountNode node) async {
		final t = AppLocalizations.of(context);
		final id = int.tryParse(node.id);
		if (id == null) return;
		final ok = await showDialog<bool>(
			context: context,
			builder: (ctx) => AlertDialog(
				title: Text(t.delete),
				content: const Text('آیا مطمئن هستید؟'),
				actions: [
					TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
					FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.delete)),
				],
			),
		);
		if (ok == true) {
			try {
				final api = ApiClient();
				await api.delete('/api/v1/accounts/account/$id');
				await _fetch();
			} catch (e) {
				if (context.mounted) {
					ScaffoldMessenger.of(context).showSnackBar(
						SnackBar(content: Text('خطا در حذف حساب: $e')),
					);
				}
			}
		}
	}

	String _localizedAccountType(AppLocalizations t, String? value) {
		if (value == null || value.isEmpty) return '-';
		final ln = t.localeName;
		if (ln.startsWith('fa')) {
			switch (value) {
				case 'bank':
					return t.accountTypeBank;
				case 'cash_register':
					return t.accountTypeCashRegister;
				case 'petty_cash':
					return t.accountTypePettyCash;
				case 'check':
					return t.accountTypeCheck;
				case 'person':
					return t.accountTypePerson;
				case 'product':
					return t.accountTypeProduct;
				case 'service':
					return t.accountTypeService;
				case 'accounting_document':
					return t.accountTypeAccountingDocument;
				default:
					return value;
			}
		}
		// English and other locales: humanize
		String humanize(String v) {
			return v
				.split('_')
				.map((p) => p.isEmpty ? p : (p[0].toUpperCase() + p.substring(1)))
				.join(' ');
		}
		switch (value) {
			case 'bank':
				return t.accountTypeBank;
			case 'cash_register':
				return t.accountTypeCashRegister;
			case 'petty_cash':
				return t.accountTypePettyCash;
			case 'check':
				return t.accountTypeCheck;
			case 'person':
				return t.accountTypePerson;
			case 'product':
				return t.accountTypeProduct;
			case 'service':
				return t.accountTypeService;
			case 'accounting_document':
				return t.accountTypeAccountingDocument;
			default:
				return humanize(value);
		}
	}

	@override
	Widget build(BuildContext context) {
		final t = AppLocalizations.of(context);
		if (_loading) return const Center(child: CircularProgressIndicator());
		if (_error != null) return Center(child: Text(_error!));
		final visible = _buildVisibleNodes();
		return Scaffold(
			appBar: AppBar(title: Text(t.chartOfAccounts)),
			body: Column(
				children: [
					Container(
						padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
						color: Theme.of(context).colorScheme.surfaceContainerHighest,
										child: Row(
							children: [
								const SizedBox(width: 28), // expander space
								Expanded(flex: 2, child: Text(t.code, style: const TextStyle(fontWeight: FontWeight.w600))),
								Expanded(flex: 5, child: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600))),
								Expanded(flex: 3, child: Text(t.type, style: const TextStyle(fontWeight: FontWeight.w600))),
							],
						),
					),
					Expanded(
						child: RefreshIndicator(
							onRefresh: _fetch,
							child: ListView.builder(
								itemCount: visible.length,
								itemBuilder: (context, index) {
									final item = visible[index];
									final node = item.node;
									final level = item.level;
									final isExpanded = _expandedIds.contains(node.id);
									final canExpand = node.hasChildren;
									return InkWell(
										onTap: canExpand ? () => _toggleExpand(node) : null,
										child: Container(
											padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
											child: Row(
												children: [
													SizedBox(width: 12.0 * level),
													SizedBox(
														width: 28,
														child: canExpand
															? IconButton(
																padding: EdgeInsets.zero,
																iconSize: 20,
																visualDensity: VisualDensity.compact,
																icon: Icon(isExpanded ? Icons.expand_more : Icons.chevron_right),
																onPressed: () => _toggleExpand(node),
															)
														: const SizedBox.shrink(),
													),
													Expanded(flex: 2, child: Text(node.code, style: const TextStyle(fontFeatures: []))),
													Expanded(flex: 5, child: Text(node.name)),
												Expanded(flex: 3, child: Text(_localizedAccountType(t, node.accountType))),
												SizedBox(
													width: 40,
													child: PopupMenuButton<String>(
														padding: EdgeInsets.zero,
														onSelected: (v) {
															if (v == 'edit') _openEditDialog(node);
															if (v == 'delete') _confirmDelete(node);
														},
														itemBuilder: (context) => [
															const PopupMenuItem<String>(value: 'edit', child: Text('ویرایش')),
															const PopupMenuItem<String>(value: 'delete', child: Text('حذف')),
														],
													),
												),
												],
											),
										),
									);
								},
							),
						),
					),
				],
			),
			floatingActionButton: widget.authStore.canWriteSection('accounting')
				? FloatingActionButton(
					onPressed: _openCreateDialog,
					child: const Icon(Icons.add),
				)
				: null,
		);
	}
}


