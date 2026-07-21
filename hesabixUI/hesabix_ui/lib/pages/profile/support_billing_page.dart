import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/support_billing_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportBillingPage extends StatefulWidget {
  const SupportBillingPage({super.key});

  @override
  State<SupportBillingPage> createState() => _SupportBillingPageState();
}

class _SupportBillingPageState extends State<SupportBillingPage>
    with SingleTickerProviderStateMixin {
  late final SupportBillingService _service;
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _entitlement;
  Map<String, dynamic>? _subscription;
  List<Map<String, dynamic>> _plans = const [];
  List<Map<String, dynamic>> _invoices = const [];
  List<Map<String, dynamic>> _gateways = const [];
  int? _selectedGatewayId;
  bool _checkingOut = false;

  @override
  void initState() {
    super.initState();
    _service = SupportBillingService(ApiClient());
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entitlement = await _service.getEntitlement();
      final subscription = await _service.getSubscription();
      final plans = await _service.listPlans();
      final invoicesData = await _service.listInvoices();
      final gateways = await _service.listGateways();
      final items = (invoicesData['items'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _entitlement = entitlement;
        _subscription = subscription;
        _plans = plans;
        _invoices = items;
        _gateways = gateways;
        _selectedGatewayId = gateways.isNotEmpty ? gateways.first['id'] as int? : null;
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

  String _formatPrice(dynamic price) {
    final v = (price is num) ? price.toDouble() : double.tryParse('$price') ?? 0;
    if (v <= 0) return 'رایگان';
    return '${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} ریال';
  }

  Future<void> _checkout(Map<String, dynamic> plan) async {
    final planId = plan['id'] as int?;
    if (planId == null) return;
    setState(() => _checkingOut = true);
    try {
      final result = await _service.checkout(
        planId: planId,
        gatewayId: _selectedGatewayId,
        source: 'app',
      );
      if (!mounted) return;
      final paymentUrl = result['payment_url'] as String?;
      final requiresPayment = result['requires_payment'] == true;
      if (requiresPayment && paymentUrl != null && paymentUrl.isNotEmpty) {
        final uri = Uri.parse(paymentUrl);
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok && mounted) {
          SnackBarHelper.showError(context, 'نتوانستیم درگاه پرداخت را باز کنیم');
        } else if (mounted) {
          SnackBarHelper.showSuccess(context, 'در حال انتقال به درگاه پرداخت…');
        }
      } else {
        SnackBarHelper.showSuccess(context, 'اشتراک پشتیبانی فعال شد');
        await _load();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('اشتراک و صورتحساب پشتیبانی'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/user/profile/support'),
        ),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'وضعیت'),
            Tab(text: 'خرید پلن'),
            Tab(text: 'صورت‌حساب‌ها'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('تلاش مجدد')),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildStatusTab(theme),
                    _buildPlansTab(theme),
                    _buildInvoicesTab(theme),
                  ],
                ),
    );
  }

  Widget _buildStatusTab(ThemeData theme) {
    final mode = _entitlement?['mode']?.toString() ?? 'free';
    final canCreate = _entitlement?['can_create_ticket'] == true;
    final upsell = _entitlement?['upsell_required'] == true;
    final quota = _entitlement?['quota'] as Map?;
    final sub = _subscription ?? (_entitlement?['subscription'] as Map?);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('وضعیت دسترسی', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(_modeLabel(mode)),
                const SizedBox(height: 4),
                Text(canCreate ? 'می‌توانید تیکت جدید ثبت کنید.' : 'ثبت تیکت جدید فعلاً ممکن نیست.'),
                if (quota != null) ...[
                  const SizedBox(height: 8),
                  Text('سهمیه رایگان ماهانه: ${quota['used']}/${quota['limit']}'),
                ],
                if (upsell) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => _tabs.animateTo(1),
                    child: const Text('خرید اشتراک پشتیبانی'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('اشتراک فعلی', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (sub == null)
                  const Text('اشتراک فعالی ندارید.')
                else ...[
                  Text('پلن: ${(sub['plan'] as Map?)?['name'] ?? '-'}'),
                  Text('وضعیت: ${sub['status']}'),
                  Text('پایان: ${sub['ends_at'] ?? '-'}'),
                  if (sub['grace_ends_at'] != null) Text('پایان مهلت ارفاق: ${sub['grace_ends_at']}'),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _modeLabel(String mode) {
    switch (mode) {
      case 'paid':
        return 'حالت سیستم: پشتیبانی پولی';
      case 'hybrid':
        return 'حالت سیستم: ترکیبی (سهمیه رایگان + اشتراک)';
      default:
        return 'حالت سیستم: رایگان برای همه';
    }
  }

  Widget _buildPlansTab(ThemeData theme) {
    if (_plans.isEmpty) {
      return const Center(child: Text('پلنی برای خرید فعال نیست.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_gateways.length > 1)
          DropdownButtonFormField<int>(
            value: _selectedGatewayId,
            decoration: const InputDecoration(
              labelText: 'درگاه پرداخت',
              border: OutlineInputBorder(),
            ),
            items: _gateways
                .map(
                  (g) => DropdownMenuItem<int>(
                    value: g['id'] as int,
                    child: Text('${g['display_name']} (${g['provider']})'),
                  ),
                )
                .toList(),
            onChanged: _checkingOut
                ? null
                : (v) => setState(() => _selectedGatewayId = v),
          ),
        if (_gateways.length > 1) const SizedBox(height: 16),
        ..._plans.map((plan) {
          final months = plan['period_months'];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan['name']?.toString() ?? '', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('$months ماهه · ${_formatPrice(plan['price'])}'),
                  if ((plan['description'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(plan['description'].toString()),
                  ],
                  if (plan['includes_priority_support'] == true) ...[
                    const SizedBox(height: 6),
                    Chip(
                      label: const Text('پشتیبانی اولویت‌دار'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: theme.colorScheme.primaryContainer,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: _checkingOut ? null : () => _checkout(plan),
                      child: Text(
                        (plan['is_free'] == true || (plan['price'] as num? ?? 0) <= 0)
                            ? 'فعال‌سازی رایگان'
                            : 'پرداخت و فعال‌سازی',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildInvoicesTab(ThemeData theme) {
    if (_invoices.isEmpty) {
      return const Center(child: Text('صورت‌حسابی ثبت نشده است.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _invoices.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final inv = _invoices[i];
          return Card(
            child: ListTile(
              title: Text(inv['code']?.toString() ?? ''),
              subtitle: Text(
                '${inv['plan_name'] ?? '-'} · ${_formatPrice(inv['amount'])}\n'
                'وضعیت: ${inv['status']} · ${inv['paid_at'] ?? inv['issued_at'] ?? ''}',
              ),
              isThreeLine: true,
              trailing: inv['gateway_trace'] != null
                  ? Text('#${inv['gateway_trace']}', style: theme.textTheme.bodySmall)
                  : null,
            ),
          );
        },
      ),
    );
  }
}
