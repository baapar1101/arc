import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/date_utils.dart';
import '../../models/public_person_share_payload.dart';
import '../../models/public_invoice_details.dart';
import '../../services/public_person_share_service.dart';

class PublicPersonShareLinkPage extends StatefulWidget {
  final String code;

  const PublicPersonShareLinkPage({super.key, required this.code});

  @override
  State<PublicPersonShareLinkPage> createState() => _PublicPersonShareLinkPageState();
}

class _PublicPersonShareLinkPageState extends State<PublicPersonShareLinkPage> {
  final _service = PublicPersonShareService();
  bool _loading = true;
  String? _error;
  PublicPersonSharePayload? _payload;
  /// نمایش عمومی: پیش‌فرض شمسی (بدون وابستگی به CalendarController اپ اصلی)
  bool _useJalaliCalendar = true;

  String _formatDate(DateTime? date) =>
      HesabixDateUtils.formatForDisplay(date, _useJalaliCalendar);

  NumberFormat _numberFormat() => NumberFormat('#,##0', 'fa_IR');

  String _formatCurrencySuffix(String? code) {
    final t = code?.trim();
    if (t == null || t.isEmpty) return '';
    return ' $t';
  }

  /// فقط طرف غیرصفر بدهکار/بستانکار + ارز سند
  String _ledgerNetSideLine(PublicLedgerItem item, NumberFormat formatter) {
    final d = item.debit ?? 0.0;
    final c = item.credit ?? 0.0;
    final cur = _formatCurrencySuffix(item.currencyCode);
    if (d > 0 && c <= 0) {
      return 'بدهکار: ${formatter.format(d)}$cur';
    }
    if (c > 0 && d <= 0) {
      return 'بستانکار: ${formatter.format(c)}$cur';
    }
    if (d > 0 && c > 0) {
      final net = d - c;
      if (net > 0) {
        return 'بدهکار: ${formatter.format(net)}$cur';
      }
      if (net < 0) {
        return 'بستانکار: ${formatter.format(-net)}$cur';
      }
      return 'بالانس$cur';
    }
    if (d == 0 && c == 0) {
      return '—$cur';
    }
    return '—$cur';
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.fetchByCode(widget.code);
      if (!mounted) return;
      setState(() {
        _payload = result;
        _loading = false;
      });
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      if (!mounted) return;
      setState(() {
        _error = message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1024),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: _buildBody(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('در حال بارگذاری اطلاعات...'),
        ],
      );
    }

    if (_error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 64),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _fetch,
            icon: const Icon(Icons.refresh),
            label: const Text('تلاش مجدد'),
          ),
        ],
      );
    }

    final data = _payload!;
    final formatter = _numberFormat();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCalendarToggle(theme),
          const SizedBox(height: 12),
          _buildHeader(theme, data),
          const SizedBox(height: 16),
          _buildBusinessCard(theme, data),
          const SizedBox(height: 20),
          _buildSummaryCards(theme, data, formatter),
          const SizedBox(height: 20),
          if (data.options.includeLedger) _buildLedgerSection(theme, data, formatter),
          if (data.options.includeLedger) const SizedBox(height: 20),
          if (data.options.includeInvoices) _buildInvoicesSection(theme, data, formatter),
          const SizedBox(height: 40),
          Align(
            alignment: Alignment.center,
            child: Text(
              'این صفحه فقط برای مشاهده اطلاعات کارت حساب صادر شده توسط کسب‌وکار بالا است.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarToggle(ThemeData theme) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment<bool>(value: true, label: Text('شمسی'), icon: Icon(Icons.calendar_month, size: 18)),
          ButtonSegment<bool>(value: false, label: Text('میلادی'), icon: Icon(Icons.event, size: 18)),
        ],
        selected: {_useJalaliCalendar},
        onSelectionChanged: (set) {
          setState(() => _useJalaliCalendar = set.first);
        },
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, PublicPersonSharePayload data) {
    final share = data.shareLink;
    final shortUrl = share?.shortUrl;
    final status = share?.status;
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.person.aliasName ?? data.person.companyName ?? 'مشتری',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              data.business.name ?? 'کسب‌وکار',
              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 12),
            if (shortUrl != null && shortUrl.isNotEmpty)
              SelectableText(
                shortUrl,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (status != null) ...[
              const SizedBox(height: 4),
              Text('وضعیت لینک: $status', style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessCard(ThemeData theme, PublicPersonSharePayload data) {
    final business = data.business;
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('اطلاعات کسب‌وکار', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _businessInfoRow(theme, Icons.business, business.name ?? 'نامشخص'),
            if ((business.address ?? '').isNotEmpty)
              _businessInfoRow(theme, Icons.location_on_outlined, business.address!),
            if ((business.phone ?? '').isNotEmpty)
              _businessInfoRow(theme, Icons.phone_outlined, business.phone!),
            if ((business.mobile ?? '').isNotEmpty)
              _businessInfoRow(theme, Icons.smartphone_outlined, business.mobile!),
            if ((business.city ?? '').isNotEmpty)
              _businessInfoRow(theme, Icons.map_outlined, business.city!),
          ],
        ),
      ),
    );
  }

  Widget _businessInfoRow(ThemeData theme, IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(ThemeData theme, PublicPersonSharePayload data, NumberFormat formatter) {
    final summary = data.summary;
    final balance = summary.balance ?? 0;
    Color balanceColor;
        if (balance > 0) {
      balanceColor = Colors.green[700] ?? Colors.green;
    } else if (balance < 0) {
      balanceColor = theme.colorScheme.error;
    } else {
      balanceColor = theme.colorScheme.primary;
    }

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _summaryCard(
          theme: theme,
          title: 'تراز جاری',
          value: formatter.format(balance),
          color: balanceColor,
        ),
        _summaryCard(
          theme: theme,
          title: 'وضعیت حساب',
          value: summary.status ?? 'نامشخص',
          color: theme.colorScheme.onSurface,
        ),
        _summaryCard(
          theme: theme,
          title: 'جمع بستانکار',
          value: formatter.format(summary.totalCredit ?? 0),
          color: Colors.green[700] ?? theme.colorScheme.primary,
        ),
        _summaryCard(
          theme: theme,
          title: 'جمع بدهکار',
          value: formatter.format(summary.totalDebit ?? 0),
          color: theme.colorScheme.error,
        ),
      ],
    );
  }

  Widget _summaryCard({
    required ThemeData theme,
    required String title,
    required String value,
    required Color color,
  }) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLedgerSection(ThemeData theme, PublicPersonSharePayload data, NumberFormat formatter) {
    final items = data.ledger;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('تراکنش‌های کارت حساب', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(onPressed: _fetch, icon: const Icon(Icons.refresh)),
              ],
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Text('اطلاعاتی برای نمایش وجود ندارد.', style: theme.textTheme.bodyMedium)
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final subtitleParts = <String>[];
                  final docType = item.documentTypeName?.trim();
                  if (docType != null && docType.isNotEmpty) {
                    subtitleParts.add(docType);
                  }
                  final dateText = _formatDate(item.documentDate);
                  if (dateText.isNotEmpty) {
                    subtitleParts.add(dateText);
                  }
                  final subtitleText = subtitleParts.join(' • ');
                  final desc = item.description?.trim();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    isThreeLine: desc != null && desc.isNotEmpty,
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                      child: Icon(Icons.receipt_long, color: theme.colorScheme.primary),
                    ),
                    title: Text(item.documentCode ?? '-', style: theme.textTheme.titleMedium),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subtitleText.isEmpty ? '-' : subtitleText,
                          style: theme.textTheme.bodySmall,
                        ),
                        if (desc != null && desc.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(desc, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                          ),
                      ],
                    ),
                    trailing: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        _ledgerNetSideLine(item, formatter),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall,
                        softWrap: true,
                      ),
                    ),
                  );
                },
                separatorBuilder: (_, __) => const Divider(),
                itemCount: items.length,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoicesSection(ThemeData theme, PublicPersonSharePayload data, NumberFormat formatter) {
    final items = data.invoices;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('فهرست فاکتورها', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Text('فاکتوری برای نمایش وجود ندارد.', style: theme.textTheme.bodyMedium)
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final amount =
                      '${formatter.format(item.amount ?? 0)}${_formatCurrencySuffix(item.currencyCode)}';
                  final subtitleParts = <String>[];
                  final docType = item.documentTypeName?.trim();
                  if (docType != null && docType.isNotEmpty) {
                    subtitleParts.add(docType);
                  }
                  final dateText = _formatDate(item.documentDate);
                  if (dateText.isNotEmpty) {
                    subtitleParts.add(dateText);
                  }
                  final subtitleText = subtitleParts.join(' • ');
                  final invDesc = item.description?.trim();
                  return InkWell(
                    onTap: item.documentId != null
                        ? () => _showInvoiceDetails(context, theme, item.documentId!)
                        : null,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      isThreeLine: invDesc != null && invDesc.isNotEmpty,
                      title: Text(item.documentCode ?? '-', style: theme.textTheme.titleMedium),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subtitleText.isEmpty ? '-' : subtitleText,
                            style: theme.textTheme.bodySmall,
                          ),
                          if (invDesc != null && invDesc.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(invDesc, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                            ),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('مبلغ: $amount', style: theme.textTheme.bodySmall),
                          Text('وضعیت: ${item.status ?? '-'}', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  );
                },
                separatorBuilder: (_, __) => const Divider(),
                itemCount: items.length,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showInvoiceDetails(BuildContext context, ThemeData theme, int documentId) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final details = await _service.getInvoiceDetails(widget.code, documentId);
      if (!mounted) return;

      Navigator.of(context).pop(); // بستن loading dialog

      showDialog(
        context: context,
        builder: (context) => _InvoiceDetailsDialog(
          theme: theme,
          details: details,
          useJalali: _useJalaliCalendar,
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // بستن loading dialog
      final message = _extractErrorMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطا در دریافت جزئیات: $message'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // بستن loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطا: ${e.toString()}'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  String _extractErrorMessage(DioException exception) {
    final response = exception.response?.data;
    if (response is Map<String, dynamic>) {
      final error = response['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message']?.toString();
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }
      final message = response['message']?.toString();
      if (message != null && message.isNotEmpty) {
        return message;
      }
    }
    final fallback = exception.error?.toString();
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }
    return 'خطا در دریافت اطلاعات کارت حساب';
  }
}

class _InvoiceDetailsDialog extends StatelessWidget {
  final ThemeData theme;
  final PublicInvoiceDetails details;
  final bool useJalali;

  const _InvoiceDetailsDialog({
    required this.theme,
    required this.details,
    required this.useJalali,
  });

  static const double _compactBreakpointWidth = 600;

  String get _currencyLabel {
    final c = details.currencyCode?.trim();
    if (c == null || c.isEmpty) return '';
    return c;
  }

  String _amountWithCurrency(NumberFormat formatter, double value, {bool negativePrefix = false}) {
    final core = formatter.format(value);
    final withCur = _currencyLabel.isEmpty ? core : '$core ${_currencyLabel}';
    if (negativePrefix) return '- $withCur';
    return withCur;
  }

  String _optionalAmountWithCurrency(NumberFormat formatter, double? value) {
    if (value == null) return '-';
    return _amountWithCurrency(formatter, value);
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0', 'fa_IR');
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < _compactBreakpointWidth;

    final scrollBody = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildDetailSections(context, formatter),
      ),
    );

    if (isCompact) {
      // useSafeArea پیش‌فرض true است؛ بدون SafeArea اضافه تا پدینگ دوبل نشود
      return Dialog.fullscreen(
        child: Material(
          color: theme.colorScheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, roundedTop: false),
              Expanded(child: scrollBody),
              _buildFooter(context),
            ],
          ),
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: theme.colorScheme.surface,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 880,
            maxHeight: math.min(720, size.height * 0.9),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, roundedTop: true),
              Expanded(child: scrollBody),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, {required bool roundedTop}) {
    return Material(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, roundedTop ? 16 : 12, 8, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'جزئیات فاکتور',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (details.code != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'شماره فاکتور: ${details.code}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
    );
  }

  List<Widget> _buildDetailSections(BuildContext context, NumberFormat formatter) {
    return [
      _buildInfoSection(
        theme,
        'اطلاعات کلی',
        [
          _buildInfoRow('نوع فاکتور', details.documentType ?? '-'),
          _buildInfoRow('تاریخ فاکتور', details.formattedDate(jalali: useJalali)),
          _buildInfoRow(
            'ارز فاکتور',
            _currencyLabel.isEmpty ? 'نامشخص' : _currencyLabel,
          ),
          if (details.description != null)
            _buildInfoRow('توضیحات', details.description!),
        ],
      ),
      const SizedBox(height: 16),
      if (details.productLines.isNotEmpty) ...[
        _buildInfoSection(
          theme,
          'کالاها',
          [
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final minTableWidth = w.isFinite && w > 0 ? w : 320.0;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: minTableWidth),
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2.2),
                        1: FlexColumnWidth(1),
                        2: FlexColumnWidth(1),
                        3: FlexColumnWidth(1),
                        4: FlexColumnWidth(1),
                        5: FlexColumnWidth(1.2),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          children: [
                            _buildTableCell(theme, 'نام کالا', isHeader: true),
                            _buildTableCell(theme, 'تعداد', isHeader: true),
                            _buildTableCell(theme, 'فی', isHeader: true),
                            _buildTableCell(theme, 'تخفیف', isHeader: true),
                            _buildTableCell(theme, 'مالیات', isHeader: true),
                            _buildTableCell(theme, 'جمع ردیف', isHeader: true),
                          ],
                        ),
                        ...details.productLines.map((line) {
                          String money(double? v) => _optionalAmountWithCurrency(formatter, v);
                          final lineTotal = line.lineTotal ??
                              ((line.quantity != null && line.unitPrice != null)
                                  ? (line.quantity! * line.unitPrice!) -
                                      (line.lineDiscount ?? 0) +
                                      (line.taxAmount ?? 0)
                                  : null);
                          return TableRow(
                            children: [
                              _buildTableCell(theme, line.productName ?? '-'),
                              _buildTableCell(
                                theme,
                                line.quantity != null ? formatter.format(line.quantity) : '-',
                              ),
                              _buildTableCell(theme, money(line.unitPrice)),
                              _buildTableCell(theme, money(line.lineDiscount)),
                              _buildTableCell(theme, money(line.taxAmount)),
                              _buildTableCell(theme, money(lineTotal)),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (details.productLines.any((l) => l.unitPrice == null && l.lineTotal == null))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'برای برخی ردیف‌ها جزئیات قیمت در سند ذخیره نشده است.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
      if (details.accountLines.isNotEmpty) ...[
        _buildInfoSection(
          theme,
          'سطرهای حساب (خلاصه)',
          [
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final minTableWidth = w.isFinite && w > 0 ? w : 320.0;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: minTableWidth),
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2.5),
                        1: FlexColumnWidth(1.2),
                        2: FlexColumnWidth(1.2),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          children: [
                            _buildTableCell(theme, 'حساب', isHeader: true),
                            _buildTableCell(theme, 'بدهکار', isHeader: true),
                            _buildTableCell(theme, 'بستانکار', isHeader: true),
                          ],
                        ),
                        ...details.accountLines.map(
                          (line) => TableRow(
                            children: [
                              _buildTableCell(
                                theme,
                                [
                                  line.accountName ?? '-',
                                  if ((line.accountCode ?? '').isNotEmpty) ' (${line.accountCode})',
                                ].join(),
                              ),
                              _buildTableCell(
                                theme,
                                line.debit != 0
                                    ? _amountWithCurrency(formatter, line.debit)
                                    : '-',
                              ),
                              _buildTableCell(
                                theme,
                                line.credit != 0
                                    ? _amountWithCurrency(formatter, line.credit)
                                    : '-',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
      _buildInfoSection(
        theme,
        'خلاصه مالی',
        [
          _buildInfoRow(
            'جمع قبل از تخفیف',
            _amountWithCurrency(formatter, details.subtotal),
          ),
          if (details.discountAmount > 0)
            _buildInfoRow(
              'تخفیف',
              _amountWithCurrency(formatter, details.discountAmount, negativePrefix: true),
              color: theme.colorScheme.error,
            ),
          if (details.taxAmount > 0)
            _buildInfoRow(
              'مالیات',
              _amountWithCurrency(formatter, details.taxAmount),
              color: theme.colorScheme.primary,
            ),
          const Divider(),
          _buildInfoRow(
            'جمع کل نهایی',
            _amountWithCurrency(formatter, details.total),
            isBold: true,
            color: theme.colorScheme.primary,
          ),
        ],
      ),
    ];
  }

  Widget _buildInfoSection(ThemeData theme, String title, List<Widget> children) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableCell(ThemeData theme, String text, {bool isHeader = false}) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: isHeader
            ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)
            : theme.textTheme.bodyMedium,
      ),
    );
  }
}

