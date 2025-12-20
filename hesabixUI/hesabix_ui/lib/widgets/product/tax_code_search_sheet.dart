import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/tax_product_code_service.dart';
import '../../utils/number_normalizer.dart';

class TaxCodeSearchSheet extends StatefulWidget {
  final TaxProductCodeService service;

  const TaxCodeSearchSheet({
    super.key,
    required this.service,
  });

  @override
  State<TaxCodeSearchSheet> createState() => _TaxCodeSearchSheetState();
}

class _TaxCodeSearchSheetState extends State<TaxCodeSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = false;
  bool _hasMore = false;
  int _skip = 0;
  String _currentQuery = '';
  String? _errorMessage;
  static const int _pageSize = 40;
  static const String _stuffIdUrl = 'https://stuffid.tax.gov.ir/';

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openStuffIdSite() async {
    final uri = Uri.parse(_stuffIdUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showSnack('امکان باز کردن لینک وجود ندارد. می‌توانید لینک را کپی کنید.');
      }
    } catch (_) {
      _showSnack('خطا در باز کردن لینک. می‌توانید لینک را کپی کنید.');
    }
  }

  Future<void> _copyStuffIdLink() async {
    await Clipboard.setData(const ClipboardData(text: _stuffIdUrl));
    _showSnack('لینک کپی شد');
  }

  String _normalizeTaxCodeInput(String input) {
    final clean = toEnglishDigits(input).trim();
    return clean.replaceAll(RegExp(r'[\s\-]'), '');
  }

  Future<void> _promptManualTaxCode() async {
    final controller = TextEditingController();
    String? errorText;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('ورود دستی کد مالیاتی'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('کد مالیاتی باید دقیقاً ۱۳ رقم باشد.'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    const EnglishDigitsFormatter(),
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(13),
                  ],
                  decoration: InputDecoration(
                    labelText: 'کد ۱۳ رقمی',
                    hintText: 'مثلاً 1234567890123',
                    errorText: errorText,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (_) {
                    if (errorText != null) {
                      setState(() => errorText = null);
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    await _openStuffIdSite();
                  },
                  child: const Text('باز کردن سایت stuffid.tax.gov.ir'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () {
                  final normalized = _normalizeTaxCodeInput(controller.text);
                  if (!RegExp(r'^\d{13}$').hasMatch(normalized)) {
                    setState(() => errorText = 'کد باید دقیقاً ۱۳ رقم و فقط عدد باشد');
                    return;
                  }
                  Navigator.of(ctx).pop(normalized);
                },
                child: const Text('ثبت'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    final code = (result ?? '').trim();
    if (code.isEmpty) return;
    Navigator.of(context).pop(<String, dynamic>{
      'code': code,
      'description': null,
      'manual': true,
    });
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100 &&
        !_isLoading &&
        _hasMore) {
      _performSearch(_currentQuery, reset: false);
    }
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _performSearch(query, reset: true);
    });
  }

  Future<void> _performSearch(String query, {required bool reset}) async {
    if (query.length < 2) {
      setState(() {
        _items = [];
        _hasMore = false;
        _skip = 0;
        _currentQuery = query;
        _errorMessage = null;
      });
      return;
    }

    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      if (reset) {
        _items = [];
        _skip = 0;
      }
      _errorMessage = null;
    });

    try {
      final response = await widget.service.searchTaxCodes(
        query: query,
        skip: reset ? 0 : _skip,
        limit: _pageSize,
      );
      final rawItems = response['items'];
      final total = response['total'] is int ? response['total'] as int : int.tryParse('${response['total']}') ?? 0;
      final newItems = rawItems is List
          ? rawItems.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _currentQuery = query;
        _items = reset ? newItems : [..._items, ...newItems];
        _skip = _items.length;
        _hasMore = _items.length < total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'خطا در دریافت نتایج: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'جستجوی کد مالیاتی کالا',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _openStuffIdSite,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('stuffid.tax.gov.ir'),
                    ),
                    TextButton.icon(
                      onPressed: _promptManualTaxCode,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('ورود دستی کد ۱۳ رقمی'),
                    ),
                    TextButton.icon(
                      onPressed: _copyStuffIdLink,
                      icon: const Icon(Icons.copy),
                      label: const Text('کپی لینک'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'کد یا شرح کالا را وارد کنید...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'برای نتایج دقیق‌تر حداقل دو کاراکتر وارد کنید. جستجو بر اساس کد و شرح انجام می‌شود.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Text(
                    _errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              Expanded(
                child: _buildResultsList(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsList(ThemeData theme) {
    if (_currentQuery.length >= 2 && _items.isEmpty && !_isLoading && _errorMessage == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'موردی یافت نشد.',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'اگر کد را در لیست پیدا نمی‌کنید، می‌توانید از سایت stuffid.tax.gov.ir کد مالیاتی را پیدا کنید و همین‌جا کد ۱۳ رقمی را دستی وارد کنید.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _promptManualTaxCode,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('ورود دستی کد ۱۳ رقمی'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _openStuffIdSite,
                icon: const Icon(Icons.open_in_new),
                label: const Text('باز کردن سایت stuffid.tax.gov.ir'),
              ),
              TextButton.icon(
                onPressed: _copyStuffIdLink,
                icon: const Icon(Icons.copy),
                label: const Text('کپی لینک'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final item = _items[index];
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                title: Text(
                  item['code']?.toString() ?? '-',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['description']?.toString() ?? '',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if ((item['vat_rate'] ?? '').toString().isNotEmpty)
                          _buildInfoChip(
                            theme,
                            label: 'VAT: ${item['vat_rate']}%',
                            icon: Icons.percent,
                          ),
                        if ((item['taxable_status'] ?? '').toString().isNotEmpty)
                          _buildInfoChip(
                            theme,
                            label: item['taxable_status'].toString(),
                            icon: Icons.receipt_long_outlined,
                          ),
                      ],
                    ),
                  ],
                ),
                onTap: () => Navigator.of(context).pop(item),
              ),
            );
          },
        ),
        if (_isLoading)
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.shadow.withValues(alpha: 0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'در حال دریافت اطلاعات...',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInfoChip(ThemeData theme, {required String label, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }
}

