import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/services/support_billing_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
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
  CalendarController? _calendar;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _entitlement;
  Map<String, dynamic>? _subscription;
  List<Map<String, dynamic>> _plans = const [];
  List<Map<String, dynamic>> _invoices = const [];
  List<Map<String, dynamic>> _gateways = const [];
  int? _selectedGatewayId;
  bool _checkingOut = false;
  bool _handledReturnQuery = false;

  @override
  void initState() {
    super.initState();
    _service = SupportBillingService(ApiClient());
    _calendar = ApiClient.getCalendarController();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledReturnQuery) return;
    _handledReturnQuery = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _handlePaymentReturnQuery());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool get _isJalali => _calendar?.isJalali ?? true;

  Future<void> _handlePaymentReturnQuery() async {
    if (!mounted) return;
    final qp = GoRouterState.of(context).uri.queryParameters;
    final status = qp['status'];
    if (status == null || status.isEmpty) return;

    if (status == 'success') {
      SnackBarHelper.showSuccess(
        context,
        message: 'پرداخت با موفقیت انجام شد و اشتراک پشتیبانی فعال شد.',
      );
      _tabs.animateTo(0);
      await _load();
    } else if (status == 'failed') {
      SnackBarHelper.showError(
        context,
        message: 'پرداخت ناموفق بود. در صورت کسر وجه، با پشتیبانی تماس بگیرید.',
      );
      _tabs.animateTo(2);
      await _load();
    }

    // پاک کردن پارامترهای بازگشت از URL بدون رفرش کامل
    if (mounted) {
      context.go('/user/profile/support/billing');
    }
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
    return '${formatWithThousands(v, decimalPlaces: 0)} ریال';
  }

  String _formatDate(dynamic value) {
    if (value == null || '$value'.trim().isEmpty) return '—';
    // ISO کامل (با ساعت) را مستقیم parse می‌کنیم تا زمان از دست نرود
    final raw = value.toString().trim();
    final full = DateTime.tryParse(raw);
    if (full != null) {
      return HesabixDateUtils.formatDateTime(full, _isJalali);
    }
    final parsed = HesabixDateUtils.parseApiDate(value);
    if (parsed != null) {
      return HesabixDateUtils.formatDateTime(parsed, _isJalali);
    }
    return HesabixDateUtils.formatApiDateForDisplay(value, _isJalali);
  }

  String _subscriptionStatusLabel(String? status) {
    switch (status) {
      case 'active':
        return 'فعال';
      case 'pending':
        return 'در انتظار';
      case 'grace':
        return 'مهلت ارفاق';
      case 'expired':
        return 'منقضی';
      case 'cancelled':
        return 'لغو شده';
      case 'replaced':
        return 'جایگزین شده';
      default:
        return status ?? '—';
    }
  }

  Color _subscriptionStatusColor(String? status, ColorScheme cs) {
    switch (status) {
      case 'active':
        return const Color(0xFF2E7D32);
      case 'grace':
      case 'pending':
        return const Color(0xFFEF6C00);
      case 'expired':
      case 'cancelled':
        return const Color(0xFFC62828);
      default:
        return cs.outline;
    }
  }

  String _invoiceStatusLabel(String? status) {
    switch (status) {
      case 'paid':
        return 'پرداخت‌شده';
      case 'awaiting_payment':
        return 'در انتظار پرداخت';
      case 'failed':
        return 'ناموفق';
      case 'expired':
        return 'منقضی';
      case 'void':
        return 'باطل';
      case 'refunded':
        return 'استرداد شده';
      case 'draft':
        return 'پیش‌نویس';
      default:
        return status ?? '—';
    }
  }

  Color _invoiceStatusColor(String? status) {
    switch (status) {
      case 'paid':
        return const Color(0xFF2E7D32);
      case 'awaiting_payment':
        return const Color(0xFFEF6C00);
      case 'failed':
      case 'void':
      case 'expired':
        return const Color(0xFFC62828);
      case 'refunded':
        return const Color(0xFF1565C0);
      default:
        return const Color(0xFF757575);
    }
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
          SnackBarHelper.showError(context, message: 'نتوانستیم درگاه پرداخت را باز کنیم');
        } else if (mounted) {
          SnackBarHelper.showSuccess(context, message: 'در حال انتقال به درگاه پرداخت…');
        }
      } else {
        SnackBarHelper.showSuccess(context, message: 'اشتراک پشتیبانی فعال شد');
        await _load();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('اشتراک و صورتحساب پشتیبانی'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/user/profile/support'),
        ),
        actions: [
          IconButton(
            tooltip: 'بروزرسانی',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(icon: Icon(Icons.verified_user_outlined, size: 20), text: 'وضعیت'),
            Tab(icon: Icon(Icons.workspace_premium_outlined, size: 20), text: 'پلن‌ها'),
            Tab(icon: Icon(Icons.receipt_long_outlined, size: 20), text: 'صورتحساب‌ها'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
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
    final cs = theme.colorScheme;
    final mode = _entitlement?['mode']?.toString() ?? 'free';
    final canCreate = _entitlement?['can_create_ticket'] == true;
    final upsell = _entitlement?['upsell_required'] == true;
    final quota = _entitlement?['quota'] as Map?;
    final sub = _subscription ?? (_entitlement?['subscription'] as Map?);
    final subStatus = sub?['status']?.toString();
    final statusColor = _subscriptionStatusColor(subStatus, cs);
    final used = (quota?['used'] as num?)?.toInt() ?? 0;
    final limit = (quota?['limit'] as num?)?.toInt() ?? 0;
    final quotaProgress = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          _HeroAccessCard(
            modeLabel: _modeLabel(mode),
            modeIcon: _modeIcon(mode),
            canCreate: canCreate,
            accent: canCreate ? const Color(0xFF2E7D32) : const Color(0xFFEF6C00),
            upsell: upsell,
            onBuy: () => _tabs.animateTo(1),
          ),
          if (quota != null) ...[
            const SizedBox(height: 14),
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.pie_chart_outline_rounded, color: cs.primary, size: 22),
                      const SizedBox(width: 10),
                      Text('سهمیه رایگان ماهانه', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text(
                        '$used از $limit',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: quotaProgress,
                      minHeight: 10,
                      backgroundColor: cs.surfaceContainerHighest,
                      color: quotaProgress >= 1 ? const Color(0xFFC62828) : cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.card_membership_rounded, color: cs.primary, size: 22),
                    const SizedBox(width: 10),
                    Text('اشتراک فعلی', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 16),
                if (sub == null)
                  _EmptyHint(
                    icon: Icons.workspace_premium_outlined,
                    title: 'اشتراک فعالی ندارید',
                    subtitle: 'با خرید یکی از پلن‌ها می‌توانید از پشتیبانی اختصاصی استفاده کنید.',
                    actionLabel: 'مشاهده پلن‌ها',
                    onAction: () => _tabs.animateTo(1),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (sub['plan'] as Map?)?['name']?.toString() ?? '—',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      _StatusChip(
                        label: _subscriptionStatusLabel(subStatus),
                        color: statusColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _InfoRow(
                    icon: Icons.event_rounded,
                    label: 'تاریخ پایان',
                    value: _formatDate(sub['ends_at']),
                  ),
                  if (sub['grace_ends_at'] != null) ...[
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.hourglass_bottom_rounded,
                      label: 'پایان مهلت ارفاق',
                      value: _formatDate(sub['grace_ends_at']),
                    ),
                  ],
                  if (sub['starts_at'] != null) ...[
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.play_circle_outline_rounded,
                      label: 'شروع',
                      value: _formatDate(sub['starts_at']),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _modeLabel(String mode) {
    switch (mode) {
      case 'paid':
        return 'پشتیبانی غیر رایگان';
      case 'hybrid':
        return 'ترکیبی (سهمیه رایگان + اشتراک)';
      default:
        return 'رایگان برای همه';
    }
  }

  IconData _modeIcon(String mode) {
    switch (mode) {
      case 'paid':
        return Icons.lock_outline_rounded;
      case 'hybrid':
        return Icons.tune_rounded;
      default:
        return Icons.volunteer_activism_outlined;
    }
  }

  Widget _buildPlansTab(ThemeData theme) {
    final cs = theme.colorScheme;

    if (_plans.isEmpty) {
      return const _EmptyHint(
        icon: Icons.workspace_premium_outlined,
        title: 'پلنی برای خرید فعال نیست',
        subtitle: 'فعلاً پلن پشتیبانی قابل خریدی تعریف نشده است.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          Text(
            'پلن مناسب خود را انتخاب کنید',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'پس از پرداخت، اشتراک پشتیبانی بلافاصله فعال می‌شود.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.65),
            ),
          ),
          if (_gateways.length > 1) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _selectedGatewayId,
              decoration: InputDecoration(
                labelText: 'درگاه پرداخت',
                filled: true,
                fillColor: cs.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              items: _gateways
                  .map(
                    (g) => DropdownMenuItem<int>(
                      value: g['id'] as int,
                      child: Text('${g['display_name']} (${g['provider']})'),
                    ),
                  )
                  .toList(),
              onChanged: _checkingOut ? null : (v) => setState(() => _selectedGatewayId = v),
            ),
          ],
          const SizedBox(height: 18),
          ..._plans.asMap().entries.map((entry) {
            final index = entry.key;
            final plan = entry.value;
            final isFree = plan['is_free'] == true || ((plan['price'] as num?) ?? 0) <= 0;
            final highlighted = index == 0 && !isFree;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _PlanCard(
                plan: plan,
                priceLabel: _formatPrice(plan['price']),
                highlighted: highlighted,
                checkingOut: _checkingOut,
                onCheckout: () => _checkout(plan),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInvoicesTab(ThemeData theme) {
    if (_invoices.isEmpty) {
      return const _EmptyHint(
        icon: Icons.receipt_long_outlined,
        title: 'صورت‌حسابی ثبت نشده است',
        subtitle: 'پس از خرید اشتراک، صورت‌حساب‌ها اینجا نمایش داده می‌شوند.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        itemCount: _invoices.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final inv = _invoices[i];
          final status = inv['status']?.toString();
          final statusColor = _invoiceStatusColor(status);
          final dateValue = inv['paid_at'] ?? inv['issued_at'];

          return _InvoiceCard(
            code: inv['code']?.toString() ?? '—',
            planName: inv['plan_name']?.toString() ?? '—',
            amountLabel: _formatPrice(inv['amount']),
            statusLabel: _invoiceStatusLabel(status),
            statusColor: statusColor,
            dateLabel: _formatDate(dateValue),
            gatewayTrace: inv['gateway_trace']?.toString(),
          );
        },
      ),
    );
  }
}

class _HeroAccessCard extends StatelessWidget {
  const _HeroAccessCard({
    required this.modeLabel,
    required this.modeIcon,
    required this.canCreate,
    required this.accent,
    required this.upsell,
    required this.onBuy,
  });

  final String modeLabel;
  final IconData modeIcon;
  final bool canCreate;
  final Color accent;
  final bool upsell;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            accent.withValues(alpha: 0.14),
            accent.withValues(alpha: 0.04),
            theme.colorScheme.surface,
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(modeIcon, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'وضعیت دسترسی',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      modeLabel,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  canCreate ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  color: accent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    canCreate
                        ? 'می‌توانید تیکت جدید ثبت کنید.'
                        : 'ثبت تیکت جدید فعلاً ممکن نیست.',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          if (upsell) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onBuy,
                icon: const Icon(Icons.shopping_bag_outlined),
                label: const Text('خرید اشتراک پشتیبانی'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Row(
      children: [
        Icon(icon, size: 18, color: muted),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
        const Spacer(),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.priceLabel,
    required this.highlighted,
    required this.checkingOut,
    required this.onCheckout,
  });

  final Map<String, dynamic> plan;
  final String priceLabel;
  final bool highlighted;
  final bool checkingOut;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final months = plan['period_months'];
    final isFree = plan['is_free'] == true || ((plan['price'] as num?) ?? 0) <= 0;
    final hasPriority = plan['includes_priority_support'] == true;
    final description = (plan['description'] ?? '').toString();
    final accent = highlighted ? cs.primary : cs.outline;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlighted ? cs.primary.withValues(alpha: 0.45) : cs.outline.withValues(alpha: 0.14),
          width: highlighted ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: highlighted ? cs.primary.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.04),
            blurRadius: highlighted ? 18 : 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            if (highlighted)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 4,
                  color: cs.primary,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isFree ? Icons.card_giftcard_rounded : Icons.workspace_premium_rounded,
                          color: highlighted ? cs.primary : cs.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan['name']?.toString() ?? '',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$months ماهه',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.65),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (highlighted)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'پیشنهادی',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    priceLabel,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: highlighted ? cs.primary : cs.onSurface,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.72),
                        height: 1.45,
                      ),
                    ),
                  ],
                  if (hasPriority) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF6C00).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFEF6C00).withValues(alpha: 0.35)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt_rounded, size: 16, color: Color(0xFFEF6C00)),
                          SizedBox(width: 4),
                          Text(
                            'پشتیبانی اولویت‌دار',
                            style: TextStyle(
                              color: Color(0xFFEF6C00),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: checkingOut ? null : onCheckout,
                      style: FilledButton.styleFrom(
                        backgroundColor: highlighted ? cs.primary : null,
                        foregroundColor: highlighted ? cs.onPrimary : null,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: checkingOut
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(isFree ? 'فعال‌سازی رایگان' : 'پرداخت و فعال‌سازی'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.code,
    required this.planName,
    required this.amountLabel,
    required this.statusLabel,
    required this.statusColor,
    required this.dateLabel,
    this.gatewayTrace,
  });

  final String code;
  final String planName;
  final String amountLabel;
  final String statusLabel;
  final Color statusColor;
  final String dateLabel;
  final String? gatewayTrace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      statusColor,
                      statusColor.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.receipt_long_rounded, color: statusColor, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  code,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  planName,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _StatusChip(label: statusLabel, color: statusColor),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              amountLabel,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.primary,
                              ),
                            ),
                          ),
                          Icon(Icons.calendar_today_rounded, size: 14, color: cs.onSurface.withValues(alpha: 0.5)),
                          const SizedBox(width: 4),
                          Text(
                            dateLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                      if (gatewayTrace != null && gatewayTrace!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'رهگیری درگاه: #$gatewayTrace',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: cs.primary.withValues(alpha: 0.75)),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.6),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFC62828)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('تلاش مجدد')),
          ],
        ),
      ),
    );
  }
}
