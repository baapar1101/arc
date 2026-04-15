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
  int _refreshCounter = 0;
  final Set<int> _selectedRowIndices = {};
  List<WarrantyCode> _currentPageCodes = [];
  bool _isFirstRowInNewLoad = true;

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
      _currentPageCodes.clear();
      _selectedRowIndices.clear();
      _isFirstRowInNewLoad = true;
      _refreshCounter++; // تغییر counter برای rebuild کامل
    });
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
          if (_selectedRowIndices.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'حذف موارد انتخاب شده',
              onPressed: () => _confirmBulkDelete(context),
            ),
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
          if (_selectedRowIndices.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: colorScheme.primaryContainer,
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: colorScheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Text(
                    '${_selectedRowIndices.length} مورد انتخاب شده',
                    style: TextStyle(color: colorScheme.onPrimaryContainer),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _selectedRowIndices.clear()),
                    child: Text('لغو انتخاب', style: TextStyle(color: colorScheme.onPrimaryContainer)),
                  ),
                ],
              ),
            ),
          SingleChildScrollView(
            child: DataTableWidget<WarrantyCode>(
              key: ValueKey('warranty_codes_${_statusFilter}_${_productIdFilter}_$_refreshCounter'),
              calendarController: widget.calendarController,
              config: _buildTableConfig(t, theme),
              fromJson: (json) {
                final code = WarrantyCode.fromJson(json);
                // ذخیره کدها برای استفاده در حذف
                // اگر این اولین ردیف است، لیست را پاک کن
                if (_isFirstRowInNewLoad) {
                  _currentPageCodes.clear();
                  _isFirstRowInNewLoad = false;
                }
                _currentPageCodes.add(code);
                return code;
              },
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
      enableRowSelection: true,
      enableMultiRowSelection: true,
      selectedRows: _selectedRowIndices,
      onRowSelectionChanged: (selectedIndices) {
        setState(() {
          _selectedRowIndices.clear();
          _selectedRowIndices.addAll(selectedIndices);
        });
      },
      columns: [
        ActionColumn(
          'actions',
          'عملیات',
          actions: [
            DataTableAction(
              icon: Icons.visibility,
              label: 'مشاهده',
              onTap: (item) => _showCodeDetails(context, item as WarrantyCode),
            ),
            DataTableAction(
              icon: Icons.delete_outline,
              label: 'حذف',
              color: theme.colorScheme.error,
              onTap: (item) => _confirmSingleDelete(context, item as WarrantyCode),
            ),
          ],
        ),
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
      expandBodyHeightToFitRows: true,
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

  Future<void> _confirmSingleDelete(BuildContext context, WarrantyCode code) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // بررسی وضعیت کد
    final isActivated = code.status == WarrantyStatus.activated || code.status == WarrantyStatus.used;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: colorScheme.error),
            const SizedBox(width: 8),
            const Text('تأیید حذف'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('آیا از حذف کد گارانتی "${code.code}" اطمینان دارید؟'),
            if (isActivated) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'این کد فعال شده است. حذف آن ممکن است داده‌های مشتری را تحت تأثیر قرار دهد.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _deleteSingleCode(code, isActivated);
    }
  }

  Future<void> _deleteSingleCode(WarrantyCode code, bool force) async {
    if (code.id == null) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'شناسه کد گارانتی معتبر نیست');
      }
      return;
    }
    
    try {
      await _warrantyService.deleteCode(
        widget.businessId,
        code.id!,
        force: force,
      );
      
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: 'کد گارانتی با موفقیت حذف شد');
        _refreshTable();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در حذف کد گارانتی: $e');
      }
    }
  }

  Future<void> _confirmBulkDelete(BuildContext context) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: colorScheme.error),
            const SizedBox(width: 8),
            const Text('تأیید حذف گروهی'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('آیا از حذف ${_selectedRowIndices.length} کد گارانتی اطمینان دارید؟'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'کدهای فعال شده به صورت خودکار حذف می‌شوند. این عملیات قابل بازگشت نیست.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('حذف همه'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _deleteBulkCodes();
    }
  }

  Future<void> _deleteBulkCodes() async {
    // تبدیل index های انتخاب شده به id های واقعی
    final selectedCodes = _selectedRowIndices
        .where((index) => index < _currentPageCodes.length)
        .map((index) => _currentPageCodes[index])
        .where((code) => code.id != null)
        .toList();
    
    if (selectedCodes.isEmpty) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'هیچ کد معتبری برای حذف انتخاب نشده است');
      }
      return;
    }
    
    final codeIds = selectedCodes.map((code) => code.id!).toList();
    
    try {
      final result = await _warrantyService.deleteCodes(
        widget.businessId,
        codeIds,
        force: true,
      );
      
      if (mounted) {
        final summary = result.summary;
        final deleted = summary['deleted'] ?? 0;
        final skipped = summary['skipped'] ?? 0;
        final failed = summary['failed'] ?? 0;

        if (failed > 0 || skipped > 0) {
          _showBulkDeleteResult(context, result);
        } else {
          SnackBarHelper.showSuccess(
            context,
            message: '$deleted کد گارانتی با موفقیت حذف شد',
          );
        }
        
        setState(() {
          _selectedRowIndices.clear();
          _currentPageCodes.clear();
        });
        _refreshTable();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در حذف گروهی: $e');
      }
    }
  }

  void _showBulkDeleteResult(BuildContext context, WarrantyBulkDeleteResponse result) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info, color: colorScheme.primary),
            const SizedBox(width: 8),
            const Text('نتیجه حذف گروهی'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSummaryRow('موفق:', result.summary['deleted'] ?? 0, colorScheme.primary),
              _buildSummaryRow('رد شده:', result.summary['skipped'] ?? 0, colorScheme.tertiary),
              _buildSummaryRow('خطا:', result.summary['failed'] ?? 0, colorScheme.error),
              const SizedBox(height: 16),
              if (result.skippedCodes.isNotEmpty) ...[
                Text(
                  'کدهای رد شده:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.tertiary),
                ),
                const SizedBox(height: 8),
                ...result.skippedCodes.take(5).map((code) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '- ${code['code']}: ${code['reason']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                )),
                if (result.skippedCodes.length > 5)
                  Text('... و ${result.skippedCodes.length - 5} مورد دیگر', style: const TextStyle(fontSize: 12)),
              ],
              if (result.failedCodes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'کدهای خطا:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.error),
                ),
                const SizedBox(height: 8),
                ...result.failedCodes.take(5).map((code) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '- ID ${code['id']}: ${code['reason']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                )),
                if (result.failedCodes.length > 5)
                  Text('... و ${result.failedCodes.length - 5} مورد دیگر', style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('بستن'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: color)),
          Text('$count', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
