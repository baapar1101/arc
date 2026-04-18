import 'dart:async';


import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/business_ftp_backup_service.dart';
import 'package:hesabix_ui/services/errors/api_error.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

class BusinessFtpBackupSettingsPage extends StatefulWidget {
  final int businessId;

  const BusinessFtpBackupSettingsPage({super.key, required this.businessId});

  @override
  State<BusinessFtpBackupSettingsPage> createState() => _BusinessFtpBackupSettingsPageState();
}

class _BusinessFtpBackupSettingsPageState extends State<BusinessFtpBackupSettingsPage> {
  final BusinessFtpBackupService _service = BusinessFtpBackupService();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '21');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _remotePath = TextEditingController(text: '/');

  bool _passive = true;
  bool _useFtps = false;
  bool _useSftp = false;
  bool _configured = false;
  bool _hasPassword = false;
  String? _updatedAt;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  String? _jobId;
  bool _jobRunning = false;
  int _jobProgress = 0;
  String? _jobMessage;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _remotePath.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getSettings(widget.businessId);
      final configured = data['configured'] == true;
      setState(() {
        _configured = configured;
        if (configured) {
          _host.text = (data['host'] as String?) ?? '';
          _port.text = '${data['port'] ?? 21}';
          _username.text = (data['username'] as String?) ?? '';
          _remotePath.text = (data['remote_path'] as String?) ?? '/';
          _passive = data['passive'] != false;
          _useFtps = data['use_ftps'] == true;
          _useSftp = data['use_sftp'] == true;
          _hasPassword = data['has_password'] == true;
          _updatedAt = data['updated_at'] as String?;
        } else {
          _host.clear();
          _port.text = '21';
          _username.clear();
          _password.clear();
          _remotePath.text = '/';
          _passive = true;
          _useFtps = false;
          _useSftp = false;
          _hasPassword = false;
          _updatedAt = null;
        }
      });
    } catch (e) {
      setState(() {
        _error = _formatError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _formatError(Object e) {
    if (e is DioException && e.error is ApiErrorDetails) {
      return (e.error! as ApiErrorDetails).message ?? e.toString();
    }
    return e.toString();
  }

  Map<String, dynamic> _readJobMeta(Map<String, dynamic> st) {
    final meta = st['meta'];
    if (meta is Map) {
      return Map<String, dynamic>.from(meta);
    }
    return const {};
  }

  int? _readProgress(Map<String, dynamic> st) {
    final meta = _readJobMeta(st);
    final p = meta['progress'] ?? st['progress'];
    if (p is int) return p;
    if (p is num) return p.toInt();
    return null;
  }

  String? _readMessage(Map<String, dynamic> st) {
    final meta = _readJobMeta(st);
    return (meta['message'] as String?) ?? (st['message'] as String?);
  }

  void _startPolling(void Function(Map<String, dynamic> st) onDone) {
    _pollTimer?.cancel();
    if (_jobId == null || _jobId!.isEmpty) return;
    final ctx = context;
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final st = await _service.getJobStatus(_jobId!);
        if (!ctx.mounted) return;
        final prog = _readProgress(st);
        final msg = _readMessage(st);
        setState(() {
          _jobProgress = prog ?? _jobProgress;
          if (msg != null && msg.isNotEmpty) {
            _jobMessage = msg;
          }
        });
        final state = (st['state'] as String?) ?? '';
        if (state == 'succeeded' || state == 'finished') {
          timer.cancel();
          setState(() {
            _jobRunning = false;
            _jobId = null;
            _jobMessage = null;
          });
          if (ctx.mounted) {
            onDone(st);
          }
        } else if (state == 'failed') {
          timer.cancel();
          setState(() {
            _jobRunning = false;
            _jobId = null;
            _jobMessage = null;
          });
          if (!ctx.mounted) return;
          final err = st['error'];
          final text = err is Map ? (err['message'] as String?) ?? '$err' : '$err';
          SnackBarHelper.showError(ctx, message: text.isNotEmpty ? text : AppLocalizations.of(ctx).error);
        }
      } catch (e) {
        timer.cancel();
        if (!ctx.mounted) return;
        setState(() {
          _jobRunning = false;
          _jobId = null;
          _jobMessage = null;
        });
        SnackBarHelper.showError(ctx, message: _formatError(e));
      }
    });
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final port = int.tryParse(_port.text.trim()) ?? 21;
    if (_host.text.trim().isEmpty || _username.text.trim().isEmpty) {
      SnackBarHelper.showError(context, message: t.error);
      return;
    }
    if (!_configured && _password.text.trim().isEmpty) {
      SnackBarHelper.showError(context, message: '${t.ftpPassword} ${t.required}');
      return;
    }
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'host': _host.text.trim(),
        'port': port,
        'username': _username.text.trim(),
        'remote_path': _remotePath.text.trim().isEmpty ? '/' : _remotePath.text.trim(),
        'passive': _passive,
        'use_ftps': _useSftp ? false : _useFtps,
        'use_sftp': _useSftp,
      };
      final pw = _password.text.trim();
      if (pw.isNotEmpty) {
        body['password'] = pw;
      } else {
        body['password'] = null;
      }
      await _service.saveSettings(widget.businessId, body);
      if (!mounted) return;
      _password.clear();
      SnackBarHelper.show(context, message: t.operationSuccessful);
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: _formatError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.ftpDeleteSettingsConfirmTitle),
        content: Text(t.ftpDeleteSettingsConfirmMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.dialogClose)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.delete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteSettings(widget.businessId);
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.operationSuccessful);
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: _formatError(e));
      }
    }
  }

  Future<void> _runTestJob() async {
    final t = AppLocalizations.of(context);
    final useSaved = _configured && _password.text.trim().isEmpty;
    if (!useSaved) {
      if (_host.text.trim().isEmpty || _username.text.trim().isEmpty || _password.text.trim().isEmpty) {
        SnackBarHelper.showError(context, message: '${t.ftpPassword} ${t.required}');
        return;
      }
    }
    setState(() {
      _jobRunning = true;
      _jobProgress = 0;
      _jobMessage = t.jobFtpTestStarting;
    });
    try {
      final port = int.tryParse(_port.text.trim()) ?? 21;
      final Map<String, dynamic> body;
      if (useSaved) {
        body = {'use_saved': true};
      } else {
        body = {
          'use_saved': false,
          'host': _host.text.trim(),
          'port': port,
          'username': _username.text.trim(),
          'password': _password.text.trim(),
          'remote_path': _remotePath.text.trim().isEmpty ? '/' : _remotePath.text.trim(),
          'passive': _passive,
          'use_ftps': _useSftp ? false : _useFtps,
          'use_sftp': _useSftp,
        };
      }
      final jobId = await _service.startTestJob(widget.businessId, body);
      if (!mounted) return;
      setState(() => _jobId = jobId);
      _startPolling((st) {
        final raw = st['result'];
        final result = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
        _showResultDialog(t.ftpTestResultTitle, _describeTestResult(t, result));
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _jobRunning = false;
          _jobMessage = null;
        });
        SnackBarHelper.showError(context, message: _formatError(e));
      }
    }
  }

  String _describeTestResult(AppLocalizations t, Map<String, dynamic> r) {
    if (r['ok'] == true) {
      final cwd = r['cwd'] ?? '';
      final n = r['sample_count'];
      final lines = StringBuffer()
        ..writeln(t.jobFtpTestCompleted)
        ..writeln('${t.ftpRemotePath}: $cwd');
      if (n is int && n > 0) {
        lines.writeln(t.ftpTestResultSampleCount(n));
      } else if (n is num && n.toInt() > 0) {
        lines.writeln(t.ftpTestResultSampleCount(n.toInt()));
      }
      return lines.toString().trim();
    }
    return r.toString();
  }

  Future<void> _runUsageScan() async {
    final t = AppLocalizations.of(context);
    if (!_configured) {
      SnackBarHelper.showError(context, message: t.ftpNotConfigured);
      return;
    }
    setState(() {
      _jobRunning = true;
      _jobProgress = 0;
      _jobMessage = t.jobFtpUsageStarting;
    });
    try {
      final jobId = await _service.startUsageScanJob(widget.businessId);
      if (!mounted) return;
      setState(() => _jobId = jobId);
      _startPolling((st) {
        final raw = st['result'];
        final result = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
        final bytes = (result['total_bytes'] as num?)?.toInt() ?? 0;
        final files = (result['file_count'] as num?)?.toInt() ?? 0;
        final truncated = result['truncated'] == true;
        final scannedAt = result['scanned_at'] as String?;
        final buf = StringBuffer()
          ..writeln('${t.ftpUsageTotal}: ${_formatBytes(t, bytes)}')
          ..writeln('${t.ftpUsageFiles}: $files');
        if (truncated) {
          buf.writeln(t.ftpUsageTruncated);
        }
        if (scannedAt != null && scannedAt.isNotEmpty) {
          buf.writeln('${t.ftpLastScan}: $scannedAt');
        }
        _showResultDialog(t.ftpScanUsage, buf.toString());
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _jobRunning = false;
          _jobMessage = null;
        });
        SnackBarHelper.showError(context, message: _formatError(e));
      }
    }
  }

  String _formatBytes(AppLocalizations t, int bytes) {
    if (bytes <= 0) {
      return '0 ${t.byteUnitB}';
    }
    final units = [t.byteUnitB, t.byteUnitKB, t.byteUnitMB, t.byteUnitGB, t.byteUnitTB];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(value < 10 && unitIndex > 0 ? 1 : 0)} ${units[unitIndex]}';
  }

  void _showResultDialog(String title, String body) {
    final t = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: SelectableText(body)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.ftpClose)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.ftpBackupSettingsTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/business/${widget.businessId}/dashboard');
            }
          },
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Text(t.ftpBackupSettingsDescription, style: Theme.of(context).textTheme.bodyLarge),
                    if (!_useFtps && !_useSftp) ...[
                      const SizedBox(height: 12),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
                              const SizedBox(width: 8),
                              Expanded(child: Text(t.ftpInsecureWarning, style: Theme.of(context).textTheme.bodyMedium)),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_updatedAt != null && _updatedAt!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('${t.ftpSettingsUpdatedAt}: $_updatedAt', style: Theme.of(context).textTheme.bodySmall),
                    ],
                    if (!_configured)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(t.ftpNotConfigured, style: Theme.of(context).textTheme.labelLarge),
                      ),
                    if (_jobRunning || (_jobMessage != null && _jobMessage!.isNotEmpty)) ...[
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_jobMessage ?? t.inProgress, style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(value: _jobProgress > 0 ? _jobProgress / 100.0 : null),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    TextField(
                      controller: _host,
                      decoration: InputDecoration(labelText: t.ftpHost, border: const OutlineInputBorder()),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _port,
                      decoration: InputDecoration(labelText: t.ftpPort, border: const OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _username,
                      decoration: InputDecoration(labelText: t.ftpUsername, border: const OutlineInputBorder()),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: t.ftpPassword,
                        helperText: _hasPassword ? t.ftpPasswordLeaveEmptyHint : null,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _remotePath,
                      decoration: InputDecoration(labelText: t.ftpRemotePath, border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: Text(t.ftpUseSftp),
                      value: _useSftp,
                      onChanged: _saving || _jobRunning
                          ? null
                          : (v) {
                              setState(() {
                                _useSftp = v;
                                if (v) {
                                  _useFtps = false;
                                  if ((_port.text.trim().isEmpty) || _port.text.trim() == '21') {
                                    _port.text = '22';
                                  }
                                }
                              });
                            },
                    ),
                    SwitchListTile(
                      title: Text(t.ftpPassiveMode),
                      value: _passive,
                      onChanged: _saving || _jobRunning || _useSftp ? null : (v) => setState(() => _passive = v),
                    ),
                    SwitchListTile(
                      title: Text(t.ftpUseFtps),
                      value: _useFtps,
                      onChanged: _saving || _jobRunning || _useSftp
                          ? null
                          : (v) => setState(() => _useFtps = v),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving || _jobRunning ? null : _save,
                      icon: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined),
                      label: Text(t.ftpSaveSettings),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving || _jobRunning ? null : _runTestJob,
                            icon: const Icon(Icons.link),
                            label: Text(t.ftpTestConnection),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving || _jobRunning || !_configured ? null : _runUsageScan,
                            icon: const Icon(Icons.analytics_outlined),
                            label: Text(t.ftpScanUsage),
                          ),
                        ),
                      ],
                    ),
                    if (_configured) ...[
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: _saving || _jobRunning ? null : _delete,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(t.ftpDeleteSettings),
                      ),
                    ],
                  ],
                ),
    );
  }
}
