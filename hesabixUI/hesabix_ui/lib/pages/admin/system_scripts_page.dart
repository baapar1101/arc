import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

class SystemScriptsPage extends StatefulWidget {
  const SystemScriptsPage({super.key});

  @override
  State<SystemScriptsPage> createState() => _SystemScriptsPageState();
}

class _SystemScriptsPageState extends State<SystemScriptsPage> {
  final AdminScriptsService _service = AdminScriptsService(ApiClient());
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _dryRun = true;
  final TextEditingController _businessIdController = TextEditingController();
  final TextEditingController _limitController = TextEditingController();

  List<Map<String, dynamic>> _scripts = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _runs = <Map<String, dynamic>>[];
  int? _selectedRunId;
  Map<String, dynamic>? _selectedRunDetails;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _businessIdController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() => _isLoading = true);
    try {
      final scripts = await _service.listScripts();
      final runsData = await _service.listRuns(take: 50, skip: 0);
      final runs = ((runsData['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _scripts = scripts;
        _runs = runs;
      });
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message:
            '${adminTx(context, 'خطا در بارگذاری اسکریپت‌ها', 'Could not load scripts')}: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startRun(String scriptKey) async {
    if (_isSubmitting) return;
    if (!_dryRun) {
      final controller = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          var phraseError = '';
          return StatefulBuilder(
            builder: (context, setLocal) {
              return AlertDialog(
                title: Text(adminTx(context, 'تأیید اجرای واقعی', 'Confirm a real run')),
                content: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: adminTx(context, 'برای اجرا RUN را بنویسید', 'Type RUN to execute'),
                    errorText: phraseError.isEmpty ? null : phraseError,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(adminTx(context, 'انصراف', 'Cancel')),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (controller.text.trim() != 'RUN') {
                        setLocal(() => phraseError = adminTx(context, 'عبارت باید دقیقاً RUN باشد', 'The phrase must be exactly RUN'));
                        return;
                      }
                      Navigator.pop(dialogContext, true);
                    },
                    child: Text(adminTx(context, 'اجرا', 'Run')),
                  ),
                ],
              );
            },
          );
        },
      );
      controller.dispose();
      if (confirmed != true) return;
    }
    setState(() => _isSubmitting = true);
    try {
      final params = <String, dynamic>{};
      final businessIdText = _businessIdController.text.trim();
      final limitText = _limitController.text.trim();
      final parsedBusinessId = int.tryParse(businessIdText);
      final parsedLimit = int.tryParse(limitText);
      if (parsedBusinessId != null && parsedBusinessId > 0) {
        params['business_id'] = parsedBusinessId;
      }
      if (parsedLimit != null && parsedLimit > 0) {
        params['limit'] = parsedLimit;
      }
      await _service.createRun(
        scriptKey: scriptKey,
        dryRun: _dryRun,
        params: params,
        confirmation: _dryRun ? null : 'RUN',
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: adminTx(context, 'اجرای اسکریپت در صف قرار گرفت', 'Script run queued'));
      await _refreshRuns();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: '${adminTx(context, 'خطا در شروع اجرا', 'Could not start the run')}: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _refreshRuns() async {
    try {
      final runsData = await _service.listRuns(take: 50, skip: 0);
      final runs = ((runsData['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _runs = runs;
      });
      if (_selectedRunId != null) {
        await _loadRunDetails(_selectedRunId!);
      }
    } catch (_) {}
  }

  Future<void> _loadRunDetails(int runId) async {
    try {
      final details = await _service.getRunDetails(runId);
      if (!mounted) return;
      setState(() {
        _selectedRunId = runId;
        _selectedRunDetails = details;
      });
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message:
            '${adminTx(context, 'خطا در دریافت جزئیات اجرا', 'Could not load run details')}: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  Color _statusColor(String status, ColorScheme scheme) {
    switch (status) {
      case 'completed':
        return SemanticColorResolver.positive(context);
      case 'running':
        return scheme.primary;
      case 'failed':
        return scheme.error;
      case 'cancelled':
        return SemanticColorResolver.warning(context);
      default:
        return scheme.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hub = context.settingsHub;
    final textTheme = Theme.of(context).textTheme;
    return AdminCompactScaffold(
      title: adminTx(context, 'اسکریپت‌های سیستمی', 'System scripts'),
      actions: [
        IconButton(
          onPressed: _refreshRuns,
          icon: const Icon(Icons.refresh, size: 20),
          tooltip: adminTx(context, 'بازخوانی', 'Refresh'),
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: hub.pagePadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          adminTx(context, 'اجرای اسکریپت', 'Run a script'),
                          style: hub.cardTitleStyle(textTheme, color: scheme.onSurface),
                        ),
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            adminTx(context, 'اجرای آزمایشی (بدون اعمال تغییر)', 'Dry run (no changes)'),
                            style: hub.cardSubtitleStyle(textTheme, color: scheme.onSurface),
                          ),
                          value: _dryRun,
                          onChanged: (v) => setState(() => _dryRun = v),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _businessIdController,
                                keyboardType: TextInputType.number,
                                style: hub.cardSubtitleStyle(textTheme, color: scheme.onSurface),
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: adminTx(context, 'شناسه کسب‌وکار (اختیاری)', 'Business ID (optional)'),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _limitController,
                                keyboardType: TextInputType.number,
                                style: hub.cardSubtitleStyle(textTheme, color: scheme.onSurface),
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: adminTx(context, 'سقف (اختیاری)', 'Limit (optional)'),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ..._scripts.map((s) {
                          final key = (s['key'] ?? '').toString();
                          return Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                (s['title'] ?? key).toString(),
                                style: hub.cardTitleStyle(textTheme, color: scheme.onSurface),
                              ),
                              subtitle: Text(
                                (s['description'] ?? '').toString(),
                                style: hub.cardSubtitleStyle(textTheme, color: scheme.onSurfaceVariant),
                              ),
                              trailing: FilledButton(
                                onPressed: _isSubmitting ? null : () => _startRun(key),
                                child: Text(adminTx(context, 'اجرا', 'Run')),
                              ),
                            ),
                          );
                        }),
                        const Divider(),
                        Text(
                          adminTx(context, 'تاریخچه اجراها', 'Run history'),
                          style: hub.cardTitleStyle(textTheme, color: scheme.onSurface),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _runs.length,
                            itemBuilder: (context, index) {
                              final item = _runs[index];
                              final runId = item['id'] as int?;
                              final status = (item['status'] ?? '').toString();
                              return Card(
                                margin: const EdgeInsets.only(bottom: 4),
                                child: ListTile(
                                  dense: true,
                                  onTap: runId != null ? () => _loadRunDetails(runId) : null,
                                  selected: runId != null && runId == _selectedRunId,
                                  title: Text(
                                    '#${item['id']} · ${item['script_key'] ?? ''}',
                                    style: hub.cardTitleStyle(textTheme, color: scheme.onSurface),
                                  ),
                                  subtitle: Text(
                                    '${adminTx(context, 'اسکن', 'Scanned')}: ${item['scanned_count'] ?? 0} · ${adminTx(context, 'به‌روزرسانی', 'Updated')}: ${item['updated_count'] ?? 0} · ${adminTx(context, 'خطا', 'Errors')}: ${item['error_count'] ?? 0}',
                                    style: hub.cardSubtitleStyle(textTheme, color: scheme.onSurfaceVariant),
                                  ),
                                  trailing: Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(status, style: const TextStyle(fontSize: 11)),
                                    backgroundColor: _statusColor(status, scheme).withValues(alpha: 0.15),
                                    labelStyle: TextStyle(color: _statusColor(status, scheme)),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: hub.pagePadding,
                    child: _selectedRunDetails == null
                        ? Center(
                            child: Text(
                              adminTx(context, 'یک اجرا را برای مشاهده جزئیات انتخاب کنید', 'Select a run to see details'),
                              style: hub.cardSubtitleStyle(textTheme, color: scheme.onSurfaceVariant),
                            ),
                          )
                        : _buildDetailsPanel(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDetailsPanel() {
    final details = _selectedRunDetails!;
    final run = Map<String, dynamic>.from(details['run'] as Map? ?? const {});
    final logs = ((details['logs'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final hub = context.settingsHub;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${adminTx(context, 'جزئیات اجرا', 'Run')} #${run['id'] ?? ''}',
          style: hub.cardTitleStyle(textTheme, color: scheme.onSurface),
        ),
        const SizedBox(height: 6),
        Text(
          '${adminTx(context, 'وضعیت', 'Status')}: ${run['status'] ?? '-'}',
          style: hub.cardSubtitleStyle(textTheme, color: scheme.onSurface),
        ),
        Text(
          '${adminTx(context, 'آزمایشی', 'Dry run')}: ${run['dry_run'] == true ? adminTx(context, 'بله', 'Yes') : adminTx(context, 'خیر', 'No')}',
          style: hub.cardSubtitleStyle(textTheme, color: scheme.onSurface),
        ),
        Text(
          '${adminTx(context, 'به‌روزرسانی', 'Updated')}: ${run['updated_count'] ?? 0} / ${adminTx(context, 'اسکن', 'Scanned')}: ${run['scanned_count'] ?? 0}',
          style: hub.cardSubtitleStyle(textTheme, color: scheme.onSurface),
        ),
        if ((run['error_text'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${adminTx(context, 'خطا', 'Error')}: ${run['error_text']}',
              style: hub.cardSubtitleStyle(textTheme, color: SemanticColorResolver.negative(context)),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          adminTx(context, 'لاگ اجرا', 'Run log'),
          style: hub.cardTitleStyle(textTheme, color: scheme.onSurface),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              return ListTile(
                dense: true,
                title: Text((log['message'] ?? '').toString()),
                subtitle: Text('${log['level'] ?? ''} - ${log['created_at'] ?? ''}'),
              );
            },
          ),
        ),
      ],
    );
  }
}

