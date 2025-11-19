import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
    final formatter = NumberFormat('#,##0');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  final dateText = item.formattedDate();
                  if (dateText.isNotEmpty) {
                    subtitleParts.add(dateText);
                  }
                  final subtitleText = subtitleParts.join(' • ');
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                      child: Icon(Icons.receipt_long, color: theme.colorScheme.primary),
                    ),
                    title: Text(item.documentCode ?? '-', style: theme.textTheme.titleMedium),
                    subtitle: Text(
                      subtitleText.isEmpty ? '-' : subtitleText,
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('بدهکار: ${formatter.format(item.debit ?? 0)}', style: theme.textTheme.bodySmall),
                        Text('بستانکار: ${formatter.format(item.credit ?? 0)}', style: theme.textTheme.bodySmall),
                      ],
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
                  final amount = formatter.format(item.amount ?? 0);
                  final subtitleParts = <String>[];
                  final docType = item.documentTypeName?.trim();
                  if (docType != null && docType.isNotEmpty) {
                    subtitleParts.add(docType);
                  }
                  final dateText = item.formattedDate();
                  if (dateText.isNotEmpty) {
                    subtitleParts.add(dateText);
                  }
                  final subtitleText = subtitleParts.join(' • ');
                  return InkWell(
                    onTap: item.documentId != null
                        ? () => _showInvoiceDetails(context, theme, item.documentId!)
                        : null,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.documentCode ?? '-', style: theme.textTheme.titleMedium),
                      subtitle: Text(
                        subtitleText.isEmpty ? '-' : subtitleText,
                        style: theme.textTheme.bodySmall,
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
        builder: (context) => _InvoiceDetailsDialog(theme: theme, details: details),
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

  const _InvoiceDetailsDialog({
    required this.theme,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0');
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
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
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // اطلاعات کلی
                    _buildInfoSection(
                      theme,
                      'اطلاعات کلی',
                      [
                        _buildInfoRow('نوع فاکتور', details.documentType ?? '-'),
                        _buildInfoRow('تاریخ فاکتور', details.formattedDate()),
                        if (details.description != null)
                          _buildInfoRow('توضیحات', details.description!),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // کالاها
                    if (details.productLines.isNotEmpty) ...[
                      _buildInfoSection(
                        theme,
                        'کالاها',
                        [
                          Table(
                            columnWidths: const {
                              0: FlexColumnWidth(2),
                              1: FlexColumnWidth(1),
                              2: FlexColumnWidth(1),
                            },
                            children: [
                              TableRow(
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                ),
                                children: [
                                  _buildTableCell(theme, 'نام کالا', isHeader: true),
                                  _buildTableCell(theme, 'تعداد', isHeader: true),
                                  _buildTableCell(theme, 'توضیحات', isHeader: true),
                                ],
                              ),
                              ...details.productLines.map((line) => TableRow(
                                    children: [
                                      _buildTableCell(theme, line.productName ?? '-'),
                                      _buildTableCell(theme, line.quantity != null
                                          ? formatter.format(line.quantity)
                                          : '-'),
                                      _buildTableCell(theme, line.description ?? '-'),
                                    ],
                                  )),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    // خلاصه مالی
                    _buildInfoSection(
                      theme,
                      'خلاصه مالی',
                      [
                        _buildInfoRow('جمع کل', formatter.format(details.subtotal)),
                        if (details.discountAmount > 0)
                          _buildInfoRow(
                            'تخفیف',
                            '- ${formatter.format(details.discountAmount)}',
                            color: theme.colorScheme.error,
                          ),
                        if (details.taxAmount > 0)
                          _buildInfoRow(
                            'مالیات',
                            formatter.format(details.taxAmount),
                            color: theme.colorScheme.primary,
                          ),
                        const Divider(),
                        _buildInfoRow(
                          'جمع کل نهایی',
                          formatter.format(details.total),
                          isBold: true,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
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

  Widget _buildInfoSection(ThemeData theme, String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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

