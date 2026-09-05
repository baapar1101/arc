import 'dart:async';

import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/distribution_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart' as Hd;
import '../../../core/distribution_map_tiles.dart';
import '../../../widgets/distribution/distribution_map_marker.dart';
import '../../../widgets/distribution/distribution_memaps_map.dart';
import '../../../widgets/distribution/distribution_person_location_sheet.dart';
import '../../../widgets/distribution/distribution_ui_helpers.dart';
import '../../../widgets/jalali_date_picker.dart';
import '../../../widgets/business_subpage_back_leading.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

/// نقشهٔ تیم — تازه‌سازی خودکار موقعیت زنده ویزیتورها.
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
  bool _autoRefresh = true;
  Timer? _refreshTimer;
  DateTime? _lastLoadedAt;
  DistributionMapTileConfig _tileConfig = const DistributionMapTileConfig();

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final d = await _svc.getTeamMap(businessId: widget.businessId, planDate: _iso(_day));
      DistributionMapTileConfig tiles = _tileConfig;
      try {
        final settings = await _svc.getDistributionSettings(businessId: widget.businessId);
        tiles = DistributionMapTileConfig.fromSettings(settings);
      } catch (_) {
        // نقشه تیم بدون تنظیمات تایل هم باید نمایش داده شود
      }
      if (mounted) {
        setState(() {
          _data = d;
          _tileConfig = tiles;
          _lastLoadedAt = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  void _syncTimer() {
    _refreshTimer?.cancel();
    if (_autoRefresh) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
    }
  }

  List<DistributionMapMarker> _mapMarkers(List<dynamic> rawMarkers, AppLocalizations t) {
    final out = <DistributionMapMarker>[];
    for (final raw in rawMarkers) {
      final m = Map<String, dynamic>.from(raw as Map);
      final lat = m['visit_latitude'] ?? m['customer_latitude'];
      final lng = m['visit_longitude'] ?? m['customer_longitude'];
      if (lat == null || lng == null) continue;
      final la = double.tryParse('$lat');
      final ln = double.tryParse('$lng');
      if (la == null || ln == null) continue;
      final label = m['user_name']?.toString().isNotEmpty == true
          ? m['user_name'].toString()
          : (m['person_name']?.toString() ?? 'user ${m['user_id']}');
      final statusLabel = distributionVisitStatusLabel(t, m['status']?.toString());
      out.add(
        DistributionMapMarker(
          lat: la,
          lng: ln,
          label: label,
          subtitle: '$statusLabel'
              '${m['location_source'] != null ? ' · ${m['location_source']}' : ''}',
          color: m['status'] == 'in_progress' ? SemanticColorResolver.warning(context) : SemanticColorResolver.info(context),
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
      tileConfig: _tileConfig,
    );
    if (saved == true) await _load();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _syncTimer();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final markers = (_data?['markers'] as List?) ?? [];
    final mapMarkers = _mapMarkers(markers, t);
    final jalali = widget.calendarController.isJalali;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.distributionTabTeamMap),
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        actions: [
          IconButton(
            tooltip: t.distributionRefresh,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                OutlinedButton.icon(
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
                FilterChip(
                  selected: _autoRefresh,
                  label: Text(t.distributionLiveRefresh),
                  onSelected: (v) {
                    setState(() => _autoRefresh = v);
                    _syncTimer();
                  },
                ),
              ],
            ),
          ),
          if (_lastLoadedAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  '${t.distributionLastUpdated}: ${_lastLoadedAt!.hour.toString().padLeft(2, '0')}:${_lastLoadedAt!.minute.toString().padLeft(2, '0')}:${_lastLoadedAt!.second.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: mapMarkers.isEmpty
                ? Center(child: Text(t.distributionTeamMapEmpty))
                : LayoutBuilder(
                    builder: (context, constraints) => DistributionMemapsMap(
                      markers: mapMarkers,
                      height: constraints.maxHeight,
                      tileConfig: _tileConfig,
                    ),
                  ),
          ),
          SizedBox(
            height: 220,
            child: ListView.builder(
              itemCount: markers.length,
              itemBuilder: (context, i) {
                final m = Map<String, dynamic>.from(markers[i] as Map);
                final lat = double.tryParse('${m['visit_latitude'] ?? m['customer_latitude']}');
                final lng = double.tryParse('${m['visit_longitude'] ?? m['customer_longitude']}');
                return ListTile(
                  leading: Icon(
                    m['status'] == 'in_progress' ? Icons.directions_walk : Icons.place_outlined,
                    color: m['status'] == 'in_progress' ? SemanticColorResolver.warning(context) : null,
                  ),
                  title: Text(
                    m['user_name']?.toString().isNotEmpty == true
                        ? m['user_name'].toString()
                        : 'user ${m['user_id']}',
                  ),
                  subtitle: Text(
                    '${m['person_name'] ?? m['person_id']} · ${distributionVisitStatusLabel(t, m['status']?.toString())}'
                    '${m['live_updated_at'] != null ? '\n${t.distributionLiveAt}: ${m['live_updated_at']}' : ''}',
                  ),
                  isThreeLine: m['live_updated_at'] != null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (lat != null && lng != null)
                        IconButton(
                          icon: const Icon(Icons.map_outlined),
                          onPressed: () => _openExternalMaps(lat, lng),
                        ),
                      if (widget.canManageLocations)
                        IconButton(
                          icon: const Icon(Icons.edit_location_alt_outlined),
                          onPressed: () => _editCustomerLocation(m),
                        ),
                    ],
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
