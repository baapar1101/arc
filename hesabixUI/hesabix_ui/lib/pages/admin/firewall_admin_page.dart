import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/admin_firewall_service.dart';

/// مدیریت فایروال داخلی، لاگ مسدودشده‌ها و گزارش.
class FirewallAdminPage extends StatefulWidget {
  const FirewallAdminPage({super.key});

  @override
  State<FirewallAdminPage> createState() => _FirewallAdminPageState();
}

class _FirewallAdminPageState extends State<FirewallAdminPage> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _svc = AdminFirewallService(ApiClient());

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.settingsFirewall),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: t.firewallTabRules),
            Tab(text: t.firewallTabRatePolicies),
            Tab(text: t.firewallTabBlockLogs),
            Tab(text: t.firewallTabAudit),
            Tab(text: t.firewallTabReports),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _FirewallRulesTab(service: _svc),
          _FirewallRatePoliciesTab(service: _svc),
          _FirewallBlockLogsTab(service: _svc),
          _FirewallAuditTab(service: _svc),
          _FirewallReportsTab(service: _svc),
        ],
      ),
    );
  }
}

class _FirewallRulesTab extends StatefulWidget {
  const _FirewallRulesTab({required this.service});
  final AdminFirewallService service;

  @override
  State<_FirewallRulesTab> createState() => _FirewallRulesTabState();
}

class _FirewallRulesTabState extends State<_FirewallRulesTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  bool _activeOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.service.listRules(activeOnly: _activeOnly);
      final raw = data['items'] as List<dynamic>? ?? [];
      _items = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _error = ErrorExtractor.forContext(e, context);
    }
    setState(() => _loading = false);
  }

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    final t = AppLocalizations.of(context);
    var actionVal = existing?['action']?.toString() ?? 'deny';
    final ipCtrl = TextEditingController(text: existing?['ip_cidr']?.toString() ?? '');
    final pathCtrl = TextEditingController(text: existing?['path_prefix']?.toString() ?? '');
    final methodsCtrl = TextEditingController(text: existing?['http_methods']?.toString() ?? '');
    final priCtrl = TextEditingController(text: existing?['priority']?.toString() ?? '100');
    final noteCtrl = TextEditingController(text: existing?['note']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(existing == null ? t.firewallAddRule : t.firewallEditRule),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.firewallActionLabel),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'allow', label: Text(t.firewallActionAllow)),
                    ButtonSegment(value: 'deny', label: Text(t.firewallActionDeny)),
                  ],
                  selected: {actionVal},
                  onSelectionChanged: (s) {
                    if (s.isNotEmpty) {
                      setSt(() => actionVal = s.first);
                    }
                  },
                ),
                TextField(controller: ipCtrl, decoration: InputDecoration(labelText: t.firewallIpCidr)),
                TextField(controller: pathCtrl, decoration: InputDecoration(labelText: t.firewallPathPrefixOptional)),
                TextField(controller: methodsCtrl, decoration: InputDecoration(labelText: t.firewallHttpMethodsOptional)),
                TextField(controller: priCtrl, decoration: InputDecoration(labelText: t.firewallPriority)),
                TextField(controller: noteCtrl, decoration: InputDecoration(labelText: t.firewallNoteOptional)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final body = <String, dynamic>{
        'action': actionVal.trim(),
        'ip_cidr': ipCtrl.text.trim(),
        'path_prefix': pathCtrl.text.trim().isEmpty ? null : pathCtrl.text.trim(),
        'http_methods': methodsCtrl.text.trim().isEmpty ? null : methodsCtrl.text.trim(),
        'priority': int.tryParse(priCtrl.text.trim()) ?? 100,
        'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      };
      if (existing == null) {
        await widget.service.createRule(body);
      } else {
        await widget.service.updateRule((existing['id'] as num).toInt(), body);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.firewallSaved)));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.error}: ${ErrorExtractor.forContext(e, context)}')),
        );
      }
    }
  }

  Future<void> _quickBan() async {
    final t = AppLocalizations.of(context);
    final ipCtrl = TextEditingController();
    final minCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.firewallBanIp),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: ipCtrl, decoration: InputDecoration(labelText: t.firewallIpCidr)),
            TextField(
              controller: minCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: t.firewallDurationMinutesHint),
            ),
            TextField(controller: noteCtrl, decoration: InputDecoration(labelText: t.firewallNoteOptional)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.confirm)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final mins = int.tryParse(minCtrl.text.trim());
    int? sec;
    if (mins != null && mins > 0) {
      sec = mins * 60;
    }
    try {
      await widget.service.banIp(ip: ipCtrl.text.trim(), durationSeconds: sec, note: noteCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.firewallBanDone)));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorExtractor.forContext(e, context))),
      );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: SelectableText('${t.error}: $_error'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: Text(t.firewallActiveOnlyFilter),
                selected: _activeOnly,
                onSelected: (v) {
                  setState(() => _activeOnly = v);
                  _load();
                },
              ),
              FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(t.firewallRefresh)),
              FilledButton.tonalIcon(onPressed: _quickBan, icon: const Icon(Icons.block), label: Text(t.firewallBanIp)),
              FilledButton.icon(onPressed: () => _openEditor(), icon: const Icon(Icons.add), label: Text(t.firewallAddRule)),
            ],
          ),
        ),
        Expanded(
          child: _items.isEmpty
              ? Center(child: Text(t.firewallNoRules))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (ctx, i) {
                    final r = _items[i];
                    final id = (r['id'] as num).toInt();
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        title: Text('${r['action']} — ${r['ip_cidr']}'),
                        subtitle: Text(
                          '${t.firewallPriority}: ${r['priority']}  •  ${r['path_prefix'] ?? '—'}  •  ${r['expires_at'] ?? t.firewallNoExpiry}',
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _openEditor(existing: r),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final del = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: Text(t.firewallDeleteConfirmTitle),
                                    content: Text(t.firewallDeleteConfirmBody),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
                                      FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t.delete)),
                                    ],
                                  ),
                                );
                                if (!context.mounted) {
                                  return;
                                }
                                if (del == true) {
                                  try {
                                    await widget.service.deleteRule(id);
                                    await _load();
                                  } catch (e) {
                                    if (context.mounted) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(ErrorExtractor.forContext(e, context)),
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FirewallRatePoliciesTab extends StatefulWidget {
  const _FirewallRatePoliciesTab({required this.service});
  final AdminFirewallService service;

  @override
  State<_FirewallRatePoliciesTab> createState() => _FirewallRatePoliciesTabState();
}

class _FirewallRatePoliciesTabState extends State<_FirewallRatePoliciesTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.service.listRatePolicies();
      final raw = data['items'] as List<dynamic>? ?? [];
      _items = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _error = ErrorExtractor.forContext(e, context);
    }
    setState(() => _loading = false);
  }

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    final t = AppLocalizations.of(context);
    var enabledVal = existing?['enabled'] == true || existing?['enabled'] == 1 || existing == null;
    final pathCtrl = TextEditingController(text: existing?['path_prefix']?.toString() ?? '/api/v1/public/crm-chat');
    final methodsCtrl = TextEditingController(text: existing?['http_methods']?.toString() ?? '');
    final maxCtrl = TextEditingController(text: existing?['max_requests']?.toString() ?? '100');
    final winCtrl = TextEditingController(text: existing?['window_seconds']?.toString() ?? '60');
    final priCtrl = TextEditingController(text: existing?['priority']?.toString() ?? '100');
    final noteCtrl = TextEditingController(text: existing?['note']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(existing == null ? t.firewallAddRatePolicy : t.firewallEditRatePolicy),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  title: Text(t.firewallEnabled),
                  value: enabledVal,
                  onChanged: (v) => setSt(() => enabledVal = v),
                ),
                TextField(
                  controller: pathCtrl,
                  decoration: InputDecoration(labelText: t.firewallRatePolicyPathRequired),
                ),
                TextField(
                  controller: methodsCtrl,
                  decoration: InputDecoration(labelText: t.firewallHttpMethodsOptional),
                ),
                TextField(
                  controller: maxCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: t.firewallRateMaxRequests),
                ),
                TextField(
                  controller: winCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: t.firewallRateWindowSeconds),
                ),
                TextField(
                  controller: priCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: t.firewallPriority),
                ),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(labelText: t.firewallNoteOptional),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final maxR = int.tryParse(maxCtrl.text.trim()) ?? 1;
      final winS = int.tryParse(winCtrl.text.trim()) ?? 60;
      final pri = int.tryParse(priCtrl.text.trim()) ?? 100;
      if (existing == null) {
        await widget.service.createRatePolicy({
          'enabled': enabledVal,
          'priority': pri,
          'path_prefix': pathCtrl.text.trim(),
          'http_methods': methodsCtrl.text.trim().isEmpty ? null : methodsCtrl.text.trim(),
          'max_requests': maxR,
          'window_seconds': winS,
          'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        });
      } else {
        await widget.service.updateRatePolicy((existing['id'] as num).toInt(), {
          'enabled': enabledVal,
          'priority': pri,
          'path_prefix': pathCtrl.text.trim(),
          'http_methods': methodsCtrl.text.trim().isEmpty ? null : methodsCtrl.text.trim(),
          'max_requests': maxR,
          'window_seconds': winS,
          'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.firewallSaved)));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.error}: ${ErrorExtractor.forContext(e, context)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: SelectableText('${t.error}: $_error'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(t.firewallRefresh)),
              FilledButton.icon(onPressed: () => _openEditor(), icon: const Icon(Icons.add), label: Text(t.firewallAddRatePolicy)),
            ],
          ),
        ),
        Expanded(
          child: _items.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(t.firewallNoRatePolicies)))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (ctx, i) {
                    final r = _items[i];
                    final id = (r['id'] as num).toInt();
                    final en = r['enabled'] == true || r['enabled'] == 1;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        title: Text('${r['path_prefix']}  •  ${r['max_requests']}/${r['window_seconds']}s'),
                        subtitle: Text(
                          '${t.firewallEnabled}: $en  •  ${t.firewallPriority}: ${r['priority']}  •  ${r['http_methods'] ?? 'ALL'}  •  ${r['note'] ?? '—'}',
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _openEditor(existing: r),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final del = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: Text(t.firewallDeleteRatePolicyTitle),
                                    content: Text(t.firewallDeleteRatePolicyBody),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
                                      FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t.delete)),
                                    ],
                                  ),
                                );
                                if (!context.mounted) return;
                                if (del == true) {
                                  try {
                                    await widget.service.deleteRatePolicy(id);
                                    await _load();
                                  } catch (e) {
                                    if (context.mounted) {
                                      messenger.showSnackBar(
                                        SnackBar(content: Text(ErrorExtractor.forContext(e, context))),
                                      );
                                    }
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FirewallBlockLogsTab extends StatefulWidget {
  const _FirewallBlockLogsTab({required this.service});
  final AdminFirewallService service;

  @override
  State<_FirewallBlockLogsTab> createState() => _FirewallBlockLogsTabState();
}

class _FirewallBlockLogsTabState extends State<_FirewallBlockLogsTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  int _skip = 0;
  static const _limit = 40;
  final _ipFilter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ipFilter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.service.requestLogs(
        skip: _skip,
        limit: _limit,
        clientIp: _ipFilter.text.trim().isEmpty ? null : _ipFilter.text.trim(),
        hours: 168,
      );
      final raw = data['items'] as List<dynamic>? ?? [];
      _items = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _total = (data['total'] as num?)?.toInt() ?? 0;
    } catch (e) {
      _error = ErrorExtractor.forContext(e, context);
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: SelectableText(_error!));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ipFilter,
                  decoration: InputDecoration(
                    labelText: t.firewallFilterByIp,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: () {
                _skip = 0;
                _load();
              }, child: Text(t.search)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _items.length,
            itemBuilder: (ctx, i) {
              final r = _items[i];
              return ListTile(
                dense: true,
                title: Text('${r['client_ip']} — ${r['method']} ${r['path']}'),
                subtitle: Text('${r['created_at'] ?? ''}  •  rule ${r['rule_id'] ?? '—'}'),
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _skip > 0
                  ? () {
                      _skip = (_skip - _limit).clamp(0, 1 << 30);
                      _load();
                    }
                  : null,
              child: Text(t.previousPage),
            ),
            Text('$_skip / $_total'),
            TextButton(
              onPressed: _skip + _limit < _total
                  ? () {
                      _skip += _limit;
                      _load();
                    }
                  : null,
              child: Text(t.nextPage),
            ),
          ],
        ),
      ],
    );
  }
}

class _FirewallAuditTab extends StatefulWidget {
  const _FirewallAuditTab({required this.service});
  final AdminFirewallService service;

  @override
  State<_FirewallAuditTab> createState() => _FirewallAuditTabState();
}

class _FirewallAuditTabState extends State<_FirewallAuditTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.service.auditLogs(limit: 80, hours: 168);
      final raw = data['items'] as List<dynamic>? ?? [];
      _items = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _error = ErrorExtractor.forContext(e, context);
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: SelectableText(_error!));
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(t.firewallRefresh)),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _items.length,
            itemBuilder: (ctx, i) {
              final r = _items[i];
              return ListTile(
                dense: true,
                title: Text('${r['event_type']} — ${r['ip_cidr'] ?? ''}'),
                subtitle: Text('${r['created_at'] ?? ''}  user ${r['actor_user_id'] ?? '—'}  rule ${r['rule_id'] ?? '—'}'),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FirewallReportsTab extends StatefulWidget {
  const _FirewallReportsTab({required this.service});
  final AdminFirewallService service;

  @override
  State<_FirewallReportsTab> createState() => _FirewallReportsTabState();
}

class _FirewallReportsTabState extends State<_FirewallReportsTab> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _data = await widget.service.reportsSummary(days: 7);
    } catch (e) {
      _error = ErrorExtractor.forContext(e, context);
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: SelectableText(_error!));
    }
    final d = _data!;
    final top = (d['top_blocked_ips'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final byDay = (d['blocks_by_day'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(t.firewallRefresh)),
          ],
        ),
        const SizedBox(height: 16),
        Text('${t.firewallReportsPeriod}: ${d['period_days']} ${t.firewallReportsDays}', style: Theme.of(context).textTheme.titleMedium),
        Text('${t.firewallReportsTotalBlocks}: ${d['total_blocked_requests']}'),
        Text('${t.firewallReportsActiveDenyRules}: ${d['active_deny_rules']}'),
        const SizedBox(height: 16),
        Text(t.firewallReportsTopIps, style: Theme.of(context).textTheme.titleSmall),
        ...top.map((e) => Text('${e['client_ip']}: ${e['count']}')),
        const SizedBox(height: 16),
        Text(t.firewallReportsByDay, style: Theme.of(context).textTheme.titleSmall),
        ...byDay.map((e) => Text('${e['date']}: ${e['count']}')),
      ],
    );
  }
}
