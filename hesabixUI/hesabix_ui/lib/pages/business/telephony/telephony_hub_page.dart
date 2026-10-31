import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../config/brand_config.dart';
import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../services/telephony/telephony_api.dart';
import '../../../widgets/telephony/telephony_dialer_sheet.dart';
import '../../../widgets/telephony/telephony_recording_player.dart';
import '../../../services/telephony/telephony_session_controller.dart';
import '../../../widgets/business_subpage_back_leading.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/telephony/telephony_l10n.dart';

class TelephonyHubPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const TelephonyHubPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<TelephonyHubPage> createState() => _TelephonyHubPageState();
}

class _TelephonyHubPageState extends State<TelephonyHubPage> {
  final _api = TelephonyApi();
  Map<String, dynamic>? _dashboard;
  bool _loading = true;
  String? _error;

  bool get _canManage =>
      widget.authStore.hasBusinessPermission('telephony', 'manage') ||
      (_dashboard?['access'] is Map && (_dashboard?['access'] as Map)['can_manage'] == true);

  bool get _canLive =>
      widget.authStore.hasBusinessPermission('telephony', 'live_monitor') ||
      widget.authStore.hasBusinessPermission('telephony', 'supervise') ||
      widget.authStore.hasBusinessPermission('telephony', 'manage');

  bool get _canReports =>
      widget.authStore.hasBusinessPermission('telephony', 'reports') ||
      widget.authStore.hasBusinessPermission('telephony', 'supervise') ||
      widget.authStore.hasBusinessPermission('telephony', 'manage');

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
      final data = await _api.getDashboard(widget.businessId);
      if (mounted) {
        setState(() {
          _dashboard = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final today = _dashboard?['today'] as Map? ?? {};
    final pbx = (_dashboard?['pbx_connections'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      scheme.primary.withValues(alpha: 0.16),
                      scheme.tertiary.withValues(alpha: 0.10),
                      scheme.surfaceContainerLow,
                    ],
                  ),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        HesabixBackButton(businessId: widget.businessId),
                        Icon(Icons.phone_in_talk_rounded, color: scheme.primary, size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            t.telephonyMenu,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.telephonySubtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: () => showTelephonyDialerSheet(
                            context,
                            businessId: widget.businessId,
                            session: TelephonySessionStore.instance.controller
                              ..bindBusiness(widget.businessId, pluginActive: true),
                          ),
                          icon: const Icon(Icons.dialpad_rounded),
                          label: Text(t.telephonyDialer),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'telephony/calls')),
                          icon: const Icon(Icons.history_rounded),
                          label: Text(t.history),
                        ),
                        if (_canLive)
                          OutlinedButton.icon(
                            onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'telephony/live')),
                            icon: const Icon(Icons.monitor_heart_outlined),
                            label: Text(t.telephonyLive),
                          ),
                        if (_canReports)
                          OutlinedButton.icon(
                            onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'telephony/reports')),
                            icon: const Icon(Icons.insights_outlined),
                            label: Text(t.telephonyReports),
                          ),
                        if (_canManage)
                          OutlinedButton.icon(
                            onPressed: () =>
                                context.go(context.businessPanelUrl(widget.businessId, 'settings/telephony')),
                            icon: const Icon(Icons.settings_outlined),
                            label: Text(t.settings),
                          ),
                        TextButton.icon(
                          onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'telephony/softphone')),
                          icon: const Icon(Icons.headset_mic_outlined),
                          label: const Text('Softphone'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.35,
                  ),
                  delegate: SliverChildListDelegate([
                    _KpiTile(label: t.telephonyInboundToday, value: '${today['inbound'] ?? 0}', icon: Icons.call_received_rounded, color: scheme.primary),
                    _KpiTile(label: t.telephonyOutboundToday, value: '${today['outbound'] ?? 0}', icon: Icons.call_made_rounded, color: scheme.tertiary),
                    _KpiTile(label: t.telephonyAnswered, value: '${today['answered'] ?? 0}', icon: Icons.call_rounded, color: const Color(0xFF159947)),
                    _KpiTile(label: t.telephonyMissed, value: '${today['missed'] ?? 0}', icon: Icons.call_missed_rounded, color: scheme.error),
                    _KpiTile(label: t.telephonyActiveCall, value: '${_dashboard?['active_calls'] ?? 0}', icon: Icons.graphic_eq_rounded, color: const Color(0xFFD97706)),
                    _KpiTile(label: t.telephonyMyMissed, value: '${today['my_missed'] ?? 0}', icon: Icons.person_off_outlined, color: scheme.secondary),
                  ]),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text(t.telephonyPbxStatusTitle, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
              if (pbx.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                      ),
                      child: Column(
                        children: [
                          Text(t.telephonyNoPbxConnected),
                          const SizedBox(height: 12),
                          if (_canManage)
                            FilledButton(
                              onPressed: () =>
                                  context.go(context.businessPanelUrl(widget.businessId, 'settings/telephony')),
                              child: Text(t.telephonyConnectIssabel),
                            )
                          else
                            Text(t.telephonyAskAdminMapExt),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final row = pbx[i];
                      final online = '${row['status']}' == 'online';
                      return ListTile(
                        leading: Icon(
                          Icons.dns_rounded,
                          color: online ? const Color(0xFF159947) : scheme.outline,
                        ),
                        title: Text('${row['name']}'),
                        subtitle: Text('${row['pbx_type']} · ${row['status']}'),
                        trailing: online
                            ? Chip(label: Text(t.telephonyOnline), visualDensity: VisualDensity.compact)
                            : Chip(label: Text(t.telephonyOffline), visualDensity: VisualDensity.compact),
                      );
                    },
                    childCount: pbx.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ],
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: scheme.surface,
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class TelephonyCallsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const TelephonyCallsPage({super.key, required this.businessId, required this.authStore});

  @override
  State<TelephonyCallsPage> createState() => _TelephonyCallsPageState();
}

class _TelephonyCallsPageState extends State<TelephonyCallsPage> {
  final _api = TelephonyApi();
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _filterStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _api.listCalls(
        widget.businessId,
        status: _filterStatus,
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
      );
      final items = (data['items'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _statusColor(String status, ColorScheme scheme) {
    switch (status) {
      case 'missed':
        return scheme.error;
      case 'completed':
      case 'answered':
        return const Color(0xFF159947);
      case 'ringing':
        return const Color(0xFFD97706);
      default:
        return scheme.outline;
    }
  }

  String _statusFa(String status) {
    return telephonyCallStatusLabel(AppLocalizations.of(context), status);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.telephonyCallHistoryTitle),
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: t.telephonySearchNumberOrNote,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final e in [
                  (null, t.all),
                  ('missed', t.telephonyStatusMissed),
                  ('completed', t.telephonyFilterSuccessful),
                  ('ringing', t.telephonyStatusActive),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(e.$2),
                      selected: _filterStatus == e.$1,
                      onSelected: (_) {
                        setState(() => _filterStatus = e.$1);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final c = _items[i];
                        final status = '${c['status'] ?? ''}';
                        final dir = '${c['direction'] ?? ''}';
                        final peer = dir == 'inbound'
                            ? (c['from_number_normalized'] ?? c['from_number_raw'])
                            : (c['to_number_normalized'] ?? c['to_number_raw']);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _statusColor(status, scheme).withValues(alpha: 0.15),
                            child: Icon(
                              dir == 'inbound' ? Icons.call_received_rounded : Icons.call_made_rounded,
                              color: _statusColor(status, scheme),
                            ),
                          ),
                          title: Text('$peer'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.telephonyCallListSubtitle(_statusFa(status), '${c['extension'] ?? '—'}', '${c['duration_sec'] ?? 0}'),
                              ),
                              if ('${c['recording_status']}' == 'available')
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: TelephonyRecordingPlayer(
                                    businessId: widget.businessId,
                                    callId: int.parse('${c['id']}'),
                                  ),
                                ),
                            ],
                          ),
                          isThreeLine: '${c['recording_status']}' == 'available',
                          trailing: Text('${c['started_at'] ?? ''}'.split('T').first),
                          onTap: () async {
                            final note = TextEditingController(text: '${c['note'] ?? ''}');
                            final category = TextEditingController(text: '${c['category'] ?? ''}');
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(t.telephonyCallDetails),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextField(
                                      controller: note,
                                      minLines: 3,
                                      maxLines: 5,
                                      decoration: InputDecoration(labelText: t.telephonyNote),
                                    ),
                                    TextField(
                                      controller: category,
                                      decoration: InputDecoration(
                                        labelText: t.telephonyCategoryHint,
                                      ),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.close)),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(t.save),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await _api.patchCall(widget.businessId, int.parse('${c['id']}'), {
                                'note': note.text,
                                'category': category.text.trim().isEmpty ? null : category.text.trim(),
                              });
                              _load();
                            }
                          },
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

class TelephonySettingsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const TelephonySettingsPage({super.key, required this.businessId, required this.authStore});

  @override
  State<TelephonySettingsPage> createState() => _TelephonySettingsPageState();
}

class _TelephonySettingsPageState extends State<TelephonySettingsPage> {
  final _api = TelephonyApi();
  List<Map<String, dynamic>> _pbx = [];
  List<Map<String, dynamic>> _extensions = [];
  List<Map<String, dynamic>> _userExt = [];
  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic>? _settings;
  bool _loading = true;
  String? _freshToken;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.authStore.hasBusinessPermission('telephony', 'manage')) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final settings = await _api.getSettings(widget.businessId);
      final pbx = await _api.listPbx(widget.businessId);
      final ext = await _api.listExtensions(widget.businessId);
      final ue = await _api.listUserExtensions(widget.businessId);
      List<Map<String, dynamic>> users = const [];
      try {
        users = await _api.listAssignableUsers(widget.businessId);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _settings = settings;
          _pbx = pbx;
          _extensions = ext;
          _userExt = ue;
          _users = users;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _addPbx() async {
    final t = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: t.telephonyDefaultPbxName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.telephonyAddPbx),
        content: TextField(controller: nameCtrl, decoration: InputDecoration(labelText: t.telephonyPbxName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.create)),
        ],
      ),
    );
    if (ok != true) return;
    final created = await _api.createPbx(widget.businessId, {
      'name': nameCtrl.text.trim(),
      'pbx_type': 'issabel',
    });
    setState(() => _freshToken = created['connector_token']?.toString());
    await _load();
  }

  Future<void> _addExtension() async {
    final t = AppLocalizations.of(context);
    if (_pbx.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.telephonyCreatePbxFirst)));
      return;
    }
    final extCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final teamCtrl = TextEditingController();
    var allowShared = false;
    var pbxId = int.tryParse('${_pbx.first['id']}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(t.telephonyAddExtension),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_pbx.length > 1)
                DropdownButtonFormField<int>(
                  value: pbxId,
                  decoration: InputDecoration(labelText: t.telephonyPbx),
                  items: _pbx
                      .map(
                        (p) => DropdownMenuItem(
                          value: int.tryParse('${p['id']}'),
                          child: Text('${p['name']}'),
                        ),
                      )
                      .where((e) => e.value != null)
                      .toList(),
                  onChanged: (v) => setLocal(() => pbxId = v),
                ),
              TextField(controller: extCtrl, decoration: InputDecoration(labelText: t.telephonyExtensionNumber)),
              TextField(controller: nameCtrl, decoration: InputDecoration(labelText: t.telephonyDisplayName)),
              TextField(
                controller: teamCtrl,
                decoration: InputDecoration(
                  labelText: t.telephonyTeamCode,
                  hintText: t.telephonyTeamCodeHint,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.telephonyAllowSharedExt),
                subtitle: Text(t.telephonyAllowSharedExtHint),
                value: allowShared,
                onChanged: (v) => setLocal(() => allowShared = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
          ],
        ),
      ),
    );
    if (ok != true || pbxId == null) return;
    await _api.upsertExtension(widget.businessId, {
      'pbx_id': pbxId,
      'extension': extCtrl.text.trim(),
      'display_name': nameCtrl.text.trim(),
      'team_code': teamCtrl.text.trim().isEmpty ? null : teamCtrl.text.trim(),
      'allow_shared': allowShared,
    });
    await _load();
  }

  Future<void> _mapMe() async {
    final t = AppLocalizations.of(context);
    if (_extensions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.telephonyCreateExtFirst)));
      return;
    }
    await _editUserExtensionMapping(
      userId: widget.authStore.currentUserId,
      extensionId: int.tryParse('${_extensions.first['id']}'),
      endpointMode: 'relay',
      allowFallback: true,
      isPrimary: true,
    );
  }

  Future<void> _editUserExtensionMapping({
    int? userId,
    int? linkId,
    int? extensionId,
    String endpointMode = 'desk',
    bool allowFallback = true,
    bool isPrimary = true,
    String? directSipUser,
    bool canSuperviseTeam = false,
  }) async {
    if (_extensions.isEmpty) return;
    var selectedUserId = userId ?? widget.authStore.currentUserId;
    var selectedExtId = extensionId ?? int.tryParse('${_extensions.first['id']}');
    var mode = endpointMode;
    var fallback = allowFallback;
    var primary = isPrimary;
    var supervise = canSuperviseTeam;
    final t = AppLocalizations.of(context);
    final sipCtrl = TextEditingController(text: directSipUser ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(linkId == null ? t.telephonyMapExtSoftphone : t.telephonyEditSoftphoneMapping),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: selectedUserId,
                      decoration: InputDecoration(labelText: t.telephonyBusinessUser),
                      items: [
                        for (final u in _users)
                          DropdownMenuItem(
                            value: int.tryParse('${u['id']}'),
                            child: Text('${u['name'] ?? u['id']}'),
                          ),
                        if (_users.every((u) => int.tryParse('${u['id']}') != selectedUserId) && selectedUserId != null)
                          DropdownMenuItem(value: selectedUserId, child: Text(t.telephonyUserId('$selectedUserId'))),
                      ].where((e) => e.value != null).toList(),
                      onChanged: (v) => setLocal(() => selectedUserId = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: selectedExtId,
                      decoration: InputDecoration(labelText: t.telephonyExtension),
                      items: _extensions
                          .map(
                            (e) => DropdownMenuItem(
                              value: int.tryParse('${e['id']}'),
                              child: Text('${e['extension']} ${e['display_name'] ?? ''}'),
                            ),
                          )
                          .where((e) => e.value != null)
                          .toList(),
                      onChanged: (v) => setLocal(() => selectedExtId = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: mode,
                      decoration: InputDecoration(
                        labelText: t.telephonyEndpointMode,
                        helperText: t.telephonyEndpointModeHint,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'relay',
                          child: Text(t.branded(t.telephonyEndpointRelay)),
                        ),
                        DropdownMenuItem(value: 'desk', child: Text(t.telephonyEndpointDesk)),
                        DropdownMenuItem(value: 'direct', child: Text(t.telephonyEndpointDirect)),
                      ],
                      onChanged: (v) => setLocal(() => mode = v ?? 'desk'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.telephonyAllowFallback),
                      subtitle: Text(t.telephonyAllowFallbackHint),
                      value: fallback,
                      onChanged: (v) => setLocal(() => fallback = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.telephonyPrimaryExtension),
                      value: primary,
                      onChanged: (v) => setLocal(() => primary = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.telephonyTeamSupervisor),
                      subtitle: Text(t.telephonyTeamSupervisorHint),
                      value: supervise,
                      onChanged: (v) => setLocal(() => supervise = v),
                    ),
                    if (mode == 'direct')
                      TextField(
                        controller: sipCtrl,
                        decoration: InputDecoration(
                          labelText: 'SIP user (Direct)',
                          hintText: t.telephonyDirectSipHint,
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
              ],
            );
          },
        );
      },
    );
    if (ok != true || selectedExtId == null || selectedUserId == null) return;
    await _api.upsertUserExtension(widget.businessId, {
      'user_id': selectedUserId,
      'extension_id': selectedExtId,
      'is_primary': primary,
      'receive_screen_pop': true,
      'can_click_to_call': true,
      'can_supervise_team': supervise,
      'endpoint_mode': mode,
      'allow_mode_fallback': fallback,
      if (mode == 'direct') 'direct_sip_user': sipCtrl.text.trim(),
    });
    await _load();
    TelephonySessionStore.instance.controller.refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.telephonyMappingSaved(mode))),
      );
    }
  }

  Future<void> _editPbxSoftphone(Map<String, dynamic> pbx) async {
    final t = AppLocalizations.of(context);
    final settings = Map<String, dynamic>.from((pbx['settings'] as Map?) ?? const {});
    final soft = Map<String, dynamic>.from((settings['softphone'] as Map?) ?? const {});
    var relay = soft['relay_enabled'] != false;
    var direct = soft['direct_enabled'] == true;
    final maxCtrl = TextEditingController(
      text: '${soft['max_concurrent_softphone_sessions'] ?? 50}',
    );
    final portCtrl = TextEditingController(
      text: '${soft['audiosocket_port'] ?? 9092}',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(t.telephonySoftphoneForPbx('${pbx['name']}')),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.telephonySoftphoneRelayEnabled),
                      subtitle: Text(t.telephonySoftphoneRelayHint),
                      value: relay,
                      onChanged: (v) => setLocal(() => relay = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.telephonySoftphoneDirectEnabled),
                      subtitle: Text(t.telephonySoftphoneDirectHint),
                      value: direct,
                      onChanged: (v) => setLocal(() => direct = v),
                    ),
                    TextField(
                      controller: maxCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: t.telephonyMaxSoftphoneSessions),
                    ),
                    TextField(
                      controller: portCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: t.telephonyAudiosocketPort),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    settings['softphone'] = {
      ...soft,
      'relay_enabled': relay,
      'direct_enabled': direct,
      'max_concurrent_softphone_sessions': int.tryParse(maxCtrl.text.trim()) ?? 50,
      'audiosocket_host': soft['audiosocket_host'] ?? '127.0.0.1',
      'audiosocket_port': int.tryParse(portCtrl.text.trim()) ?? 9092,
      'media_codec_prefs': soft['media_codec_prefs'] ?? ['pcm_ws_v1'],
    };
    await _api.patchPbx(widget.businessId, int.parse('${pbx['id']}'), {'settings': settings});
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.telephonySoftphoneSettingsSaved)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (!widget.authStore.hasBusinessPermission('telephony', 'manage')) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t.telephonySettingsTitle),
          leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(t.telephonyManageOnlyHint),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(t.telephonySettingsTitle),
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPbx,
        icon: const Icon(Icons.add_rounded),
        label: Text(t.telephonyPbx),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_freshToken != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.telephonyConnectorTokenOnce, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        SelectableText(_freshToken!, style: const TextStyle(fontFamily: 'monospace')),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: _freshToken!));
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.copied)));
                            }
                          },
                          icon: const Icon(Icons.copy),
                          label: Text(t.telephonyCopyToken),
                        ),
                      ],
                    ),
                  ),
                Text(t.telephonySetupStepsTitle, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  t.telephonySetupSteps,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.telephonyRelaySetupTitle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t.telephonyRelaySetupBody,
                        style: const TextStyle(height: 1.45),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () =>
                            context.go(context.businessPanelUrl(widget.businessId, 'telephony/softphone')),
                        icon: const Icon(Icons.headset_mic_outlined),
                        label: Text(t.telephonyOpenSoftphone),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.telephonyOneLineIssabelInstall,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t.branded(t.telephonyInstallCommandHelp),
                        style: const TextStyle(height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        'curl -fsSL https://source.hesabix.ir/hesabix/arc/raw/branch/master/extraScripts/HesabixTelephonyConnector/install.sh | sudo bash',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              const cmd =
                                  'curl -fsSL https://source.hesabix.ir/hesabix/arc/raw/branch/master/extraScripts/HesabixTelephonyConnector/install.sh | sudo bash';
                              await Clipboard.setData(const ClipboardData(text: cmd));
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(t.telephonyInstallCopied)),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: Text(t.telephonyCopyInstallCommand),
                          ),
                          TextButton(
                            onPressed: () async {
                              const help = 'hesabix-pbx status\nhesabix-pbx test\nhesabix-pbx update\nhesabix-pbx restart\nhesabix-pbx configure\nhesabix-pbx logs';
                              await Clipboard.setData(const ClipboardData(text: help));
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(t.telephonyManageCommandsCopied)),
                                );
                              }
                            },
                            child: Text(t.telephonyCopyManageCommands),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t.telephonyAfterInstallHint,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Screen Pop'),
                  subtitle: Text(t.telephonyScreenPopHint),
                  value: _settings?['screen_pop_enabled'] == true,
                  onChanged: (v) async {
                    await _api.updateSettings(widget.businessId, {'screen_pop_enabled': v});
                    _load();
                  },
                ),
                SwitchListTile(
                  title: Text(t.telephonyAutoCrmActivity),
                  subtitle: Text(t.telephonyAutoCrmActivityHint),
                  value: _settings?['auto_create_activity'] != false,
                  onChanged: (v) async {
                    await _api.updateSettings(widget.businessId, {'auto_create_activity': v});
                    _load();
                  },
                ),
                SwitchListTile(
                  title: Text(t.telephonyForcePostCallForm),
                  subtitle: Text(t.telephonyForcePostCallFormHint),
                  value: _settings?['post_call_form_required'] == true,
                  onChanged: (v) async {
                    await _api.updateSettings(widget.businessId, {'post_call_form_required': v});
                    _load();
                  },
                ),
                SwitchListTile(
                  title: Text(t.telephonyMissedCallTask),
                  subtitle: Text(t.telephonyMissedCallTaskHint),
                  value: _settings?['missed_call_create_task'] == true,
                  onChanged: (v) async {
                    await _api.updateSettings(widget.businessId, {'missed_call_create_task': v});
                    _load();
                  },
                ),
                if (_settings?['missed_call_create_task'] == true)
                  ListTile(
                    title: Text(t.telephonyFollowUpMinutes),
                    subtitle: Text(t.telephonyMinutesValue('${_settings?['missed_call_task_due_minutes'] ?? 60}')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: t.decrease,
                          onPressed: () async {
                            final cur = int.tryParse('${_settings?['missed_call_task_due_minutes']}') ?? 60;
                            final next = (cur - 15).clamp(15, 480);
                            await _api.updateSettings(widget.businessId, {'missed_call_task_due_minutes': next});
                            _load();
                          },
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        IconButton(
                          tooltip: t.increase,
                          onPressed: () async {
                            final cur = int.tryParse('${_settings?['missed_call_task_due_minutes']}') ?? 60;
                            final next = (cur + 15).clamp(15, 480);
                            await _api.updateSettings(widget.businessId, {'missed_call_task_due_minutes': next});
                            _load();
                          },
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ),
                ListTile(
                  title: Text(t.telephonyRecordingAccess),
                  subtitle: Text(
                    {
                          'all_operators': t.telephonyRecordingAccessAllOperatorsHint,
                          'owner_and_managers': t.telephonyRecordingAccessOwnerHint,
                        }['${_settings?['recording_access_mode']}'] ??
                        t.telephonyRecordingAccessPermissionHint,
                  ),
                  trailing: DropdownButton<String>(
                    value: '${_settings?['recording_access_mode'] ?? 'permission_based'}',
                    items: [
                      DropdownMenuItem(value: 'permission_based', child: Text(t.telephonyRecordingAccessPermissionBased)),
                      DropdownMenuItem(value: 'owner_and_managers', child: Text(t.telephonyRecordingAccessOwnerManagers)),
                      DropdownMenuItem(value: 'all_operators', child: Text(t.telephonyRecordingAccessAllowedOps)),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      await _api.updateSettings(widget.businessId, {'recording_access_mode': v});
                      _load();
                    },
                  ),
                ),
                SwitchListTile(
                  title: Text(t.telephonyMultiPbx),
                  subtitle: Text(t.telephonyMultiPbxHint),
                  value: _settings?['multi_pbx_enabled'] == true,
                  onChanged: (v) async {
                    await _api.updateSettings(widget.businessId, {'multi_pbx_enabled': v});
                    _load();
                  },
                ),
                const Divider(),
                ListTile(
                  title: Text(t.telephonyPbxs),
                  trailing: TextButton(onPressed: _addPbx, child: Text(t.add)),
                ),
                ..._pbx.map(
                  (p) {
                    final soft = ((p['settings'] as Map?)?['softphone'] as Map?) ?? const {};
                    final relayOn = soft['relay_enabled'] != false;
                    final directOn = soft['direct_enabled'] == true;
                    return ListTile(
                      leading: Icon(
                        Icons.cloud_done_outlined,
                        color: '${p['status']}' == 'online' ? const Color(0xFF159947) : scheme.outline,
                      ),
                      title: Text('${p['name']}'),
                      subtitle: Text(
                        '${p['status']} · Softphone: '
                        '${relayOn ? 'Relay' : '—'}'
                        '${directOn ? '+Direct' : ''} · '
                        '${p['connector_token_prefix'] ?? ''}…',
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          TextButton(
                            onPressed: () => _editPbxSoftphone(p),
                            child: const Text('Softphone'),
                          ),
                          TextButton(
                            onPressed: () async {
                              final r = await _api.rotateToken(widget.businessId, int.parse('${p['id']}'));
                              setState(() => _freshToken = r['connector_token']?.toString());
                              await _load();
                            },
                            child: Text(t.telephonyNewToken),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  title: Text(t.telephonyExtensions),
                  subtitle: Text(
                    t.telephonyExtensionsHint,
                  ),
                  trailing: TextButton(onPressed: _addExtension, child: Text(t.add)),
                ),
                ..._extensions.map(
                  (e) => ListTile(
                    leading: const Icon(Icons.phone_outlined),
                    title: Text('${e['extension']} ${e['display_name'] ?? ''}'),
                    subtitle: Text(
                      [
                        if ('${e['team_code'] ?? ''}'.isNotEmpty) t.telephonyTeamValue('${e['team_code']}'),
                        e['allow_shared'] == true ? t.telephonyShareable : t.telephonyExclusive,
                      ].join(' · '),
                    ),
                  ),
                ),
                const Divider(),
                ListTile(
                  title: Text(t.telephonyUserExtMapping),
                  subtitle: Text(t.telephonyUserExtMappingHint),
                  trailing: TextButton(onPressed: _mapMe, child: Text(t.telephonyAssignExtension)),
                ),
                ..._userExt.map(
                  (e) => ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(t.telephonyUserToExtension('${e['user_name'] ?? t.telephonyUserId('${e['user_id']}')}', '${e['extension']}')),
                    subtitle: Text(
                      t.telephonyMappingLine(
                        e['is_primary'] == true ? t.telephonyPrimary : t.telephonySecondary,
                        '${e['endpoint_mode'] ?? 'desk'}',
                        '${e['team_code'] ?? ''}'.isNotEmpty ? ' · ${t.telephonyTeamValue('${e['team_code']}')}' : '',
                        e['allow_mode_fallback'] == false ? ' · ${t.telephonyNoFallback}' : '',
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: t.telephonyEditMapping,
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editUserExtensionMapping(
                        userId: int.parse('${e['user_id']}'),
                        linkId: int.tryParse('${e['id']}'),
                        extensionId: int.tryParse('${e['extension_id']}'),
                        endpointMode: '${e['endpoint_mode'] ?? 'desk'}',
                        allowFallback: e['allow_mode_fallback'] != false,
                        isPrimary: e['is_primary'] == true,
                        directSipUser: e['direct_sip_user']?.toString(),
                        canSuperviseTeam: e['can_supervise_team'] == true,
                      ),
                    ),
                  ),
                ),
                const Divider(),
                ListTile(
                  title: Text(t.telephonyOpsHealth),
                  subtitle: Text(t.telephonyOpsHealthHint),
                  trailing: TextButton(
                    onPressed: () async {
                      try {
                        final metrics = await _api.opsMetrics(widget.businessId);
                        final dlq = await _api.deadLetters(widget.businessId);
                        if (!mounted) return;
                        await showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (ctx) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: SizedBox(
                                height: MediaQuery.sizeOf(ctx).height * 0.7,
                                child: ListView(
                                  children: [
                                    Text(t.telephonyMetrics, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                    Text('${metrics['metrics']}'),
                                    Text(t.telephonyOpenDlq('${metrics['open_dlq']}')),
                                    const Divider(),
                                    Text('Dead letters', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                    ...dlq.map(
                                      (d) => ListTile(
                                        title: Text('${d['error_message']}'),
                                        subtitle: Text('${d['created_at']}'),
                                        trailing: TextButton(
                                          onPressed: () async {
                                            await _api.resolveDeadLetter(widget.businessId, int.parse('${d['id']}'));
                                            Navigator.pop(ctx);
                                          },
                                          child: Text(t.telephonyResolved),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                    child: Text(t.view),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
    );
  }
}
