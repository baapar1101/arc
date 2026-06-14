import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/services/wallet_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

/// داشبورد درآمد ناشر مهارت‌های AI
class AISkillsPublisherRevenuePage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const AISkillsPublisherRevenuePage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<AISkillsPublisherRevenuePage> createState() => _AISkillsPublisherRevenuePageState();
}

class _AISkillsPublisherRevenuePageState extends State<AISkillsPublisherRevenuePage> {
  final AIService _aiService = AIService(ApiClient());
  final WalletService _walletService = WalletService(ApiClient());

  bool _loading = true;
  Map<String, dynamic> _data = {};
  Map<String, dynamic> _wallet = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _aiService.getPublisherRevenue(businessId: widget.businessId),
        _walletService.getOverview(businessId: widget.businessId),
      ]);
      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(results[0] as Map);
        _wallet = Map<String, dynamic>.from(results[1] as Map);
      });
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(num? v) {
    final sym = _wallet['base_currency_symbol']?.toString() ?? '';
    if (v == null) return '—';
    return '${v.toStringAsFixed(0)} $sym'.trim();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recent = (_data['recent_sales'] as List?)?.cast<Map>() ?? [];
    final top = (_data['top_packages'] as List?)?.cast<Map>() ?? [];
    final sharePct = (_data['publisher_share_percent'] as num?)?.toDouble() ?? 70;

    return Scaffold(
      appBar: AppBar(
        title: const Text('درآمد مهارت‌های AI'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'سهم ناشر: ${sharePct.toStringAsFixed(0)}٪',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _statCard('فروش', '${_data['sales_count'] ?? 0}', theme)),
                      const SizedBox(width: 8),
                      Expanded(child: _statCard('درآمد شما', _money(_data['publisher_earnings'] as num?), theme)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _statCard('فروش کل', _money(_data['gross_sales'] as num?), theme)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _statCard(
                          'موجودی کیف پول',
                          _money((_wallet['available_balance'] as num?)?.toDouble()),
                          theme,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/business/${widget.businessId}/wallet'),
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('مدیریت کیف پول و برداشت'),
                  ),
                  const SizedBox(height: 24),
                  Text('پرفروش‌ترین مهارت‌ها', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (top.isEmpty)
                    const Text('هنوز مهارت منتشرشده‌ای ندارید.')
                  else
                    ...top.map((p) {
                      final m = Map<String, dynamic>.from(p);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(m['title']?.toString() ?? ''),
                        subtitle: Text('${m['install_count'] ?? 0} نصب'),
                        trailing: Text(_money(m['price_amount'] as num?)),
                      );
                    }),
                  const Divider(height: 32),
                  Text('فروش‌های اخیر', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (recent.isEmpty)
                    const Text('فروشی ثبت نشده است.')
                  else
                    ...recent.map((raw) {
                      final s = Map<String, dynamic>.from(raw);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(s['skill_title']?.toString() ?? ''),
                        subtitle: Text(s['created_at']?.toString() ?? ''),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_money(s['publisher_amount'] as num? ?? s['amount'] as num?)),
                            if (s['publisher_amount'] != null)
                              Text(
                                'از ${_money(s['amount'] as num?)}',
                                style: theme.textTheme.labelSmall,
                              ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }

  Widget _statCard(String label, String value, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Text(value, style: theme.textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
