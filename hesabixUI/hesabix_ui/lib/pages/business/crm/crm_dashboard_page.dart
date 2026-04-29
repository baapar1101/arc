import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_dialog.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';
import 'package:intl/intl.dart';

/// داشبورد خلاصه CRM
class CrmDashboardPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const CrmDashboardPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<CrmDashboardPage> createState() => _CrmDashboardPageState();
}

class _CrmDashboardPageState extends State<CrmDashboardPage> {
  final CrmService _crmService = CrmService(apiClient: ApiClient());
  Map<String, dynamic>? _summary;
  List<dynamic> _followUpLeads = [];
  List<dynamic> _followUpDeals = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _crmService.getSummary(businessId: widget.businessId),
        _crmService.getFollowUpsToday(businessId: widget.businessId, daysAhead: 7),
      ]);
      if (!mounted) return;
      final summaryData = Map<String, dynamic>.from(results[0] as Map);
      final followData = Map<String, dynamic>.from(results[1] as Map);
      setState(() {
        _summary = Map<String, dynamic>.from(summaryData);
        _followUpLeads = followData['leads'] is List ? List<dynamic>.from(followData['leads'] as List) : [];
        _followUpDeals = followData['deals'] is List ? List<dynamic>.from(followData['deals'] as List) : [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authStore.canReadSection('crm')) {
      return AccessDeniedPage(message: 'شما دسترسی لازم برای مشاهده CRM را ندارید');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('داشبورد CRM'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) context.pop();
          },
        ),
        actions: [
          IconButton(
            tooltip: 'چت با دستیار هوشمند',
            icon: const Icon(Icons.smart_toy_outlined),
            onPressed: () async {
              final calendarController = await CalendarController.load();
              if (!context.mounted) return;
              AIChatDialog.show(
                context,
                authStore: widget.authStore,
                businessId: widget.businessId,
                calendarController: calendarController,
              );
            },
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
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('تلاش مجدد'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      MediaQuery.paddingOf(context).bottom + 16,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final padW = MediaQuery.paddingOf(context).horizontal;
                        final maxW = constraints.maxWidth + padW;
                        final useTwoCol = maxW >= 620;
                        final gap = maxW < 400 ? 10.0 : 12.0;
                        final tileW = useTwoCol ? (constraints.maxWidth - gap) / 2 : constraints.maxWidth;
                        Widget rowPair(Widget a, Widget b) {
                          if (!useTwoCol) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                a,
                                SizedBox(height: gap),
                                b,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: tileW, child: a),
                              SizedBox(width: gap),
                              SizedBox(width: tileW, child: b),
                            ],
                          );
                        }

                        final p1 = rowPair(
                          _SummaryCard(
                            icon: Icons.contact_phone,
                            title: 'سرنخ‌ها',
                            value: '${_summary?['total_leads'] ?? 0}',
                            subtitle: '${_summary?['converted_leads'] ?? 0} تبدیل شده',
                            onTap: () => context.go('/business/${widget.businessId}/crm/leads'),
                          ),
                          _SummaryCard(
                            icon: Icons.trending_up,
                            title: 'فرصت فروش',
                            value: '${_summary?['total_deals'] ?? 0}',
                            subtitle: '${_summary?['closed_deals'] ?? 0} بسته شده',
                            onTap: () => context.go('/business/${widget.businessId}/crm/deals'),
                          ),
                        );
                        final p2 = rowPair(
                          _SummaryCard(
                            icon: Icons.percent,
                            title: 'نرخ تبدیل',
                            value: '${_summary?['conversion_rate'] ?? 0}%',
                            subtitle: 'سرنخ به مشتری',
                          ),
                          _SummaryCard(
                            icon: Icons.account_balance_wallet,
                            title: 'مبلغ کل فرصت‌ها',
                            value: NumberFormat('#,##0').format(((_summary?['total_deals_amount'] as num?) ?? 0).toDouble()),
                            subtitle: 'ریال',
                            onTap: () => context.go('/business/${widget.businessId}/crm/deals'),
                          ),
                        );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            p1,
                            SizedBox(height: gap),
                            p2,
                            SizedBox(height: maxW < 400 ? 14 : 20),
                            _FollowUpsCard(
                              businessId: widget.businessId,
                              leads: _followUpLeads,
                              deals: _followUpDeals,
                              onRefresh: _load,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
    );
  }
}

class _FollowUpsCard extends StatelessWidget {
  final int businessId;
  final List<dynamic> leads;
  final List<dynamic> deals;
  final VoidCallback onRefresh;

  const _FollowUpsCard({
    required this.businessId,
    required this.leads,
    required this.deals,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final total = leads.length + deals.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                  child: Icon(Icons.notifications_active, color: Theme.of(context).colorScheme.onTertiaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'پیگیری‌های پیش‌رو',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '$total مورد',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'سرنخ‌ها و فرصت‌های فروشی که در ۷ روز آینده پیگیری دارند',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (total > 0) ...[
              const SizedBox(height: 12),
              ...leads.take(5).map((e) {
                final m = Map<String, dynamic>.from(e as Map);
                final at = m['next_follow_up_at']?.toString();
                final dateStr = at != null && at.isNotEmpty
                    ? DateFormat('yyyy/MM/dd HH:mm').format(DateTime.tryParse(at) ?? DateTime.now())
                    : '';
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.person_outline, size: 20),
                  title: Text(m['name']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
                  subtitle: Text('سرنخ • $dateStr', style: Theme.of(context).textTheme.bodySmall),
                  onTap: () => context.go('/business/$businessId/crm/leads?leadId=${m['id']}'),
                );
              }),
              ...deals.take(5).map((e) {
                final m = Map<String, dynamic>.from(e as Map);
                final at = m['next_follow_up_at']?.toString();
                final dateStr = at != null && at.isNotEmpty
                    ? DateFormat('yyyy/MM/dd HH:mm').format(DateTime.tryParse(at) ?? DateTime.now())
                    : '';
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.handshake_outlined, size: 20),
                  title: Text(m['title']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
                  subtitle: Text('${m['person_name'] ?? ''} • $dateStr', style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                  onTap: () => context.go('/business/$businessId/crm/deals?dealId=${m['id']}'),
                );
              }),
              if (total > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    onPressed: () => context.go('/business/$businessId/crm/leads'),
                    icon: const Icon(Icons.list),
                    label: const Text('مشاهده همه'),
                  ),
                ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'پیگیری‌ای برای ۷ روز آینده ثبت نشده است.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final VoidCallback? onTap;

  const _SummaryCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
    return card;
  }
}
