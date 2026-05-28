import 'dart:async';

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import 'package:latlong2/latlong.dart';

import '../../services/distribution_service.dart';
import '../../services/memaps_places_service.dart';
import '../../utils/distribution_location_helper.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'distribution_memaps_map.dart';

/// ثبت/ویرایش مختصات مشتری با جستجوی می‌مپس و انتخاب روی نقشه.
Future<bool?> showDistributionPersonLocationSheet({
  required BuildContext context,
  required int businessId,
  required int personId,
  required String personName,
  required DistributionService distributionService,
  double? initialLat,
  double? initialLng,
}) async {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _DistributionPersonLocationSheet(
      businessId: businessId,
      personId: personId,
      personName: personName,
      distributionService: distributionService,
      initialLat: initialLat,
      initialLng: initialLng,
    ),
  );
}

class _DistributionPersonLocationSheet extends StatefulWidget {
  final int businessId;
  final int personId;
  final String personName;
  final DistributionService distributionService;
  final double? initialLat;
  final double? initialLng;

  const _DistributionPersonLocationSheet({
    required this.businessId,
    required this.personId,
    required this.personName,
    required this.distributionService,
    this.initialLat,
    this.initialLng,
  });

  @override
  State<_DistributionPersonLocationSheet> createState() => _DistributionPersonLocationSheetState();
}

class _DistributionPersonLocationSheetState extends State<_DistributionPersonLocationSheet> {
  final MemapsPlacesService _places = MemapsPlacesService();
  final TextEditingController _searchCtl = TextEditingController();
  Timer? _debounce;
  List<MemapsPlaceResult> _suggestions = [];
  bool _searching = false;
  bool _saving = false;
  LatLng? _picked;

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLng != null) {
      _picked = LatLng(widget.initialLat!, widget.initialLng!);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final near = _picked;
        final list = await _places.searchPlaces(
          query: value,
          nearLat: near?.latitude,
          nearLng: near?.longitude,
          limit: 8,
        );
        if (mounted) setState(() => _suggestions = list);
      } catch (_) {
        if (mounted) setState(() => _suggestions = []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _useGps() async {
    final t = AppLocalizations.of(context);
    SnackBarHelper.show(context, message: t.distributionLocationCapturing);
    final loc = await readDistributionVisitLocation();
    if (!mounted) return;
    if (loc.latitude != null && loc.longitude != null) {
      setState(() => _picked = LatLng(loc.latitude!, loc.longitude!));
    } else {
      SnackBarHelper.showError(context, message: t.distributionLocationSkipped);
    }
  }

  Future<void> _save() async {
    final p = _picked;
    if (p == null) return;
    final t = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await widget.distributionService.setPersonLocation(
        businessId: widget.businessId,
        personId: widget.personId,
        latitude: p.latitude,
        longitude: p.longitude,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: t.distributionLocationSaved);
      Navigator.pop(context, true);
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
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.distributionSetPersonLocation,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(widget.personName, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtl,
              decoration: InputDecoration(
                labelText: t.distributionSearchPlace,
                border: const OutlineInputBorder(),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : const Icon(Icons.search),
              ),
              onChanged: _onSearchChanged,
            ),
            if (_suggestions.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(top: 4),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final s = _suggestions[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(s.name),
                      subtitle: Text([s.city, s.category].where((x) => x != null && x.isNotEmpty).join(' · ')),
                      onTap: () {
                        setState(() {
                          _picked = LatLng(s.lat, s.lng);
                          _suggestions = [];
                          _searchCtl.text = s.name;
                        });
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Text(t.distributionTapMapToSetLocation, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            DistributionMemapsMap(
              height: 240,
              markers: const [],
              selectedPoint: _picked,
              pickMode: true,
              onPick: (p) => setState(() => _picked = p),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _useGps,
                    icon: const Icon(Icons.my_location),
                    label: Text(t.distributionUseCurrentLocation),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving || _picked == null ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(t.save),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
