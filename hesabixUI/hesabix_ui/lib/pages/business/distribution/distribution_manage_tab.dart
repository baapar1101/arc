import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart' as Hd;
import '../../../core/distribution_map_tiles.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/person_model.dart';
import '../../../models/business_user_model.dart';
import '../../../services/business_user_service.dart';
import '../../../services/distribution_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/distribution/distribution_assortment_sheet.dart';
import '../../../widgets/distribution/distribution_field_helpers.dart';
import '../../../widgets/distribution/distribution_form_helpers.dart';
import '../../../widgets/distribution/distribution_person_location_sheet.dart';
import '../../../widgets/distribution/distribution_targets_section.dart';
import '../../../widgets/invoice/person_combobox_widget.dart';
import '../../../widgets/invoice/price_list_combobox_widget.dart';
import '../../../widgets/jalali_date_picker.dart';
import 'distribution_settings_section.dart';

class DistributionManageTab extends StatefulWidget {
  final int businessId;
  final DistributionService service;
  final CalendarController calendarController;
  final Map<String, dynamic>? settings;
  final List<dynamic> checklistTemplate;
  final TextEditingController memapsKeyController;
  final DistributionMapTileConfig mapTiles;
  final Future<void> Function() onSettingsSaved;

  const DistributionManageTab({
    super.key,
    required this.businessId,
    required this.service,
    required this.calendarController,
    required this.settings,
    required this.checklistTemplate,
    required this.memapsKeyController,
    required this.mapTiles,
    required this.onSettingsSaved,
  });

  @override
  State<DistributionManageTab> createState() => DistributionManageTabState();
}

class DistributionManageTabState extends State<DistributionManageTab> {
  List<dynamic> _routes = [];
  List<dynamic> _territories = [];
  final Map<int, List<dynamic>> _stopsByRoute = {};
  bool _loadingRoutes = false;

  bool get _jalali => widget.calendarController.isJalali;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => reload());
  }

  Future<void> reload() async {
    if (!mounted) return;
    setState(() => _loadingRoutes = true);
    try {
      final t = await widget.service.listTerritories(businessId: widget.businessId);
      final r = await widget.service.listRoutes(businessId: widget.businessId);
      if (mounted) {
        setState(() {
          _territories = t;
          _routes = r;
          _stopsByRoute.clear();
        });
      }
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loadingRoutes = false);
    }
  }

  Future<void> _loadStops(int routeId) async {
    try {
      final s = await widget.service.listRouteStops(businessId: widget.businessId, routeId: routeId);
      if (mounted) setState(() => _stopsByRoute[routeId] = s);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _confirmDeleteRoute(AppLocalizations t, int routeId) async {
    final ok = await confirmDistributionDelete(
      context: context,
      title: t.distributionDeleteRoute,
      message: t.distributionDeleteRouteConfirm,
      confirmLabel: t.distributionDeleteRoute,
    );
    if (!ok) return;
    try {
      await widget.service.deleteRoute(businessId: widget.businessId, routeId: routeId);
      await reload();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _confirmDeleteTerritory(AppLocalizations t, Map<String, dynamic> row) async {
    final id = int.tryParse('${row['id']}');
    if (id == null) return;
    final ok = await confirmDistributionDelete(
      context: context,
      title: t.distributionDeleteTerritory,
      message: t.distributionDeleteTerritoryConfirm,
    );
    if (!ok) return;
    try {
      await widget.service.deleteTerritory(businessId: widget.businessId, territoryId: id);
      await reload();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _showTerritoryDialog(AppLocalizations t, {Map<String, dynamic>? existing}) async {
    final nameCtl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final editing = existing != null;
    int? parentId = int.tryParse('${existing?['parent_id'] ?? ''}');
    int? supervisorId = int.tryParse('${existing?['supervisor_user_id'] ?? ''}');
    List<BusinessUser> team = const [];
    try {
      team = (await BusinessUserService(ApiClient()).getBusinessUsers(widget.businessId)).users;
    } catch (_) {}
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(editing ? t.distributionTerritoryEdit : t.distributionTerritoryCreate),
          content: distributionFormColumn(
            children: [
              TextField(
                controller: nameCtl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: t.distributionTerritoryName,
                  border: const OutlineInputBorder(),
                ),
              ),
              DropdownButtonFormField<int?>(
                value: parentId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t.distributionTerritoryParent,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('—')),
                  ..._territories.map((raw) {
                    final m = Map<String, dynamic>.from(raw as Map);
                    final id = int.tryParse('${m['id']}');
                    if (editing && id == int.tryParse('${existing['id']}')) {
                      return null;
                    }
                    return DropdownMenuItem<int?>(
                      value: id,
                      child: Text(distributionEntityLabel(m)),
                    );
                  }).whereType<DropdownMenuItem<int?>>(),
                ],
                onChanged: (v) => setD(() => parentId = v),
              ),
              DropdownButtonFormField<int?>(
                value: supervisorId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t.distributionTerritorySupervisor,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('—')),
                  ...team.map(
                    (u) => DropdownMenuItem<int?>(
                      value: u.userId,
                      child: Text(u.userName.isNotEmpty ? u.userName : '${u.userId}'),
                    ),
                  ),
                ],
                onChanged: (v) => setD(() => supervisorId = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
            FilledButton(
              onPressed: () async {
                final name = nameCtl.text.trim();
                if (name.isEmpty) return;
                try {
                  final payload = <String, dynamic>{
                    'name': name,
                    'parent_id': parentId,
                    'supervisor_user_id': supervisorId,
                  };
                  if (editing) {
                    await widget.service.updateTerritory(
                      businessId: widget.businessId,
                      territoryId: int.parse('${existing['id']}'),
                      payload: payload,
                    );
                  } else {
                    await widget.service.createTerritory(
                      businessId: widget.businessId,
                      payload: {
                        'code': nextDistributionCode('T', _territories),
                        ...payload,
                      },
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await reload();
                } catch (e) {
                  if (mounted) SnackBarHelper.showError(this.context, message: ErrorExtractor.forContext(e, this.context));
                }
              },
              child: Text(t.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRouteDialog(AppLocalizations t, {Map<String, dynamic>? existing}) async {
    final nameCtl = TextEditingController(text: existing?['name']?.toString() ?? '');
    int? territoryId = int.tryParse('${existing?['territory_id'] ?? ''}');
    final editing = existing != null;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(editing ? t.distributionRouteEdit : t.distributionRouteCreate),
          content: distributionFormColumn(
            children: [
              TextField(
                controller: nameCtl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: t.distributionRouteName,
                  border: const OutlineInputBorder(),
                ),
              ),
              DropdownButtonFormField<int?>(
                value: territoryId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t.distributionTerritoryName,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('—')),
                  ..._territories.map<DropdownMenuItem<int?>>((e) {
                    final m = Map<String, dynamic>.from(e as Map);
                    return DropdownMenuItem<int?>(
                      value: m['id'] as int?,
                      child: Text(distributionEntityLabel(m)),
                    );
                  }),
                ],
                onChanged: (v) => setD(() => territoryId = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
            FilledButton(
              onPressed: () async {
                final name = nameCtl.text.trim();
                if (name.isEmpty) return;
                try {
                  if (editing) {
                    await widget.service.updateRoute(
                      businessId: widget.businessId,
                      routeId: int.parse('${existing['id']}'),
                      payload: <String, dynamic>{
                        'name': name,
                        'territory_id': territoryId,
                      },
                    );
                  } else {
                    await widget.service.createRoute(
                      businessId: widget.businessId,
                      payload: <String, dynamic>{
                        'code': nextDistributionCode('R', _routes),
                        'name': name,
                        if (territoryId != null) 'territory_id': territoryId,
                      },
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await reload();
                } catch (e) {
                  if (mounted) SnackBarHelper.showError(this.context, message: ErrorExtractor.forContext(e, this.context));
                }
              },
              child: Text(t.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showStopDialog(AppLocalizations t, int routeId, {Map<String, dynamic>? existing}) async {
    Person? person;
    final pid = int.tryParse('${existing?['person_id'] ?? ''}');
    if (pid != null) {
      person = distributionPersonStub(
        businessId: widget.businessId,
        id: pid,
        name: existing?['person_name']?.toString() ?? '$pid',
      );
    }
    final stops = _stopsByRoute[routeId] ?? [];
    final defaultSort = existing != null ? '${existing['sort_order'] ?? 0}' : '${stops.length + 1}';
    final sortCtl = TextEditingController(text: defaultSort);
    int? weekday = existing?['weekday'] is int ? existing!['weekday'] as int : int.tryParse('${existing?['weekday'] ?? ''}');
    var frequency = (existing?['frequency'] ?? 'weekly').toString();
    var cls = existing?['customer_class']?.toString();
    final offsetCtl = TextEditingController(text: '${existing?['cycle_offset'] ?? 0}');
    int? priceListId = int.tryParse('${existing?['price_list_id'] ?? ''}');
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(existing == null ? t.distributionAddStop : t.distributionStopEdit),
          content: distributionFormColumn(
            children: [
              PersonComboboxWidget(
                businessId: widget.businessId,
                selectedPerson: person,
                label: t.distributionSelectPerson,
                onChanged: (p) => setD(() => person = p),
              ),
              DropdownButtonFormField<int?>(
                value: weekday,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t.distributionWeekdayLabel,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(t.distributionWeekdayAny)),
                  ...List.generate(
                    7,
                    (i) => DropdownMenuItem<int?>(value: i, child: Text(distributionWeekdayLabel(t, i))),
                  ),
                ],
                onChanged: (v) => setD(() => weekday = v),
              ),
              DropdownButtonFormField<String>(
                value: frequency,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t.distributionVisitFrequency,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: 'weekly', child: Text(t.distributionFrequencyWeekly)),
                  DropdownMenuItem(value: 'biweekly', child: Text(t.distributionFrequencyBiweekly)),
                  DropdownMenuItem(value: 'monthly', child: Text(t.distributionFrequencyMonthly)),
                ],
                onChanged: (v) => setD(() => frequency = v ?? 'weekly'),
              ),
              DropdownButtonFormField<String?>(
                value: cls,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t.distributionCustomerClass,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('—')),
                  DropdownMenuItem(value: 'A', child: Text(t.distributionClassA)),
                  DropdownMenuItem(value: 'B', child: Text(t.distributionClassB)),
                  DropdownMenuItem(value: 'C', child: Text(t.distributionClassC)),
                ],
                onChanged: (v) => setD(() => cls = v),
              ),
              TextField(
                controller: offsetCtl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t.distributionCycleOffset,
                  helperText: t.distributionCycleOffsetHint,
                  helperMaxLines: 3,
                  border: const OutlineInputBorder(),
                ),
              ),
              PriceListComboboxWidget(
                businessId: widget.businessId,
                selectedPriceListId: priceListId,
                label: t.distributionPriceList,
                hintText: t.distributionPriceList,
                onChanged: (p) => setD(() => priceListId = int.tryParse('${p?['id'] ?? ''}')),
              ),
              TextField(
                controller: sortCtl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: t.distributionSortOrder, border: const OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
            FilledButton(
              onPressed: () async {
                if (person == null) return;
                try {
                  await widget.service.upsertStop(
                    businessId: widget.businessId,
                    routeId: routeId,
                    payload: <String, dynamic>{
                      if (existing != null) 'id': existing['id'],
                      'person_id': person!.id,
                      'sort_order': int.tryParse(sortCtl.text.trim()) ?? 0,
                      'weekday': weekday,
                      'frequency': frequency,
                      'cycle_offset': int.tryParse(offsetCtl.text.trim()) ?? 0,
                      if (cls != null) 'customer_class': cls,
                    },
                  );
                  final pidSaved = person!.id;
                  if (pidSaved != null) {
                    await widget.service.upsertCustomerProfile(
                      businessId: widget.businessId,
                      personId: pidSaved,
                      payload: {
                        'visit_frequency': frequency,
                        'cycle_offset': int.tryParse(offsetCtl.text.trim()) ?? 0,
                        if (cls != null) 'customer_class': cls,
                        'price_list_id': priceListId,
                      },
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadStops(routeId);
                } catch (e) {
                  if (mounted) SnackBarHelper.showError(this.context, message: ErrorExtractor.forContext(e, this.context));
                }
              },
              child: Text(t.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAssignmentDialog(AppLocalizations t, int routeId) async {
    DateTime from = DateTime.now();
    DateTime? to;
    int? selectedUserId;
    List<BusinessUser> users = const [];
    try {
      final res = await BusinessUserService(ApiClient()).getBusinessUsers(widget.businessId);
      users = res.users;
    } catch (_) {}
    List<dynamic> existing = const [];
    try {
      existing = await widget.service.listAssignments(businessId: widget.businessId, routeId: routeId);
    } catch (_) {}

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(t.distributionAssignVisitor),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: selectedUserId,
                    decoration: InputDecoration(
                      labelText: t.distributionSelectVisitor,
                      border: const OutlineInputBorder(),
                    ),
                    items: users
                        .map(
                          (u) => DropdownMenuItem<int>(
                            value: u.userId,
                            child: Text(u.userName.isNotEmpty ? u.userName : 'user ${u.userId}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setD(() => selectedUserId = v),
                  ),
                  ListTile(
                    title: Text(Hd.HesabixDateUtils.formatForDisplay(from, _jalali)),
                    subtitle: Text(t.distributionAssignmentFrom),
                    onTap: () async {
                      final d = await showAdaptiveDatePicker(
                        context: context,
                        calendarController: widget.calendarController,
                        initialDate: from,
                      );
                      if (d != null) setD(() => from = d);
                    },
                  ),
                  ListTile(
                    title: Text(to == null ? '∞' : Hd.HesabixDateUtils.formatForDisplay(to!, _jalali)),
                    subtitle: Text(t.distributionAssignmentTo),
                    onTap: () async {
                      final d = await showAdaptiveDatePicker(
                        context: context,
                        calendarController: widget.calendarController,
                        initialDate: to ?? from,
                      );
                      setD(() => to = d);
                    },
                  ),
                  if (existing.isNotEmpty) ...[
                    const Divider(),
                    ...existing.map((raw) {
                      final m = Map<String, dynamic>.from(raw as Map);
                      return ListTile(
                        dense: true,
                        title: Text(m['user_name']?.toString() ?? 'user ${m['user_id']}'),
                        subtitle: Text(
                          '${t.distributionAssignmentFrom}: ${m['valid_from'] ?? '—'} → ${t.distributionAssignmentTo}: ${m['valid_to'] ?? '∞'}',
                        ),
                        trailing: IconButton(
                          tooltip: t.distributionDeleteAssignment,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final aid = int.tryParse('${m['id']}');
                            if (aid == null) return;
                            try {
                              await widget.service.deleteAssignment(
                                businessId: widget.businessId,
                                assignmentId: aid,
                              );
                              existing = await widget.service.listAssignments(
                                businessId: widget.businessId,
                                routeId: routeId,
                              );
                              setD(() {});
                            } catch (e) {
                              if (mounted) {
                                SnackBarHelper.showError(
                                  this.context,
                                  message: ErrorExtractor.forContext(e, this.context),
                                );
                              }
                            }
                          },
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
            FilledButton(
              onPressed: selectedUserId == null
                  ? null
                  : () async {
                      try {
                        await widget.service.createAssignment(
                          businessId: widget.businessId,
                          payload: <String, dynamic>{
                            'route_id': routeId,
                            'user_id': selectedUserId,
                            'valid_from': distributionIsoDate(from),
                            if (to != null) 'valid_to': distributionIsoDate(to!),
                          },
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          SnackBarHelper.showSuccess(this.context, message: t.distributionSettingsSaved);
                        }
                      } catch (e) {
                        if (mounted) {
                          SnackBarHelper.showError(
                            this.context,
                            message: ErrorExtractor.forContext(e, this.context),
                          );
                        }
                      }
                    },
              child: Text(t.save),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(t.distributionTargetsTitle, style: Theme.of(context).textTheme.titleMedium),
        ),
        DistributionTargetsSection(
          businessId: widget.businessId,
          service: widget.service,
          calendarController: widget.calendarController,
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(t.distributionManageSectionRoutes, style: Theme.of(context).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              Text(t.distributionTerritoryName, style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () => _showTerritoryDialog(t),
                icon: const Icon(Icons.add),
                label: Text(t.distributionTerritoryCreate),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () => showDistributionAssortmentSheet(
                  context: context,
                  businessId: widget.businessId,
                  service: widget.service,
                ),
                icon: const Icon(Icons.star_outline),
                label: Text(t.distributionAssortmentsTitle),
              ),
            ],
          ),
        ),
        if (_territories.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(t.distributionNoRoutesYet, style: Theme.of(context).textTheme.bodySmall),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _territories.map((raw) {
                final m = Map<String, dynamic>.from(raw as Map);
                return InputChip(
                  avatar: const Icon(Icons.map_outlined, size: 18),
                  label: Text(distributionEntityLabel(m)),
                  onPressed: () => _showTerritoryDialog(t, existing: m),
                  onDeleted: () => _confirmDeleteTerritory(t, m),
                  deleteIcon: const Icon(Icons.close, size: 18),
                );
              }).toList(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          child: Row(
            children: [
              Text(t.distributionSelectRoute, style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () => _showRouteDialog(t),
                icon: const Icon(Icons.add_road),
                label: Text(t.distributionRouteCreate),
              ),
            ],
          ),
        ),
        if (_loadingRoutes)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          ..._routes.map((raw) {
            final r = Map<String, dynamic>.from(raw as Map);
            final rid = r['id'] as int;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ExpansionTile(
                leading: const Icon(Icons.alt_route),
                title: Text(distributionEntityLabel(r)),
                subtitle: Text('${r['territory_name'] ?? '—'}'),
                onExpansionChanged: (ex) {
                  if (ex) _loadStops(rid);
                },
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Wrap(
                      spacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: () => _showStopDialog(t, rid),
                          icon: const Icon(Icons.add_location_alt),
                          label: Text(t.distributionAddStop),
                        ),
                        TextButton.icon(
                          onPressed: () => _showAssignmentDialog(t, rid),
                          icon: const Icon(Icons.person_add_alt),
                          label: Text(t.distributionAssignVisitor),
                        ),
                        IconButton(
                          tooltip: t.distributionRouteEdit,
                          onPressed: () => _showRouteDialog(t, existing: r),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: t.distributionDeleteRoute,
                          onPressed: () => _confirmDeleteRoute(t, rid),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                  ...(_stopsByRoute[rid] ?? []).map((s) {
                    final m = Map<String, dynamic>.from(s as Map);
                    return ListTile(
                      dense: true,
                      title: Text('${m['person_name'] ?? m['person_id']}'),
                      subtitle: Text(
                        '${t.distributionSortOrder} ${m['sort_order']} · '
                        '${t.distributionWeekdayLabel}: ${distributionWeekdayLabel(t, m['weekday'] as int?)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: t.distributionStopEdit,
                            onPressed: () => _showStopDialog(t, rid, existing: m),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_location_alt_outlined),
                            tooltip: t.distributionSetPersonLocation,
                            onPressed: () async {
                              final personId = int.tryParse('${m['person_id']}');
                              if (personId == null) return;
                              final saved = await showDistributionPersonLocationSheet(
                                context: context,
                                businessId: widget.businessId,
                                personId: personId,
                                personName: m['person_name']?.toString() ?? '$personId',
                                distributionService: widget.service,
                                tileConfig: widget.mapTiles,
                              );
                              if (saved == true) await _loadStops(rid);
                            },
                          ),
                          IconButton(
                            tooltip: t.distributionDeleteStop,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final sid = int.tryParse('${m['id']}');
                              if (sid == null) return;
                              final ok = await confirmDistributionDelete(
                                context: context,
                                title: t.distributionDeleteStop,
                                message: t.distributionDeleteStopConfirm,
                              );
                              if (!ok) return;
                              try {
                                await widget.service.deleteStop(
                                  businessId: widget.businessId,
                                  routeId: rid,
                                  stopId: sid,
                                );
                                await _loadStops(rid);
                                if (mounted) {
                                  SnackBarHelper.showSuccess(
                                    context,
                                    message: t.distributionSettingsSaved,
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  SnackBarHelper.showError(
                                    context,
                                    message: ErrorExtractor.forContext(e, context),
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
        if (widget.settings != null) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(t.distributionManageSectionSettings, style: Theme.of(context).textTheme.titleMedium),
          ),
          DistributionSettingsSection(
            t: t,
            businessId: widget.businessId,
            service: widget.service,
            settings: widget.settings!,
            checklistTemplate: widget.checklistTemplate,
            memapsKeyController: widget.memapsKeyController,
            onSaved: widget.onSettingsSaved,
          ),
        ],
        const SizedBox(height: 48),
      ],
    );
  }
}
