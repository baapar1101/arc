import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart';
import '../../../services/office_automation_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/office_automation/oa_ui.dart';
import 'oa_process_designer_page.dart';

class OaProcessesPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const OaProcessesPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<OaProcessesPage> createState() => _OaProcessesPageState();
}

class _OaProcessesPageState extends State<OaProcessesPage> {
  final OfficeAutomationService _svc = OfficeAutomationService();
  bool _loading = true;
  List<Map<String, dynamic>> _positions = [];
  int? _positionId;
  List<Map<String, dynamic>> _versions = [];
  List<Map<String, dynamic>> _tasks = [];

  bool get _canAdmin =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('office_automation', 'admin');

  bool get _canRefer =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('office_automation', 'refer');

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
      final versions = await _svc.listProcessVersions(businessId: widget.businessId);
      final tasks = active == null
          ? <Map<String, dynamic>>[]
          : await _svc.listProcessTasks(businessId: widget.businessId, positionId: active);
      if (!mounted) return;
      setState(() {
        _positions = positions;
        _positionId = active;
        _versions = versions;
        _tasks = tasks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _start(int versionId) async {
    if (_positionId == null || !_canRefer) return;
    try {
      await _svc.startProcess(businessId: widget.businessId, versionId: versionId, positionId: _positionId!);
      if (mounted) SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).oaStartProcess);
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _publish() async {
    final t = AppLocalizations.of(context);
    final name = TextEditingController();
    final label = TextEditingController();
    Map<String, dynamic>? assignee;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(t.oaPublishProcess),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: InputDecoration(labelText: t.oaProcessName, border: const OutlineInputBorder())),
                const SizedBox(height: 8),
                OaPositionPicker(
                  businessId: widget.businessId,
                  label: t.oaActingAs,
                  value: assignee,
                  onChanged: (v) => setLocal(() => assignee = v),
                ),
                const SizedBox(height: 8),
                TextField(controller: label, decoration: InputDecoration(labelText: t.oaFormLabel, border: const OutlineInputBorder())),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
          ],
        ),
      ),
    );
    final assigneeId = oaId(assignee?['id']);
    final processName = name.text.trim();
    final formLabel = label.text.trim();
    name.dispose();
    label.dispose();
    if (ok != true || processName.isEmpty || assigneeId == null) return;
    try {
      await _svc.publishLinearProcess(
        businessId: widget.businessId,
        name: processName,
        assigneePositionId: assigneeId,
        formLabel: formLabel,
      );
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _complete(Map<String, dynamic> task) async {
    if (_positionId == null) return;
    final t = AppLocalizations.of(context);
    final form = task['form'];
    final fields = form is List ? form.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
    final controllers = {for (final field in fields) '${field['key']}': TextEditingController()};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${task['name'] ?? t.oaCompleteTask}'),
        content: SizedBox(
          width: 420,
          child: fields.isEmpty
              ? Text(t.oaCompleteTask)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final field in fields) ...[
                      TextField(
                        controller: controllers['${field['key']}'],
                        decoration: InputDecoration(
                          labelText: '${field['label'] ?? field['key']}',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.oaCompleteTask)),
        ],
      ),
    );
    final payload = {for (final entry in controllers.entries) entry.key: entry.value.text.trim()};
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (ok != true) return;
    final taskId = oaId(task['id']);
    if (taskId == null) return;
    try {
      await _svc.completeProcessTask(
        businessId: widget.businessId,
        taskId: taskId,
        positionId: _positionId!,
        form: payload,
      );
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.oaProcesses),
        actions: [
          if (_canAdmin)
            IconButton(
              tooltip: t.oaProcessDesigner,
              icon: const Icon(Icons.account_tree_outlined),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OaProcessDesignerPage(businessId: widget.businessId),
                  ),
                );
                if (mounted) await _load();
              },
            ),
          if (_canAdmin) IconButton(tooltip: t.oaPublishProcess, icon: const Icon(Icons.linear_scale), onPressed: _publish),
          IconButton(tooltip: t.refresh, icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_positions.isNotEmpty)
                  DropdownButtonFormField<int>(
                    initialValue: _positionId,
                    decoration: InputDecoration(labelText: t.oaActingAs, border: const OutlineInputBorder()),
                    items: [
                      for (final p in _positions)
                        if (oaId(p['id']) != null) DropdownMenuItem(value: oaId(p['id']), child: Text(oaPositionLabel(p))),
                    ],
                    onChanged: (id) {
                      setState(() => _positionId = id);
                      _load();
                    },
                  ),
                const SizedBox(height: 16),
                OaSectionCard(
                  title: t.oaProcessTasks,
                  child: _tasks.isEmpty
                      ? Text(t.oaEmptyFolder)
                      : Column(
                          children: [
                            for (final task in _tasks)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('${task['name'] ?? ''}'),
                                subtitle: Text(_due(task['due_at'])),
                                trailing: _canRefer ? FilledButton(onPressed: () => _complete(task), child: Text(t.oaCompleteTask)) : null,
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                OaSectionCard(
                  title: t.oaProcesses,
                  child: _versions.isEmpty
                      ? Text(t.oaEmptyFolder)
                      : Column(
                          children: [
                            for (final version in _versions)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('${version['name'] ?? ''}'),
                                subtitle: Text('${version['version_no'] ?? ''}'),
                                trailing: _canRefer && _positionId != null
                                    ? OutlinedButton(
                                        onPressed: () => _start(oaId(version['id']) ?? 0),
                                        child: Text(t.oaStartProcess),
                                      )
                                    : null,
                              ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  String _due(Object? value) {
    if (value == null) return '';
    return HesabixDateUtils.formatApiDateForDisplay(value, widget.calendarController.isJalali, fallback: '');
  }
}
