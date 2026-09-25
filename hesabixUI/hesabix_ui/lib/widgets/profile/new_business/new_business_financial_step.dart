import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart';
import '../../../models/business_models.dart';
import '../../../utils/responsive_helper.dart';
import '../../date_input_field.dart';
import 'new_business_shared.dart';

class NewBusinessFinancialStep extends StatelessWidget {
  final BusinessData data;
  final List<Map<String, dynamic>> currencies;
  final CalendarController calendarController;
  final TextEditingController fiscalTitleController;
  final ValueChanged<BusinessData> onChanged;
  final String Function(DateTime end) fiscalAutoTitle;
  final bool Function(String title) isAutoFiscalTitle;

  const NewBusinessFinancialStep({
    super.key,
    required this.data,
    required this.currencies,
    required this.calendarController,
    required this.fiscalTitleController,
    required this.onChanged,
    required this.fiscalAutoTitle,
    required this.isAutoFiscalTitle,
  });

  FiscalYearData get _fiscal {
    if (data.fiscalYears.isEmpty) {
      data.fiscalYears.add(FiscalYearData(isLast: true));
    }
    return data.fiscalYears.first;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final spacing = ResponsiveHelper.responsiveValue(
      context,
      mobile: 18,
      tablet: 20,
      desktop: 22,
    );
    final fiscal = _fiscal;
    final isMobile = ResponsiveHelper.isMobile(context);

    return NewBusinessFormShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NewBusinessSectionHeader(
            title: t.newBusinessFinancialStepTitle,
            subtitle: t.newBusinessFinancialStepSubtitle,
          ),
          SizedBox(height: spacing * 1.25),
          NewBusinessSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.currency,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  key: ValueKey('default-currency-${data.defaultCurrencyId}'),
                  initialValue: data.defaultCurrencyId,
                  isExpanded: true,
                  items: currencies.map((c) {
                    return DropdownMenuItem<int>(
                      value: c['id'] as int,
                      child: Text('${c['title']} (${c['code']})'),
                    );
                  }).toList(),
                  decoration: newBusinessInputDecoration(
                    context,
                    labelText: t.defaultCurrency,
                    required: true,
                  ),
                  onChanged: (v) {
                    final ids = List<int>.from(data.currencyIds);
                    if (v != null && !ids.contains(v)) ids.add(v);
                    onChanged(
                      data.copyWith(defaultCurrencyId: v, currencyIds: ids),
                    );
                  },
                ),
                const SizedBox(height: 16),
                NewBusinessCurrencyMultiSelect(
                  currencies: currencies,
                  selectedIds: data.currencyIds,
                  defaultId: data.defaultCurrencyId,
                  onChanged: (ids) {
                    final next = List<int>.from(ids);
                    final d = data.defaultCurrencyId;
                    if (d != null && !next.contains(d)) next.add(d);
                    onChanged(data.copyWith(currencyIds: next));
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: spacing),
          NewBusinessSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.fiscalYear,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                if (isMobile) ...[
                  DateInputField(
                    value: fiscal.startDate,
                    labelText: '${t.fiscalStartDate} *',
                    lastDate: fiscal.endDate,
                    calendarController: calendarController,
                    onChanged: (d) => _onStartChanged(d),
                  ),
                  const SizedBox(height: 12),
                  DateInputField(
                    value: fiscal.endDate,
                    labelText: '${t.fiscalEndDate} *',
                    firstDate: fiscal.startDate,
                    calendarController: calendarController,
                    onChanged: (d) => _onEndChanged(d),
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: DateInputField(
                          value: fiscal.startDate,
                          labelText: '${t.fiscalStartDate} *',
                          lastDate: fiscal.endDate,
                          calendarController: calendarController,
                          onChanged: (d) => _onStartChanged(d),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DateInputField(
                          value: fiscal.endDate,
                          labelText: '${t.fiscalEndDate} *',
                          firstDate: fiscal.startDate,
                          calendarController: calendarController,
                          onChanged: (d) => _onEndChanged(d),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: fiscalTitleController,
                  decoration: newBusinessInputDecoration(
                    context,
                    labelText: t.fiscalYearTitleLabel,
                    required: true,
                  ),
                  onChanged: (v) {
                    fiscal.title = v;
                    onChanged(data);
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  t.fiscalYearRequiredHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onStartChanged(DateTime? d) {
    final fiscal = _fiscal;
    fiscal.startDate = d;
    if (fiscal.startDate != null) {
      fiscal.endDate = HesabixDateUtils.fiscalYearInclusiveEndFromStart(
        fiscal.startDate!,
        calendarController.isJalali,
      );
      fiscal.title = fiscalAutoTitle(fiscal.endDate!);
      fiscalTitleController.text = fiscal.title;
    }
    onChanged(data);
  }

  void _onEndChanged(DateTime? d) {
    final fiscal = _fiscal;
    fiscal.endDate = d;
    if (d != null && isAutoFiscalTitle(fiscal.title)) {
      fiscal.title = fiscalAutoTitle(d);
      fiscalTitleController.text = fiscal.title;
    }
    onChanged(data);
  }
}

class NewBusinessCurrencyMultiSelect extends StatefulWidget {
  final List<Map<String, dynamic>> currencies;
  final List<int> selectedIds;
  final int? defaultId;
  final ValueChanged<List<int>> onChanged;

  const NewBusinessCurrencyMultiSelect({
    super.key,
    required this.currencies,
    required this.selectedIds,
    required this.defaultId,
    required this.onChanged,
  });

  @override
  State<NewBusinessCurrencyMultiSelect> createState() =>
      _NewBusinessCurrencyMultiSelectState();
}

class _NewBusinessCurrencyMultiSelectState
    extends State<NewBusinessCurrencyMultiSelect> {
  late List<int> _selected;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _panelOpen = false;

  @override
  void initState() {
    super.initState();
    _selected = List<int>.from(widget.selectedIds);
  }

  @override
  void didUpdateWidget(covariant NewBusinessCurrencyMultiSelect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIds != widget.selectedIds) {
      _selected = List<int>.from(widget.selectedIds);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggle(int id) {
    setState(() {
      if (_selected.contains(id)) {
        if (widget.defaultId != id) {
          _selected.remove(id);
        }
      } else {
        _selected.add(id);
      }
      widget.onChanged(List<int>.from(_selected));
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final filtered = widget.currencies.where((c) {
      final q = _searchCtrl.text.trim();
      if (q.isEmpty) return true;
      final title = (c['title'] ?? '').toString();
      final code = (c['code'] ?? '').toString();
      return title.contains(q) || code.toLowerCase().contains(q.toLowerCase());
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.extraCurrencies, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _panelOpen = !_panelOpen),
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(14),
                color: cs.surfaceContainerHighest.withValues(alpha: 0.28),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _selected.isEmpty
                          ? [
                              Text(
                                t.selectCurrencies,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.hintColor,
                                ),
                              ),
                            ]
                          : _selected.map((id) {
                              final c = widget.currencies.firstWhere(
                                (e) => e['id'] == id,
                                orElse: () => <String, dynamic>{},
                              );
                              final isDefault = widget.defaultId == id;
                              return Chip(
                                label: Text(
                                  '${c['title'] ?? id} (${c['code'] ?? ''})',
                                ),
                                avatar: isDefault
                                    ? Icon(
                                        Icons.star_rounded,
                                        size: 16,
                                        color: cs.primary,
                                      )
                                    : null,
                                onDeleted: isDefault ? null : () => _toggle(id),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              );
                            }).toList(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(_panelOpen ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
        ),
        if (_panelOpen) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _searchCtrl,
            decoration:
                newBusinessInputDecoration(
                  context,
                  labelText: t.searchCurrencyHint,
                  prefixIcon: const Icon(Icons.search),
                ).copyWith(
                  isDense: true,
                  labelText: null,
                  hintText: t.searchCurrencyHint,
                ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: Scrollbar(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final c = filtered[index];
                  final id = c['id'] as int;
                  final selected = _selected.contains(id);
                  final isDefault = widget.defaultId == id;
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (_) => _toggle(id),
                    dense: true,
                    title: Text('${c['title']} (${c['code']})'),
                    secondary: isDefault
                        ? Icon(Icons.star_rounded, size: 18, color: cs.primary)
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}
