import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';

class AccountsPage extends StatefulWidget {
	final int businessId;
	const AccountsPage({super.key, required this.businessId});

	@override
	State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
	bool _loading = true;
	String? _error;
	List<dynamic> _tree = const [];

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
			setState(() { _tree = res.data['data']['items'] ?? []; });
		} catch (e) {
			setState(() { _error = e.toString(); });
		} finally {
			setState(() { _loading = false; });
		}
	}

	Widget _buildNode(Map<String, dynamic> node) {
		final children = (node['children'] as List?) ?? const [];
		if (children.isEmpty) {
			return ListTile(
				title: Text('${node['code']} - ${node['name']}'),
			);
		}
		return ExpansionTile(
			title: Text('${node['code']} - ${node['name']}'),
			children: children.map<Widget>((c) => _buildNode(Map<String, dynamic>.from(c))).toList(),
		);
	}

	@override
	Widget build(BuildContext context) {
		final t = AppLocalizations.of(context);
		if (_loading) return const Center(child: CircularProgressIndicator());
		if (_error != null) return Center(child: Text(_error!));
		return Scaffold(
			appBar: AppBar(title: Text(t.chartOfAccounts)),
			body: RefreshIndicator(
				onRefresh: _fetch,
				child: ListView(
					children: _tree.map<Widget>((n) => _buildNode(Map<String, dynamic>.from(n))).toList(),
				),
			),
		);
	}
}


