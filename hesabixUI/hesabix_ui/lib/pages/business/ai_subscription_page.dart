import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import '../../utils/snackbar_helper.dart';

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
  UserAISubscription? _currentSubscription;
  List<AIPlan> _availablePlans = [];
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _aiService = AIService(api);
    _load();
  }

  Future<void> _load() async {
    if (_isRefreshing) return;
    setState(() {
      _loading = true;
      _isRefreshing = true;
    });
    try {
      final subscription = await _aiService.getCurrentSubscription(
        businessId: widget.businessId,
      );
      final plans = await _aiService.listAIPlans(onlyActive: true);
      setState(() {
        _currentSubscription = subscription;
        _availablePlans = plans;
        _loading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _isRefreshing = false;
      });
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا: $e');
      }
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
        SnackBarHelper.show(context, message: 'خطا: $e');
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
        SnackBarHelper.show(context, message: 'خطا: $e');
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
          SnackBarHelper.show(context, message: 'خطا: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('اشتراک AI')),
        body: const Center(child: CircularProgressIndicator()),
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
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: _SubscriptionHero(
                  subscription: _currentSubscription,
                  onCancel: _cancelSubscription,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: _UsageSummary(subscription: _currentSubscription),
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
                      onCancel: _cancelSubscription,
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

  const _SubscriptionHero({
    required this.subscription,
    required this.onCancel,
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
              theme.colorScheme.primary.withOpacity(0.15),
              theme.colorScheme.primary.withOpacity(0.05),
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
            color: theme.colorScheme.primary.withOpacity(0.2),
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
                  side: BorderSide(color: theme.colorScheme.onPrimary.withOpacity(0.6)),
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
              color: theme.colorScheme.onPrimary.withOpacity(0.8),
            ),
          ),
          if (subscription!.periodEnd != null) ...[
            const SizedBox(height: 12),
            Text(
              'تاریخ انقضا: ${_formatDate(subscription!.periodEnd!)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimary.withOpacity(0.9),
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

  String _formatDate(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }
}

class _UsageSummary extends StatelessWidget {
  final UserAISubscription? subscription;

  const _UsageSummary({required this.subscription});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (subscription == null) {
      return const SizedBox.shrink();
    }

    final tokensLimit = subscription!.tokensLimit ?? 0;
    final tokensUsed = subscription!.tokensUsed;
    final remaining = subscription!.remainingTokens;
    final usageRatio = (tokensLimit > 0) ? (tokensUsed / tokensLimit).clamp(0.0, 1.0) : 0.0;

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
                    label: Text('تا ${_formatDate(subscription!.periodEnd!)}'),
                  )
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _InfoCard(
                    label: 'مصرف شده',
                    value: '$tokensUsed',
                    icon: Icons.data_usage,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoCard(
                    label: tokensLimit == 0 ? 'نامحدود' : 'باقی‌مانده',
                    value: tokensLimit == 0 ? '∞' : '$remaining',
                    icon: Icons.savings_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoCard(
                    label: 'حداکثر توکن',
                    value: tokensLimit == 0 ? 'نامحدود' : '$tokensLimit',
                    icon: Icons.speed,
                  ),
                ),
              ],
            ),
            if (tokensLimit > 0) ...[
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

  String _formatDate(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }
}

class _PlanGrid extends StatelessWidget {
  final List<AIPlan> plans;
  final UserAISubscription? currentSubscription;
  final void Function(AIPlan plan) onSelect;
  final void Function(AIPlan plan) onUpgrade;
  final VoidCallback onCancel;

  const _PlanGrid({
    required this.plans,
    required this.currentSubscription,
    required this.onSelect,
    required this.onUpgrade,
    required this.onCancel,
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
                onCancel: onCancel,
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
  final VoidCallback onCancel;

  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.canUpgrade,
    required this.onSelect,
    required this.onUpgrade,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                      : 'سقف توکن ${plan.tokensLimit}',
                ),
                if (plan.monthlyTokensLimit != null)
                  _FeatureChip(
                    icon: Icons.calendar_month,
                    label: 'سقف ماهانه ${plan.monthlyTokensLimit}',
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
                  OutlinedButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.cancel_schedule_send_outlined),
                    label: const Text('لغو اشتراک'),
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
              Text(
                label,
                style: theme.textTheme.bodySmall,
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

