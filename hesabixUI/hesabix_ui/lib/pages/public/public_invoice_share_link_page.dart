import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hesabix_ui/config/app_config.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/models/invoice_type_model.dart';
import 'package:hesabix_ui/services/public_invoice_share_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;

class PublicInvoiceShareLinkPage extends StatefulWidget {
  final String code;

  const PublicInvoiceShareLinkPage({super.key, required this.code});

  @override
  State<PublicInvoiceShareLinkPage> createState() => _PublicInvoiceShareLinkPageState();
}

class _PublicInvoiceShareLinkPageState extends State<PublicInvoiceShareLinkPage> {
  final _service = PublicInvoiceShareService();
  final ScrollController _linesTableHorizontalScroll = ScrollController();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _payload;
  /// نمایش عمومی: پیش‌فرض شمسی
  bool _useJalaliCalendar = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _linesTableHorizontalScroll.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _service.fetchByCode(widget.code);
      if (!mounted) return;
      setState(() {
        _payload = r;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.userMessage(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.userMessage(e);
        _loading = false;
      });
    }
  }

  NumberFormat _intFmt() => NumberFormat('#,##0', 'fa_IR');
  NumberFormat _decFmt() => NumberFormat('#,##0.##', 'fa_IR');

  String _formatInt(num? n) {
    if (n == null) return '—';
    return _intFmt().format(n);
  }

  String _formatAmount(num? n) {
    if (n == null) return '—';
    if (n == n.roundToDouble()) {
      return _intFmt().format(n);
    }
    return _decFmt().format(n);
  }

  String _formatDateField(dynamic raw) {
    if (raw == null) return '—';
    final s = raw.toString();
    if (s.isEmpty) return '—';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    return HesabixDateUtils.formatForDisplay(dt.toLocal(), _useJalaliCalendar);
  }

  String _formatDateTimeField(dynamic raw) {
    if (raw == null) return '—';
    final s = raw.toString();
    if (s.isEmpty) return '—';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    return HesabixDateUtils.formatDateTime(dt.toLocal(), _useJalaliCalendar);
  }

  String _documentTypeLabel(String? type) {
    if (type == null || type.isEmpty) return '—';
    final parsed = InvoiceType.fromValue(type);
    if (parsed != null) return parsed.label;
    return type;
  }

  String? _currencySuffix(String? code) {
    final t = code?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  Future<void> _openPhone(String? raw) async {
    final s = (raw ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    if (s.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: s);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _copyToClipboard(String text) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('کپی شد')),
    );
  }

  Future<void> _exportPdf() async {
    try {
      final bytes = await _service.fetchPdfByCode(
        widget.code,
        calendarType: _useJalaliCalendar ? 'jalali' : 'gregorian',
      );
      if (bytes.isEmpty) return;
      final name = 'invoice_${widget.code}.pdf';
      if (kIsWeb) {
        await web_utils.saveBytesAsFileWeb(
          bytes,
          name,
          mimeType: 'application/pdf',
        );
      } else {
        await Printing.sharePdf(
          bytes: Uint8List.fromList(bytes),
          filename: name,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فایل PDF آماده شد')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorExtractor.userMessage(e))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorExtractor.userMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('نمایش فاکتور'),
        actions: [
          IconButton(
            onPressed: _fetch,
            icon: const Icon(Icons.refresh),
            tooltip: 'بارگذاری مجدد',
          ),
        ],
      ),
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
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
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
          Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
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
    final data = _payload;
    if (data == null) {
      return const Center(child: Text('داده‌ای وجود ندارد'));
    }
    final business = data['business'] as Map<String, dynamic>?;
    final invoice = data['invoice'] as Map<String, dynamic>?;
    final installments = data['installments'] as Map<String, dynamic>?;
    final auth = data['authenticity'] as Map<String, dynamic>?;
    final shareLink = data['share_link'] as Map<String, dynamic>?;
    if (invoice == null) {
      return const Center(child: Text('فاکتور یافت نشد'));
    }

    final lines = (invoice['product_lines'] as List<dynamic>?) ?? const [];
    final extra = (invoice['extra_info'] as Map<String, dynamic>?) ?? const {};
    final totals = (extra['totals'] as Map<String, dynamic>?) ?? const {};
    final currency = invoice['currency_code']?.toString();
    final curSuffix = _currencySuffix(currency);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCalendarToggle(theme),
              const SizedBox(height: 12),
              if (auth != null) _buildAuthenticityCard(theme, auth),
              if (auth != null) const SizedBox(height: 16),
              if (shareLink != null) _buildShareLinkCard(theme, shareLink),
              if (shareLink != null) const SizedBox(height: 16),
              if (business != null) _buildBusinessCard(theme, business),
              if (business != null) const SizedBox(height: 16),
              _buildInvoiceHeaderCard(theme, invoice, curSuffix),
              const SizedBox(height: 16),
              _buildMetaRows(theme, invoice, extra),
              const SizedBox(height: 16),
              _buildLinesSection(
                theme: theme,
                lines: lines,
                currencySuffix: curSuffix,
              ),
              const SizedBox(height: 16),
              _buildTotalsCard(theme, totals, curSuffix),
              if ((installments?['has_installments'] == true)) ...[
                const SizedBox(height: 16),
                _buildInstallmentsCard(theme, installments!, curSuffix),
              ],
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.center,
                child: Text(
                  'این صفحه فقط برای مشاهدهٔ فاکتور صادرشده توسط کسب‌وکار است. برای اطمینان از صحت، اطلاعات بالا را با نسخهٔ رسیده از فروشنده تطابق دهید.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCalendarToggle(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        final calendar = SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: true,
              label: Text('شمسی'),
              icon: Icon(Icons.calendar_month, size: 18),
            ),
            ButtonSegment<bool>(
              value: false,
              label: Text('میلادی'),
              icon: Icon(Icons.event, size: 18),
            ),
          ],
          selected: {_useJalaliCalendar},
          onSelectionChanged: (set) {
            setState(() => _useJalaliCalendar = set.first);
          },
        );
        final invoiceBtn = FilledButton.icon(
          onPressed: _loading ? null : _exportPdf,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
          label: const Text('دریافت فاکتور'),
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              calendar,
              const SizedBox(height: 12),
              invoiceBtn,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: invoiceBtn)),
            const SizedBox(width: 12),
            calendar,
          ],
        );
      },
    );
  }

  Widget _buildAuthenticityCard(ThemeData theme, Map<String, dynamic> auth) {
    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified_outlined, color: theme.colorScheme.primary, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                auth['message_fa']?.toString() ?? 'این فاکتور در سامانه حسابیکس (Hesabix) ثبت شده است.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareLinkCard(ThemeData theme, Map<String, dynamic> share) {
    final shortUrl = share['short_url']?.toString();
    final status = share['status']?.toString();
    final expires = share['expires_at']?.toString();
    final remaining = share['remaining_hours'];
    final views = share['view_count'];
    final maxViews = share['max_view_count'];
    final lastView = share['last_view_at']?.toString();

    String? expLine;
    if (expires != null && expires.isNotEmpty) {
      final dt = DateTime.tryParse(expires);
      if (dt != null) {
        final label = HesabixDateUtils.formatDateTime(dt.toLocal(), _useJalaliCalendar);
        if (remaining is num) {
          final h = _formatInt(remaining.round());
          expLine = 'انقضای لینک: $label (حدود $h ساعت باقی‌مانده)';
        } else {
          expLine = 'انقضای لینک: $label';
        }
      }
    } else {
      expLine = 'انقضای لینک: بدون محدودیت';
    }

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'لینک اشتراک',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (status != null && status.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('وضعیت: $status', style: theme.textTheme.bodySmall),
            ],
            if (expLine != null) ...[
              const SizedBox(height: 4),
              Text(expLine, style: theme.textTheme.bodySmall),
            ],
            if (views != null) ...[
              const SizedBox(height: 4),
              Text(
                maxViews != null
                    ? 'تعداد بازدید: ${_formatInt(_asNum(views) ?? 0)} از ${_formatInt(_asNum(maxViews) ?? 0)}'
                    : 'تعداد بازدید: ${_formatInt(_asNum(views) ?? 0)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (lastView != null && lastView.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'آخرین بازدید: ${_formatDateTimeField(lastView)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (shortUrl != null && shortUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(
                shortUrl,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  num? _asNum(dynamic v) {
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  bool _businessHasLogo(Map<String, dynamic> b) => b['has_logo'] == true;

  String _invoiceShareLogoImageUrl() {
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final c = Uri.encodeComponent(widget.code);
    return '$base/api/v1/public/invoice-links/$c/business-logo';
  }

  Widget _buildBusinessCard(ThemeData theme, Map<String, dynamic> b) {
    final name = b['name']?.toString() ?? '—';
    final address = b['address']?.toString();
    final phone = b['phone']?.toString();
    final mobile = b['mobile']?.toString();
    final showLogo = _businessHasLogo(b);

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showLogo) ...[
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    _invoiceShareLogoImageUrl(),
                    height: 76,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.storefront_outlined,
                      size: 56,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Text(
              'کسب‌وکار',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _businessInfoRow(
              theme,
              Icons.storefront_outlined,
              name,
              onCopy: () => _copyToClipboard(name),
            ),
            if (address != null && address.isNotEmpty)
              _businessInfoRow(
                theme,
                Icons.location_on_outlined,
                address,
                onCopy: () => _copyToClipboard(address),
              ),
            if (phone != null && phone.isNotEmpty)
              _businessInfoRow(
                theme,
                Icons.phone_outlined,
                phone,
                onTap: () => _openPhone(phone),
                onCopy: () => _copyToClipboard(phone),
              ),
            if (mobile != null && mobile.isNotEmpty)
              _businessInfoRow(
                theme,
                Icons.smartphone_outlined,
                mobile,
                onTap: () => _openPhone(mobile),
                onCopy: () => _copyToClipboard(mobile),
              ),
          ],
        ),
      ),
    );
  }

  Widget _businessInfoRow(
    ThemeData theme,
    IconData icon,
    String value, {
    VoidCallback? onTap,
    VoidCallback? onCopy,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Text(value, style: theme.textTheme.bodyMedium),
            ),
          ),
          if (onCopy != null)
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'کپی',
              onPressed: onCopy,
            ),
        ],
      ),
    );
  }

  Widget _buildInvoiceHeaderCard(
    ThemeData theme,
    Map<String, dynamic> inv,
    String? curSuffix,
  ) {
    final code = inv['code']?.toString() ?? '—';
    final docType = _documentTypeLabel(inv['document_type']?.toString());
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'فاکتور $code',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              docType,
              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
            ),
            if (curSuffix != null) ...[
              const SizedBox(height: 4),
              Text('ارز: $curSuffix', style: theme.textTheme.bodySmall),
            ],
            if (inv['is_proforma'] == true) ...[
              const SizedBox(height: 6),
              Chip(
                label: const Text('پیش‌فاکتور'),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetaRows(
    ThemeData theme,
    Map<String, dynamic> inv,
    Map<String, dynamic> extra,
  ) {
    final rows = <_MetaPair>[
      _MetaPair('تاریخ سند', _formatDateField(inv['document_date'])),
      _MetaPair('زمان ثبت', _formatDateTimeField(inv['registered_at'])),
    ];

    final due = extra['due_date'];
    if (due != null && due.toString().isNotEmpty) {
      rows.add(_MetaPair('سررسید', _formatDateField(due)));
    }

    final desc = inv['description']?.toString();
    if (desc != null && desc.isNotEmpty) {
      rows.add(_MetaPair('شرح', desc));
    }

    final project = inv['project_name']?.toString();
    if (project != null && project.isNotEmpty) {
      rows.add(_MetaPair('پروژه', project));
    }

    final createdBy = inv['created_by_name']?.toString();
    if (createdBy != null && createdBy.isNotEmpty) {
      rows.add(_MetaPair('ایجادکننده', createdBy));
    }

    final tags = inv['tags'] as List<dynamic>?;
    if (tags != null && tags.isNotEmpty) {
      rows.add(_MetaPair('برچسب‌ها', tags.map((e) => e.toString()).join('، ')));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (final p in rows)
              ListTile(
                title: Text(
                  p.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                subtitle: Text(
                  p.value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                isThreeLine: p.value.length > 80,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinesSection({
    required ThemeData theme,
    required List<dynamic> lines,
    String? currencySuffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('اقلام فاکتور', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (lines.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('اقلامی ثبت نشده است.', style: theme.textTheme.bodyMedium),
            ),
          )
        else
          _buildLinesTable(theme, lines, currencySuffix),
      ],
    );
  }

  Widget _buildLinesTable(ThemeData theme, List<dynamic> lines, String? currencySuffix) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        controller: _linesTableHorizontalScroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _linesTableHorizontalScroll,
          scrollDirection: Axis.horizontal,
          primary: false,
          child: DataTable(
            headingRowColor: WidgetStatePropertyAll(theme.colorScheme.surfaceContainerHighest),
            columns: [
              DataColumn(label: Text('ردیف', style: theme.textTheme.labelLarge)),
              DataColumn(label: Text('کد', style: theme.textTheme.labelLarge)),
              DataColumn(label: Text('شرح / کالا', style: theme.textTheme.labelLarge)),
              DataColumn(
                label: Text('تعداد / واحد', style: theme.textTheme.labelLarge),
              ),
              const DataColumn(
                label: Text('قیمت واحد', textAlign: TextAlign.end),
                numeric: true,
              ),
              const DataColumn(
                label: Text('تخفیف', textAlign: TextAlign.end),
                numeric: true,
              ),
              const DataColumn(
                label: Text('مالیات', textAlign: TextAlign.end),
                numeric: true,
              ),
              const DataColumn(
                label: Text('مبلغ ردیف', textAlign: TextAlign.end),
                numeric: true,
              ),
            ],
            rows: [
              for (var i = 0; i < lines.length; i++)
                if (lines[i] is Map)
                  _dataRow(
                    lines[i] as Map<dynamic, dynamic>,
                    i + 1,
                    currencySuffix,
                  ),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _dataRow(Map<dynamic, dynamic> row, int index, String? currencySuffix) {
    final name = (row['product_name'] ?? row['description'] ?? '-').toString();
    final code = (row['product_code']?.toString() ?? '—');
    final unit = (row['product_main_unit']?.toString() ?? '').trim();
    final qty = _asNum(row['quantity']);
    final qtyText = unit.isNotEmpty ? '${_formatAmount(qty)} $unit' : _formatAmount(qty);
    final up = _asNum(row['unit_price']);
    final disc = _asNum(row['line_discount']);
    final tax = _asNum(row['tax_amount']);
    final lineTotal = _asNum(row['line_total']);
    return DataRow(
      cells: [
        DataCell(Text(_formatInt(index))),
        DataCell(Text(code)),
        DataCell(
          SizedBox(
            width: 200,
            child: Text(
              name,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(Text(qtyText)),
        DataCell(
          Text(
            up != null ? _formatAmount(up) : '—',
            textAlign: TextAlign.end,
          ),
        ),
        DataCell(
          Text(
            disc != null ? _formatAmount(disc) : '—',
            textAlign: TextAlign.end,
          ),
        ),
        DataCell(
          Text(
            tax != null ? _formatAmount(tax) : '—',
            textAlign: TextAlign.end,
          ),
        ),
        DataCell(
          Text(
            lineTotal != null ? _formatAmount(lineTotal) : '—',
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  String _suffix(String? c) => c != null && c.isNotEmpty ? ' ($c)' : '';

  Widget _buildTotalsCard(ThemeData theme, Map<String, dynamic> totals, String? curSuffix) {
    final s = _suffix(curSuffix);
    return Card(
      elevation: 1,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('خلاصه مبالغ', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            if (curSuffix != null) ...[
              const SizedBox(height: 4),
              Text('واحد پول: $curSuffix', style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            if (totals['gross'] != null) _totRow('جمع${s != '' ? s : ''}', totals['gross'], theme, negate: false),
            if (totals['discount'] != null) _totRow('تخفیف${s != '' ? s : ''}', totals['discount'], theme, negate: true),
            if (totals['tax'] != null) _totRow('مالیات${s != '' ? s : ''}', totals['tax'], theme),
            if (totals['net'] != null) _totRow('مبلغ قابل پرداخت${s != '' ? s : ''}', totals['net'], theme, strong: true),
            if (totals.isEmpty)
              const Text('جمعی ثبت نشده است.'),
          ],
        ),
      ),
    );
  }

  Widget _totRow(
    String label,
    dynamic value,
    ThemeData theme, {
    bool strong = false,
    bool negate = false,
  }) {
    num? n;
    if (value is num) {
      n = value;
    } else {
      n = num.tryParse(value.toString());
    }
    if (negate && n != null) {
      n = -n;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: strong ? const TextStyle(fontWeight: FontWeight.w700) : null),
          Text(
            n != null ? _formatAmount(n) : value.toString(),
            textAlign: TextAlign.end,
            style: strong
                ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)
                : null,
          ),
        ],
      ),
    );
  }

  String _statusLabel(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'paid':
        return 'پرداخت‌شده';
      case 'partial':
        return 'پرداخت ناقص';
      case 'overdue':
        return 'سررسید گذشته';
      case 'pending':
      default:
        return 'در انتظار';
    }
  }

  Widget _buildInstallmentsCard(
    ThemeData theme,
    Map<String, dynamic> installments,
    String? curSuffix,
  ) {
    final summary = installments['summary'] as Map<String, dynamic>?;
    final schedule = (installments['schedule'] as List<dynamic>?) ?? const [];
    final s = _suffix(curSuffix);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'اطلاعات اقساط',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (summary != null) ...[
              _totRow('تعداد اقساط', summary['installment_count'], theme),
              _totRow('تعداد پرداخت‌شده', summary['paid_count'], theme),
              _totRow('تعداد سررسید گذشته', summary['overdue_count'], theme),
              _totRow('پیش‌پرداخت${s != '' ? s : ''}', summary['down_payment'], theme),
              _totRow('جمع اصل${s != '' ? s : ''}', summary['principal_total'], theme),
              _totRow('جمع سود${s != '' ? s : ''}', summary['interest_total'], theme),
              _totRow('جمع کل${s != '' ? s : ''}', summary['grand_total'], theme),
              _totRow('پرداخت‌شده${s != '' ? s : ''}', summary['paid_total'], theme),
              _totRow('مانده${s != '' ? s : ''}', summary['remaining_total'], theme, strong: true),
              const Divider(height: 24),
            ],
            if (schedule.isEmpty)
              const Text('برنامه زمانی اقساط ثبت نشده است.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('قسط')),
                    DataColumn(label: Text('سررسید')),
                    DataColumn(label: Text('اصل'), numeric: true),
                    DataColumn(label: Text('سود'), numeric: true),
                    DataColumn(label: Text('مبلغ'), numeric: true),
                    DataColumn(label: Text('پرداخت'), numeric: true),
                    DataColumn(label: Text('مانده'), numeric: true),
                    DataColumn(label: Text('وضعیت')),
                  ],
                  rows: [
                    for (final raw in schedule)
                      if (raw is Map)
                        DataRow(
                          cells: [
                            DataCell(Text(_formatInt(_asNum(raw['seq'])))),
                            DataCell(Text(_formatDateField(raw['due_date']))),
                            DataCell(Text(_formatAmount(_asNum(raw['principal'])))),
                            DataCell(Text(_formatAmount(_asNum(raw['interest'])))),
                            DataCell(Text(_formatAmount(_asNum(raw['total'])))),
                            DataCell(Text(_formatAmount(_asNum(raw['paid_amount'])))),
                            DataCell(Text(_formatAmount(_asNum(raw['remaining'])))),
                            DataCell(Text(_statusLabel(raw['status']?.toString()))),
                          ],
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

class _MetaPair {
  const _MetaPair(this.label, this.value);
  final String label;
  final String value;
}
