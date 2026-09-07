import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/distribution_service.dart';
import 'package:hesabix_ui/utils/distribution_location_helper.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/invoice/price_list_combobox_widget.dart';

Future<bool> showDistributionNewOutletSheet({
  required BuildContext context,
  required int businessId,
  required DistributionService service,
  int? routeId,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _NewOutletSheet(businessId: businessId, service: service, routeId: routeId),
  );
  return ok == true;
}

class _NewOutletSheet extends StatefulWidget {
  const _NewOutletSheet({required this.businessId, required this.service, this.routeId});
  final int businessId;
  final DistributionService service;
  final int? routeId;

  @override
  State<_NewOutletSheet> createState() => _NewOutletSheetState();
}

class _NewOutletSheetState extends State<_NewOutletSheet> {
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _address = TextEditingController();
  String _cls = 'B';
  String _outlet = 'grocery';
  int? _priceListId;
  double? _lat;
  double? _lng;
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _pinHere() async {
    final loc = await readDistributionVisitLocation();
    if (!mounted) return;
    setState(() {
      _lat = loc.latitude;
      _lng = loc.longitude;
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) return;
    setState(() => _saving = true);
    try {
      await widget.service.onboardOutlet(
        businessId: widget.businessId,
        payload: {
          'name': _name.text.trim(),
          if (_mobile.text.trim().isNotEmpty) 'mobile': _mobile.text.trim(),
          if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
          'customer_class': _cls,
          'outlet_type': _outlet,
          if (_priceListId != null) 'price_list_id': _priceListId,
          if (_lat != null) 'latitude': _lat,
          if (_lng != null) 'longitude': _lng,
          if (widget.routeId != null) 'route_id': widget.routeId,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.distributionNewOutlet, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(t.distributionNewOutletHint),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: t.distributionOutletName, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _mobile,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: t.distributionOutletPhone, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _address,
              decoration: InputDecoration(labelText: t.address, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _cls,
              decoration: InputDecoration(labelText: t.distributionCustomerClass, border: const OutlineInputBorder()),
              items: [
                DropdownMenuItem(value: 'A', child: Text(t.distributionClassA)),
                DropdownMenuItem(value: 'B', child: Text(t.distributionClassB)),
                DropdownMenuItem(value: 'C', child: Text(t.distributionClassC)),
              ],
              onChanged: (v) => setState(() => _cls = v ?? 'B'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _outlet,
              decoration: InputDecoration(labelText: t.distributionOutletType, border: const OutlineInputBorder()),
              items: [
                DropdownMenuItem(value: 'grocery', child: Text(t.distributionOutletGrocery)),
                DropdownMenuItem(value: 'supermarket', child: Text(t.distributionOutletSupermarket)),
                DropdownMenuItem(value: 'horeca', child: Text(t.distributionOutletHoreca)),
                DropdownMenuItem(value: 'kiosk', child: Text(t.distributionOutletKiosk)),
                DropdownMenuItem(value: 'wholesale', child: Text(t.distributionOutletWholesale)),
                DropdownMenuItem(value: 'other', child: Text(t.distributionOutletOther)),
              ],
              onChanged: (v) => setState(() => _outlet = v ?? 'grocery'),
            ),
            const SizedBox(height: 10),
            PriceListComboboxWidget(
              businessId: widget.businessId,
              selectedPriceListId: _priceListId,
              label: t.distributionPriceList,
              hintText: t.distributionPriceList,
              onChanged: (p) => setState(() => _priceListId = int.tryParse('${p?['id'] ?? ''}')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pinHere,
              icon: const Icon(Icons.my_location),
              label: Text(_lat == null ? t.distributionNavigate : '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(t.save),
            ),
          ],
        ),
      ),
    );
  }
}
