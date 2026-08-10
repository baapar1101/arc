import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart';
import '../../../models/business_models.dart';
import '../../../utils/responsive_helper.dart';
import 'new_business_labels.dart';
import 'new_business_shared.dart';

class NewBusinessReviewStep extends StatelessWidget {
  final BusinessData data;
  final List<Map<String, dynamic>> currencies;
  final CalendarController calendarController;
  final ValueChanged<int> onEditStep;

  const NewBusinessReviewStep({
    super.key,
    required this.data,
    required this.currencies,
    required this.calendarController,
    required this.onEditStep,
  });

  String? _currencyLabel(int? id) {
    if (id == null) return null;
    for (final c in currencies) {
      if (c['id'] == id) {
        return '${c['title']} (${c['code']})';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final spacing = ResponsiveHelper.responsiveValue(
      context,
      mobile: 18,
      tablet: 20,
      desktop: 22,
    );
    final fiscal = data.fiscalYears.isNotEmpty ? data.fiscalYears.first : null;
    final defaultCurrency = _currencyLabel(data.defaultCurrencyId);
    final extraCurrencies = data.currencyIds
        .where((id) => id != data.defaultCurrencyId)
        .map(_currencyLabel)
        .whereType<String>()
        .toList();

    String? dateRange;
    if (fiscal?.startDate != null && fiscal?.endDate != null) {
      final isJalali = calendarController.isJalali;
      dateRange =
          '${HesabixDateUtils.formatForDisplay(fiscal!.startDate, isJalali)} — ${HesabixDateUtils.formatForDisplay(fiscal.endDate, isJalali)}';
    }

    return NewBusinessFormShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NewBusinessSectionHeader(
            title: t.newBusinessReviewStepTitle,
            subtitle: t.newBusinessReviewStepSubtitle,
          ),
          SizedBox(height: spacing * 1.1),
          _ReviewCard(
            title: t.newBusinessIdentityStepTitle,
            onEdit: () => onEditStep(0),
            children: [
              _ReviewRow(label: t.businessName, value: data.name),
              _ReviewRow(
                label: t.businessType,
                value: data.businessType == null
                    ? '—'
                    : localizedBusinessType(t, data.businessType!),
              ),
              _ReviewRow(
                label: t.businessField,
                value: data.businessField == null
                    ? '—'
                    : localizedBusinessField(t, data.businessField!),
              ),
              _ReviewRow(
                label: t.newBusinessSampleDataShort,
                value: data.includeSampleData ? '✓' : '—',
              ),
            ],
          ),
          SizedBox(height: spacing * 0.85),
          _ReviewCard(
            title: t.newBusinessCurrencyAndFiscal,
            onEdit: () => onEditStep(1),
            children: [
              _ReviewRow(
                label: t.defaultCurrency,
                value: defaultCurrency ?? '—',
              ),
              if (extraCurrencies.isNotEmpty)
                _ReviewRow(
                  label: t.extraCurrencies,
                  value: extraCurrencies.join(' · '),
                ),
              _ReviewRow(
                label: t.fiscalYearTitleLabel,
                value: fiscal?.title.isNotEmpty == true ? fiscal!.title : '—',
              ),
              if (dateRange != null)
                _ReviewRow(label: t.fiscalYear, value: dateRange),
            ],
          ),
          if (_hasOptionalDetails(data)) ...[
            SizedBox(height: spacing * 0.85),
            _ReviewCard(
              title: t.newBusinessOptionalDetails,
              onEdit: () => onEditStep(0),
              children: [
                if (data.address?.isNotEmpty == true)
                  _ReviewRow(label: t.address, value: data.address!),
                if (data.phone?.isNotEmpty == true)
                  _ReviewRow(label: t.phone, value: data.phone!),
                if (data.mobile?.isNotEmpty == true)
                  _ReviewRow(label: t.mobile, value: data.mobile!),
                if (data.postalCode?.isNotEmpty == true)
                  _ReviewRow(label: t.postalCode, value: data.postalCode!),
                if (data.country?.isNotEmpty == true)
                  _ReviewRow(label: t.country, value: data.country!),
                if (data.province?.isNotEmpty == true)
                  _ReviewRow(label: t.province, value: data.province!),
                if (data.city?.isNotEmpty == true)
                  _ReviewRow(label: t.city, value: data.city!),
                if (data.nationalId?.isNotEmpty == true)
                  _ReviewRow(label: t.nationalId, value: data.nationalId!),
                if (data.registrationNumber?.isNotEmpty == true)
                  _ReviewRow(
                    label: t.registrationNumber,
                    value: data.registrationNumber!,
                  ),
                if (data.economicId?.isNotEmpty == true)
                  _ReviewRow(label: t.economicId, value: data.economicId!),
              ],
            ),
          ],
          SizedBox(height: spacing),
          DecoratedBox(
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_outlined, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.newBusinessReadyToCreate,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t.newBusinessCompleteLaterHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasOptionalDetails(BusinessData data) {
    bool filled(String? v) => v != null && v.trim().isNotEmpty;
    return filled(data.address) ||
        filled(data.phone) ||
        filled(data.mobile) ||
        filled(data.postalCode) ||
        filled(data.country) ||
        filled(data.province) ||
        filled(data.city) ||
        filled(data.nationalId) ||
        filled(data.registrationNumber) ||
        filled(data.economicId);
  }
}

class _ReviewCard extends StatelessWidget {
  final String title;
  final VoidCallback onEdit;
  final List<Widget> children;

  const _ReviewCard({
    required this.title,
    required this.onEdit,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return NewBusinessSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: onEdit,
                child: Text(t.newBusinessEditSection),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReviewRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: ResponsiveHelper.responsiveValue(
              context,
              mobile: 110,
              tablet: 130,
              desktop: 150,
            ),
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NewBusinessLivePreview extends StatelessWidget {
  final BusinessData data;
  final List<Map<String, dynamic>> currencies;

  const NewBusinessLivePreview({
    super.key,
    required this.data,
    required this.currencies,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final name = data.name.trim().isEmpty ? '—' : data.name.trim();
    final type = data.businessType == null
        ? '—'
        : localizedBusinessType(t, data.businessType!);
    final field = data.businessField == null
        ? '—'
        : localizedBusinessField(t, data.businessField!);
    String? currency;
    if (data.defaultCurrencyId != null) {
      for (final c in currencies) {
        if (c['id'] == data.defaultCurrencyId) {
          currency = '${c['code']}';
          break;
        }
      }
    }
    final fiscalTitle =
        data.fiscalYears.isNotEmpty &&
            data.fiscalYears.first.title.trim().isNotEmpty
        ? data.fiscalYears.first.title
        : null;

    return NewBusinessSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.newBusinessLivePreview,
            style: theme.textTheme.labelLarge?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              data.businessType == null
                  ? Icons.storefront_outlined
                  : businessTypeIcon(data.businessType!),
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PreviewPill(label: type),
              _PreviewPill(label: field),
              if (currency != null) _PreviewPill(label: currency),
            ],
          ),
          if (fiscalTitle != null) ...[
            const SizedBox(height: 16),
            Text(
              fiscalTitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
          if (data.includeSampleData) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: cs.tertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    t.newBusinessSampleDataShort,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewPill extends StatelessWidget {
  final String label;
  const _PreviewPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
