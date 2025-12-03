import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../services/warranty_service.dart';
import '../../models/warranty_models.dart';
import '../../core/api_client.dart';
import '../../utils/snackbar_helper.dart';
import '../../core/date_utils.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../services/product_service.dart';
import '../../models/product_model.dart';
import '../../widgets/warranty/warranty_code_details_dialog.dart';
import '../../widgets/warranty/generate_warranty_codes_dialog.dart';

class WarrantyManagementPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const WarrantyManagementPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<WarrantyManagementPage> createState() => _WarrantyManagementPageState();
}

class _WarrantyManagementPageState extends State<WarrantyManagementPage> {
  final WarrantyService _warrantyService = WarrantyService();
  final ProductService _productService = ProductService();
  String? _statusFilter;
  int? _productIdFilter;
  List<Product> _products = [];
  bool _loadingProducts = false;
  final GlobalKey _refreshKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _loadingProducts = true);
    try {
      final productsData = await _productService.searchProducts(
        businessId: widget.businessId,
        limit: 1000,
      );
      if (mounted) {
        setState(() {
          _products = productsData.map((json) => Product.fromJson(json)).toList();
          _loadingProducts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingProducts = false);
      }
    }
  }

  void _refreshTable() {
    // بررسی mounted قبل از فراخوانی setState برای جلوگیری از خطا
    if (!mounted) return;
    
    setState(() {
      _refreshKey.currentState;
    });
    // Force rebuild by changing key
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.warrantyManagement),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'لینک فعال‌سازی گارانتی',
            onPressed: () => _showActivationLinkDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: t.warrantySettings,
            onPressed: () {
              context.push('/business/${widget.businessId}/warranty/settings');
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: t.generateWarrantyCodes,
            onPressed: () => _showGenerateDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(context, theme, t),
          Expanded(
            child: DataTableWidget<WarrantyCode>(
              key: ValueKey('warranty_codes_${_statusFilter}_${_productIdFilter}_${_refreshKey}'),
              calendarController: widget.calendarController,
              config: _buildTableConfig(t, theme),
              fromJson: (json) => WarrantyCode.fromJson(json),
              onRefresh: _refreshTable,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context, ThemeData theme, AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _statusFilter,
              decoration: InputDecoration(
                labelText: t.warrantyFilterByStatus,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                DropdownMenuItem(value: null, child: Text('همه')),
                DropdownMenuItem(value: 'generated', child: Text(t.warrantyGenerated)),
                DropdownMenuItem(value: 'activated', child: Text(t.warrantyActivated)),
                DropdownMenuItem(value: 'expired', child: Text(t.warrantyExpired)),
                DropdownMenuItem(value: 'used', child: Text(t.warrantyUsed)),
                DropdownMenuItem(value: 'revoked', child: Text(t.warrantyRevoked)),
              ],
              onChanged: (value) {
                setState(() {
                  _statusFilter = value;
                });
                _refreshTable();
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: DropdownButtonFormField<Product>(
              value: _productIdFilter != null
                  ? _products.firstWhere(
                      (p) => p.id == _productIdFilter,
                      orElse: () => _products.first,
                    )
                  : null,
              decoration: InputDecoration(
                labelText: 'فیلتر بر اساس کالا',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                DropdownMenuItem<Product>(
                  value: null,
                  child: Text('همه کالاها'),
                ),
                ..._products.map((product) {
                  return DropdownMenuItem<Product>(
                    value: product,
                    child: Text(product.displayName),
                  );
                }),
              ],
              onChanged: _loadingProducts
                  ? null
                  : (value) {
                      setState(() {
                        _productIdFilter = value?.id;
                      });
                      _refreshTable();
                    },
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'بارگذاری مجدد',
            onPressed: _refreshTable,
          ),
        ],
      ),
    );
  }

  DataTableConfig<WarrantyCode> _buildTableConfig(AppLocalizations t, ThemeData theme) {
    final queryParams = <String, dynamic>{};
    if (_statusFilter != null) {
      queryParams['status'] = _statusFilter;
    }
    if (_productIdFilter != null) {
      queryParams['product_id'] = _productIdFilter;
    }

    String endpoint = '/api/v1/warranty/business/${widget.businessId}/codes';
    if (queryParams.isNotEmpty) {
      final queryString = queryParams.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value.toString())}')
          .join('&');
      endpoint = '$endpoint?$queryString';
    }

    return DataTableConfig<WarrantyCode>(
      endpoint: endpoint,
      httpMethod: 'GET',
      onRowTap: (code) => _showCodeDetails(context, code as WarrantyCode),
      columns: [
        TextColumn(
          'code',
          t.warrantyCode,
          formatter: (item) => (item as WarrantyCode).code,
        ),
        TextColumn(
          'warranty_serial',
          t.warrantySerial,
          formatter: (item) => (item as WarrantyCode).warrantySerial,
        ),
        TextColumn(
          'status',
          t.warrantyStatus,
          formatter: (item) => _getStatusLabel((item as WarrantyCode).status, t),
        ),
        DateColumn(
          'generated_at',
          t.warrantyGeneratedAt,
          showTime: true,
          formatter: (item) {
            final code = item as WarrantyCode;
            return HesabixDateUtils.formatDateTime(
              code.generatedAt,
              widget.calendarController.isJalali,
            );
          },
        ),
        DateColumn(
          'activated_at',
          t.warrantyActivatedAt,
          showTime: true,
          formatter: (item) {
            final code = item as WarrantyCode;
            if (code.activatedAt == null) return '-';
            return HesabixDateUtils.formatDateTime(
              code.activatedAt!,
              widget.calendarController.isJalali,
            );
          },
        ),
        DateColumn(
          'expires_at',
          t.warrantyExpiresAt,
          showTime: true,
          formatter: (item) {
            final code = item as WarrantyCode;
            if (code.expiresAt == null) return '-';
            return HesabixDateUtils.formatDateTime(
              code.expiresAt!,
              widget.calendarController.isJalali,
            );
          },
        ),
      ],
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

  void _showCodeDetails(BuildContext context, WarrantyCode code) {
    showDialog(
      context: context,
      builder: (context) => WarrantyCodeDetailsDialog(
        warrantyCode: code,
        calendarController: widget.calendarController,
      ),
    );
  }

  Future<void> _showGenerateDialog(BuildContext context) async {
    final result = await showDialog<List<WarrantyCode>>(
      context: context,
      builder: (context) => GenerateWarrantyCodesDialog(
        businessId: widget.businessId,
        warrantyService: _warrantyService,
      ),
    );

    if (result != null && result.isNotEmpty) {
      // بارگذاری مجدد لیست
      _refreshTable();
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: '${result.length} کد گارانتی با موفقیت تولید شد');
      }
    }
  }

  void _showActivationLinkDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // ساخت URL لینک فعال‌سازی با business_id
    final baseUrl = Uri.base.origin;
    final activationLink = '$baseUrl/public/warranty/activate/${widget.businessId}';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.link, color: colorScheme.primary),
            const SizedBox(width: 8),
            const Text('لینک فعال‌سازی گارانتی'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'این لینک را برای مشتریان خود ارسال کنید تا بتوانند گارانتی محصولات خود را فعال کنند:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            const Text(
              'نکته: مشتریان باید کد و سریال گارانتی خود را داشته باشند.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('بستن'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: activationLink));
              Navigator.of(context).pop();
              SnackBarHelper.showSuccess(context, message: 'لینک کپی شد');
            },
            icon: const Icon(Icons.copy),
            label: const Text('کپی لینک'),
          ),
        ],
      ),
    );
  }
}
