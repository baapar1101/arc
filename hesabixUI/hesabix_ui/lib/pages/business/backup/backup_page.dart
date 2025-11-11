import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/backup_service.dart';
import 'package:file_saver/file_saver.dart';

class BusinessBackupPage extends StatefulWidget {
  final int businessId;
  const BusinessBackupPage({super.key, required this.businessId});

  @override
  State<BusinessBackupPage> createState() => _BusinessBackupPageState();
}

class _BusinessBackupPageState extends State<BusinessBackupPage> {
  final BackupService _service = BackupService();
  bool _loading = true;
  bool _creating = false;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  String? _currentJobId;
  int _jobProgress = 0;
  String? _jobMessage;
  bool _jobRunning = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.listBackups(widget.businessId);
      setState(() {
        _items = items;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _createBackup() async {
    setState(() {
      _creating = true;
    });
    try {
      final jobId = await _service.startBackupAsync(widget.businessId);
      _startJob(jobId, AppLocalizations.of(context).inProgress);
      _startPollingJob();
      if (mounted) {
        _showSnackBar(AppLocalizations.of(context).inProgress);
      }
    } catch (e) {
      _showSnackBar('$e');
    } finally {
      if (mounted) {
        setState(() {
          _creating = false;
        });
      }
    }
  }

  void _startPollingJob() {
    _pollTimer?.cancel();
    if (_currentJobId == null || _currentJobId!.isEmpty) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final st = await _service.getJobStatus(_currentJobId!);
        setState(() {
          _jobProgress = (st['progress'] as int?) ?? _jobProgress;
          _jobMessage = (st['message'] as String?) ?? _jobMessage;
        });
        final state = (st['state'] as String?) ?? '';
        if (state == 'succeeded') {
          timer.cancel();
          setState(() {
            _jobRunning = false;
          });
          await _load();
          if (mounted) {
            _showSnackBar(AppLocalizations.of(context).operationSuccessful);
          }
        } else if (state == 'failed') {
          timer.cancel();
          setState(() {
            _jobRunning = false;
          });
          final err = (st['error'] as String?) ?? AppLocalizations.of(context).error;
          _showSnackBar(err);
        }
      } catch (_) {}
    });
  }

  Future<void> _download(String id, String filename) async {
    try {
      final bytes = await _service.downloadBackup(widget.businessId, id);
      await FileSaver.instance.saveFile(
        name: filename,
        bytes: bytes,
        ext: 'hbx',
        mimeType: MimeType.other,
      );
    } catch (e) {
      _showSnackBar('$e');
    }
  }

  Future<void> _delete(String id) async {
    final t = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.delete),
        content: Text(t.deleteConfirmMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.dialogClose)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.delete)),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _service.deleteBackup(widget.businessId, id);
      await _load();
    } catch (e) {
      _showSnackBar('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.dataBackup),
      ),
      body: _buildBody(t),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: FilledButton.icon(
          onPressed: _creating || _jobRunning ? null : _createBackup,
          icon: _creating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.backup),
          label: Text(t.backup),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startJob(String jobId, String message) {
    setState(() {
      _currentJobId = jobId;
      _jobRunning = true;
      _jobProgress = 0;
      _jobMessage = message;
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildBody(AppLocalizations t) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          Text(t.dataBackupDescription, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (_jobRunning || _jobMessage != null) _buildJobStatusCard(t),
          if (_items.isEmpty)
            _buildEmptyState(t)
          else ..._items.map((it) => _buildBackupCard(t, it)).toList(),
        ],
      ),
    );
  }

  Widget _buildJobStatusCard(AppLocalizations t) {
    final theme = Theme.of(context);
    final isActive = _jobRunning;
    final colorScheme = theme.colorScheme;
    final message = _jobMessage ?? t.inProgress;
    return Card(
      color: isActive ? colorScheme.surfaceContainerHighest : colorScheme.surfaceVariant.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isActive ? Icons.sync : Icons.check_circle, color: isActive ? colorScheme.primary : colorScheme.secondary),
                const SizedBox(width: 12),
                Expanded(child: Text(message, style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _jobProgress > 0 ? _jobProgress / 100.0 : null),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations t) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.archive_outlined, size: 48),
            const SizedBox(height: 12),
            Text(t.noDataFound, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              t.dataBackupDialogContent,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupCard(AppLocalizations t, Map<String, dynamic> data) {
    final id = data['id'] as String? ?? '';
    final name = (data['filename'] as String?) ?? 'backup.hbx';
    final size = (data['size'] as int?) ?? 0;
    final createdAt = (data['created_at'] as String?) ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.archive),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('$createdAt • ${_formatBytes(size)}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _download(id, name),
                  icon: const Icon(Icons.download),
                  label: Text(t.downloadTemplate),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _delete(id),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(t.delete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(value < 10 && unitIndex > 0 ? 1 : 0)} ${units[unitIndex]}';
  }
}


