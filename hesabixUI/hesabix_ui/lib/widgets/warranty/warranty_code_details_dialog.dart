import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../models/warranty_models.dart';
import '../../core/date_utils.dart';
import '../../core/calendar_controller.dart';
import '../../utils/snackbar_helper.dart';

class WarrantyCodeDetailsDialog extends StatelessWidget {
  final WarrantyCode warrantyCode;
  final CalendarController calendarController;

  const WarrantyCodeDetailsDialog({
    super.key,
    required this.warrantyCode,
    required this.calendarController,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user, color: colorScheme.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'جزئیات کد گارانتی',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: colorScheme.onPrimaryContainer),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(context, theme, t.warrantyCode, warrantyCode.code),
                    _buildInfoRow(context, theme, t.warrantySerial, warrantyCode.warrantySerial),
                    _buildInfoRow(
                      context,
                      theme,
                      t.warrantyStatus,
                      _getStatusLabel(warrantyCode.status, t),
                    ),
                    _buildInfoRow(
                      context,
                      theme,
                      t.warrantyGeneratedAt,
                      HesabixDateUtils.formatDateTime(warrantyCode.generatedAt, calendarController.isJalali),
                    ),
                    if (warrantyCode.activatedAt != null)
                      _buildInfoRow(
                        context,
                        theme,
                        t.warrantyActivatedAt,
                        HesabixDateUtils.formatDateTime(warrantyCode.activatedAt!, calendarController.isJalali),
                      ),
                    if (warrantyCode.expiresAt != null)
                      _buildInfoRow(
                        context,
                        theme,
                        t.warrantyExpiresAt,
                        HesabixDateUtils.formatDateTime(warrantyCode.expiresAt!, calendarController.isJalali),
                      ),
                    _buildInfoRow(
                      context,
                      theme,
                      t.warrantyDurationDays,
                      '${warrantyCode.warrantyDurationDays} روز',
                    ),
                    if (warrantyCode.trackingLinkCode != null)
                      _buildInfoRow(
                        context,
                        theme,
                        t.warrantyTrackingLink,
                        warrantyCode.trackingLinkCode!,
                      ),
                    if (warrantyCode.status == WarrantyStatus.generated) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      _buildActivationSection(context, theme, colorScheme),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('بستن'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusLabel(WarrantyStatus status, AppLocalizations t) {
    switch (status) {
      case WarrantyStatus.generated:
        return t.warrantyGenerated;
      case WarrantyStatus.activated:
        return t.warrantyActivated;
      case WarrantyStatus.expired:
        return t.warrantyExpired;
      case WarrantyStatus.used:
        return t.warrantyUsed;
      case WarrantyStatus.revoked:
        return t.warrantyRevoked;
    }
  }

  Widget _buildActivationSection(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    final baseUrl = Uri.base.origin;
    final activationLink = '$baseUrl/public/warranty/activate/${warrantyCode.businessId}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.link, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'لینک فعال‌سازی',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outline),
          ),
          child: SelectableText(
            activationLink,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: activationLink));
                  SnackBarHelper.showSuccess(context, message: 'لینک کپی شد');
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('کپی لینک'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  context.push('/public/warranty/activate/${warrantyCode.businessId}');
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('باز کردن'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

