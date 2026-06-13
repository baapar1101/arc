import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

class AISubscriptionPage extends StatefulWidget {
  final int? businessId;
  final AuthStore authStore;

  const AISubscriptionPage({
    super.key,
    this.businessId,
    required this.authStore,
  });

  @override
  State<AISubscriptionPage> createState() => _AISubscriptionPageState();
}

class _AISubscriptionPageState extends State<AISubscriptionPage> {
  late final AIService _aiService;
  bool _loading = true;
  String? _loadError;
  UserAISubscription? _currentSubscription;
  List<AIPlan> _availablePlans = [];
  Map<String, dynamic> _usageStats = {};
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _aiService = AIService(api);
    _load();
  }

  Future<Map<String, dynamic>> _loadUsageStatsSafe() async {
    try {
      return await _aiService.getSubscriptionUsageStats(
        businessId: widget.businessId,
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _load() async {
    if (_isRefreshing) return;
    setState(() {
      _loading = true;
      _isRefreshing = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        _aiService.getCurrentSubscription(businessId: widget.businessId),
        _aiService.listPublicAIPlans(businessId: widget.businessId),
        _loadUsageStatsSafe(),
      ]);
      if (!mounted) return;
      setState(() {
        _currentSubscription = results[0] as UserAISubscription?;
        _availablePlans = results[1] as List<AIPlan>;
        _usageStats = results[2] as Map<String, dynamic>;
        _loading = false;
        _isRefreshing = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      setState(() {
        _loading = false;
        _isRefreshing = false;
        _loadError = ErrorExtractor.extractErrorMessage(e, t);
      });
    }
  }

  Future<void> _subscribeToPlan(AIPlan plan) async {
    try {
      await _aiService.subscribeToPlan(
        planId: plan.id!,
        businessId: widget.businessId,
      );
      if (mounted) {
        SnackBarHelper.show(context, message: 'اشتراک با موفقیت فعال شد');
        _load();
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.extractErrorMessage(e, t),
        );
      }
    }
  }

  Future<void> _upgradeSubscription(AIPlan newPlan) async {
    try {
      await _aiService.upgradeSubscription(
        newPlanId: newPlan.id!,
        businessId: widget.businessId,
      );
      if (mounted) {
        SnackBarHelper.show(context, message: 'اشتراک با موفقیت ارتقا یافت');
        _load();
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.extractErrorMessage(e, t),
        );
      }
    }
  }

  Future<void> _cancelSubscription() async {
    if (await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('لغو اشتراک'),
            content: const Text('آیا از لغو اشتراک اطمینان دارید؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('لغو'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('لغو اشتراک'),
              ),
            ],
          ),
        ) ??
        false) {
      try {
        await _aiService.cancelSubscription(businessId: widget.businessId);
        if (mounted) {
          SnackBarHelper.show(context, message: 'اشتراک لغو شد');
          _load();
        }
      } catch (e) {
        if (mounted) {
          final t = AppLocalizations.of(context);
          SnackBarHelper.showError(
            context,
            message: ErrorExtractor.extractErrorMessage(e, t),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isJalali = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('fa');

    if (_loading && _loadError == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('اشتراک AI')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null &&
        _currentSubscription == null &&
        _availablePlans.isEmpty &&
        !_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('اشتراک هوش مصنوعی'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () {
              if (context.canPop()) context.pop();
            },
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  'بارگذاری اطلاعات انجام نشد.',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _loadError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('تلاش دوباره'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('اشتراک هوش مصنوعی'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () {
            if (!mounted) return;
            if (context.canPop()) {
              context.pop();
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: _SubscriptionHero(
                  subscription: _currentSubscription,
                  onCancel: _cancelSubscription,
                  isJalali: isJalali,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: _UsageSummary(
                  subscription: _currentSubscription,
                  usageStats: _usageStats,
                  isJalali: isJalali,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'پلن‌های موجود',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PlanGrid(
                      plans: _availablePlans,
                      currentSubscription: _currentSubscription,
                      onSelect: _subscribeToPlan,
                      onUpgrade: _upgradeSubscription,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionHero extends StatelessWidget {
  final UserAISubscription? subscription;
  final VoidCallback onCancel;
  final bool isJalali;

  const _SubscriptionHero({
    required this.subscription,
    required this.onCancel,
    required this.isJalali,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (subscription == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.15),
              theme.colorScheme.primary.withValues(alpha: 0.05),
            ],
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.bolt_outlined, size: 32, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              'اشتراک فعال ندارید',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'برای استفاده از دستیار هوش مصنوعی، یکی از پلن‌های زیر را فعال کنید.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    final plan = subscription!.plan;
    final planName = plan?.name ?? 'پلن فعال';
    final planType = plan?.planType ?? AIPlanType.free;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primaryContainer,
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified, color: theme.colorScheme.onPrimary, size: 32),
              const SizedBox(width: 12),
              Text(
                'اشتراک فعال',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.onPrimary,
                  side: BorderSide(color: theme.colorScheme.onPrimary.withValues(alpha: 0.6)),
                ),
                onPressed: onCancel,
                icon: const Icon(Icons.power_settings_new, size: 18),
                label: const Text('غیرفعال‌سازی'),
              )
            ],
          ),
          const SizedBox(height: 18),
          Text(
            planName,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _planBadge(planType),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
            ),
          ),
          if (subscription!.periodEnd != null) ...[
            const SizedBox(height: 12),
            Text(
              'تاریخ انقضا: ${HesabixDateUtils.formatForDisplay(subscription!.periodEnd!.toLocal(), isJalali)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.9),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _planBadge(AIPlanType type) {
    switch (type) {
      case AIPlanType.free:
        return 'پلن رایگان';
      case AIPlanType.subscription:
        return 'پلن اشتراکی';
      case AIPlanType.payAsGo:
        return 'پرداخت به ازای استفاده';
      case AIPlanType.hybrid:
        return 'پلن ترکیبی';
    }
  }
}

class _UsageSummary extends StatelessWidget {
  final UserAISubscription? subscription;
  final Map<String, dynamic> usageStats;
  final bool isJalali;

  const _UsageSummary({
    required this.subscription,
    required this.usageStats,
    required this.isJalali,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (subscription == null) {
      return const SizedBox.shrink();
    }

    final hasCap = subscription!.hasTokenCap;
    final tokensLimit = subscription!.tokensLimit;
    final tokensUsed = subscription!.tokensUsed;
    final remaining = subscription!.remainingTokens;
    final usageRatio = hasCap && (tokensLimit ?? 0) > 0
        ? (tokensUsed / (tokensLimit!)).clamp(0.0, 1.0)
        : 0.0;

    final int logTokens = (usageStats['total_tokens'] as num?)?.toInt() ?? 0;
    final int logRequests = (usageStats['total_requests'] as num?)?.toInt() ?? 0;
    final bool hasAnyLog = logTokens > 0 || logRequests > 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'وضعیت استفاده',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (subscription!.periodEnd != null)
                  Chip(
                    avatar: Icon(Icons.hourglass_bottom,
                        size: 16, color: theme.colorScheme.primary),
                    label: Text(
                      'تا ${HesabixDateUtils.formatForDisplay(
                        subscription!.periodEnd!.toLocal(),
                        isJalali,
                      )}',
                    ),
                  )
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _InfoCard(
                    label: 'مصرف شده (سهمیه)',
                    value: formatWithThousands(tokensUsed),
                    icon: Icons.data_usage,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoCard(
                    label: !hasCap ? 'باقی‌مانده' : 'باقی‌مانده (سهمیه)',
                    value: !hasCap
                        ? '∞'
                        : formatWithThousands(remaining ?? 0),
                    icon: Icons.savings_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoCard(
                    label: 'حداکثر توکن (دوره)',
                    value: !hasCap
                        ? 'نامحدود'
                        : formatWithThousands(tokensLimit!),
                    icon: Icons.speed,
                  ),
                ),
              ],
            ),
            if (hasAnyLog) ...[
              const SizedBox(height: 16),
              Text(
                'ثبت در لاگ (تمام زمانه)',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (logTokens > 0)
                    Chip(
                      avatar: Icon(Icons.notes, size: 16, color: theme.colorScheme.secondary),
                      label: Text('مجموع توکن ثبت‌شده: ${formatWithThousands(logTokens)}'),
                    ),
                  if (logRequests > 0)
                    Chip(
                      avatar: Icon(Icons.request_quote, size: 16, color: theme.colorScheme.secondary),
                      label: Text('تعداد درخواست: ${formatWithThousands(logRequests)}'),
                    ),
                ],
              ),
            ],
            if (hasCap) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: usageRatio,
                borderRadius: BorderRadius.circular(8),
                minHeight: 8,
              ),
              const SizedBox(height: 6),
              Text(
                '${(usageRatio * 100).toStringAsFixed(1)}% از سهمیه مصرف شده است',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanGrid extends StatelessWidget {
  final List<AIPlan> plans;
  final UserAISubscription? currentSubscription;
  final void Function(AIPlan plan) onSelect;
  final void Function(AIPlan plan) onUpgrade;

  const _PlanGrid({
    required this.plans,
    required this.currentSubscription,
    required this.onSelect,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) {
      return const Text('پلنی برای نمایش وجود ندارد');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth;
        final int crossAxisCount = maxWidth > 1000
            ? 3
            : maxWidth > 700
                ? 2
                : 1;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: plans.map((plan) {
            final bool isCurrentPlan = currentSubscription?.planId == plan.id;
            final bool canUpgrade = currentSubscription != null &&
                !isCurrentPlan &&
                plan.planType != AIPlanType.free;

            return SizedBox(
              width: maxWidth / crossAxisCount - (crossAxisCount > 1 ? 16 : 0),
              child: _PlanCard(
                plan: plan,
                isCurrent: isCurrentPlan,
                canUpgrade: canUpgrade,
                onSelect: () => onSelect(plan),
                onUpgrade: () => onUpgrade(plan),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _PlanCard extends StatelessWidget {
  final AIPlan plan;
  final bool isCurrent;
  final bool canUpgrade;
  final VoidCallback onSelect;
  final VoidCallback onUpgrade;

  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.canUpgrade,
    required this.onSelect,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priceText = _planPriceText(plan);
    return Card(
      elevation: isCurrent ? 6 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _planTypeLabel(plan.planType),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCurrent)
                  Chip(
                    avatar: Icon(Icons.check, color: theme.colorScheme.onPrimary),
                    backgroundColor: theme.colorScheme.primary,
                    label: Text(
                      'پلن فعال',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
              ],
            ),
            if (priceText != null) ...[
              const SizedBox(height: 8),
              Text(
                priceText,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
            if (plan.description != null) ...[
              const SizedBox(height: 12),
              Text(
                plan.description!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FeatureChip(
                  icon: Icons.token,
                  label: plan.tokensLimit == null
                      ? 'توکن نامحدود'
                      : 'سقف توکن ${formatWithThousands(plan.tokensLimit)}',
                ),
                if (plan.monthlyTokensLimit != null)
                  _FeatureChip(
                    icon: Icons.calendar_month,
                    label: 'سقف ماهانه ${formatWithThousands(plan.monthlyTokensLimit)}',
                  ),
                if (plan.autoRenew)
                  const _FeatureChip(
                    icon: Icons.autorenew,
                    label: 'تمدید خودکار',
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isCurrent)
                  Expanded(
                    child: Text(
                      'این پلن برای شما فعال است؛ برای تغییر، پلن دیگری را انتخاب کنید.',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else if (canUpgrade)
                  FilledButton.icon(
                    onPressed: onUpgrade,
                    icon: const Icon(Icons.trending_up),
                    label: const Text('ارتقا'),
                  )
                else
                  FilledButton.icon(
                    onPressed: onSelect,
                    icon: const Icon(Icons.playlist_add_check),
                    label: const Text('فعال‌سازی'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _planPriceText(AIPlan plan) {
    final pc = plan.pricingConfig;
    if (pc.isEmpty) return null;
    if (plan.planType == AIPlanType.free) {
      return 'رایگان';
    }
    if (plan.planType == AIPlanType.subscription || plan.planType == AIPlanType.hybrid) {
      final sub = pc['subscription'];
      if (sub is Map) {
        final m = sub['monthly_price'];
        final y = sub['yearly_price'];
        final parts = <String>[];
        if (m != null) {
          final n = m is num ? m.toDouble() : double.tryParse(m.toString());
          if (n != null && n > 0) {
            parts.add('${formatWithThousands(n)} تومان / ماه');
          }
        }
        if (y != null) {
          final n = y is num ? y.toDouble() : double.tryParse(y.toString());
          if (n != null && n > 0) {
            parts.add('${formatWithThousands(n)} تومان / سال');
          }
        }
        if (parts.isNotEmpty) {
          return parts.join(' — ');
        }
      }
    }
    if (plan.planType == AIPlanType.payAsGo) {
      final p = pc['pay_as_go'];
      if (p is Map) {
        final inP = p['price_per_1k_input_tokens'];
        final outP = p['price_per_1k_output_tokens'];
        if (inP != null || outP != null) {
          return 'پرداخت بر اساس مصرف (هر ۱۰۰۰ توکن: ورودی/خروجی متفاوت)';
        }
      }
    }
    return null;
  }

  String _planTypeLabel(AIPlanType type) {
    switch (type) {
      case AIPlanType.free:
        return 'رایگان';
      case AIPlanType.subscription:
        return 'اشتراکی';
      case AIPlanType.payAsGo:
        return 'پرداخت به ازای استفاده';
      case AIPlanType.hybrid:
        return 'ترکیبی';
    }
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      avatar: Icon(icon, size: 16, color: theme.colorScheme.primary),
      label: Text(label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _InfoCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
