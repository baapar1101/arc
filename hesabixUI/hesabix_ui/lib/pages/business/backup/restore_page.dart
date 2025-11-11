import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/backup_service.dart';

enum _RestoreSource { stored, file }

class BusinessRestorePage extends StatefulWidget {
  final int businessId;
  const BusinessRestorePage({super.key, required this.businessId});

  @override
  State<BusinessRestorePage> createState() => _BusinessRestorePageState();
}

class _BusinessRestorePageState extends State<BusinessRestorePage> {
  final BackupService _service = BackupService();
  bool _loading = true;
  String? _error;
  String? _selectedBackupId;
  List<Map<String, dynamic>> _items = const [];
  bool _restoring = false;
  String _mode = 'new_business';
  String? _currentJobId;
  int _jobProgress = 0;
  String? _jobMessage;
  bool _jobRunning = false;
  Timer? _pollTimer;
  String? _selectedFilePath;
  String? _selectedFileName;
  _RestoreSource _source = _RestoreSource.stored;

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

  Future<void> _restore() async {
    final t = AppLocalizations.of(context);
    if (!_canSubmit) {
      _showSnackBar(t.error);
      return;
    }
    setState(() {
      _restoring = true;
    });
    try {
      late final String jobId;
      if (_source == _RestoreSource.file && _selectedFilePath != null) {
        jobId = await _service.startRestoreFromFileAsync(
          widget.businessId,
          _selectedFilePath!,
          filename: _selectedFileName,
          mode: _mode,
        );
        _startJob(jobId, t.inProgress);
      } else if (_selectedBackupId != null) {
        jobId = await _service.startRestoreAsync(
          widget.businessId,
          _selectedBackupId!,
          mode: _mode,
        );
        _startJob(jobId, t.inProgress);
      } else {
        throw Exception(t.error);
      }
      _startPollingJob();
      _showSnackBar(t.inProgress);
    } catch (e) {
      _showSnackBar('$e');
    } finally {
      if (mounted) {
        setState(() {
          _restoring = false;
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
          _showSnackBar(AppLocalizations.of(context).operationSuccessful);
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.dataRestore),
      ),
      body: _buildBody(t),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: FilledButton.icon(
          onPressed: _restoring || !_canSubmit ? null : _restore,
          icon: _restoring ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.restore),
          label: Text(t.restore),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  bool get _canSubmit {
    if (_jobRunning) return false;
    if (_source == _RestoreSource.file) {
      return _selectedFilePath != null && _selectedFilePath!.isNotEmpty;
    }
    return _selectedBackupId != null && _selectedBackupId!.isNotEmpty;
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
          Text(t.dataRestoreDescription, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (_jobRunning || _jobMessage != null) _buildJobStatusCard(t),
          const SizedBox(height: 16),
          _buildSourceSelector(t),
          const SizedBox(height: 16),
          if (_source == _RestoreSource.stored) _buildStoredBackupsCard(t) else _buildFilePickerCard(t),
          const SizedBox(height: 16),
          _buildModeSelectorCard(t),
        ],
      ),
    );
  }

  Widget _buildJobStatusCard(AppLocalizations t) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final message = _jobMessage ?? t.inProgress;
    return Card(
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_jobRunning ? Icons.sync : Icons.check_circle, color: _jobRunning ? colorScheme.primary : colorScheme.secondary),
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

  Widget _buildSourceSelector(AppLocalizations t) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.restore, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SegmentedButton<_RestoreSource>(
              segments: [
                ButtonSegment<_RestoreSource>(
                  value: _RestoreSource.stored,
                  label: Text(t.dataBackup),
                  icon: const Icon(Icons.cloud),
                ),
                ButtonSegment<_RestoreSource>(
                  value: _RestoreSource.file,
                  label: Text(t.restoreFile),
                  icon: const Icon(Icons.upload_file),
                ),
              ],
              selected: {_source},
              onSelectionChanged: (value) {
                if (value.isEmpty) return;
                setState(() {
                  _source = value.first;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoredBackupsCard(AppLocalizations t) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedBackupId,
              isExpanded: true,
              items: _items
                  .map(
                    (e) => DropdownMenuItem<String>(
                      value: e['id'] as String,
                      child: Text((e['filename'] as String?) ?? 'backup.hbx', overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: _jobRunning
                  ? null
                  : (v) {
                      setState(() {
                        _selectedBackupId = v;
                        _selectedFilePath = null;
                        _selectedFileName = null;
                      });
                    },
              decoration: InputDecoration(labelText: t.dataBackup),
            ),
            if (_items.isEmpty) ...[
              const SizedBox(height: 12),
              Text(t.noDataFound, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilePickerCard(AppLocalizations t) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file),
              label: Text(_selectedFileName ?? t.selectBackupFile),
              onPressed: _jobRunning
                  ? null
                  : () async {
                      try {
                        final res = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: const ['hbx', 'zip'],
                          withData: false,
                        );
                        if (res != null && res.files.isNotEmpty) {
                          final f = res.files.first;
                          setState(() {
                            _selectedFilePath = f.path;
                            _selectedFileName = f.name;
                            _selectedBackupId = null;
                            _source = _RestoreSource.file;
                          });
                        }
                      } catch (e) {
                        _showSnackBar('$e');
                      }
                    },
            ),
            if (_selectedFilePath != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedFileName ?? '',
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: t.clear,
                    onPressed: _jobRunning
                        ? null
                        : () {
                            setState(() {
                              _selectedFilePath = null;
                              _selectedFileName = null;
                            });
                          },
                    icon: const Icon(Icons.clear),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelectorCard(AppLocalizations t) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioListTile<String>(
              value: 'new_business',
              groupValue: _mode,
              onChanged: _jobRunning ? null : (v) => setState(() => _mode = v ?? 'new_business'),
              title: Text(t.restoreModeNewBusiness),
            ),
            RadioListTile<String>(
              value: 'replace',
              groupValue: _mode,
              onChanged: _jobRunning ? null : (v) => setState(() => _mode = v ?? 'replace'),
              title: Text(t.restoreModeReplace),
            ),
          ],
        ),
      ),
    );
  }
}


