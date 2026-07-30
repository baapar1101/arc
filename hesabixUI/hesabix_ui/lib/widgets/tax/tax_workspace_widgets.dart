import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// چیپ وضعیت ارسال مالیاتی با رنگ معنادار
class TaxStatusChip extends StatelessWidget {
  final String status;
  final AppLocalizations t;
  final VoidCallback? onTap;

  const TaxStatusChip({
    super.key,
    required this.status,
    required this.t,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = _metaFor(status, t, theme);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: meta.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: meta.fg.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: 14, color: meta.fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              meta.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: meta.fg,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: chip,
    );
  }

  static _StatusMeta _metaFor(String status, AppLocalizations t, ThemeData theme) {
    switch (status) {
      case 'pending':
        return _StatusMeta(
          t.taxStatusPending,
          Icons.hourglass_top_rounded,
          const Color(0xFFB45309),
          const Color(0xFFFFF7ED),
        );
      case 'sent':
        return _StatusMeta(
          t.taxStatusSent,
          Icons.cloud_done_outlined,
          const Color(0xFF1D4ED8),
          const Color(0xFFEFF6FF),
        );
      case 'finalized':
      case 'success':
      case 'accepted':
        return _StatusMeta(
          t.taxStatusFinalized,
          Icons.verified_outlined,
          const Color(0xFF047857),
          const Color(0xFFECFDF5),
        );
      case 'failed':
        return _StatusMeta(
          t.taxStatusFailed,
          Icons.error_outline,
          theme.colorScheme.error,
          theme.colorScheme.errorContainer.withValues(alpha: 0.45),
        );
      case 'cancelled':
        return _StatusMeta(
          t.taxStatusCancelled,
          Icons.cancel_outlined,
          theme.colorScheme.onSurfaceVariant,
          theme.colorScheme.surfaceContainerHighest,
        );
      case 'not_sent':
      default:
        return _StatusMeta(
          t.taxStatusNotSent,
          Icons.outgoing_mail,
          theme.colorScheme.onSurfaceVariant,
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        );
    }
  }
}

class _StatusMeta {
  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;
  const _StatusMeta(this.label, this.icon, this.fg, this.bg);
}

/// نوار KPI صف‌های کارپوشه
class TaxWorkspaceKpiStrip extends StatelessWidget {
  final Map<String, int> counts;
  final String? selectedStatus;
  final ValueChanged<String?> onSelect;
  final AppLocalizations t;

  const TaxWorkspaceKpiStrip({
    super.key,
    required this.counts,
    required this.selectedStatus,
    required this.onSelect,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final items = <_KpiItem>[
      _KpiItem(null, t.taxKpiAll, counts['all'] ?? 0, Icons.inbox_outlined, const Color(0xFF475569)),
      _KpiItem('not_sent', t.taxKpiQueue, counts['not_sent'] ?? 0, Icons.outgoing_mail, const Color(0xFF64748B)),
      _KpiItem('pending', t.taxKpiPending, counts['pending'] ?? 0, Icons.hourglass_top_rounded, const Color(0xFFB45309)),
      _KpiItem('failed', t.taxKpiFailed, counts['failed'] ?? 0, Icons.error_outline, const Color(0xFFDC2626)),
      _KpiItem('finalized', t.taxKpiSuccess, (counts['finalized'] ?? 0) + (counts['success'] ?? 0) + (counts['sent'] ?? 0), Icons.verified_outlined, const Color(0xFF059669)),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          for (final item in items) ...[
            _KpiCard(
              item: item,
              selected: selectedStatus == item.status,
              onTap: () => onSelect(item.status),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _KpiItem {
  final String? status;
  final String label;
  final int count;
  final IconData icon;
  final Color accent;
  const _KpiItem(this.status, this.label, this.count, this.icon, this.accent);
}

class _KpiCard extends StatelessWidget {
  final _KpiItem item;
  final bool selected;
  final VoidCallback onTap;

  const _KpiCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? item.accent.withValues(alpha: 0.14)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 118,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? item.accent.withValues(alpha: 0.55) : theme.colorScheme.outline.withValues(alpha: 0.18),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(item.icon, size: 16, color: item.accent),
                  const Spacer(),
                  Text(
                    '${item.count}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: item.accent,
                      height: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// چیپ سلامت اتصال مودیان
class TaxHealthChip extends StatelessWidget {
  final bool? healthy;
  final bool loading;
  final String? message;
  final VoidCallback onTap;
  final VoidCallback? onRetry;
  final AppLocalizations t;

  const TaxHealthChip({
    super.key,
    required this.healthy,
    required this.loading,
    required this.message,
    required this.onTap,
    required this.t,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color fg;
    Color bg;
    IconData icon;
    String label;

    if (loading) {
      fg = theme.colorScheme.primary;
      bg = theme.colorScheme.primaryContainer.withValues(alpha: 0.5);
      icon = Icons.sync;
      label = t.taxHealthChecking;
    } else if (healthy == true) {
      fg = const Color(0xFF047857);
      bg = const Color(0xFFECFDF5);
      icon = Icons.cloud_done_outlined;
      label = t.taxHealthConnected;
    } else if (healthy == false) {
      fg = theme.colorScheme.error;
      bg = theme.colorScheme.errorContainer.withValues(alpha: 0.55);
      icon = Icons.cloud_off_outlined;
      label = t.taxHealthDisconnected;
    } else {
      fg = theme.colorScheme.onSurfaceVariant;
      bg = theme.colorScheme.surfaceContainerHighest;
      icon = Icons.cloud_queue_outlined;
      label = t.taxHealthUnknown;
    }

    return Tooltip(
      message: message ?? label,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                else
                  Icon(icon, size: 16, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (healthy == false) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_left, size: 16, color: fg),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// کارت فاکتور برای موبایل در کارپوشه
class TaxWorkspaceMobileCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final AppLocalizations t;
  final bool isJalali;
  final String Function(DateTime?, bool) formatDate;
  final VoidCallback? onSend;
  final VoidCallback? onDetails;
  final VoidCallback? onOpenInvoice;
  final VoidCallback? onRemove;
  final List<PopupMenuEntry<String>> Function()? moreActions;
  final void Function(String value)? onMoreSelected;

  const TaxWorkspaceMobileCard({
    super.key,
    required this.item,
    required this.t,
    required this.isJalali,
    required this.formatDate,
    this.onSend,
    this.onDetails,
    this.onOpenInvoice,
    this.onRemove,
    this.moreActions,
    this.onMoreSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = item['code']?.toString() ?? '-';
    final typeName = item['document_type_name']?.toString() ?? item['document_type']?.toString() ?? '';
    final status = item['tax_status']?.toString() ?? 'not_sent';
    final amount = item['total_amount'];
    final currency = item['currency_code']?.toString() ?? t.taxCurrencyRial;
    final tracking = item['tax_tracking_code']?.toString();
    final err = item['tax_error_message']?.toString();
    final counterparty = item['counterparty']?.toString() ??
        item['person_name']?.toString() ??
        '';

    DateTime? docDate;
    final raw = item['document_date'];
    if (raw is String) docDate = DateTime.tryParse(raw);
    if (raw is DateTime) docDate = raw;

    final canSend = status != 'sent' && status != 'finalized' && item['tax_cancelled_in_modian'] != true;
    final hasFailure = status == 'failed' || (err != null && err.isNotEmpty);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasFailure
              ? theme.colorScheme.error.withValues(alpha: 0.35)
              : theme.colorScheme.outline.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onOpenInvoice,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        code,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (typeName.isNotEmpty) typeName,
                          if (counterparty.isNotEmpty) counterparty,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              TaxStatusChip(
                status: status,
                t: t,
                onTap: hasFailure ? onDetails : null,
              ),
              if (moreActions != null)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: onMoreSelected,
                  itemBuilder: (_) => moreActions!(),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _miniMeta(theme, Icons.event, formatDate(docDate, isJalali)),
              if (amount != null)
                _miniMeta(theme, Icons.payments_outlined, '$amount $currency'),
              if (tracking != null && tracking.isNotEmpty)
                _miniMeta(theme, Icons.tag, tracking),
            ],
          ),
          if (hasFailure && err != null && err.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              err.length > 90 ? '${err.substring(0, 90)}…' : err,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (canSend)
                FilledButton.tonalIcon(
                  onPressed: onSend,
                  icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: Text(t.taxSendSingle),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              if (hasFailure) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onDetails,
                  icon: const Icon(Icons.healing_outlined, size: 18),
                  label: Text(t.taxFixNow),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: theme.colorScheme.error,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
              const Spacer(),
              if (onRemove != null && canSend)
                IconButton(
                  tooltip: t.taxRemoveFromWorkspaceSingle,
                  onPressed: onRemove,
                  icon: Icon(Icons.remove_circle_outline, color: theme.colorScheme.error),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniMeta(ThemeData theme, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(text, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// نوار چسبان عملیات انتخاب‌شده (موبایل)
class TaxWorkspaceStickyBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback? onSend;
  final VoidCallback? onInquire;
  final VoidCallback? onRemove;
  final AppLocalizations t;

  const TaxWorkspaceStickyBar({
    super.key,
    required this.selectedCount,
    required this.t,
    this.onSend,
    this.onInquire,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedCount <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2))),
          ),
          child: Row(
            children: [
              Text(
                t.taxStickySelected(selectedCount),
                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                tooltip: t.taxInquireSelectedTooltip,
                onPressed: onInquire,
                icon: const Icon(Icons.sync),
              ),
              IconButton(
                tooltip: t.taxRemoveSelectedTooltip,
                onPressed: onRemove,
                icon: Icon(Icons.remove_circle_outline, color: theme.colorScheme.error),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: onSend,
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: Text(t.taxStickySend),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// حالت خالی غنی‌تر
class TaxWorkspaceEmptyState extends StatelessWidget {
  final AppLocalizations t;
  final VoidCallback onRefresh;
  final VoidCallback onOpenInvoices;
  final VoidCallback onOpenSettings;

  const TaxWorkspaceEmptyState({
    super.key,
    required this.t,
    required this.onRefresh,
    required this.onOpenInvoices,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.18),
                  theme.colorScheme.tertiary.withValues(alpha: 0.12),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(Icons.account_balance_outlined, size: 40, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 18),
          Text(
            t.taxEmptyStateTitle,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            t.taxEmptyStateHint,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: onOpenInvoices,
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(t.taxEmptyStateGoInvoices),
              ),
              OutlinedButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
                label: Text(t.taxSettingsOpen),
              ),
              TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: Text(t.refresh),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// کارت راهنمای یک خطای مودیان (playbook)
class TaxErrorPlaybookCard extends StatelessWidget {
  final Map<String, dynamic> error;
  final AppLocalizations t;
  final VoidCallback? onAction;

  const TaxErrorPlaybookCard({
    super.key,
    required this.error,
    required this.t,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = error['code']?.toString();
    final title = error['title']?.toString() ?? error['message']?.toString() ?? t.taxSubmissionFailedTitle;
    final explanation = error['explanation']?.toString();
    final action = error['action']?.toString();
    final actionLabel = error['action_label']?.toString() ?? t.taxFixNow;
    final severity = error['severity']?.toString() ?? 'error';
    final isWarn = severity == 'warning';
    final accent = isWarn ? const Color(0xFFB45309) : theme.colorScheme.error;
    final bg = isWarn
        ? const Color(0xFFFFF7ED)
        : theme.colorScheme.errorContainer.withValues(alpha: 0.35);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(isWarn ? Icons.warning_amber_rounded : Icons.report_gmailerrorred_outlined, color: accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: accent)),
                    if (code != null && code.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${t.taxErrorCodeLabel}: $code',
                          style: theme.textTheme.labelSmall?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (explanation != null && explanation.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(t.taxErrorPlaybookWhat, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(explanation, style: theme.textTheme.bodySmall),
          ],
          if (action != null && action.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(t.taxErrorPlaybookHow, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(action, style: theme.textTheme.bodySmall),
          ],
          if (onAction != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                onPressed: onAction,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: Text(actionLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
