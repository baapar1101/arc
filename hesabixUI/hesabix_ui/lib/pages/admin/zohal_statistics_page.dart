import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../services/zohal_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';

class ZohalStatisticsPage extends StatefulWidget {
  const ZohalStatisticsPage({super.key});

  @override
  State<ZohalStatisticsPage> createState() => _ZohalStatisticsPageState();
}

class _ZohalStatisticsPageState extends State<ZohalStatisticsPage> {
  late final ZohalService _zohalService;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _statistics;

  DateTime? _startDate;
  DateTime? _endDate;
  int? _selectedBusinessId;
  int? _selectedServiceId;

  @override
  void initState() {
    super.initState();
    _zohalService = ZohalService(ApiClient());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stats = await _zohalService.getStatistics(
        startDate: _startDate?.toIso8601String(),
        endDate: _endDate?.toIso8601String(),
        businessId: _selectedBusinessId,
        serviceId: _selectedServiceId,
      );
      setState(() {
        _statistics = stats;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AdminCompactScaffold(
      title: adminTx(context, 'آمار زحل', 'Zohal statistics'),
      subtitle: adminTx(context, 'مصرف سرویس‌های استعلام', 'Inquiry service usage'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: _load,
          tooltip: adminTx(context, 'بارگذاری مجدد', 'Reload'),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: Text(adminTx(context, 'تلاش مجدد', 'Retry')),
                      ),
                    ],
                  ),
                )
              : _statistics == null
                  ? Center(child: Text(adminTx(context, 'داده‌ای نیست', 'No data'), style: context.settingsHub.cardSubtitleStyle(theme.textTheme, color: theme.colorScheme.onSurfaceVariant)))
                  : SingleChildScrollView(
                      padding: context.settingsHub.pagePadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // خلاصه آمار
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    adminTx(context, 'خلاصه', 'Summary'),
                                    style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildStatCard(
                                          theme,
                                          adminTx(context, 'کل درخواست‌ها', 'All requests'),
                                          (_statistics!['total_requests'] ?? 0).toString(),
                                          Icons.request_quote,
                                          theme.colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildStatCard(
                                          theme,
                                          adminTx(context, 'موفق', 'Succeeded'),
                                          (_statistics!['successful_requests'] ?? 0).toString(),
                                          Icons.check_circle,
                                          SemanticColorResolver.positive(context),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: _buildStatCard(
                                          theme,
                                          adminTx(context, 'ناموفق', 'Failed'),
                                          (_statistics!['failed_requests'] ?? 0).toString(),
                                          Icons.cancel,
                                          SemanticColorResolver.negative(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _buildStatCard(
                                    theme,
                                    adminTx(context, 'کل درآمد', 'Total revenue'),
                                    '${formatWithThousands((_statistics!['total_revenue'] ?? 0).toDouble())}',
                                    Icons.attach_money,
                                    theme.colorScheme.primary,
                                    fullWidth: true,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // آمار به تفکیک سرویس
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    adminTx(context, 'به تفکیک سرویس', 'By service'),
                                    style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
                                  ),
                                  const SizedBox(height: 16),
                                  ...((_statistics!['by_service'] as List?) ?? []).map((service) {
                                    return ListTile(
                                      leading: const Icon(Icons.search),
                                      title: Text(service['service_name'] ?? ''),
                                      subtitle: Text('${service['request_count'] ?? 0} ${adminTx(context, 'درخواست', 'requests')}'),
                                      trailing: Text(
                                        '${formatWithThousands((service['revenue'] ?? 0).toDouble())}',
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // آمار به تفکیک کسب‌وکار
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    adminTx(context, 'به تفکیک کسب‌وکار', 'By business'),
                                    style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
                                  ),
                                  const SizedBox(height: 16),
                                  ...((_statistics!['by_business'] as List?) ?? []).map((business) {
                                    return ListTile(
                                      leading: const Icon(Icons.business),
                                      title: Text(business['business_name'] ?? ''),
                                      subtitle: Text('${business['request_count'] ?? 0} ${adminTx(context, 'درخواست', 'requests')}'),
                                      trailing: Text(
                                        '${formatWithThousands((business['revenue'] ?? 0).toDouble())}',
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildStatCard(
    ThemeData theme,
    String label,
    String value,
    IconData icon,
    Color color, {
    bool fullWidth = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

