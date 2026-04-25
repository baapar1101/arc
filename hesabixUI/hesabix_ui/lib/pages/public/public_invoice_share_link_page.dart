import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hesabix_ui/services/public_invoice_share_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';

class PublicInvoiceShareLinkPage extends StatefulWidget {
  final String code;

  const PublicInvoiceShareLinkPage({super.key, required this.code});

  @override
  State<PublicInvoiceShareLinkPage> createState() => _PublicInvoiceShareLinkPageState();
}

class _PublicInvoiceShareLinkPageState extends State<PublicInvoiceShareLinkPage> {
  final _service = PublicInvoiceShareService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _payload;

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

  NumberFormat _num() => NumberFormat('#,##0', 'en_US');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
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
            constraints: const BoxConstraints(maxWidth: 800),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _buildBody(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
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
    final auth = data['authenticity'] as Map<String, dynamic>?;
    if (invoice == null) {
      return const Center(child: Text('فاکتور یافت نشد'));
    }
    final lines = (invoice['product_lines'] as List<dynamic>?) ?? const [];
    final extra = (invoice['extra_info'] as Map<String, dynamic>?) ?? const {};
    final totals = (extra['totals'] as Map<String, dynamic>?) ?? const {};

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (auth != null)
            Card(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.verified_outlined, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        auth['message_fa']?.toString() ?? 'سند در سامانه ثبت شده است.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          ListTile(
            title: const Text('کسب‌وکار'),
            subtitle: Text(
              (business?['name'] ?? '-').toString(),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('شماره سند'),
            trailing: Text(
              (invoice['code'] ?? '-').toString(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ListTile(
            title: const Text('تاریخ'),
            trailing: Text((invoice['document_date'] ?? '-').toString()),
          ),
          ListTile(
            title: const Text('نوع'),
            trailing: Text((invoice['document_type'] ?? '-').toString()),
          ),
          if (invoice['is_proforma'] == true)
            const ListTile(
              title: Text('وضعیت'),
              trailing: Text('پیش‌فاکتور'),
            ),
          if (invoice['currency_code'] != null)
            ListTile(
              title: const Text('ارز'),
              trailing: Text((invoice['currency_code']).toString()),
            ),
          const SizedBox(height: 8),
          Text('اقلام', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final raw in lines)
            if (raw is Map)
              _lineTile(raw, theme),
          const SizedBox(height: 12),
          const Text('مبالغ', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (totals['gross'] != null) _totRow('جمع', totals['gross'], theme),
          if (totals['discount'] != null) _totRow('تخفیف', totals['discount'], theme, negate: true),
          if (totals['tax'] != null) _totRow('مالیات', totals['tax'], theme),
          if (totals['net'] != null) _totRow('مبلغ قابل پرداخت', totals['net'], theme, strong: true),
        ],
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: strong ? const TextStyle(fontWeight: FontWeight.w600) : null),
          Text(
            n != null ? _num().format(n) : value.toString(),
            textAlign: TextAlign.end,
            style: strong
                ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _lineTile(Map<dynamic, dynamic> row, ThemeData theme) {
    final name = (row['product_name'] ?? row['description'] ?? '-').toString();
    final qty = row['quantity'];
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        title: Text(name),
        subtitle: row['description'] != null
            ? Text((row['description']).toString(), maxLines: 2, overflow: TextOverflow.ellipsis)
            : null,
        trailing: Text('${qty ?? '-'}'),
        dense: true,
      ),
    );
  }
}
