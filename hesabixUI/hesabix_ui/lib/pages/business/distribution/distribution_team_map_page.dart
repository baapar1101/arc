import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/distribution_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
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

/// نقشهٔ تیم — موقعیت زنده ویزیتورها جدا از پین مشتری، با مسیر روز.
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
  bool _onlineOnly = false;
  bool _showCustomers = true;
  Timer? _refreshTimer;
  DateTime? _lastLoadedAt;
  DistributionMapTileConfig _tileConfig = const DistributionMapTileConfig();
  int? _selectedUserId;
  List<LatLng> _trail = const [];
  bool _trailLoading = false;
  int _fitNonce = 0;

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool get _shareLive => _data?['share_live_location'] != false;

  List<Map<String, dynamic>> get _visitors {
    final raw = _data?['visitors'] ?? _data?['markers'];
    if (raw is! List) return const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  List<Map<String, dynamic>> get _customers {
    final raw = _data?['customers'];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    final out = <Map<String, dynamic>>[];
    final seen = <int>{};
    for (final v in _visitors) {
      final pid = int.tryParse('${v['person_id']}');
      final lat = double.tryParse('${v['customer_latitude']}');
      final lng = double.tryParse('${v['customer_longitude']}');
      if (pid == null || lat == null || lng == null || seen.contains(pid)) continue;
      seen.add(pid);
      out.add({
        'person_id': pid,
        'person_name': v['person_name'],
        'latitude': lat,
        'longitude': lng,
        'user_id': v['user_id'],
      });
    }
    return out;
  }

  List<Map<String, dynamic>> get _visibleVisitors {
    if (!_onlineOnly) return _visitors;
    return _visitors.where((v) => v['presence'] == 'online' || v['presence'] == 'recent').toList();
  }

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
          if (!silent) _fitNonce++;
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

  double? _visitorLat(Map<String, dynamic> m) {
    return double.tryParse('${m['latitude'] ?? m['visit_latitude']}');
  }

  double? _visitorLng(Map<String, dynamic> m) {
    return double.tryParse('${m['longitude'] ?? m['visit_longitude']}');
  }

  List<DistributionMapMarker> _mapMarkers(AppLocalizations t) {
    final out = <DistributionMapMarker>[];
    for (final m in _visibleVisitors) {
      final la = _visitorLat(m);
      final ln = _visitorLng(m);
      if (la == null || ln == null) continue;
      final uid = int.tryParse('${m['user_id']}');
      final presence = m['presence']?.toString();
      final label = m['user_name']?.toString().isNotEmpty == true
          ? m['user_name'].toString()
          : 'user ${m['user_id']}';
      final customer = m['person_name']?.toString();
      final status = m['status']?.toString();
      final subtitleParts = <String>[
        distributionPresenceLabel(t, presence),
        if (status == 'in_progress' && customer != null && customer.isNotEmpty) customer,
      ];
      out.add(
        DistributionMapMarker(
          id: uid == null ? null : 'v:$uid',
          lat: la,
          lng: ln,
          label: label,
          subtitle: subtitleParts.join(' · '),
          color: distributionPresenceColor(context, presence),
          icon: status == 'in_progress' ? Icons.directions_walk : Icons.person_pin_circle,
          kind: DistributionMapMarkerKind.visitor,
          selected: uid != null && uid == _selectedUserId,
          payload: m,
        ),
      );
    }
    if (_showCustomers) {
      for (final c in _customers) {
        final la = double.tryParse('${c['latitude']}');
        final ln = double.tryParse('${c['longitude']}');
        if (la == null || ln == null) continue;
        final pid = int.tryParse('${c['person_id']}');
        out.add(
          DistributionMapMarker(
            id: pid == null ? null : 'c:$pid',
            lat: la,
            lng: ln,
            label: c['person_name']?.toString() ?? '${c['person_id']}',
            subtitle: t.distributionTeamMapCustomers,
            color: SemanticColorResolver.info(context).withValues(alpha: 0.9),
            icon: Icons.storefront,
            kind: DistributionMapMarkerKind.customer,
            payload: c,
          ),
        );
      }
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
      initialLat: double.tryParse('${m['latitude'] ?? m['customer_latitude']}'),
      initialLng: double.tryParse('${m['longitude'] ?? m['customer_longitude']}'),
      tileConfig: _tileConfig,
    );
    if (saved == true) await _load();
  }

  Future<void> _selectVisitor(Map<String, dynamic> m, {bool loadTrail = true}) async {
    final uid = int.tryParse('${m['user_id']}');
    if (uid == null) return;
    setState(() {
      _selectedUserId = uid;
      _trail = const [];
      _fitNonce++;
    });
    if (!loadTrail) return;
    setState(() => _trailLoading = true);
    try {
      final data = await _svc.getUserDayTrail(
        businessId: widget.businessId,
        userId: uid,
        day: _iso(_day),
      );
      final pts = <LatLng>[];
      final raw = data['points'];
      if (raw is List) {
        for (final p in raw) {
          final row = Map<String, dynamic>.from(p as Map);
          final la = double.tryParse('${row['latitude']}');
          final ln = double.tryParse('${row['longitude']}');
          if (la == null || ln == null) continue;
          pts.add(LatLng(la, ln));
        }
      }
      if (!mounted) return;
      setState(() {
        _trail = pts;
        _fitNonce++;
      });
      if (pts.isEmpty && mounted) {
        SnackBarHelper.showInfo(context, message: AppLocalizations.of(context).distributionTeamMapNoTrail);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _trailLoading = false);
    }
  }

  void _onMarkerTap(DistributionMapMarker marker) {
    final payload = marker.payload;
    if (payload is! Map<String, dynamic>) return;
    if (marker.kind == DistributionMapMarkerKind.customer) {
      if (widget.canManageLocations) {
        _editCustomerLocation(payload);
      }
      return;
    }
    _selectVisitor(payload);
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

  Widget _legendChip(Color color, IconData icon, String label) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }

  Widget _visitorTile(AppLocalizations t, Map<String, dynamic> m) {
    final uid = int.tryParse('${m['user_id']}');
    final selected = uid != null && uid == _selectedUserId;
    final presence = m['presence']?.toString();
    final lat = _visitorLat(m);
    final lng = _visitorLng(m);
    final name = m['user_name']?.toString().isNotEmpty == true
        ? m['user_name'].toString()
        : 'user ${m['user_id']}';
    final customer = m['person_name']?.toString();
    final status = m['status']?.toString();
    final liveAt = m['live_updated_at']?.toString();
    final subtitle = StringBuffer(distributionPresenceLabel(t, presence));
    if (status == 'in_progress' && customer != null && customer.isNotEmpty) {
      subtitle.write(' · $customer');
    } else if (status != null && status.isNotEmpty) {
      subtitle.write(' · ${distributionVisitStatusLabel(t, status)}');
    }
    if (liveAt != null && liveAt.isNotEmpty) {
      subtitle.write('\n${t.distributionLiveAt}: $liveAt');
    }
    final color = distributionPresenceColor(context, presence);
    return ListTile(
      selected: selected,
      selectedTileColor: color.withValues(alpha: 0.08),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.18),
        child: Icon(distributionPresenceIcon(presence), color: color, size: 20),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle.toString()),
      isThreeLine: liveAt != null && liveAt.isNotEmpty,
      onTap: () => _selectVisitor(m),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_trailLoading && selected)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(Icons.route, color: selected ? Theme.of(context).colorScheme.primary : null, size: 20),
          if (lat != null && lng != null)
            IconButton(
              tooltip: t.distributionNavigate,
              icon: const Icon(Icons.map_outlined),
              onPressed: () => _openExternalMaps(lat, lng),
            ),
        ],
      ),
    );
  }

  Widget _visitorList(AppLocalizations t) {
    final items = _visibleVisitors;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            t.distributionTeamMapEmptyHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _visitorTile(t, items[i]),
    );
  }

  Widget _mapPane(AppLocalizations t) {
    return LayoutBuilder(
      builder: (context, c) {
        final markers = _mapMarkers(t);
        return Stack(
          children: [
            DistributionMemapsMap(
              markers: markers,
              height: c.maxHeight,
              tileConfig: _tileConfig,
              polyline: _trail,
              fitNonce: _fitNonce,
              onMarkerTap: _onMarkerTap,
            ),
            if (markers.isEmpty && _trail.isEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.explore_off_outlined, size: 36, color: Theme.of(context).colorScheme.outline),
                              const SizedBox(height: 8),
                              Text(t.distributionTeamMapEmpty, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 6),
                              Text(t.distributionTeamMapEmptyHint, textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final jalali = widget.calendarController.isJalali;
    final cs = Theme.of(context).colorScheme;

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
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showAdaptiveDatePicker(
                      context: context,
                      calendarController: widget.calendarController,
                      initialDate: _day,
                    );
                    if (d != null) {
                      setState(() {
                        _day = d;
                        _trail = const [];
                        _selectedUserId = null;
                      });
                      await _load();
                    }
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: Text(Hd.HesabixDateUtils.formatForDisplay(_day, jalali)),
                ),
                FilterChip(
                  selected: _autoRefresh,
                  label: Text(t.distributionLiveRefresh),
                  avatar: Icon(_autoRefresh ? Icons.sensors : Icons.sensors_off, size: 18),
                  onSelected: (v) {
                    setState(() => _autoRefresh = v);
                    _syncTimer();
                  },
                ),
                FilterChip(
                  selected: _onlineOnly,
                  label: Text(t.distributionTeamMapOnlineOnly),
                  onSelected: (v) => setState(() => _onlineOnly = v),
                ),
                FilterChip(
                  selected: _showCustomers,
                  label: Text(t.distributionTeamMapShowCustomers),
                  onSelected: (v) {
                    setState(() {
                      _showCustomers = v;
                      _fitNonce++;
                    });
                  },
                ),
                if (_lastLoadedAt != null)
                  Text(
                    '${t.distributionLastUpdated}: ${_lastLoadedAt!.hour.toString().padLeft(2, '0')}:${_lastLoadedAt!.minute.toString().padLeft(2, '0')}:${_lastLoadedAt!.second.toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _legendChip(distributionPresenceColor(context, 'online'), Icons.directions_walk, t.distributionTeamMapVisitors),
                  _legendChip(SemanticColorResolver.info(context), Icons.storefront, t.distributionTeamMapCustomers),
                  _legendChip(cs.primary, Icons.route, t.distributionTeamMapTrail),
                  _legendChip(distributionPresenceColor(context, 'online'), Icons.sensors, t.distributionPresenceOnline),
                  _legendChip(distributionPresenceColor(context, 'recent'), Icons.schedule, t.distributionPresenceRecent),
                  _legendChip(distributionPresenceColor(context, 'stale'), Icons.history, t.distributionPresenceStale),
                ],
              ),
            ),
          ),
          if (!_shareLive)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Card(
                color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.45),
                child: ListTile(
                  leading: const Icon(Icons.location_off_outlined),
                  title: Text(t.distributionLiveLocationDisabledBanner),
                ),
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 840;
                if (wide) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _mapPane(t)),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 360,
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                                  child: Text(
                                    '${t.distributionTeamMapVisitors} (${_visibleVisitors.length})',
                                    style: Theme.of(context).textTheme.titleSmall,
                                  ),
                                ),
                                const Divider(height: 1),
                                Expanded(child: _visitorList(t)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final listH = (constraints.maxHeight * 0.38).clamp(180.0, 280.0);
                return Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: _mapPane(t),
                      ),
                    ),
                    SizedBox(
                      height: listH,
                      child: Card(
                        margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  '${t.distributionTeamMapVisitors} (${_visibleVisitors.length})',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(child: _visitorList(t)),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
