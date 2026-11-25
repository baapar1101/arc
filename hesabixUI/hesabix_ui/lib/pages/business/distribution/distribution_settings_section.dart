import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/distribution_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/invoice/warehouse_combobox_widget.dart';

class DistributionSettingsSection extends StatelessWidget {
  final AppLocalizations t;
  final int businessId;
  final DistributionService service;
  final Map<String, dynamic> settings;
  final List<dynamic> checklistTemplate;
  final TextEditingController memapsKeyController;
  final Future<void> Function() onSaved;

  const DistributionSettingsSection({
    super.key,
    required this.t,
    required this.businessId,
    required this.service,
    required this.settings,
    required this.checklistTemplate,
    required this.memapsKeyController,
    required this.onSaved,
  });

  Future<void> _persist(BuildContext context, Map<String, dynamic> patch) async {
    try {
      await service.updateDistributionSettings(
        businessId: businessId,
        payload: <String, dynamic>{
          'shared_routing_catalog': settings['shared_routing_catalog'] == true,
          'require_visit_in_daily_plan': settings['require_visit_in_daily_plan'] == true,
          ...patch,
        },
      );
      if (!context.mounted) return;
      SnackBarHelper.showSuccess(context, message: t.distributionSettingsSaved);
      await onSaved();
    } catch (e) {
      if (context.mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = settings;
    final mapSource = (ds['map_tile_source'] ?? 'osm').toString() == 'memaps' ? 'memaps' : 'osm';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(t.distributionMapSectionTitle, style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.distributionMapTileSource, style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 4),
                Text(
                  t.distributionMapTileSourceHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.distributionMapTileSourceOsm),
                  value: 'osm',
                  groupValue: mapSource,
                  onChanged: (v) {
                    if (v != null) _persist(context, {'map_tile_source': v});
                  },
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.distributionMapTileSourceMemaps),
                  value: 'memaps',
                  groupValue: mapSource,
                  onChanged: (v) {
                    if (v != null) _persist(context, {'map_tile_source': v});
                  },
                ),
              ],
            ),
          ),
          if (mapSource == 'memaps')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: memapsKeyController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: t.distributionMemapsApiKey,
                  helperText: t.distributionMemapsApiKeyHint,
                  helperMaxLines: 4,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: t.save,
                    icon: const Icon(Icons.save_outlined),
                    onPressed: () => _persist(context, {'memaps_api_key': memapsKeyController.text.trim()}),
                  ),
                ),
                onSubmitted: (v) => _persist(context, {'memaps_api_key': v.trim()}),
              ),
            ),
          SwitchListTile(
            title: Text(t.distributionShareLiveLocation),
            subtitle: Text(t.distributionShareLiveLocationHint),
            value: ds['share_live_location'] == true,
            onChanged: (v) => _persist(context, {'share_live_location': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionRequireLocationConsent),
            subtitle: Text(t.distributionRequireLocationConsentHint),
            value: ds['require_location_consent'] != false,
            onChanged: (v) => _persist(context, {'require_location_consent': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionExclusiveAssignments),
            subtitle: Text(t.distributionExclusiveAssignmentsHint),
            value: ds['exclusive_assignments'] != false,
            onChanged: (v) => _persist(context, {'exclusive_assignments': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionExclusiveTerritories),
            subtitle: Text(t.distributionExclusiveTerritoriesHint),
            value: ds['exclusive_territories'] == true,
            onChanged: (v) => _persist(context, {'exclusive_territories': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionExclusiveCustomerOwnership),
            subtitle: Text(t.distributionExclusiveCustomerOwnershipHint),
            value: ds['exclusive_customer_ownership'] != false,
            onChanged: (v) => _persist(context, {'exclusive_customer_ownership': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionLockPublishedPlans),
            subtitle: Text(t.distributionLockPublishedPlansHint),
            value: ds['lock_published_plans'] == true,
            onChanged: (v) => _persist(context, {'lock_published_plans': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionRequirePublishedPlan),
            subtitle: Text(t.distributionRequirePublishedPlanHint),
            value: ds['require_published_plan'] == true,
            onChanged: (v) => _persist(context, {'require_published_plan': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionSharedRoutingCatalog),
            subtitle: Text(t.distributionSharedRoutingCatalogHint),
            value: ds['shared_routing_catalog'] == true,
            onChanged: (v) => _persist(context, {'shared_routing_catalog': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionRequireVisitInDailyPlan),
            subtitle: Text(t.distributionRequireVisitInDailyPlanHint),
            value: ds['require_visit_in_daily_plan'] == true,
            onChanged: (v) => _persist(context, {'require_visit_in_daily_plan': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionEnableVanSales),
            value: ds['enable_van_sales'] == true,
            onChanged: (v) => _persist(context, {'enable_van_sales': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionEnablePresell),
            subtitle: Text(t.distributionEnablePresellHint),
            value: ds['enable_presell'] == true,
            onChanged: (v) => _persist(context, {'enable_presell': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionEnablePromotions),
            value: ds['enable_promotions'] == true,
            onChanged: (v) => _persist(context, {'enable_promotions': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionEnableSuggestedOrder),
            value: ds['enable_suggested_order'] != false,
            onChanged: (v) => _persist(context, {'enable_suggested_order': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionCarryOver),
            value: ds['carry_over_missed_visits'] != false,
            onChanged: (v) => _persist(context, {'carry_over_missed_visits': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionRequirePodSignature),
            value: ds['require_pod_signature'] == true,
            onChanged: (v) => _persist(context, {'require_pod_signature': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionRequirePodPhoto),
            value: ds['require_pod_photo'] == true,
            onChanged: (v) => _persist(context, {'require_pod_photo': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionAutoPromo),
            value: ds['auto_apply_promotions'] != false,
            onChanged: (v) => _persist(context, {'auto_apply_promotions': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionPerfectStore),
            value: ds['enable_perfect_store'] != false,
            onChanged: (v) => _persist(context, {'enable_perfect_store': v}),
          ),
          DropdownButtonFormField<String>(
            value: (ds['nav_provider'] ?? 'neshan').toString(),
            decoration: InputDecoration(
              labelText: t.distributionNavProvider,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(value: 'neshan', child: Text(t.distributionNavNeshan)),
              DropdownMenuItem(value: 'google', child: Text(t.distributionNavGoogle)),
              DropdownMenuItem(value: 'waze', child: Text(t.distributionNavWaze)),
            ],
            onChanged: (v) {
              if (v != null) _persist(context, {'nav_provider': v});
            },
          ),
          ListTile(
            title: Text(t.distributionNearExpiryDays),
            subtitle: Text('${ds['near_expiry_days'] ?? 14}'),
            trailing: SizedBox(
              width: 72,
              child: TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                controller: TextEditingController(text: '${ds['near_expiry_days'] ?? 14}'),
                onSubmitted: (v) {
                  final n = int.tryParse(v.trim());
                  if (n != null && n >= 1 && n <= 90) _persist(context, {'near_expiry_days': n});
                },
              ),
            ),
          ),
          ListTile(
            title: Text(t.distributionVisitorMaxDiscount),
            subtitle: Text('${ds['visitor_max_discount_percent'] ?? 0} %'),
            trailing: SizedBox(
              width: 72,
              child: TextField(
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                controller: TextEditingController(text: '${ds['visitor_max_discount_percent'] ?? 0}'),
                onSubmitted: (v) {
                  final n = double.tryParse(v.trim().replaceAll(',', '.'));
                  if (n != null && n >= 0 && n <= 100) _persist(context, {'visitor_max_discount_percent': n});
                },
              ),
            ),
          ),
          SwitchListTile(
            title: Text(t.distributionRequireGeofence),
            subtitle: Text(t.distributionGeofenceRadius),
            value: ds['require_geofence'] == true,
            onChanged: (v) => _persist(context, {'require_geofence': v}),
          ),
          ListTile(
            title: Text(t.distributionGeofenceRadius),
            subtitle: Text('${ds['geofence_radius_meters'] ?? 0} m'),
            trailing: SizedBox(
              width: 72,
              child: TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                controller: TextEditingController(text: '${ds['geofence_radius_meters'] ?? 200}'),
                onSubmitted: (v) {
                  final n = int.tryParse(v.trim());
                  if (n != null && n >= 0) _persist(context, {'geofence_radius_meters': n});
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: WarehouseComboboxWidget(
              businessId: businessId,
              selectedWarehouseId: ds['default_source_warehouse_id'] is int
                  ? ds['default_source_warehouse_id'] as int
                  : int.tryParse('${ds['default_source_warehouse_id'] ?? ''}'),
              label: t.distributionDefaultWarehouse,
              onChanged: (id) => _persist(context, {'default_source_warehouse_id': id}),
            ),
          ),
          ListTile(
            title: Text(t.distributionChecklistTitle),
            subtitle: Text(
              checklistTemplate.isEmpty
                  ? t.distributionChecklistAddItem
                  : '${checklistTemplate.length} ${t.distributionChecklistAddItem}',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () async {
                final ctl = TextEditingController();
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    title: Text(t.distributionChecklistAddItem),
                    content: TextField(
                      controller: ctl,
                      decoration: InputDecoration(
                        labelText: t.distributionChecklistTitle,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(t.cancel)),
                      FilledButton(onPressed: () => Navigator.pop(dctx, true), child: Text(t.save)),
                    ],
                  ),
                );
                if (ok != true || ctl.text.trim().isEmpty) return;
                final next = List<dynamic>.from(checklistTemplate)
                  ..add({'id': 'c_${DateTime.now().millisecondsSinceEpoch}', 'label': ctl.text.trim(), 'required': false});
                if (!context.mounted) return;
                await _persist(context, {'visit_checklist_template': next});
              },
            ),
          ),
        ],
      ),
    );
  }
}
