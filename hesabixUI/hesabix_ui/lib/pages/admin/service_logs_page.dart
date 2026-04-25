import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/api_client.dart';
import '../../services/system_services_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/loading_indicator.dart';

enum _SeverityFilter { all, errorsOnly, warningsUp }

class ServiceLogsPage extends StatefulWidget {
  const ServiceLogsPage({super.key});

  @override
  State<ServiceLogsPage> createState() => _ServiceLogsPageState();
}

class _ServiceLogsPageState extends State<ServiceLogsPage> with WidgetsBindingObserver {
  final _service = SystemServicesService(ApiClient());
  final _searchController = TextEditingController();
  final _restartConfirmController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<String> _availableServices = const [
    'hesabix-api',
    'hesabix-rq-worker',
    'hesabix-notification-moderation',
  ];

  String _selectedService = 'hesabix-api';
  List<Map<String, dynamic>> _logs = [];
  Map<String, dynamic>? _serviceStatus;

  bool _isLoading = false;
  bool _autoRefresh = true;
  bool _followTail = true;
  int _lines = 100;
  String? _error;

  _SeverityFilter _severityFilter = _SeverityFilter.all;

  Timer? _refreshTimer;
  bool _wasNearBottomBeforeLastLoad = true;

  static const _nearBottomPx = 80.0;
  static const _lineChoices = [50, 100, 250, 500, 1000];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(_onSearchChanged);
    unawaited(_bootstrap());
  }

  void _onSearchChanged() {
    setState(() {});
  }

  Future<void> _bootstrap() async {
    await _loadAllowedServices();
    if (!mounted) return;
    await _loadData();
    _startAutoRefresh();
  }

  Future<void> _loadAllowedServices() async {
    try {
      final names = await _service.getAllowedServices();
      if (!mounted || names.isEmpty) return;
      setState(() {
        _availableServices = List<String>.from(names);
        if (!_availableServices.contains(_selectedService)) {
          _selectedService = _availableServices.first;
        }
      });
    } catch (e) {
      debugPrint('getAllowedServices: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _restartConfirmController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_autoRefresh) _startAutoRefresh();
    } else {
      _refreshTimer?.cancel();
    }
  }

  void _captureScrollAnchor() {
    if (!_scrollController.hasClients) {
      _wasNearBottomBeforeLastLoad = true;
      return;
    }
    final p = _scrollController.position;
    _wasNearBottomBeforeLastLoad = p.pixels >= p.maxScrollExtent - _nearBottomPx;
  }

  void _startAutoRefresh() {
    if (!_autoRefresh) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) unawaited(_loadLogs(silent: true));
    });
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadLogs(silent: false),
      _loadServiceStatus(),
    ]);
  }

  bool _shouldScrollAfterLoad({required bool silent}) {
    if (!silent) return true;
    return _followTail && _wasNearBottomBeforeLastLoad;
  }

  Future<void> _loadLogs({bool silent = false}) async {
    _captureScrollAnchor();

    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final data = await _service.getServiceLogs(
        serviceName: _selectedService,
        lines: _lines,
      );

      if (!mounted) return;

      setState(() {
        _logs = List<Map<String, dynamic>>.from(data['logs'] as List? ?? []);
        _isLoading = false;
        _error = null;
      });

      if (_shouldScrollAfterLoad(silent: silent)) {
        _scheduleScrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      final err = ErrorExtractor.forContext(e, context);
      setState(() {
        _error = err;
        _isLoading = false;
      });
      if (!silent) {
        final loc = AppLocalizations.of(context);
        SnackBarHelper.showError(
          context,
          message: loc.serviceLogsFetchError(err),
        );
      }
    }
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_visibleLogs().isEmpty) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _loadServiceStatus() async {
    try {
      final status = await _service.getServiceStatus(serviceName: _selectedService);
      if (mounted) {
        setState(() => _serviceStatus = status);
      }
    } catch (e) {
      debugPrint('getServiceStatus: $e');
    }
  }

  List<Map<String, dynamic>> _visibleLogs() {
    final q = _searchController.text.trim().toLowerCase();
    return _logs.where((log) {
      final level = '${log['level'] ?? '6'}';
      if (!_matchesSeverity(level, _severityFilter)) return false;
      if (q.isEmpty) return true;
      final msg = (log['message'] as String? ?? '').toLowerCase();
      return msg.contains(q);
    }).toList();
  }

  bool _matchesSeverity(String levelStr, _SeverityFilter f) {
    final n = int.tryParse(levelStr) ?? 6;
    switch (f) {
      case _SeverityFilter.all:
        return true;
      case _SeverityFilter.errorsOnly:
        return n <= 3;
      case _SeverityFilter.warningsUp:
        return n <= 4;
    }
  }

  Future<void> _restartService() async {
    final t = AppLocalizations.of(context);
    _restartConfirmController.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final ok = _restartConfirmController.text.trim() == _selectedService;
            return AlertDialog(
              title: Text(t.serviceLogsRestartConfirmTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t.serviceLogsRestartConfirmBody(_selectedService)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _restartConfirmController,
                    decoration: InputDecoration(
                      hintText: t.serviceLogsRestartTypeHint,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(t.cancel),
                ),
                ElevatedButton(
                  onPressed: ok ? () => Navigator.of(context).pop(true) : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: Text(t.serviceLogsRestart),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      setState(() => _isLoading = true);
      final result = await _service.restartService(serviceName: _selectedService);
      if (!mounted) return;
      final loc = AppLocalizations.of(context);
      final msg = result['message'] as String? ?? loc.serviceLogsRestartSuccessDefault;
      SnackBarHelper.showSuccess(context, message: msg);
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      final loc = AppLocalizations.of(context);
      SnackBarHelper.showError(
        context,
        message: loc.serviceLogsRestartError(
          ErrorExtractor.forContext(e, context),
        ),
      );
      setState(() => _isLoading = false);
    }
  }

  void _toggleAutoRefresh() {
    setState(() => _autoRefresh = !_autoRefresh);
    if (_autoRefresh) {
      _startAutoRefresh();
    } else {
      _refreshTimer?.cancel();
    }
  }

  void _toggleFollowTail() {
    setState(() => _followTail = !_followTail);
    if (_followTail) _scheduleScrollToBottom();
  }

  Color _getLogLevelColor(String level) {
    final levelNum = int.tryParse(level) ?? 6;
    switch (levelNum) {
      case 0:
      case 1:
      case 2:
      case 3:
        return Colors.red;
      case 4:
        return Colors.orange;
      case 5:
      case 6:
        return Colors.blue;
      case 7:
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      final s = timestamp.trim();
      if (s.isEmpty) return '—';
      final v = double.tryParse(s);
      if (v == null) return timestamp;
      final us = v.round();
      final dt = DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true).toLocal();
      final y = dt.year;
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      final sec = dt.second.toString().padLeft(2, '0');
      return '$y/$m/$d $h:$mm:$sec';
    } catch (_) {
      return timestamp;
    }
  }

  String _levelShortLabel(String level) {
    switch (level) {
      case '3':
        return 'ERR';
      case '4':
        return 'WARN';
      case '6':
        return 'INFO';
      case '7':
        return 'DEBUG';
      default:
        return 'LOG';
    }
  }

  void _showStatusDetails(AppLocalizations t) {
    final out = _serviceStatus?['status_output'] as String?;
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.serviceLogsStatusDetails),
        content: SizedBox(
          width: 560,
          height: 360,
          child: SingleChildScrollView(
            child: SelectableText(
              (out != null && out.isNotEmpty) ? out : t.serviceLogsNoStatusOutput,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(t.cancel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final visible = _visibleLogs();
    final dropdownValue =
        _availableServices.contains(_selectedService) ? _selectedService : _availableServices.first;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.settingsServiceLogs),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/user/profile/system-settings'),
        ),
        actions: [
          IconButton(
            icon: Icon(_autoRefresh ? Icons.pause : Icons.play_arrow),
            onPressed: _toggleAutoRefresh,
            tooltip: _autoRefresh ? t.serviceLogsPauseAutoRefreshTooltip : t.serviceLogsResumeAutoRefreshTooltip,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(),
            tooltip: t.serviceLogsRefreshTooltip,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            elevation: 1,
            color: theme.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 280,
                          child: DropdownButton<String>(
                            value: dropdownValue,
                            isExpanded: true,
                            items: _availableServices
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s, textDirection: TextDirection.ltr),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _selectedService = v);
                              _loadData();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_serviceStatus != null) ...[
                          _StatusChip(
                            label: (_serviceStatus!['is_active'] as bool? ?? false)
                                ? t.serviceLogsActive
                                : t.serviceLogsInactive,
                            color: (_serviceStatus!['is_active'] as bool? ?? false) ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 6),
                          _StatusChip(
                            label: (_serviceStatus!['is_enabled'] as bool? ?? false)
                                ? t.serviceLogsEnabled
                                : t.serviceLogsDisabled,
                            color: (_serviceStatus!['is_enabled'] as bool? ?? false) ? Colors.teal : Colors.grey,
                          ),
                          IconButton(
                            icon: const Icon(Icons.info_outline),
                            tooltip: t.serviceLogsStatusDetails,
                            onPressed: () => _showStatusDetails(t),
                          ),
                        ],
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _restartService,
                          icon: const Icon(Icons.restart_alt),
                          label: Text(t.serviceLogsRestart),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.serviceLogsLinesLabel),
                          const SizedBox(width: 6),
                          DropdownButton<int>(
                            value: _lineChoices.contains(_lines) ? _lines : 100,
                            items: _lineChoices
                                .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _lines = v);
                              unawaited(_loadLogs(silent: false));
                            },
                          ),
                        ],
                      ),
                      Tooltip(
                        message: _followTail
                            ? t.serviceLogsFollowTailOnTooltip
                            : t.serviceLogsFollowTailOffTooltip,
                        child: FilterChip(
                          label: Text(t.serviceLogsFollowTailChip),
                          selected: _followTail,
                          onSelected: (_) => _toggleFollowTail(),
                        ),
                      ),
                      ChoiceChip(
                        label: Text(t.serviceLogsFilterAll),
                        selected: _severityFilter == _SeverityFilter.all,
                        onSelected: (v) {
                          if (v) setState(() => _severityFilter = _SeverityFilter.all);
                        },
                      ),
                      ChoiceChip(
                        label: Text(t.serviceLogsFilterErrors),
                        selected: _severityFilter == _SeverityFilter.errorsOnly,
                        onSelected: (v) {
                          if (v) setState(() => _severityFilter = _SeverityFilter.errorsOnly);
                        },
                      ),
                      ChoiceChip(
                        label: Text(t.serviceLogsFilterWarnings),
                        selected: _severityFilter == _SeverityFilter.warningsUp,
                        onSelected: (v) {
                          if (v) setState(() => _severityFilter = _SeverityFilter.warningsUp);
                        },
                      ),
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: t.serviceLogsSearchHint,
                            isDense: true,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.search, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _buildLogBody(theme, t, visible),
          ),
          if (_logs.isNotEmpty)
            _buildFooter(theme, t, visible),
        ],
      ),
    );
  }

  Widget _buildLogBody(ThemeData theme, AppLocalizations t, List<Map<String, dynamic>> visible) {
    if (_isLoading && _logs.isEmpty) {
      return const Center(child: LoadingIndicator());
    }
    if (_error != null && _logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(t.serviceLogsErrorTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SelectableText(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadData(),
              child: Text(t.serviceLogsRetry),
            ),
          ],
        ),
      );
    }
    if (_logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(t.serviceLogsEmpty, style: theme.textTheme.titleLarge),
          ],
        ),
      );
    }
    if (visible.isEmpty) {
      return Center(
        child: Text(t.serviceLogsEmpty, style: theme.textTheme.titleLarge),
      );
    }

    return ColoredBox(
      color: Colors.black87,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          itemCount: visible.length,
          itemBuilder: (context, index) {
            final log = visible[index];
            final message = log['message'] as String? ?? '';
            final level = '${log['level'] ?? '6'}';
            final timestamp = log['timestamp'] as String? ?? '';

            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border(
                  left: BorderSide(color: _getLogLevelColor(level), width: 3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      _formatTimestamp(timestamp),
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getLogLevelColor(level).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _levelShortLabel(level),
                      style: TextStyle(
                        color: _getLogLevelColor(level),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      message,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFooter(ThemeData theme, AppLocalizations t, List<Map<String, dynamic>> visible) {
    final countLabel = visible.length == _logs.length
        ? t.serviceLogsLogCount(_logs.length)
        : t.serviceLogsFilteredCount(visible.length, _logs.length);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(countLabel, style: theme.textTheme.bodySmall),
          ),
          Row(
            children: [
              _LegendDot(color: Colors.red, label: t.serviceLogsLegendError),
              _LegendDot(color: Colors.orange, label: t.serviceLogsLegendWarn),
              _LegendDot(color: Colors.blue, label: t.serviceLogsLegendInfo),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
