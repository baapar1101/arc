import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
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
      final data = await _crmService.getSummary(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _summary = data is Map ? Map<String, dynamic>.from(data) : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      SnackBarHelper.show(context, message: 'خطا در بارگذاری: $e', isError: true);
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
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryCard(
                                icon: Icons.contact_phone,
                                title: 'سرنخ‌ها',
                                value: '${_summary?['total_leads'] ?? 0}',
                                subtitle: '${_summary?['converted_leads'] ?? 0} تبدیل شده',
                                onTap: () => context.go('/business/${widget.businessId}/crm/leads'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _SummaryCard(
                                icon: Icons.trending_up,
                                title: 'فرصت فروش',
                                value: '${_summary?['total_deals'] ?? 0}',
                                subtitle: '${_summary?['closed_deals'] ?? 0} بسته شده',
                                onTap: () => context.go('/business/${widget.businessId}/crm/deals'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryCard(
                                icon: Icons.percent,
                                title: 'نرخ تبدیل',
                                value: '${_summary?['conversion_rate'] ?? 0}%',
                                subtitle: 'سرنخ به مشتری',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _SummaryCard(
                                icon: Icons.account_balance_wallet,
                                title: 'مبلغ کل فرصت‌ها',
                                value: NumberFormat('#,##0').format(((_summary?['total_deals_amount'] as num?) ?? 0).toDouble()),
                                subtitle: 'ریال',
                                onTap: () => context.go('/business/${widget.businessId}/crm/deals'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
