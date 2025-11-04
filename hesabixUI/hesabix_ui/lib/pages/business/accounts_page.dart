import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';

class AccountNode {
	final String id;
	final String code;
	final String name;
	final String? accountType;
	final int? businessId;
	final List<AccountNode> children;
	final bool hasChildren;

	const AccountNode({
		required this.id,
		required this.code,
		required this.name,
		this.accountType,
		this.businessId,
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
			businessId: json['business_id'] is int
				? (json['business_id'] as int)
				: (json['business_id'] != null ? int.tryParse(json['business_id'].toString()) : null),
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
				"business_id": n.businessId?.toString() ?? "",
				"has_children": n.hasChildren ? "1" : "0",
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

	String? _suggestNextCode({String? parentId}) {
		List<String> codes = <String>[];
		if (parentId == null || parentId.isEmpty) {
			codes = _roots.map((e) => e.code).toList();
		} else {
			AccountNode? find(AccountNode n) {
				if (n.id == parentId) return n;
				for (final c in n.children) {
					final x = find(c);
					if (x != null) return x;
				}
				return null;
			}
			AccountNode? parent;
			for (final r in _roots) {
				parent = find(r);
				if (parent != null) break;
			}
			if (parent != null) codes = parent.children.map((e) => e.code).toList();
		}
		final numeric = codes.map((c) => int.tryParse(c)).whereType<int>().toList();
		if (numeric.isEmpty) return null;
		final next = (numeric..sort()).last + 1;
		return next.toString();
	}

	Future<void> _openCreateDialog({AccountNode? parent}) async {
		final t = AppLocalizations.of(context);
		final codeCtrl = TextEditingController();
		final nameCtrl = TextEditingController();
		String? selectedType;
		String? selectedParentId = parent?.id;
		final parents = _flattenNodes();
		final result = await showDialog<bool>(
			context: context,
			builder: (ctx) {
				return AlertDialog(
					title: Text(t.addAccount),
					content: ConstrainedBox(
						constraints: const BoxConstraints(maxWidth: 460),
						child: SingleChildScrollView(
							child: Column(
								mainAxisSize: MainAxisSize.min,
								children: [
									Row(children: [
										Expanded(child: TextField(
											controller: codeCtrl,
											decoration: InputDecoration(labelText: t.code, prefixIcon: const Icon(Icons.numbers)),
										)),
										const SizedBox(width: 8),
										OutlinedButton.icon(
											onPressed: () {
												final s = _suggestNextCode(parentId: selectedParentId);
												if (s != null) codeCtrl.text = s;
											},
											icon: const Icon(Icons.auto_fix_high, size: 18),
											label: const Text('پیشنهاد کد'),
										),
									]),
									const SizedBox(height: 10),
									TextField(
										controller: nameCtrl,
										decoration: InputDecoration(labelText: t.title, prefixIcon: const Icon(Icons.title)),
									),
									const SizedBox(height: 10),
									DropdownButtonFormField<String>(
										value: selectedType,
										items: const [
											DropdownMenuItem(value: 'bank', child: Text('بانک')),
											DropdownMenuItem(value: 'cash_register', child: Text('صندوق')),
											DropdownMenuItem(value: 'petty_cash', child: Text('تنخواه')),
											DropdownMenuItem(value: 'check', child: Text('چک')),
											DropdownMenuItem(value: 'person', child: Text('شخص')),
											DropdownMenuItem(value: 'product', child: Text('کالا')),
											DropdownMenuItem(value: 'service', child: Text('خدمت')),
											DropdownMenuItem(value: 'accounting_document', child: Text('سند حسابداری')),
										],
										onChanged: (v) { selectedType = v; },
										decoration: InputDecoration(labelText: t.type, prefixIcon: const Icon(Icons.category)),
									),
									const SizedBox(height: 10),
									DropdownButtonFormField<String>(
										value: selectedParentId,
										items: [
											...(() {
												List<Map<String, String>> src = parents;
												if (parent != null) {
													return src.where((p) => p['id'] == parent.id).map((p) => DropdownMenuItem<String>(value: p["id"], child: Text(p["title"]!))).toList();
												}
												return src.where((p) {
													final bid = p['business_id'];
													final hc = p['has_children'];
													final isPublic = (bid == null || bid.isEmpty);
													final isSameBusiness = bid == widget.businessId.toString();
													return (isPublic && hc == '1') || isSameBusiness;
												}).map((p) => DropdownMenuItem<String>(value: p["id"], child: Text(p["title"]!))).toList();
											})(),
										],
										onChanged: parent != null ? null : (v) {
											selectedParentId = v;
											if ((codeCtrl.text).trim().isEmpty) {
												final s = _suggestNextCode(parentId: selectedParentId);
												if (s != null) codeCtrl.text = s;
											}
										},
										decoration: const InputDecoration(labelText: 'حساب والد', prefixIcon: Icon(Icons.account_tree)),
									),
								],
							),
						),
					),
					actions: [
						TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
						FilledButton(
							onPressed: () async {
								final name = nameCtrl.text.trim();
								final code = codeCtrl.text.trim();
								final atype = (selectedType ?? '').trim();
								if (name.isEmpty || code.isEmpty || atype.isEmpty || selectedParentId == null || selectedParentId!.isEmpty) {
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
		String? selectedType = node.accountType;
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
								DropdownButtonFormField<String>(
									value: selectedType,
									items: const [
										DropdownMenuItem(value: 'bank', child: Text('بانک')),
										DropdownMenuItem(value: 'cash_register', child: Text('صندوق')),
										DropdownMenuItem(value: 'petty_cash', child: Text('تنخواه')),
										DropdownMenuItem(value: 'check', child: Text('چک')),
										DropdownMenuItem(value: 'person', child: Text('شخص')),
										DropdownMenuItem(value: 'product', child: Text('کالا')),
										DropdownMenuItem(value: 'service', child: Text('خدمت')),
										DropdownMenuItem(value: 'accounting_document', child: Text('سند حسابداری')),
									],
									onChanged: (v) { selectedType = v; },
									decoration: InputDecoration(labelText: t.type),
								),
								DropdownButtonFormField<String>(
									value: selectedParentId,
									items: [
										DropdownMenuItem<String>(value: null, child: Text('بدون والد')),
										...parents.where((p) {
											final bid = p['business_id'];
											return (bid == null || bid.isEmpty) || bid == widget.businessId.toString();
										}).map((p) => DropdownMenuItem<String>(value: p["id"], child: Text(p["title"]!))).toList(),
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
								final atype = (selectedType ?? '').trim();
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
										if (node.businessId == null) const SizedBox(width: 20, child: Icon(Icons.lock_outline, size: 16)),
										Expanded(flex: 2, child: Text(node.code, style: const TextStyle(fontFeatures: []))),
													Expanded(flex: 5, child: Text(node.name)),
												Expanded(flex: 3, child: Text(_localizedAccountType(t, node.accountType))),
												SizedBox(
													width: 40,
													child: PopupMenuButton<String>(
														padding: EdgeInsets.zero,
									onSelected: (v) {
										if (v == 'add_child') _openCreateDialog(parent: node);
										if (v == 'edit') _openEditDialog(node);
										if (v == 'delete') _confirmDelete(node);
									},
								itemBuilder: (context) {
									final bool isOwned = node.businessId != null && node.businessId == widget.businessId;
									final bool canEdit = isOwned;
									final bool canDelete = isOwned && !node.hasChildren;
									final bool canAddChild = widget.authStore.canWriteSection('accounting') && ((node.businessId == null && node.hasChildren) || isOwned);
									final List<PopupMenuEntry<String>> items = <PopupMenuEntry<String>>[];
									if (canAddChild) {
										items.add(const PopupMenuItem<String>(value: 'add_child', child: Text('افزودن ریز حساب')));
									}
									if (canEdit) {
										items.add(const PopupMenuItem<String>(value: 'edit', child: Text('ویرایش')));
									}
									if (canDelete) {
										items.add(const PopupMenuItem<String>(value: 'delete', child: Text('حذف')));
									}
									if (items.isEmpty) {
										return [const PopupMenuItem<String>(value: 'noop', enabled: false, child: Text('غیرقابل ویرایش'))];
									}
									return items;
								},
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


