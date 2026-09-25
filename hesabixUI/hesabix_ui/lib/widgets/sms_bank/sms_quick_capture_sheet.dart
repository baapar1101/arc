import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../models/business_dashboard_models.dart';
import '../../pages/business/receipts_payments_list_page.dart' show BulkSettlementDialog;
import '../../services/business_dashboard_service.dart';
import '../../services/sms_bank/sms_bank_assistant_service.dart';
import '../../services/sms_bank/sms_bank_models.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/expense_income/expense_income_form_dialog.dart';
import '../../widgets/transfer/transfer_form_dialog.dart';

/// Bottom sheet: choose how to book a matched bank SMS (multi-business aware).
Future<void> showSmsQuickCaptureSheet({
  required BuildContext context,
  required SmsBankEvent event,
  AuthStore? authStore,
  CalendarController? calendarController,
}) async {
  final service = createSmsBankAssistantService();
  await showGlassModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      return _SmsQuickCaptureBody(
        event: event,
        authStore: authStore ?? ApiClient.getAuthStore(),
        calendarController: calendarController,
        service: service,
      );
    },
  );
}

class _SmsQuickCaptureBody extends StatefulWidget {
  final SmsBankEvent event;
  final AuthStore? authStore;
  final CalendarController? calendarController;
  final SmsBankAssistantService service;

  const _SmsQuickCaptureBody({
    required this.event,
    required this.authStore,
    required this.calendarController,
    required this.service,
  });

  @override
  State<_SmsQuickCaptureBody> createState() => _SmsQuickCaptureBodyState();
}

class _SmsQuickCaptureBodyState extends State<_SmsQuickCaptureBody> {
  late SmsBankEvent _event;
  late SmsBankDirection _direction;
  bool _busy = false;
  bool _showRaw = false;
  bool _loadingBusinesses = false;
  List<BusinessWithPermission> _userBusinesses = const [];
  BusinessWithPermission? _resolvedBusiness;

  final _businessService = BusinessDashboardService(ApiClient());

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _direction = _event.direction == SmsBankDirection.unknown
        ? SmsBankDirection.debit
        : _event.direction;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapBusinessContext();
    });
  }

  bool get _needsBusinessPick =>
      _event.needsBusinessChoice || _event.businessId == null;

  Color get _dirColor {
    switch (_direction) {
      case SmsBankDirection.credit:
        return const Color(0xFF2E7D32);
      case SmsBankDirection.debit:
        return const Color(0xFFC62828);
      case SmsBankDirection.unknown:
        return const Color(0xFF546E7A);
    }
  }

  String get _dirLabel {
    switch (_direction) {
      case SmsBankDirection.credit:
        return 'واریز';
      case SmsBankDirection.debit:
        return 'برداشت';
      case SmsBankDirection.unknown:
        return 'نامشخص';
    }
  }

  Future<void> _bootstrapBusinessContext() async {
    if (!mounted) return;
    setState(() => _loadingBusinesses = true);
    try {
      final list = await _businessService.getUserBusinesses();
      if (!mounted) return;
      setState(() => _userBusinesses = list);

      if (_event.businessId != null && !_event.needsBusinessChoice) {
        await _resolveAndSwitch(_event.businessId!);
        return;
      }

      // Enrich candidate names from user businesses
      if (_event.candidates.isNotEmpty) {
        final enriched = _event.candidates.map((c) {
          final hit = list.where((b) => b.id == c.businessId).toList();
          if (hit.isEmpty || (c.businessName != null && c.businessName!.isNotEmpty)) {
            return c;
          }
          return SmsBankBusinessCandidate(
            businessId: c.businessId,
            businessName: hit.first.name,
            patternId: c.patternId,
            patternName: c.patternName,
            bankAccountId: c.bankAccountId,
            bankAccountName: c.bankAccountName,
            confidence: c.confidence,
          );
        }).toList();
        setState(() {
          _event = _event.copyWith(candidates: enriched);
        });
      }

      // Single accessible business → auto-pick
      if (_event.businessId == null && list.length == 1) {
        await _chooseBusinessId(list.first.id, businessName: list.first.name);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در بارگذاری کسب‌وکارها');
      }
    } finally {
      if (mounted) setState(() => _loadingBusinesses = false);
    }
  }

  Future<void> _chooseBusinessId(int businessId, {String? businessName}) async {
    SmsBankBusinessCandidate? fromCandidates;
    for (final c in _event.candidates) {
      if (c.businessId == businessId) {
        fromCandidates = c;
        break;
      }
    }
    final chosen = fromCandidates ??
        SmsBankBusinessCandidate(
          businessId: businessId,
          businessName: businessName,
          patternId: _event.patternId,
          patternName: _event.patternName,
          bankAccountId: _event.bankAccountId,
          bankAccountName: _event.bankAccountName,
          confidence: _event.confidence,
        );

    final next = _event.withChosenBusiness(chosen).copyWith(
          businessName: chosen.businessName ?? businessName,
        );
    setState(() => _event = next);
    await widget.service.updateEvent(next);
    await _resolveAndSwitch(businessId);
  }

  Future<void> _resolveAndSwitch(int businessId) async {
    final auth = widget.authStore;
    if (auth == null) return;
    try {
      BusinessWithPermission biz;
      final cached = _userBusinesses.where((b) => b.id == businessId).toList();
      if (cached.isNotEmpty) {
        // Prefer fresh permissions for document dialogs
        try {
          biz = await _businessService.getBusinessWithPermissions(businessId);
        } catch (_) {
          biz = cached.first;
        }
      } else {
        biz = await _businessService.getBusinessWithPermissions(businessId);
      }
      if (!mounted) return;
      if (auth.currentBusiness?.id != businessId) {
        await auth.setCurrentBusiness(biz);
      }
      setState(() {
        _resolvedBusiness = biz;
        _event = _event.copyWith(
          businessId: businessId,
          businessName: biz.name,
          clearBusinessChoice: true,
          needsBusinessChoice: false,
        );
      });
      await widget.service.updateEvent(_event);
    } catch (_) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: 'امکان سوئیچ به کسب‌وکار انتخاب‌شده نیست',
        );
      }
    }
  }

  Future<void> _dismiss() async {
    await widget.service.updateEventStatus(_event.id, SmsBankEventStatus.dismissed);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _later() async {
    if (mounted) Navigator.of(context).pop();
  }

  Future<BusinessWithPermission?> _ensureBusinessReady() async {
    final businessId = _event.businessId;
    if (businessId == null) {
      SnackBarHelper.showError(context, message: 'ابتدا کسب‌وکار را انتخاب کنید');
      return null;
    }
    if (_resolvedBusiness?.id == businessId) return _resolvedBusiness;
    await _resolveAndSwitch(businessId);
    return _resolvedBusiness;
  }

  Future<void> _openReceiptPayment() async {
    final auth = widget.authStore;
    if (auth == null) return;
    setState(() => _busy = true);
    try {
      final biz = await _ensureBusinessReady();
      if (biz == null || !mounted) return;
      final cal = widget.calendarController ?? await CalendarController.load();
      if (!mounted) return;
      Navigator.of(context).pop();
      final isReceipt = _direction == SmsBankDirection.credit;
      await showGlassDialog<bool>(
        context: context,
        builder: (ctx) => BulkSettlementDialog(
          businessId: biz.id,
          calendarController: cal,
          isReceipt: isReceipt,
          businessInfo: biz,
          apiClient: ApiClient(),
          authStore: auth,
          initialAmount: _event.amount,
          initialBankId: _event.bankAccountId?.toString(),
          initialBankName: _event.bankAccountName,
          initialDescription: _defaultDescription(),
        ),
      );
      await widget.service.updateEventStatus(_event.id, SmsBankEventStatus.registered);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openExpenseIncome() async {
    final auth = widget.authStore;
    if (auth == null) return;
    setState(() => _busy = true);
    try {
      final biz = await _ensureBusinessReady();
      if (biz == null || !mounted) return;
      final cal = widget.calendarController ?? await CalendarController.load();
      if (!mounted) return;
      Navigator.of(context).pop();
      final isIncome = _direction == SmsBankDirection.credit;
      await showGlassDialog<bool>(
        context: context,
        builder: (ctx) => ExpenseIncomeFormDialog(
          businessId: biz.id,
          calendarController: cal,
          isIncome: isIncome,
          businessInfo: biz,
          apiClient: ApiClient(),
          initialAmount: _event.amount,
          initialBankId: _event.bankAccountId?.toString(),
          initialBankName: _event.bankAccountName,
          initialDescription: _defaultDescription(),
        ),
      );
      await widget.service.updateEventStatus(_event.id, SmsBankEventStatus.registered);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openInvoice() async {
    final biz = await _ensureBusinessReady();
    if (biz == null || !mounted) return;
    await widget.service.updateEventStatus(_event.id, SmsBankEventStatus.captured);
    if (!mounted) return;
    Navigator.of(context).pop();
    final amount = _event.amount;
    final note = Uri.encodeComponent(_defaultDescription());
    context.go('/business/${biz.id}/invoice/new?smsAmount=$amount&smsNote=$note');
  }

  Future<void> _openTransfer() async {
    final auth = widget.authStore;
    if (auth == null) return;
    setState(() => _busy = true);
    try {
      final biz = await _ensureBusinessReady();
      if (biz == null || !mounted) return;
      final cal = widget.calendarController ?? await CalendarController.load();
      if (!mounted) return;
      Navigator.of(context).pop();
      await showGlassDialog<bool>(
        context: context,
        builder: (ctx) => TransferFormDialog(
          businessId: biz.id,
          calendarController: cal,
          authStore: auth,
          apiClient: ApiClient(),
          initial: <String, dynamic>{
            'amount': _event.amount,
            'description': _defaultDescription(),
            if (_event.bankAccountId != null) 'from_bank_account_id': _event.bankAccountId,
          },
        ),
      );
      await widget.service.updateEventStatus(_event.id, SmsBankEventStatus.registered);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _defaultDescription() {
    final parts = <String>[
      'از پیامک بانکی',
      if (_event.businessName != null) _event.businessName!,
      if (_event.patternName != null) _event.patternName!,
      if (_event.channel != null) _event.channel!,
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amountText = formatWithThousands(_event.amount);
    final account = _event.bankAccountName ??
        _event.accountMask ??
        _event.patternName ??
        'حساب نامشخص';

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'تراکنش بانکی',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'بستن',
                onPressed: _busy ? null : _later,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _dirColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _dirColor.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _dirColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _dirLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() {
                                _direction = _direction == SmsBankDirection.credit
                                    ? SmsBankDirection.debit
                                    : SmsBankDirection.credit;
                              });
                            },
                      child: const Text('تغییر جهت'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '$amountText ریال',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _dirColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(account, style: theme.textTheme.bodyMedium),
                if (_event.businessName != null && !_needsBusinessPick) ...[
                  const SizedBox(height: 4),
                  Text(
                    'کسب‌وکار: ${_event.businessName}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _formatWhen(_event.receivedAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (_loadingBusinesses) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ] else if (_needsBusinessPick) ...[
            const SizedBox(height: 16),
            Text(
              'این پیامک مربوط به کدام کسب‌وکار است؟',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'به‌خاطر چند کسب‌وکار فعال، باید مقصد ثبت را مشخص کنید.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ..._businessPickTiles(theme),
          ] else ...[
            const SizedBox(height: 20),
            Text(
              'این مبلغ بابت چیست؟',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _ActionTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'دریافت و پرداخت',
              subtitle: 'مبلغ و حساب بانکی از قبل پر می‌شود',
              accent: theme.colorScheme.primary,
              onTap: _busy ? null : _openReceiptPayment,
            ),
            const SizedBox(height: 8),
            _ActionTile(
              icon: Icons.receipt_long_outlined,
              title: 'هزینه / درآمد',
              subtitle: _direction == SmsBankDirection.credit
                  ? 'پیشنهاد: درآمد'
                  : 'پیشنهاد: هزینه',
              accent: const Color(0xFF00897B),
              onTap: _busy ? null : _openExpenseIncome,
            ),
            const SizedBox(height: 8),
            _ActionTile(
              icon: Icons.description_outlined,
              title: 'فاکتور',
              subtitle: 'انتقال به فاکتور جدید با یادداشت مبلغ',
              accent: const Color(0xFF5E35B1),
              onTap: _busy ? null : _openInvoice,
            ),
            const SizedBox(height: 8),
            _ActionTile(
              icon: Icons.swap_horiz,
              title: 'انتقال بین حساب',
              subtitle: 'اگر جابه‌جایی بین حساب‌های خودتان بوده',
              accent: const Color(0xFFEF6C00),
              onTap: _busy ? null : _openTransfer,
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _showRaw = !_showRaw),
            child: Text(_showRaw ? 'مخفی کردن متن پیامک' : 'جزئیات پیامک'),
          ),
          if (_showRaw)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _event.body,
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _later,
                  child: const Text('بعداً بررسی می‌کنم'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextButton(
                  onPressed: _busy ? null : _dismiss,
                  child: const Text('نادیده بگیر'),
                ),
              ),
            ],
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
    );
  }

  List<Widget> _businessPickTiles(ThemeData theme) {
    final fromCandidates = _event.candidates.where((c) => c.businessId > 0).toList();
    if (fromCandidates.isNotEmpty) {
      return [
        for (final c in fromCandidates) ...[
          _ActionTile(
            icon: Icons.business_outlined,
            title: c.businessName ?? 'کسب‌وکار #${c.businessId}',
            subtitle: [
              if (c.bankAccountName != null) c.bankAccountName!,
              if (c.patternName != null) c.patternName!,
            ].where((e) => e.isNotEmpty).join(' · '),
            accent: theme.colorScheme.primary,
            onTap: _busy ? null : () => _chooseBusinessId(c.businessId, businessName: c.businessName),
          ),
          const SizedBox(height: 8),
        ],
      ];
    }

    if (_userBusinesses.isEmpty) {
      return [
        Text(
          'کسب‌وکاری برای انتخاب پیدا نشد.',
          style: theme.textTheme.bodyMedium,
        ),
      ];
    }

    return [
      for (final b in _userBusinesses) ...[
        _ActionTile(
          icon: Icons.business_outlined,
          title: b.name,
          subtitle: 'ثبت در این کسب‌وکار',
          accent: theme.colorScheme.primary,
          onTap: _busy ? null : () => _chooseBusinessId(b.id, businessName: b.name),
        ),
        const SizedBox(height: 8),
      ],
    ];
  }

  String _formatWhen(DateTime dt) {
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}/${two(l.month)}/${two(l.day)}  ${two(l.hour)}:${two(l.minute)}';
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback? onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_left, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
