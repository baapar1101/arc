import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart';
import '../../../services/office_automation_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/office_automation/oa_ui.dart';

class OaMyDeskPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const OaMyDeskPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<OaMyDeskPage> createState() => _OaMyDeskPageState();
}

class _OaMyDeskPageState extends State<OaMyDeskPage> {
  final OfficeAutomationService _svc = OfficeAutomationService();
  bool _loading = true;
  List<Map<String, dynamic>> _positions = [];
  int? _positionId;
  Map<String, dynamic> _desk = const {};
  List<Map<String, dynamic>> _confirmations = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dash = await _svc.getDashboard(businessId: widget.businessId, positionId: _positionId);
      final positions = List<Map<String, dynamic>>.from(dash['my_positions'] as List? ?? const []);
      final active = _positionId ?? (dash['active_position_id'] as num?)?.toInt();
      Map<String, dynamic> desk = const {};
      if (active != null) {
        desk = await _svc.getPersonalDesk(businessId: widget.businessId, positionId: active);
      }
      final confirmations = await _svc.listMcpConfirmations(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _positions = positions;
        _positionId = active;
        _desk = desk;
        _confirmations = confirmations;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _decide(int id, bool accept) async {
    try {
      await _svc.decideMcpConfirmation(businessId: widget.businessId, confirmationId: id, accept: accept);
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  void _openLetter(int? letterId) {
    if (letterId == null) return;
    context.go(
      context.businessPanelUrl(widget.businessId, 'office-automation/letters/$letterId'),
      extra: {'positionId': _positionId},
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final counts = Map<String, dynamic>.from(_desk['counts'] as Map? ?? const {});
    return Scaffold(
      appBar: AppBar(
        title: Text(t.oaMyDesk),
        actions: [
          IconButton(
            tooltip: t.oaCartable,
            icon: const Icon(Icons.inbox_outlined),
            onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'office-automation')),
          ),
          IconButton(tooltip: t.refresh, icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _positions.isEmpty
              ? Center(child: Text(t.oaNoPositions))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: _positionId,
                      decoration: InputDecoration(labelText: t.oaActingAs, border: const OutlineInputBorder()),
                      items: [
                        for (final p in _positions)
                          if (oaId(p['id']) != null)
                            DropdownMenuItem(value: oaId(p['id']), child: Text(oaPositionLabel(p))),
                      ],
                      onChanged: (id) {
                        if (id == null) return;
                        setState(() => _positionId = id);
                        _load();
                      },
                    ),
                    const SizedBox(height: 16),
                    OaSectionCard(
                      title: t.oaPendingConfirmations,
                      child: _confirmations.isEmpty
                          ? Text(t.oaNoPendingConfirmations)
                          : Column(
                              children: [
                                for (final row in _confirmations)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(row['summary']?.toString() ?? ''),
                                    subtitle: Text(row['status']?.toString() ?? ''),
                                    trailing: row['status'] == 'pending' && oaId(row['id']) != null
                                        ? Wrap(
                                            spacing: 4,
                                            children: [
                                              TextButton(onPressed: () => _decide(oaId(row['id'])!, true), child: Text(t.oaApproveAction)),
                                              TextButton(onPressed: () => _decide(oaId(row['id'])!, false), child: Text(t.oaRejectAction)),
                                            ],
                                          )
                                        : null,
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _count(t.oaInbox, counts['inbox']),
                        _count(t.oaAction, counts['action']),
                        _count(t.oaOverdue, counts['overdue']),
                        _count(t.oaDrafts, counts['drafts']),
                        _count(t.oaFollowUp, counts['followup']),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _section(t.oaOverdue, _rows('overdue'), (row) => _line(row, row['due_at'])),
                    _section(t.oaDueSoon, _rows('due_soon'), (row) => _line(row, row['due_at'])),
                    _section(t.oaFollowUpsDue, _rows('follow_ups'), (row) => _line(row, row['follow_up_at'])),
                  ],
                ),
    );
  }

  Widget _count(String label, Object? value) {
    final n = value is num ? value.toInt() : 0;
    return Chip(
      avatar: CircleAvatar(child: Text('$n', style: const TextStyle(fontSize: 11))),
      label: Text(label),
    );
  }

  List<Map<String, dynamic>> _rows(String key) {
    final raw = _desk[key];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Widget _section(String title, List<Map<String, dynamic>> rows, String Function(Map<String, dynamic>) subtitle) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OaSectionCard(
        title: title,
        child: rows.isEmpty
            ? Text(t.oaEmptyFolder)
            : Column(
                children: [
                  for (final row in rows)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${row['subject'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(subtitle(row)),
                      trailing: '${row['confidentiality'] ?? 'normal'}' == 'normal'
                          ? null
                          : const Icon(Icons.lock_outline, size: 18),
                      onTap: () => _openLetter(oaId(row['letter_id'])),
                    ),
                ],
              ),
      ),
    );
  }

  String _line(Map<String, dynamic> row, Object? when) {
    final date = HesabixDateUtils.formatApiDateForDisplay(
      when,
      widget.calendarController.isJalali,
      fallback: '',
    );
    final number = '${row['number'] ?? ''}'.trim();
    return [number, date].where((part) => part.isNotEmpty).join(' · ');
  }
}
