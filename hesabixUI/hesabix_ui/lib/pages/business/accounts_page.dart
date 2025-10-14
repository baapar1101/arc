import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';

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
	const AccountsPage({super.key, required this.businessId});

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
		);
	}
}


