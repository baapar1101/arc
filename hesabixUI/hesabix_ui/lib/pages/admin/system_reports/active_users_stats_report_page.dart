import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';

/// گزارش خلاصهٔ کاربران و فعالیت اخیر (آنلاین تقریبی).
class ActiveUsersStatsReportPage extends StatefulWidget {
  const ActiveUsersStatsReportPage({super.key});

  @override
  State<ActiveUsersStatsReportPage> createState() => _ActiveUsersStatsReportPageState();
}

class _ActiveUsersStatsReportPageState extends State<ActiveUsersStatsReportPage> {
  final _api = ApiClient();
  bool _loading = true;
  String? _error;
  int? _totalUsers;
  int? _activeUsers;
  int? _inactiveUsers;
  double? _activePct;
  int? _recentlyActive;
  int _windowMinutes = 5;

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
      final summary = await _api.get<Map<String, dynamic>>('/api/v1/users/stats/summary');
      final online = await _api.get<Map<String, dynamic>>(
        '/api/v1/users/stats/online',
        query: {'window_minutes': _windowMinutes},
      );
      if (!mounted) return;
      final sBody = summary.data;
      final oBody = online.data;
      final sData = sBody != null && sBody['data'] is Map<String, dynamic>
          ? sBody['data'] as Map<String, dynamic>
          : null;
      final oData = oBody != null && oBody['data'] is Map<String, dynamic>
          ? oBody['data'] as Map<String, dynamic>
          : null;
      setState(() {
        _loading = false;
        if (sData != null) {
          _totalUsers = _asInt(sData['total_users']);
          _activeUsers = _asInt(sData['active_users']);
          _inactiveUsers = _asInt(sData['inactive_users']);
          final ap = sData['active_percentage'];
          _activePct = ap is num ? ap.toDouble() : double.tryParse('$ap');
        }
        if (oData != null) {
          _recentlyActive = _asInt(oData['recently_active_count']);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorExtractor.forContext(e, context);
      });
    }
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.systemReportActiveUsersTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/user/profile/system-settings/reports'),
        ),
        actions: [
          IconButton(
            tooltip: t.systemReportRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: scheme.error),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: Text(t.systemReportRefresh)),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      t.systemReportActiveUsersDescription,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${t.systemReportActiveWindowLabel}: $_windowMinutes',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _windowMinutes.toDouble(),
                      min: 1,
                      max: 120,
                      divisions: 119,
                      label: '$_windowMinutes',
                      onChanged: (v) {
                        setState(() => _windowMinutes = v.round());
                      },
                      onChangeEnd: (_) => _load(),
                    ),
                    const SizedBox(height: 8),
                    _StatCard(
                      icon: Icons.groups_outlined,
                      title: t.systemReportSummaryTotal,
                      value: '${_totalUsers ?? '—'}',
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 12),
                    _StatCard(
                      icon: Icons.verified_user_outlined,
                      title: t.systemReportSummaryActive,
                      value: '${_activeUsers ?? '—'}',
                      color: const Color(0xFF2E7D32),
                    ),
                    const SizedBox(height: 12),
                    _StatCard(
                      icon: Icons.person_off_outlined,
                      title: t.systemReportSummaryInactive,
                      value: '${_inactiveUsers ?? '—'}',
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 12),
                    _StatCard(
                      icon: Icons.percent,
                      title: t.systemReportSummaryActivePct,
                      value: _activePct != null ? '${_activePct!.toStringAsFixed(1)}%' : '—',
                      color: scheme.secondary,
                    ),
                    const SizedBox(height: 12),
                    _StatCard(
                      icon: Icons.sensors_rounded,
                      title: t.systemReportOnlineApprox,
                      value: '${_recentlyActive ?? '—'}',
                      color: const Color(0xFF00695C),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t.systemReportOnlineNote,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
