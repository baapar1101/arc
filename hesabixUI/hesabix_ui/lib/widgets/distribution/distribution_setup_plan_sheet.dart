import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart' as Hd;
import '../../l10n/app_localizations.dart';
import '../../models/business_user_model.dart';
import '../../services/business_user_service.dart';
import '../../services/distribution_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/jalali_date_picker.dart';
import 'distribution_form_helpers.dart';

/// ویزارد تخصیص مسیر به ویزیتور برای ساخت برنامهٔ روز.
Future<int?> showDistributionSetupPlanSheet({
  required BuildContext context,
  required int businessId,
  required DistributionService service,
  required CalendarController calendarController,
  required List<dynamic> routes,
  required DateTime planDate,
}) {
  return showGlassModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _SetupPlanSheet(
        businessId: businessId,
        service: service,
        calendarController: calendarController,
        routes: routes,
        planDate: planDate,
      ),
    ),
  );
}

class _SetupPlanSheet extends StatefulWidget {
  final int businessId;
  final DistributionService service;
  final CalendarController calendarController;
  final List<dynamic> routes;
  final DateTime planDate;

  const _SetupPlanSheet({
    required this.businessId,
    required this.service,
    required this.calendarController,
    required this.routes,
    required this.planDate,
  });

  @override
  State<_SetupPlanSheet> createState() => _SetupPlanSheetState();
}

class _SetupPlanSheetState extends State<_SetupPlanSheet> {
  int? _userId;
  int? _routeId;
  late DateTime _from;
  List<BusinessUser> _users = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _from = widget.planDate;
    _routeId = widget.routes.isNotEmpty
        ? int.tryParse('${(widget.routes.first as Map)['id']}')
        : null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsers());
  }

  Future<void> _loadUsers() async {
    try {
      final res = await BusinessUserService(ApiClient()).getBusinessUsers(widget.businessId);
      if (mounted) setState(() => _users = res.users);
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_userId == null || _routeId == null) return;
    setState(() => _saving = true);
    try {
      await widget.service.createAssignment(
        businessId: widget.businessId,
        payload: {
          'route_id': _routeId,
          'user_id': _userId,
          'valid_from':
              '${_from.year.toString().padLeft(4, '0')}-${_from.month.toString().padLeft(2, '0')}-${_from.day.toString().padLeft(2, '0')}',
        },
      );
      if (mounted) Navigator.pop(context, _userId);
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
    final jalali = widget.calendarController.isJalali;
    final activeRoutes = widget.routes
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .where((m) => m['is_active'] != false)
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.distributionSetupPlan, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(t.distributionSetupPlanHint, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          if (activeRoutes.isEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(t.distributionNoRoutesYet),
                subtitle: Text(t.distributionGoToManageHint),
              ),
            )
          else ...[
            DropdownButtonFormField<int>(
              value: _userId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: t.distributionSelectVisitor,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
              items: _users
                  .map(
                    (u) => DropdownMenuItem<int>(
                      value: u.userId,
                      child: Text(u.userName.isNotEmpty ? u.userName : '${u.userId}'),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _userId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _routeId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: t.distributionSelectRoute,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.alt_route),
              ),
              items: activeRoutes
                  .map(
                    (m) => DropdownMenuItem<int>(
                      value: int.tryParse('${m['id']}'),
                      child: Text(
                        [
                          distributionEntityLabel(m),
                          if ('${m['territory_name'] ?? ''}'.trim().isNotEmpty) '${m['territory_name']}',
                        ].join(' · '),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _routeId = v),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(t.distributionAssignmentFrom),
              subtitle: Text(Hd.HesabixDateUtils.formatForDisplay(_from, jalali)),
              onTap: () async {
                final d = await showAdaptiveDatePicker(
                  context: context,
                  calendarController: widget.calendarController,
                  initialDate: _from,
                );
                if (d != null) setState(() => _from = d);
              },
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving || _userId == null || _routeId == null ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(t.distributionAssignAndShowPlan),
            ),
          ],
        ],
      ),
    );
  }
}
