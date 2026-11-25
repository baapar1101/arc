import 'package:flutter/material.dart';

import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart' as Hd;
import '../../../core/distribution_map_tiles.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/distribution_service.dart';
import '../../../widgets/distribution/distribution_field_helpers.dart';
import '../../../widgets/distribution/distribution_map_marker.dart';
import '../../../widgets/distribution/distribution_memaps_map.dart';
import '../../../widgets/distribution/distribution_plan_stop_card.dart';
import '../../../widgets/distribution/distribution_scorecard_card.dart';
import '../../../widgets/distribution/distribution_ui_helpers.dart';
import '../../../widgets/jalali_date_picker.dart';

class DistributionFieldTabData {
  final DateTime planDay;
  final int? teamTargetUserId;
  final Map<String, dynamic>? dailyPlan;
  final List<dynamic>? optimizedPlanItems;
  final Map<String, dynamic> summary;
  final Map<String, dynamic>? scorecard;
  final Map<String, dynamic>? activeVisit;
  final Map<String, dynamic>? visitListPayload;
  final bool loadingPlan;
  final bool loadingSummary;
  final int offlinePending;
  final bool shareLiveLocation;
  final bool requireLocationConsent;
  final bool locationConsent;
  final bool? liveGpsOk;
  final bool planPublished;
  final bool planLocked;
  final bool setupCompleted;
  final bool canOperate;
  final bool canManage;
  final bool canTeam;
  final String navProvider;
  final DistributionMapTileConfig mapTiles;

  const DistributionFieldTabData({
    required this.planDay,
    required this.teamTargetUserId,
    required this.dailyPlan,
    required this.optimizedPlanItems,
    required this.summary,
    required this.scorecard,
    required this.activeVisit,
    required this.visitListPayload,
    required this.loadingPlan,
    required this.loadingSummary,
    required this.offlinePending,
    required this.shareLiveLocation,
    required this.requireLocationConsent,
    required this.locationConsent,
    required this.liveGpsOk,
    required this.planPublished,
    required this.planLocked,
    required this.setupCompleted,
    required this.canOperate,
    required this.canManage,
    required this.canTeam,
    required this.navProvider,
    required this.mapTiles,
  });
}

class DistributionFieldTabActions {
  final Future<void> Function() onRefresh;
  final Future<void> Function(DateTime day) onPlanDayChanged;
  final Future<void> Function(int? userId) onTeamTargetChanged;
  final VoidCallback onGrantConsent;
  final VoidCallback onRevokeConsent;
  final VoidCallback onTogglePublish;
  final VoidCallback onPublishAll;
  final void Function(int visitId, int? personId) onCompleteVisit;
  final VoidCallback onCancelVisit;
  final void Function(Map<String, dynamic> item) onStartVisit;
  final VoidCallback onSetupPlan;
  final VoidCallback onGoToManage;
  final VoidCallback onOptimize;
  final VoidCallback onPrintPlan;
  final VoidCallback onOpenTeamMap;
  final VoidCallback onOpenReports;
  final void Function(Map<String, dynamic> item) onSetPersonLocation;
  final VoidCallback onShowOfflineQueue;
  final Future<void> Function() onOpenSetupWizard;

  const DistributionFieldTabActions({
    required this.onRefresh,
    required this.onPlanDayChanged,
    required this.onTeamTargetChanged,
    required this.onGrantConsent,
    required this.onRevokeConsent,
    required this.onTogglePublish,
    required this.onPublishAll,
    required this.onCompleteVisit,
    required this.onCancelVisit,
    required this.onStartVisit,
    required this.onSetupPlan,
    required this.onGoToManage,
    required this.onOptimize,
    required this.onPrintPlan,
    required this.onOpenTeamMap,
    required this.onOpenReports,
    required this.onSetPersonLocation,
    required this.onShowOfflineQueue,
    required this.onOpenSetupWizard,
  });
}

class DistributionFieldTab extends StatelessWidget {
  final AppLocalizations t;
  final CalendarController calendarController;
  final DistributionService? service;
  final int businessId;
  final DistributionFieldTabData data;
  final DistributionFieldTabActions actions;

  const DistributionFieldTab({
    super.key,
    required this.t,
    required this.calendarController,
    this.service,
    required this.businessId,
    required this.data,
    required this.actions,
  });

  bool get _jalali => calendarController.isJalali;

  String _stopKind(int? personId) => distributionPlanStopKind(
        personId: personId,
        planDay: data.planDay,
        activeVisit: data.activeVisit,
        visitItems: (data.visitListPayload?['items'] as List?) ?? const [],
      );

  List<DistributionMapMarker> _planMapMarkers(List<dynamic> items) {
    return items
        .map((raw) => DistributionMapMarker.tryFromPayload(Map<String, dynamic>.from(raw as Map)))
        .whereType<DistributionMapMarker>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final planItems = (data.optimizedPlanItems ?? (data.dailyPlan?['items'] as List?)) ?? [];
    var doneCount = 0;
    var remainingCount = 0;
    Map<String, dynamic>? nextStop;
    for (final raw in planItems) {
      final item = Map<String, dynamic>.from(raw as Map);
      final pid = int.tryParse('${item['person_id']}');
      final kind = _stopKind(pid);
      if (kind == 'done') {
        doneCount++;
      } else {
        remainingCount++;
        nextStop ??= item;
      }
    }
    final progress = planItems.isEmpty ? 0.0 : doneCount / planItems.length;
    final mapMarkers = planItems.isEmpty ? const <DistributionMapMarker>[] : _planMapMarkers(planItems);

    return RefreshIndicator(
      onRefresh: actions.onRefresh,
      child: CustomScrollView(
        slivers: [
          if (data.shareLiveLocation && data.requireLocationConsent && !data.locationConsent)
            SliverToBoxAdapter(
              child: Card(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(t.distributionLocationConsentTitle),
                  subtitle: Text(t.distributionLocationConsentHint),
                  trailing: FilledButton(
                    onPressed: actions.onGrantConsent,
                    child: Text(t.distributionLocationConsentAllow),
                  ),
                ),
              ),
            ),
          if (data.shareLiveLocation && data.requireLocationConsent && data.locationConsent)
            SliverToBoxAdapter(
              child: Card(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: ListTile(
                  leading: const Icon(Icons.my_location_outlined),
                  title: Text(t.distributionLocationConsentTitle),
                  subtitle: Text(t.distributionLocationConsentActive),
                  trailing: TextButton(
                    onPressed: actions.onRevokeConsent,
                    child: Text(t.distributionLocationConsentRevoke),
                  ),
                ),
              ),
            ),
          if (data.canManage)
            SliverToBoxAdapter(
              child: Card(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      leading: Icon(data.planLocked ? Icons.lock_outline : Icons.publish_outlined),
                      title: Text(data.planPublished ? t.distributionPlanPublished : t.distributionPlanUnpublished),
                      subtitle: Text(
                        data.planLocked ? t.distributionPlanLockedHint : t.distributionPlanPublishHint,
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: actions.onTogglePublish,
                        child: Text(data.planPublished ? t.distributionPlanUnlock : t.distributionPlanPublish),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Tooltip(
                          message: t.distributionPlanPublishAllHint,
                          child: TextButton.icon(
                            onPressed: actions.onPublishAll,
                            icon: const Icon(Icons.groups_outlined),
                            label: Text(t.distributionPlanPublishAll),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (data.activeVisit != null)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.timelapse, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(t.distributionActiveVisitBanner, style: theme.textTheme.titleSmall),
                        ),
                        distributionStatusChip(context, t, data.activeVisit!['status']?.toString()),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${data.activeVisit!['person_name'] ?? data.activeVisit!['person_id']}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (data.canOperate) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => actions.onCompleteVisit(
                          int.parse('${data.activeVisit!['id']}'),
                          int.tryParse('${data.activeVisit!['person_id']}'),
                        ),
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(t.distributionCompleteVisitCta),
                      ),
                      TextButton(
                        onPressed: actions.onCancelVisit,
                        child: Text(t.distributionCancelVisit),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (data.canOperate)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Card(
                  color: data.shareLiveLocation
                      ? (data.liveGpsOk == false ? cs.errorContainer.withValues(alpha: 0.55) : cs.surfaceContainerHighest)
                      : cs.surfaceContainerHighest,
                  child: ListTile(
                    leading: Icon(
                      !data.shareLiveLocation
                          ? Icons.location_off_outlined
                          : (data.liveGpsOk == false ? Icons.gps_off : Icons.my_location),
                    ),
                    title: Text(
                      !data.shareLiveLocation
                          ? t.distributionLiveLocationDisabledBanner
                          : (data.liveGpsOk == false
                              ? t.distributionLiveLocationGpsUnavailable
                              : t.distributionLiveLocationVisitorHint),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (data.canManage && !data.setupCompleted)
                    Card(
                      color: cs.tertiaryContainer.withValues(alpha: 0.5),
                      child: ListTile(
                        leading: const Icon(Icons.auto_fix_high_outlined),
                        title: Text(t.distributionSetupNeeded),
                        trailing: FilledButton(
                          onPressed: () => actions.onOpenSetupWizard(),
                          child: Text(t.distributionStartWizard),
                        ),
                      ),
                    ),
                  if (!data.canManage)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(t.distributionVisitorHomeHint, style: theme.textTheme.bodySmall),
                    ),
                  if (data.scorecard != null) ...[
                    DistributionScorecardCard(kpi: data.scorecard!),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(t.distributionDayProgress, style: theme.textTheme.titleMedium),
                      ),
                      Text(
                        '$doneCount / ${planItems.length}',
                        style: theme.textTheme.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: data.loadingPlan ? null : progress,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.check, size: 16),
                        label: Text('${t.distributionStopsDone}: $doneCount'),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.more_horiz, size: 16),
                        label: Text('${t.distributionStopsRemaining}: $remainingCount'),
                      ),
                      if (!data.loadingSummary)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(Icons.assignment_return, size: 16),
                          label: Text('${t.distributionPendingReturns}: ${data.summary['pending_return_requests'] ?? 0}'),
                        ),
                      if (data.dailyPlan?['carried_over_count'] is num &&
                          (data.dailyPlan!['carried_over_count'] as num).toInt() > 0)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(Icons.history, size: 16),
                          label: Text('${t.distributionCarriedOver}: ${data.dailyPlan?['carried_over_count']}'),
                        ),
                    ],
                  ),
                  if (nextStop != null && data.activeVisit == null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${t.distributionNextStop}: ${nextStop['person_name'] ?? nextStop['person_id']}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final d = await showAdaptiveDatePicker(
                        context: context,
                        calendarController: calendarController,
                        initialDate: data.planDay,
                        helpText: t.distributionSelectDate,
                      );
                      if (d != null) await actions.onPlanDayChanged(d);
                    },
                    icon: const Icon(Icons.calendar_month),
                    label: Text(Hd.HesabixDateUtils.formatForDisplay(data.planDay, _jalali)),
                  ),
                  if (data.canManage) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: actions.onSetupPlan,
                      icon: const Icon(Icons.playlist_add_check_outlined),
                      label: Text(t.distributionSetupPlan),
                    ),
                  ],
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    tooltip: t.distributionMoreActions,
                    onSelected: (v) async {
                      if (v == 'optimize' && data.canOperate) actions.onOptimize();
                      if (v == 'pdf') actions.onPrintPlan();
                      if (v == 'map' && data.canTeam) actions.onOpenTeamMap();
                      if (v == 'reports') actions.onOpenReports();
                    },
                    itemBuilder: (ctx) => [
                      if (data.canOperate)
                        PopupMenuItem(value: 'optimize', child: Text(t.distributionOptimizeRoute)),
                      PopupMenuItem(value: 'pdf', child: Text(t.distributionPrintDailyPlan)),
                      if (data.canTeam) PopupMenuItem(value: 'map', child: Text(t.distributionTabTeamMap)),
                      PopupMenuItem(value: 'reports', child: Text(t.distributionGoToReports)),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.more_horiz, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(t.distributionMoreActions, style: theme.textTheme.labelLarge),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (data.canTeam && service != null)
                    _DistributionTeamVisitorPicker(
                      t: t,
                      service: service!,
                      businessId: businessId,
                      teamTargetUserId: data.teamTargetUserId,
                      onChanged: actions.onTeamTargetChanged,
                    ),
                ],
              ),
            ),
          ),
          if (data.offlinePending > 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Material(
                  color: cs.tertiaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    leading: Badge(
                      label: Text('${data.offlinePending}'),
                      child: const Icon(Icons.cloud_queue_outlined),
                    ),
                    title: Text(t.distributionOfflineQueued),
                    subtitle: Text('${t.distributionOfflinePending}: ${data.offlinePending}'),
                    trailing: TextButton(onPressed: actions.onShowOfflineQueue, child: Text(t.distributionViewQueue)),
                  ),
                ),
              ),
            ),
          if (data.loadingPlan)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (planItems.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: distributionEmptyState(
                context: context,
                icon: Icons.route_outlined,
                title: t.distributionNoPlan,
                subtitle: t.distributionNoPlanHint,
                action: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (data.canManage)
                      FilledButton.icon(
                        onPressed: actions.onSetupPlan,
                        icon: const Icon(Icons.playlist_add_check_outlined),
                        label: Text(t.distributionSetupPlan),
                      ),
                    if (data.canManage) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: actions.onGoToManage,
                        icon: const Icon(Icons.settings_outlined),
                        label: Text(t.distributionGoToManage),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            SliverMainAxisGroup(
              slivers: [
                if (mapMarkers.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: DistributionMemapsMap(
                          markers: mapMarkers,
                          height: 200,
                          tileConfig: data.mapTiles,
                        ),
                      ),
                    ),
                  ),
                SliverList.separated(
                  itemCount: planItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final item = Map<String, dynamic>.from(planItems[i] as Map);
                    final pid = int.tryParse('${item['person_id']}');
                    final kind = _stopKind(pid);
                    final nextId = nextStop == null ? null : '${nextStop['stop_id']}';
                    final isNext = nextId != null && '${item['stop_id']}' == nextId;
                    return DistributionPlanStopCard(
                      item: item,
                      index: i,
                      kind: kind,
                      isNext: isNext,
                      canOperate: data.canOperate,
                      canManage: data.canManage,
                      activeVisit: data.activeVisit,
                      navProvider: data.navProvider,
                      onStartVisit: () => actions.onStartVisit(item),
                      onCompleteVisit: data.activeVisit == null
                          ? null
                          : () => actions.onCompleteVisit(
                                int.parse('${data.activeVisit!['id']}'),
                                int.tryParse('${data.activeVisit!['person_id']}'),
                              ),
                      onSetPersonLocation: () => actions.onSetPersonLocation(item),
                    );
                  },
                ),
              ],
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }
}

class _DistributionTeamVisitorPicker extends StatefulWidget {
  final AppLocalizations t;
  final DistributionService service;
  final int businessId;
  final int? teamTargetUserId;
  final Future<void> Function(int? userId) onChanged;

  const _DistributionTeamVisitorPicker({
    required this.t,
    required this.service,
    required this.businessId,
    required this.teamTargetUserId,
    required this.onChanged,
  });

  @override
  State<_DistributionTeamVisitorPicker> createState() => _DistributionTeamVisitorPickerState();
}

class _DistributionTeamVisitorPickerState extends State<_DistributionTeamVisitorPicker> {
  late Future<List<dynamic>> _usersFuture;

  @override
  void initState() {
    super.initState();
    _usersFuture = widget.service.listTeamMembers(businessId: widget.businessId);
  }

  @override
  void didUpdateWidget(covariant _DistributionTeamVisitorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId || oldWidget.service != widget.service) {
      _usersFuture = widget.service.listTeamMembers(businessId: widget.businessId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _usersFuture,
      builder: (context, snap) {
        final users = snap.data ?? const <dynamic>[];
        return SizedBox(
          width: 160,
          child: DropdownButtonFormField<int?>(
            value: widget.teamTargetUserId,
            isDense: true,
            decoration: InputDecoration(
              labelText: widget.t.distributionSelectVisitor,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('—')),
              ...users.map((raw) {
                final m = Map<String, dynamic>.from(raw as Map);
                final id = int.tryParse('${m['user_id']}');
                final name = (m['user_name'] ?? id ?? '').toString();
                return DropdownMenuItem<int?>(
                  value: id,
                  child: Text(
                    name.isNotEmpty ? name : '$id',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
            ],
            onChanged: (v) => widget.onChanged(v),
          ),
        );
      },
    );
  }
}
