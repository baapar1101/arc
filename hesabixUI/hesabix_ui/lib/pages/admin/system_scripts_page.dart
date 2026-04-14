import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../services/admin_scripts_service.dart';
import '../../utils/snackbar_helper.dart';

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
      SnackBarHelper.showError(context, message: 'خطا در بارگذاری اسکریپت‌ها: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startRun(String scriptKey) async {
    if (_isSubmitting) return;
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
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'اجرای اسکریپت در صف قرار گرفت');
      await _refreshRuns();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا در شروع اجرا: $e');
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
      SnackBarHelper.showError(context, message: 'خطا در دریافت جزئیات اجرا: $e');
    }
  }

  Color _statusColor(String status, ColorScheme scheme) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'running':
        return scheme.primary;
      case 'failed':
        return scheme.error;
      case 'cancelled':
        return Colors.orange;
      default:
        return scheme.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('اسکریپت‌های سیستمی'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/user/profile/system-settings'),
        ),
        actions: [
          IconButton(
            onPressed: _refreshRuns,
            icon: const Icon(Icons.refresh),
            tooltip: 'بازخوانی',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('اجرای اسکریپت', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Dry-run (بدون اعمال تغییر)'),
                          value: _dryRun,
                          onChanged: (v) => setState(() => _dryRun = v),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _businessIdController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Business ID (اختیاری)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _limitController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Limit (اختیاری)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._scripts.map((s) {
                          final key = (s['key'] ?? '').toString();
                          return Card(
                            child: ListTile(
                              title: Text((s['title'] ?? key).toString()),
                              subtitle: Text((s['description'] ?? '').toString()),
                              trailing: FilledButton(
                                onPressed: _isSubmitting ? null : () => _startRun(key),
                                child: const Text('اجرا'),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 12),
                        const Divider(),
                        const Text('تاریخچه اجراها', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _runs.length,
                            itemBuilder: (context, index) {
                              final item = _runs[index];
                              final runId = item['id'] as int?;
                              final status = (item['status'] ?? '').toString();
                              return Card(
                                child: ListTile(
                                  onTap: runId != null ? () => _loadRunDetails(runId) : null,
                                  selected: runId != null && runId == _selectedRunId,
                                  title: Text('#${item['id']} - ${item['script_key'] ?? ''}'),
                                  subtitle: Text(
                                    'اسکن: ${item['scanned_count'] ?? 0} | آپدیت: ${item['updated_count'] ?? 0} | خطا: ${item['error_count'] ?? 0}',
                                  ),
                                  trailing: Chip(
                                    label: Text(status),
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
                    padding: const EdgeInsets.all(16),
                    child: _selectedRunDetails == null
                        ? const Center(child: Text('یک اجرا را برای مشاهده جزئیات انتخاب کنید'))
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('جزئیات اجرا #${run['id'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('وضعیت: ${run['status'] ?? '-'}'),
        Text('dry_run: ${run['dry_run'] == true ? 'true' : 'false'}'),
        Text('updated: ${run['updated_count'] ?? 0} / scanned: ${run['scanned_count'] ?? 0}'),
        if ((run['error_text'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('خطا: ${run['error_text']}', style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 12),
        const Text('لاگ اجرا', style: TextStyle(fontWeight: FontWeight.bold)),
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

