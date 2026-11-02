import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../services/office_automation_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/office_automation/oa_searchable_field.dart';
import '../../../widgets/office_automation/oa_ui.dart';

final _oaCodeRe = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$');

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

  bool _codeTaken(String code, {required bool forUnit, int? excludeId}) {
    final needle = code.trim().toLowerCase();
    final rows = forUnit ? _units : _positions;
    for (final row in rows) {
      if (oaId(row['id']) == excludeId) continue;
      if ((row['code'] ?? '').toString().trim().toLowerCase() == needle) return true;
    }
    return false;
  }

  List<Map<String, dynamic>> _unitForest() {
    final byId = <int, Map<String, dynamic>>{
      for (final u in _units)
        if (oaId(u['id']) != null) oaId(u['id'])!: u,
    };
    final children = <int?, List<Map<String, dynamic>>>{};
    for (final u in _units) {
      final parentId = oaId(u['parent_id']);
      final key = parentId != null && byId.containsKey(parentId) ? parentId : null;
      children.putIfAbsent(key, () => []).add(u);
    }
    List<Map<String, dynamic>> attach(int? parentId) {
      return [
        for (final node in children[parentId] ?? const <Map<String, dynamic>>[])
          {...node, 'children': attach(oaId(node['id']))},
      ];
    }

    return attach(null);
  }

  Future<void> _editI18n({
    required String title,
    Map<String, dynamic>? existing,
    Map<String, dynamic>? seed,
    required Future<void> Function(Map<String, dynamic> payload) onSave,
    List<Widget> Function(Map<String, dynamic> draft, void Function(void Function()) setLocal)? extra,
    required bool forUnit,
    bool requireUnit = false,
  }) async {
    final isCreate = oaId(existing?['id']) == null;
    final draft = Map<String, dynamic>.from(existing ?? seed ?? {});
    final formKey = GlobalKey<FormState>();
    final code = TextEditingController(text: isCreate ? '' : '${draft['code'] ?? ''}');
    final fa = TextEditingController(text: '${(draft['name_i18n'] as Map?)?['fa'] ?? draft['title'] ?? ''}');
    final en = TextEditingController(text: '${(draft['name_i18n'] as Map?)?['en'] ?? ''}');
    var autoCode = isCreate;
    String? errorText;
    var saving = false;
    try {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) {
            final loc = AppLocalizations.of(ctx);
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 420,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: code,
                          enabled: !saving,
                          readOnly: autoCode,
                          decoration: InputDecoration(
                            labelText: loc.oaCode,
                            hintText: autoCode ? loc.automatic : loc.oaCode,
                            suffixIconConstraints: const BoxConstraints(minHeight: 36, minWidth: 140),
                            suffixIcon: isCreate
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                                    child: ToggleButtons(
                                      isSelected: [autoCode, !autoCode],
                                      borderRadius: BorderRadius.circular(6),
                                      constraints: const BoxConstraints(minHeight: 32, minWidth: 64),
                                      onPressed: saving
                                          ? null
                                          : (index) {
                                              setLocal(() {
                                                autoCode = index == 0;
                                                errorText = null;
                                                if (autoCode) code.clear();
                                              });
                                            },
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          child: Text(loc.automatic),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          child: Text(loc.manual),
                                        ),
                                      ],
                                    ),
                                  )
                                : null,
                          ),
                          validator: (value) {
                            if (autoCode) return null;
                            final trimmed = (value ?? '').trim();
                            if (trimmed.isEmpty) return loc.codeRequired;
                            if (!_oaCodeRe.hasMatch(trimmed)) return loc.oaCodeFormat;
                            if (_codeTaken(trimmed, forUnit: forUnit, excludeId: oaId(existing?['id']))) {
                              return loc.oaCodeExists;
                            }
                            return null;
                          },
                        ),
                        TextFormField(
                          controller: fa,
                          enabled: !saving,
                          decoration: const InputDecoration(labelText: 'fa'),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty && en.text.trim().isEmpty) {
                              return loc.oaNameRequired;
                            }
                            return null;
                          },
                        ),
                        TextFormField(
                          controller: en,
                          enabled: !saving,
                          decoration: const InputDecoration(labelText: 'en'),
                        ),
                        ...?extra?.call(draft, setLocal),
                        if (errorText != null) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              errorText!,
                              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx, false),
                  child: Text(loc.cancel),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setLocal(() => errorText = null);
                          if (!(formKey.currentState?.validate() ?? false)) return;
                          if (requireUnit && oaId(draft['org_unit_id']) == null) {
                            setLocal(() => errorText = loc.oaSelectUnit);
                            return;
                          }
                          setLocal(() => saving = true);
                          final payload = <String, dynamic>{
                            if (autoCode) 'auto_generate_code': true,
                            if (!autoCode) ...{
                              'auto_generate_code': false,
                              'code': code.text.trim(),
                            },
                            'name_i18n': {'fa': fa.text.trim(), 'en': en.text.trim()},
                          };
                          if (forUnit) {
                            payload['parent_id'] = draft['parent_id'];
                          } else {
                            payload['org_unit_id'] = draft['org_unit_id'];
                            payload['is_secretariat'] = draft['is_secretariat'] == true;
                            payload['can_view_subtree'] = draft['can_view_subtree'] == true;
                          }
                          try {
                            await onSave(payload);
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (e) {
                            setLocal(() {
                              saving = false;
                              errorText = ErrorExtractor.forContext(e, ctx);
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(loc.save),
                ),
              ],
            );
          },
        ),
      );
      if (ok == true) await _load();
    } finally {
      code.dispose();
      fa.dispose();
      en.dispose();
    }
  }

  Future<void> _editUnit({Map<String, dynamic>? existing, int? parentId}) {
    final t = AppLocalizations.of(context);
    return _editI18n(
      title: existing == null ? t.oaUnits : t.edit,
      existing: existing,
      seed: parentId != null ? {'parent_id': parentId} : null,
      forUnit: true,
      extra: (draft, setLocal) {
        final loc = AppLocalizations.of(context);
        return [
          OaSearchableField(
            label: loc.oaParentUnit,
            hint: loc.oaNoParent,
            emptyText: loc.oaNoSearchResults,
            prefixIcon: Icons.account_tree_outlined,
            allowClear: true,
            value: () {
              final id = oaId(draft['parent_id']);
              if (id == null) return null;
              for (final u in _units) {
                if (oaId(u['id']) == id) {
                  return OaSearchItem(id: '$id', title: '${u['title'] ?? u['code']}', payload: u);
                }
              }
              return OaSearchItem(id: '$id', title: '$id');
            }(),
            onChanged: (item) => setLocal(() => draft['parent_id'] = item == null ? null : int.tryParse(item.id)),
            onSearch: (q) async {
              final needle = q.trim().toLowerCase();
              final rows = _units.where((u) => oaId(u['id']) != oaId(existing?['id']));
              final filtered = needle.isEmpty
                  ? rows
                  : rows.where((u) => '${u['title'] ?? ''} ${u['code'] ?? ''}'.toLowerCase().contains(needle));
              return [
                for (final u in filtered)
                  if (oaId(u['id']) != null)
                    OaSearchItem(id: '${oaId(u['id'])}', title: '${u['title'] ?? u['code']}', subtitle: '${u['code'] ?? ''}'),
              ];
            },
          ),
        ];
      },
      onSave: (p) async {
        final id = oaId(existing?['id']);
        if (id == null) {
          await _svc.createOrgUnit(businessId: widget.businessId, payload: p);
        } else {
          await _svc.updateOrgUnit(businessId: widget.businessId, unitId: id, payload: p);
        }
      },
    );
  }

  Future<void> _editPosition({Map<String, dynamic>? existing, int? unitId}) {
    final t = AppLocalizations.of(context);
    return _editI18n(
      title: existing == null ? t.oaPositions : t.edit,
      existing: existing,
      seed: unitId != null ? {'org_unit_id': unitId} : null,
      forUnit: false,
      requireUnit: true,
      extra: (draft, setLocal) {
        final loc = AppLocalizations.of(context);
        return [
          OaSearchableField(
            label: loc.oaUnits,
            hint: loc.oaSelectUnit,
            emptyText: loc.oaNoSearchResults,
            prefixIcon: Icons.apartment_outlined,
            value: () {
              final id = oaId(draft['org_unit_id']);
              if (id == null) return null;
              for (final u in _units) {
                if (oaId(u['id']) == id) {
                  return OaSearchItem(id: '$id', title: '${u['title'] ?? u['code']}', subtitle: '${u['code'] ?? ''}');
                }
              }
              return OaSearchItem(id: '$id', title: '$id');
            }(),
            onChanged: (item) => setLocal(() => draft['org_unit_id'] = item == null ? null : int.tryParse(item.id)),
            onSearch: (q) async {
              final needle = q.trim().toLowerCase();
              final filtered = needle.isEmpty
                  ? _units
                  : _units.where((u) => '${u['title'] ?? ''} ${u['code'] ?? ''}'.toLowerCase().contains(needle)).toList();
              return [
                for (final u in filtered)
                  if (oaId(u['id']) != null)
                    OaSearchItem(id: '${oaId(u['id'])}', title: '${u['title'] ?? u['code']}', subtitle: '${u['code'] ?? ''}'),
              ];
            },
          ),
          SwitchListTile(
            title: Text(loc.oaRegistry),
            value: draft['is_secretariat'] == true,
            onChanged: (v) => setLocal(() => draft['is_secretariat'] = v),
          ),
          SwitchListTile(
            title: Text(loc.oaSubtree),
            value: draft['can_view_subtree'] == true,
            onChanged: (v) => setLocal(() => draft['can_view_subtree'] = v),
          ),
        ];
      },
      onSave: (p) async {
        final id = oaId(existing?['id']);
        if (id == null) {
          await _svc.createPosition(businessId: widget.businessId, payload: p);
        } else {
          await _svc.updatePosition(businessId: widget.businessId, positionId: id, payload: p);
        }
      },
    );
  }

  int? _userIdOf(Map row) => oaId(row['user_id'] ?? row['id']);

  String _userLabel(Map row) {
    final name = (row['user_name'] ?? row['name'] ?? '').toString();
    final email = (row['user_email'] ?? row['email'] ?? '').toString();
    if (name.isNotEmpty) return name;
    return email;
  }

  Future<void> _assignHolder() async {
    final t = AppLocalizations.of(context);
    int? positionId;
    int? userId;
    String? errorText;
    var saving = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(t.oaAssign),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OaPositionPicker(
                  businessId: widget.businessId,
                  label: t.oaPositions,
                  includeInactive: true,
                  onChanged: (v) => setLocal(() {
                    positionId = oaId(v?['id']);
                    errorText = null;
                  }),
                ),
                OaUserSearchableField(
                  label: t.users,
                  users: _users,
                  valueId: userId,
                  idOf: _userIdOf,
                  labelOf: _userLabel,
                  emptyText: t.oaNoSearchResults,
                  hint: t.oaSelectUser,
                  onChanged: (v) => setLocal(() {
                    userId = v;
                    errorText = null;
                  }),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(errorText!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (positionId == null) {
                        setLocal(() => errorText = t.oaSelectPosition);
                        return;
                      }
                      if (userId == null) {
                        setLocal(() => errorText = t.oaSelectUser);
                        return;
                      }
                      setLocal(() {
                        saving = true;
                        errorText = null;
                      });
                      try {
                        await _svc.assignHolder(
                          businessId: widget.businessId,
                          payload: {'position_id': positionId, 'user_id': userId, 'is_primary': true},
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setLocal(() {
                          saving = false;
                          errorText = ErrorExtractor.forContext(e, ctx);
                        });
                      }
                    },
              child: Text(t.oaAssign),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await _load();
  }

  Future<void> _createDelegation() async {
    final t = AppLocalizations.of(context);
    int? positionId;
    int? userId;
    var scope = 'full';
    String? errorText;
    var saving = false;
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
                OaPositionPicker(
                  businessId: widget.businessId,
                  label: t.oaPositions,
                  includeInactive: true,
                  onChanged: (v) => setLocal(() {
                    positionId = oaId(v?['id']);
                    errorText = null;
                  }),
                ),
                OaUserSearchableField(
                  label: t.users,
                  users: _users,
                  valueId: userId,
                  idOf: _userIdOf,
                  labelOf: _userLabel,
                  emptyText: t.oaNoSearchResults,
                  hint: t.oaSelectUser,
                  onChanged: (v) => setLocal(() {
                    userId = v;
                    errorText = null;
                  }),
                ),
                DropdownButtonFormField<String>(
                  initialValue: scope,
                  items: const [
                    DropdownMenuItem(value: 'full', child: Text('full')),
                    DropdownMenuItem(value: 'view', child: Text('view')),
                    DropdownMenuItem(value: 'refer', child: Text('refer')),
                  ],
                  onChanged: (v) => setLocal(() => scope = v ?? 'full'),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(errorText!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (positionId == null) {
                        setLocal(() => errorText = t.oaSelectPosition);
                        return;
                      }
                      if (userId == null) {
                        setLocal(() => errorText = t.oaSelectUser);
                        return;
                      }
                      setLocal(() {
                        saving = true;
                        errorText = null;
                      });
                      try {
                        await _svc.createDelegation(
                          businessId: widget.businessId,
                          payload: {'position_id': positionId, 'delegate_user_id': userId, 'scope': scope},
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setLocal(() {
                          saving = false;
                          errorText = ErrorExtractor.forContext(e, ctx);
                        });
                      }
                    },
              child: Text(t.oaDelegate),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await _load();
  }

  Widget _treePane({
    required String emptyText,
    required VoidCallback onAddRoot,
    required List<Widget> children,
  }) {
    return Column(
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton.icon(
              onPressed: onAddRoot,
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.of(context).add),
            ),
          ),
        ),
        Expanded(
          child: children.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(emptyText, textAlign: TextAlign.center)))
              : ListView(padding: const EdgeInsets.only(bottom: 24), children: children),
        ),
      ],
    );
  }

  Widget _unitNode(Map<String, dynamic> node, {int depth = 0}) {
    final t = AppLocalizations.of(context);
    final children = List<Map<String, dynamic>>.from(node['children'] as List? ?? const []);
    final id = oaId(node['id']);
    return ExpansionTile(
      key: PageStorageKey('unit-$id'),
      initiallyExpanded: depth == 0,
      childrenPadding: const EdgeInsetsDirectional.only(start: 12),
      leading: const Icon(Icons.account_tree_outlined),
      title: Text('${node['title'] ?? node['code']}'),
      subtitle: Text('${node['code'] ?? ''}'),
      children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, bottom: 8),
            child: Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: id == null ? null : () => _editUnit(parentId: id),
                  icon: const Icon(Icons.subdirectory_arrow_right, size: 18),
                  label: Text(t.oaAddChild),
                ),
                TextButton.icon(
                  onPressed: () => _editUnit(existing: node),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(t.edit),
                ),
              ],
            ),
          ),
          for (final child in children) _unitNode(child, depth: depth + 1),
        ],
    );
  }

  Widget _positionUnitNode(Map<String, dynamic> node, {int depth = 0}) {
    final t = AppLocalizations.of(context);
    final unitId = oaId(node['id']);
    final childUnits = List<Map<String, dynamic>>.from(node['children'] as List? ?? const []);
    final positions = _positions.where((p) => oaId(p['org_unit_id']) == unitId).toList();
    return ExpansionTile(
      key: PageStorageKey('pos-unit-$unitId'),
      initiallyExpanded: depth == 0,
      childrenPadding: const EdgeInsetsDirectional.only(start: 12),
      leading: const Icon(Icons.apartment_outlined),
      title: Text('${node['title'] ?? node['code']}'),
      subtitle: Text('${positions.length} · ${node['code'] ?? ''}'),
      children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, bottom: 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: unitId == null ? null : () => _editPosition(unitId: unitId),
                icon: const Icon(Icons.badge_outlined, size: 18),
                label: Text(t.oaAddPosition),
              ),
            ),
          ),
          for (final p in positions)
            ListTile(
              leading: Icon(p['is_secretariat'] == true ? Icons.verified_outlined : Icons.badge_outlined),
              title: Text('${p['title'] ?? p['code']}'),
              subtitle: Text(
                [
                  p['code'] ?? '',
                  if (p['is_secretariat'] == true) t.oaRegistry,
                ].where((s) => s.toString().isNotEmpty).join(' · '),
              ),
              onTap: () => _editPosition(existing: p),
            ),
          for (final child in childUnits) _positionUnitNode(child, depth: depth + 1),
        ],
    );
  }

  Widget _flatList(
    List<Map<String, dynamic>> rows, {
    required String Function(Map<String, dynamic>) title,
    required VoidCallback onAdd,
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
                trailing: trailing?.call(row),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final forest = _unitForest();
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
                _treePane(
                  emptyText: t.oaEmptyUnits,
                  onAddRoot: () => _editUnit(),
                  children: [for (final node in forest) _unitNode(node)],
                ),
                _treePane(
                  emptyText: t.oaEmptyPositions,
                  onAddRoot: _units.isEmpty ? () => _editUnit() : () => _editPosition(),
                  children: [for (final node in forest) _positionUnitNode(node)],
                ),
                _flatList(
                  _holders,
                  title: (r) => '${r['user_name'] ?? r['user_id']} · ${r['position_title'] ?? r['position_id']}',
                  onAdd: _assignHolder,
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
                _flatList(
                  _delegations,
                  title: (r) => '${r['delegate_name'] ?? r['delegate_user_id']} · ${r['position_title'] ?? ''} · ${r['scope']}',
                  onAdd: _createDelegation,
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
}
