import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/business_user_model.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/services/business_user_service.dart';
import 'package:hesabix_ui/services/distribution_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/warehouse_combobox_widget.dart';

Future<bool> showDistributionSetupWizard({
  required BuildContext context,
  required int businessId,
  required DistributionService service,
}) async {
  final ok = await showGlassModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _SetupWizard(
      businessId: businessId,
      service: service,
    ),
  );
  return ok == true;
}

class _SetupWizard extends StatefulWidget {
  const _SetupWizard({required this.businessId, required this.service});
  final int businessId;
  final DistributionService service;

  @override
  State<_SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<_SetupWizard> {
  var _step = 0;
  var _mode = 'both';
  int? _warehouseId;
  final _territoryCtl = TextEditingController(text: 'منطقه ۱');
  final _routeCtl = TextEditingController(text: 'مسیر ۱');
  final _selected = <Person>[];
  int? _visitorId;
  List<BusinessUser> _users = const [];
  var _saving = false;
  String _cls = 'A';

  @override
  void initState() {
    super.initState();
    BusinessUserService(ApiClient()).getBusinessUsers(widget.businessId).then((r) {
      if (mounted) setState(() => _users = r.users);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _territoryCtl.dispose();
    _routeCtl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      await widget.service.runSetupWizard(
        businessId: widget.businessId,
        payload: {
          'enable_van_sales': _mode == 'van' || _mode == 'both',
          'enable_presell': _mode == 'presell' || _mode == 'both',
          'enable_promotions': true,
          if (_warehouseId != null) 'default_source_warehouse_id': _warehouseId,
          'territory_name': _territoryCtl.text.trim(),
          'route_name': _routeCtl.text.trim(),
          'person_ids': _selected.map((p) => p.id).whereType<int>().toList(),
          'visitor_user_id': _visitorId,
          'customer_class': _cls,
          'frequency': _cls == 'C' ? 'monthly' : (_cls == 'B' ? 'biweekly' : 'weekly'),
          'nav_provider': 'neshan',
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget body;
    switch (_step) {
      case 0:
        body = Column(
          children: [
            RadioListTile<String>(
              title: Text(t.distributionModeVan),
              value: 'van',
              groupValue: _mode,
              onChanged: (v) => setState(() => _mode = v ?? _mode),
            ),
            RadioListTile<String>(
              title: Text(t.distributionModePresell),
              value: 'presell',
              groupValue: _mode,
              onChanged: (v) => setState(() => _mode = v ?? _mode),
            ),
            RadioListTile<String>(
              title: Text(t.distributionModeBoth),
              value: 'both',
              groupValue: _mode,
              onChanged: (v) => setState(() => _mode = v ?? _mode),
            ),
          ],
        );
        break;
      case 1:
        body = WarehouseComboboxWidget(
          businessId: widget.businessId,
          selectedWarehouseId: _warehouseId,
          label: t.distributionSelectWarehouse,
          selectDefaultWhenUnset: true,
          onChanged: (id) => setState(() => _warehouseId = id),
        );
        break;
      case 2:
        body = Column(
          children: [
            TextField(
              controller: _territoryCtl,
              decoration: InputDecoration(labelText: t.distributionTerritoryName, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _routeCtl,
              decoration: InputDecoration(labelText: t.distributionSelectRoute, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _cls,
              decoration: InputDecoration(labelText: t.distributionCustomerClass, border: const OutlineInputBorder()),
              items: [
                DropdownMenuItem(value: 'A', child: Text(t.distributionClassA)),
                DropdownMenuItem(value: 'B', child: Text(t.distributionClassB)),
                DropdownMenuItem(value: 'C', child: Text(t.distributionClassC)),
              ],
              onChanged: (v) => setState(() => _cls = v ?? 'A'),
            ),
          ],
        );
        break;
      case 3:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PersonComboboxWidget(
              businessId: widget.businessId,
              label: t.distributionWizardStepCustomers,
              onChanged: (p) {
                if (p == null || p.id == null) return;
                if (_selected.any((e) => e.id == p.id)) return;
                setState(() => _selected.add(p));
              },
            ),
            const SizedBox(height: 8),
            ..._selected.map(
              (p) => ListTile(
                dense: true,
                title: Text(p.aliasName),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _selected.remove(p)),
                ),
              ),
            ),
          ],
        );
        break;
      default:
        body = DropdownButtonFormField<int>(
          value: _visitorId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: t.distributionSelectVisitor,
            border: const OutlineInputBorder(),
          ),
          items: _users
              .map((u) => DropdownMenuItem(value: u.userId, child: Text(u.userName.isNotEmpty ? u.userName : '${u.userId}')))
              .toList(),
          onChanged: (v) => setState(() => _visitorId = v),
        );
    }

    final titles = [
      t.distributionWizardStepMode,
      t.distributionWizardStepWarehouse,
      t.distributionWizardStepRoute,
      t.distributionWizardStepCustomers,
      t.distributionWizardStepVisitor,
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.distributionWizardTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(t.distributionWizardHint, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Text(titles[_step], style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
            child: SingleChildScrollView(child: body),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (_step > 0)
                TextButton(onPressed: _saving ? null : () => setState(() => _step--), child: Text(t.distributionVisitWizardBack)),
              const Spacer(),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () {
                        if (_step < 4) {
                          setState(() => _step++);
                        } else {
                          _finish();
                        }
                      },
                child: Text(_step < 4 ? t.distributionVisitWizardNext : t.distributionWizardFinish),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
