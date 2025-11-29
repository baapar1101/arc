import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../services/zohal_service.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;

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
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('آمار استفاده از سرویس‌های زحل'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'بارگذاری مجدد',
          ),
        ],
      ),
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
                        label: const Text('تلاش مجدد'),
                      ),
                    ],
                  ),
                )
              : _statistics == null
                  ? const Center(child: Text('داده‌ای یافت نشد'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
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
                                    'خلاصه آمار',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildStatCard(
                                          theme,
                                          'کل درخواست‌ها',
                                          (_statistics!['total_requests'] ?? 0).toString(),
                                          Icons.request_quote,
                                          theme.colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildStatCard(
                                          theme,
                                          'موفق',
                                          (_statistics!['successful_requests'] ?? 0).toString(),
                                          Icons.check_circle,
                                          Colors.green,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildStatCard(
                                          theme,
                                          'ناموفق',
                                          (_statistics!['failed_requests'] ?? 0).toString(),
                                          Icons.cancel,
                                          Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _buildStatCard(
                                    theme,
                                    'کل درآمد',
                                    '${formatWithThousands((_statistics!['total_revenue'] ?? 0).toDouble())} تومان',
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
                                    'آمار به تفکیک سرویس',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ...((_statistics!['by_service'] as List?) ?? []).map((service) {
                                    return ListTile(
                                      leading: const Icon(Icons.search),
                                      title: Text(service['service_name'] ?? ''),
                                      subtitle: Text('${service['request_count'] ?? 0} درخواست'),
                                      trailing: Text(
                                        '${formatWithThousands((service['revenue'] ?? 0).toDouble())} تومان',
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
                                    'آمار به تفکیک کسب‌وکار',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ...((_statistics!['by_business'] as List?) ?? []).map((business) {
                                    return ListTile(
                                      leading: const Icon(Icons.business),
                                      title: Text(business['business_name'] ?? ''),
                                      subtitle: Text('${business['request_count'] ?? 0} درخواست'),
                                      trailing: Text(
                                        '${formatWithThousands((business['revenue'] ?? 0).toDouble())} تومان',
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
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

