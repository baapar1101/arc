import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../services/office_automation_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';

class OaOrgPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const OaOrgPage({super.key, required this.businessId, required this.authStore});

  @override
  State<OaOrgPage> createState() => _OaOrgPageState();
}

class _OaOrgPageState extends State<OaOrgPage> with SingleTickerProviderStateMixin {
  final OfficeAutomationService _svc = OfficeAutomationService();
  late TabController _tabs;
  bool _loading = true;
  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _positions = [];
  List<Map<String, dynamic>> _holders = [];
  List<Map<String, dynamic>> _delegations = [];
  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _svc.listOrgUnits(businessId: widget.businessId, includeInactive: true),
        _svc.listPositions(businessId: widget.businessId, includeInactive: true),
        _svc.listHolders(businessId: widget.businessId),
        _svc.listDelegations(businessId: widget.businessId),
        _svc.listBusinessUsers(businessId: widget.businessId),
      ]);
      if (!mounted) return;
      setState(() {
        _units = results[0];
        _positions = results[1];
        _holders = results[2];
        _delegations = results[3];
        _users = results[4];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _editI18n({
    required String title,
    Map<String, dynamic>? existing,
    required Future<void> Function(Map<String, dynamic> payload) onSave,
    List<Widget> Function(Map<String, dynamic> draft, void Function(void Function()) setLocal)? extra,
  }) async {
    final t = AppLocalizations.of(context);
    final draft = Map<String, dynamic>.from(existing ?? {});
    final code = TextEditingController(text: '${draft['code'] ?? ''}');
    final fa = TextEditingController(text: '${(draft['name_i18n'] as Map?)?['fa'] ?? draft['title'] ?? ''}');
    final en = TextEditingController(text: '${(draft['name_i18n'] as Map?)?['en'] ?? ''}');
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: code, decoration: InputDecoration(labelText: t.oaCode)),
                    TextField(controller: fa, decoration: const InputDecoration(labelText: 'fa')),
                    TextField(controller: en, decoration: const InputDecoration(labelText: 'en')),
                    ...?extra?.call(draft, setLocal),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
            ],
          ),
        ),
      );
      if (ok != true) return;
      await onSave({
        ...draft,
        'code': code.text.trim(),
        'name_i18n': {'fa': fa.text.trim(), 'en': en.text.trim()},
      });
      await _load();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      code.dispose();
      fa.dispose();
      en.dispose();
    }
  }

  int? _userIdOf(Map row) => oaId(row['user_id'] ?? row['id']);

  String _userLabel(Map row) {
    final name = (row['user_name'] ?? row['name'] ?? '').toString();
    final email = (row['user_email'] ?? row['email'] ?? '').toString();
    if (name.isNotEmpty) return name;
    return email;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.oaOrg),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: t.oaUnits),
            Tab(text: t.oaPositions),
            Tab(text: t.oaHolders),
            Tab(text: t.oaDelegations),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _list(
                  _units,
                  title: (r) => '${r['title'] ?? r['code']}',
                  onAdd: () => _editI18n(
                    title: t.oaUnits,
                    extra: (draft, setLocal) => [
                      DropdownButtonFormField<int?>(
                        value: oaId(draft['parent_id']),
                        decoration: InputDecoration(labelText: t.oaParentUnit),
                        items: [
                          DropdownMenuItem<int?>(value: null, child: Text(t.oaNoParent)),
                          for (final u in _units)
                            DropdownMenuItem<int?>(value: oaId(u['id']), child: Text('${u['title'] ?? u['code']}')),
                        ],
                        onChanged: (v) => setLocal(() => draft['parent_id'] = v),
                      ),
                    ],
                    onSave: (p) => _svc.createOrgUnit(businessId: widget.businessId, payload: p),
                  ),
                  onTap: (r) => _editI18n(
                    title: t.oaUnits,
                    existing: r,
                    extra: (draft, setLocal) => [
                      DropdownButtonFormField<int?>(
                        value: oaId(draft['parent_id']),
                        decoration: InputDecoration(labelText: t.oaParentUnit),
                        items: [
                          DropdownMenuItem<int?>(value: null, child: Text(t.oaNoParent)),
                          for (final u in _units.where((u) => u['id'] != r['id']))
                            DropdownMenuItem<int?>(value: oaId(u['id']), child: Text('${u['title'] ?? u['code']}')),
                        ],
                        onChanged: (v) => setLocal(() => draft['parent_id'] = v),
                      ),
                    ],
                    onSave: (p) => _svc.updateOrgUnit(businessId: widget.businessId, unitId: oaId(r['id'])!, payload: p),
                  ),
                ),
                _list(
                  _positions,
                  title: (r) => '${r['title'] ?? r['code']} ${r['is_secretariat'] == true ? '· ${t.oaRegistry}' : ''}',
                  onAdd: () => _editI18n(
                    title: t.oaPositions,
                    extra: (draft, setLocal) => [
                      DropdownButtonFormField<int>(
                        value: oaId(draft['org_unit_id']),
                        decoration: InputDecoration(labelText: t.oaUnits),
                        items: [
                          for (final u in _units)
                            DropdownMenuItem(value: oaId(u['id']), child: Text('${u['title'] ?? u['code']}')),
                        ],
                        onChanged: (v) => setLocal(() => draft['org_unit_id'] = v),
                      ),
                      SwitchListTile(
                        title: Text(t.oaRegistry),
                        value: draft['is_secretariat'] == true,
                        onChanged: (v) => setLocal(() => draft['is_secretariat'] = v),
                      ),
                      SwitchListTile(
                        title: Text(t.oaSubtree),
                        value: draft['can_view_subtree'] == true,
                        onChanged: (v) => setLocal(() => draft['can_view_subtree'] = v),
                      ),
                    ],
                    onSave: (p) => _svc.createPosition(businessId: widget.businessId, payload: p),
                  ),
                  onTap: (r) => _editI18n(
                    title: t.oaPositions,
                    existing: r,
                    extra: (draft, setLocal) => [
                      DropdownButtonFormField<int>(
                        value: oaId(draft['org_unit_id']),
                        decoration: InputDecoration(labelText: t.oaUnits),
                        items: [
                          for (final u in _units)
                            DropdownMenuItem(value: oaId(u['id']), child: Text('${u['title'] ?? u['code']}')),
                        ],
                        onChanged: (v) => setLocal(() => draft['org_unit_id'] = v),
                      ),
                      SwitchListTile(
                        title: Text(t.oaRegistry),
                        value: draft['is_secretariat'] == true,
                        onChanged: (v) => setLocal(() => draft['is_secretariat'] = v),
                      ),
                      SwitchListTile(
                        title: Text(t.oaSubtree),
                        value: draft['can_view_subtree'] == true,
                        onChanged: (v) => setLocal(() => draft['can_view_subtree'] = v),
                      ),
                    ],
                    onSave: (p) => _svc.updatePosition(businessId: widget.businessId, positionId: oaId(r['id'])!, payload: p),
                  ),
                ),
                _list(
                  _holders,
                  title: (r) => '${r['user_name'] ?? r['user_id']} · ${r['position_title'] ?? r['position_id']}',
                  onAdd: () async {
                    int? positionId;
                    int? userId;
                    final t = AppLocalizations.of(context);
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(t.oaAssign),
                        content: SizedBox(
                          width: 420,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DropdownButtonFormField<int>(
                                decoration: InputDecoration(labelText: t.oaPositions),
                                items: [
                                  for (final p in _positions)
                                    DropdownMenuItem(value: oaId(p['id']), child: Text('${p['title'] ?? p['code']}')),
                                ],
                                onChanged: (v) => positionId = v,
                              ),
                              DropdownButtonFormField<int>(
                                decoration: InputDecoration(labelText: t.users),
                                items: [
                                  for (final u in _users)
                                    DropdownMenuItem(value: _userIdOf(u), child: Text(_userLabel(u))),
                                ],
                                onChanged: (v) => userId = v,
                              ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.oaAssign)),
                        ],
                      ),
                    );
                    if (ok == true && positionId != null && userId != null) {
                      try {
                        await _svc.assignHolder(
                          businessId: widget.businessId,
                          payload: {'position_id': positionId, 'user_id': userId, 'is_primary': true},
                        );
                        await _load();
                      } catch (e) {
                        if (!context.mounted) return;
                        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                      }
                    }
                  },
                  trailing: (r) => IconButton(
                    icon: const Icon(Icons.person_off_outlined),
                    onPressed: () async {
                      final holderId = oaId(r['id']);
                      if (holderId == null) return;
                      try {
                        await _svc.endHolder(businessId: widget.businessId, holderId: holderId);
                        await _load();
                      } catch (e) {
                        if (!context.mounted) return;
                        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                      }
                    },
                  ),
                ),
                _list(
                  _delegations,
                  title: (r) => '${r['delegate_name'] ?? r['delegate_user_id']} · ${r['position_title'] ?? ''} · ${r['scope']}',
                  onAdd: () async {
                    int? positionId;
                    int? userId;
                    String scope = 'full';
                    final t = AppLocalizations.of(context);
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => StatefulBuilder(
                        builder: (ctx, setLocal) => AlertDialog(
                          title: Text(t.oaDelegate),
                          content: SizedBox(
                            width: 420,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DropdownButtonFormField<int>(
                                  decoration: InputDecoration(labelText: t.oaPositions),
                                  items: [
                                    for (final p in _positions)
                                      DropdownMenuItem(value: oaId(p['id']), child: Text('${p['title'] ?? p['code']}')),
                                  ],
                                  onChanged: (v) => positionId = v,
                                ),
                                DropdownButtonFormField<int>(
                                  decoration: InputDecoration(labelText: t.users),
                                  items: [
                                    for (final u in _users)
                                      DropdownMenuItem(value: _userIdOf(u), child: Text(_userLabel(u))),
                                  ],
                                  onChanged: (v) => userId = v,
                                ),
                                DropdownButtonFormField<String>(
                                  value: scope,
                                  items: const [
                                    DropdownMenuItem(value: 'full', child: Text('full')),
                                    DropdownMenuItem(value: 'view', child: Text('view')),
                                    DropdownMenuItem(value: 'refer', child: Text('refer')),
                                  ],
                                  onChanged: (v) => setLocal(() => scope = v ?? 'full'),
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.oaDelegate)),
                          ],
                        ),
                      ),
                    );
                    if (ok == true && positionId != null && userId != null) {
                      try {
                        await _svc.createDelegation(
                          businessId: widget.businessId,
                          payload: {'position_id': positionId, 'delegate_user_id': userId, 'scope': scope},
                        );
                        await _load();
                      } catch (e) {
                        if (!context.mounted) return;
                        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                      }
                    }
                  },
                  trailing: (r) => IconButton(
                    icon: const Icon(Icons.stop_circle_outlined),
                    onPressed: () async {
                      final delegationId = oaId(r['id']);
                      if (delegationId == null) return;
                      try {
                        await _svc.endDelegation(businessId: widget.businessId, delegationId: delegationId);
                        await _load();
                      } catch (e) {
                        if (!context.mounted) return;
                        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                      }
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _list(
    List<Map<String, dynamic>> rows, {
    required String Function(Map<String, dynamic>) title,
    VoidCallback? onAdd,
    void Function(Map<String, dynamic>)? onTap,
    Widget Function(Map<String, dynamic>)? trailing,
  }) {
    return Column(
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(AppLocalizations.of(context).add)),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final row = rows[i];
              return ListTile(
                title: Text(title(row)),
                onTap: onTap == null ? null : () => onTap(row),
                trailing: trailing?.call(row),
              );
            },
          ),
        ),
      ],
    );
  }
}
