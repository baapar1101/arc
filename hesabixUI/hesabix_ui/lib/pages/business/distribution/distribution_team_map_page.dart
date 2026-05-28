import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/distribution_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart' as Hd;
import '../../../widgets/distribution/distribution_map_marker.dart';
import '../../../widgets/distribution/distribution_memaps_map.dart';
import '../../../widgets/distribution/distribution_person_location_sheet.dart';
import '../../../widgets/jalali_date_picker.dart';

/// نقشهٔ تیم — تایل می‌مپس + لیست ویزیت‌ها.
class DistributionTeamMapPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final bool canManageLocations;

  const DistributionTeamMapPage({
    super.key,
    required this.businessId,
    required this.calendarController,
    this.canManageLocations = false,
  });

  @override
  State<DistributionTeamMapPage> createState() => _DistributionTeamMapPageState();
}

class _DistributionTeamMapPageState extends State<DistributionTeamMapPage> {
  final DistributionService _svc = DistributionService();
  DateTime _day = DateTime.now();
  Map<String, dynamic>? _data;
  bool _loading = false;

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await _svc.getTeamMap(businessId: widget.businessId, planDate: _iso(_day));
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<DistributionMapMarker> _mapMarkers(List<dynamic> rawMarkers) {
    final out = <DistributionMapMarker>[];
    for (final raw in rawMarkers) {
      final m = Map<String, dynamic>.from(raw as Map);
      final lat = m['customer_latitude'] ?? m['visit_latitude'];
      final lng = m['customer_longitude'] ?? m['visit_longitude'];
      if (lat == null || lng == null) continue;
      final la = double.tryParse('$lat');
      final ln = double.tryParse('$lng');
      if (la == null || ln == null) continue;
      out.add(
        DistributionMapMarker(
          lat: la,
          lng: ln,
          label: m['person_name']?.toString() ?? 'user ${m['user_id']}',
          subtitle: m['status']?.toString(),
          color: m['status'] == 'in_progress' ? Colors.orange : Colors.blue,
        ),
      );
    }
    return out;
  }

  Future<void> _openExternalMaps(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _editCustomerLocation(Map<String, dynamic> m) async {
    final personId = int.tryParse('${m['person_id']}');
    if (personId == null) return;
    final saved = await showDistributionPersonLocationSheet(
      context: context,
      businessId: widget.businessId,
      personId: personId,
      personName: m['person_name']?.toString() ?? '$personId',
      distributionService: _svc,
      initialLat: double.tryParse('${m['customer_latitude']}'),
      initialLng: double.tryParse('${m['customer_longitude']}'),
    );
    if (saved == true) await _load();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final markers = (_data?['markers'] as List?) ?? [];
    final mapMarkers = _mapMarkers(markers);
    final jalali = widget.calendarController.isJalali;

    return Scaffold(
      appBar: AppBar(title: Text(t.distributionTabTeamMap)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final d = await showAdaptiveDatePicker(
                      context: context,
                      calendarController: widget.calendarController,
                      initialDate: _day,
                    );
                    if (d != null) {
                      setState(() => _day = d);
                      await _load();
                    }
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: Text(Hd.HesabixDateUtils.formatForDisplay(_day, jalali)),
                ),
                const Spacer(),
                IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (mapMarkers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DistributionMemapsMap(markers: mapMarkers, height: 260),
            ),
          Expanded(
            child: markers.isEmpty
                ? Center(child: Text(t.distributionNoPlan))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: markers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final m = Map<String, dynamic>.from(markers[i] as Map);
                      final lat = m['visit_latitude'] ?? m['customer_latitude'];
                      final lng = m['visit_longitude'] ?? m['customer_longitude'];
                      final hasCoords = lat != null && lng != null;
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text('${m['user_id'] ?? ''}'),
                          ),
                          title: Text(m['person_name']?.toString() ?? 'user ${m['user_id']}'),
                          subtitle: Text('${m['status']} · visit #${m['visit_id']}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.canManageLocations)
                                IconButton(
                                  icon: const Icon(Icons.edit_location_alt_outlined),
                                  tooltip: t.distributionSetPersonLocation,
                                  onPressed: () => _editCustomerLocation(m),
                                ),
                              if (hasCoords)
                                IconButton(
                                  icon: const Icon(Icons.open_in_new),
                                  tooltip: t.distributionOpenInMaps,
                                  onPressed: () => _openExternalMaps(
                                    double.parse('$lat'),
                                    double.parse('$lng'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
